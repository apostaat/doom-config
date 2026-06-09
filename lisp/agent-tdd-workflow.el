;;; /home/apostaat/.doom.d/lisp/agent-tdd-workflow.el -*- lexical-binding: t; -*-

;; TDD multi-role loop:
;; Architect -> Test Designer -> Codex Implementation -> Tests -> Failure Analyst -> Fixer -> Tests...
;; Produces .agent-tdd/session-*.org logs and includes git diff snapshots.

(require 'cl-lib)
(require 'json)
(require 'project)
(require 'url)

(defvar agent-tdd-ollama-host
  (let ((host (or (getenv "OLLAMA_HOST") "127.0.0.1:11434")))
    (replace-regexp-in-string "\\`https?://" "" host))
  "Ollama host used for HTTP requests.")

(defcustom agent-tdd-ollama-default-home (or (getenv "OLLAMA_HOME") nil)
  "Default HOME for the Emacs-launched Ollama server process."
  :type '(choice (const :tag "Inherit current env" nil)
                (string :tag "Explicit HOME"))
  :group 'agent-tdd-workflow)

(defcustom agent-tdd-ollama-default-models (or (getenv "OLLAMA_MODELS") nil)
  "Default OLLAMA_MODELS for the Emacs-launched Ollama server process."
  :type '(choice (const :tag "Inherit current env" nil)
                (string :tag "Explicit OLLAMA_MODELS"))
  :group 'agent-tdd-workflow)

(defvar agent-tdd-ollama-binary "ollama"
  "Executable used to run Ollama server.")

(defun agent-tdd--ensure-ollama-directory (dir)
  "Return DIR if it exists or can be created as writable dir, otherwise nil."
  (when (and dir (stringp dir) (not (string-empty-p dir)))
    (let ((expanded (expand-file-name dir)))
      (condition-case nil
          (progn
            (make-directory expanded t)
            (and (file-directory-p expanded) (file-writable-p expanded) expanded))
        (error nil)))))

(defun agent-tdd--default-ollama-home (&optional requested-home)
  "Resolve a writable directory for Ollama home.
If REQUESTED-HOME is provided, prefer it."
  (or (agent-tdd--ensure-ollama-directory requested-home)
      (agent-tdd--ensure-ollama-directory agent-tdd-ollama-default-home)
      (agent-tdd--ensure-ollama-directory (and (getenv "OLLAMA_HOME") (expand-file-name (getenv "OLLAMA_HOME"))))
      (agent-tdd--ensure-ollama-directory (and (getenv "HOME") (expand-file-name ".ollama" (getenv "HOME"))))
      (agent-tdd--ensure-ollama-directory "/tmp/ollama")))

(defun agent-tdd--default-ollama-models (&optional requested-models requested-home)
  "Resolve a writable directory for Ollama models.
If REQUESTED-MODELS is provided, prefer it."
  (or (agent-tdd--ensure-ollama-directory requested-models)
      (agent-tdd--ensure-ollama-directory agent-tdd-ollama-default-models)
      (and requested-home
           (agent-tdd--ensure-ollama-directory (expand-file-name "models" requested-home)))
      (agent-tdd--ensure-ollama-directory (and (getenv "OLLAMA_MODELS")
                                              (expand-file-name (getenv "OLLAMA_MODELS"))))
      (agent-tdd--ensure-ollama-directory "/tmp/ollama/models")))

(defvar agent-tdd--ollama-server-process nil
  "Current background `ollama serve` process, if started from Emacs.")

(defun agent-tdd-ollama--safe-buffer-string (proc)
  "Return trimmed content of PROC's buffer."
  (when (processp proc)
    (with-current-buffer (or (process-buffer proc) (current-buffer))
      (string-trim-right (buffer-substring-no-properties (point-min) (point-max))))))

(defun agent-tdd-ollama--check-startup (proc host)
  "Validate startup result of PROC for HOST and post a clear message."
  (unless (process-live-p proc)
    (setq agent-tdd--ollama-server-process nil)
    (let ((out (or (agent-tdd-ollama--safe-buffer-string proc) "")))
      (cond
       ((string-match-p "address already in use" out)
        (message "Ollama server already running on %s (port in use)." host))
       ((string-match-p "No such file or directory" out)
        (message "Failed to start Ollama: binary \"%s\" not found in PATH." agent-tdd-ollama-binary))
       (t
        (message "Ollama server failed to start. See *agent-tdd-ollama-server*."))))))

(defun agent-tdd-ollama--endpoint-live-p (endpoint)
  "Return non-nil when Ollama endpoint responds to a quick HTTP request."
  (condition-case nil
      (let ((buf (url-retrieve-synchronously endpoint nil t 0.6)))
        (when buf
          (unwind-protect
              (with-current-buffer buf
                (goto-char (point-min))
                (when (re-search-forward "^HTTP/[0-9.]+ \\([0-9][0-9][0-9]\\)" nil t)
                  (let ((code (string-to-number (match-string 1))))
                    (and (>= code 100) (<= code 599)))))
            (kill-buffer buf))))
    (error nil)))

(defgroup agent-tdd-workflow nil
  "Agentic TDD flow inside Emacs."
  :group 'tools)

(defcustom agent-tdd-ollama-endpoint
  (format "http://%s/api/chat" agent-tdd-ollama-host)
  "Ollama-compatible endpoint."
  :type 'string
  :group 'agent-tdd-workflow)

(defcustom agent-tdd-ollama-context-window 131072
  "Context window (num_ctx) passed to Ollama for each request."
  :type 'integer
  :group 'agent-tdd-workflow)

(defcustom agent-tdd-model "deepseek-r1:32b"
  "DeepSeek model name in ollama."
  :type 'string
  :group 'agent-tdd-workflow)

(defcustom agent-tdd-default-test-command "make test"
  "Default test command for new runs.
Usually overridden per repository."
  :type 'string
  :group 'agent-tdd-workflow)

(defcustom agent-tdd-max-fix-iterations 3
  "Number of failure-analysis/fix rounds."
  :type 'integer
  :group 'agent-tdd-workflow)

(defcustom agent-tdd-project-log-dir ".agent-tdd"
  "Folder in project root for session artifacts."
  :type 'string
  :group 'agent-tdd-workflow)

(defcustom agent-tdd-codex-command nil
  "Shell command for codex-cli (for example: \"codex\").
Must read prompt from stdin."
  :type '(choice (const :tag "Disabled" nil)
                 (string :tag "Command"))
  :group 'agent-tdd-workflow)

(defvar agent-tdd--session-buffer "*agent-tdd-session*")
(defvar agent-tdd--console-buffer "*agent-tdd-console*")

(defun agent-tdd-ollama-start-server (&optional host home-path models-path)
  "Start `ollama serve` in background from Emacs.

If HOST is nil, `OLLAMA_HOST` or `agent-tdd-ollama-host` is used.
If HOME-PATH is non-nil, sets HOME for this process.
If MODELS-PATH is non-nil, sets OLLAMA_MODELS for this process."
  (interactive)
  (if (and agent-tdd--ollama-server-process
           (process-live-p agent-tdd--ollama-server-process))
      (message "Ollama server already running in process %s"
               (process-name agent-tdd--ollama-server-process))
    (let* ((host-final (or host agent-tdd-ollama-host))
           (home-final (or (agent-tdd--default-ollama-home home-path)
                          (and (getenv "HOME") (expand-file-name ".ollama" (getenv "HOME")))))
           (models-final (agent-tdd--default-ollama-models models-path home-final))
           (buf-serve-buffer (get-buffer-create "*agent-tdd-ollama-server*")))
      (let ((process-environment (copy-sequence process-environment))
            (default-directory "/tmp/"))
        (setenv "OLLAMA_HOST" host-final)
        (when home-final (setenv "HOME" home-final))
        (when home-final (setenv "OLLAMA_HOME" home-final))
        (when models-final (setenv "OLLAMA_MODELS" models-final))
        (setq agent-tdd-ollama-endpoint (format "http://%s/api/chat" host-final))
        (if (agent-tdd-ollama--endpoint-live-p agent-tdd-ollama-endpoint)
            (progn
              (setq agent-tdd--ollama-server-process nil)
              (message "Ollama already running at %s (not starting a new process)." agent-tdd-ollama-endpoint)
              nil)
          (setq agent-tdd--ollama-server-process
                (start-process "agent-tdd-ollama-server"
                               buf-serve-buffer
                               agent-tdd-ollama-binary
                               "serve"))
          (set-process-query-on-exit-flag agent-tdd--ollama-server-process nil)
          (set-process-sentinel agent-tdd--ollama-server-process
                                (lambda (proc event)
                                  (message "Ollama server process %s: %s"
                                           (process-name proc) (string-trim event))))
          (message "Ollama server start requested for host=%s (buffer: %s)."
                   host-final
                   (buffer-name buf-serve-buffer))
          (run-with-timer 1 nil #'agent-tdd-ollama--check-startup agent-tdd--ollama-server-process host-final)
          agent-tdd--ollama-server-process)))))

(defun agent-tdd-ollama-stop-server ()
  "Stop background `ollama serve` process started from Emacs."
  (interactive)
  (if (and agent-tdd--ollama-server-process
           (process-live-p agent-tdd--ollama-server-process))
      (progn
        (delete-process agent-tdd--ollama-server-process)
        (setq agent-tdd--ollama-server-process nil)
        (message "Ollama server stopped."))
    (message "Ollama server process is not running.")))

(defun agent-tdd--project-root ()
  (or (let ((project (project-current nil)))
        (and project (project-root project)))
      default-directory))

(defun agent-tdd--session-dir ()
  (expand-file-name (concat (file-name-as-directory (agent-tdd--project-root))
                           agent-tdd-project-log-dir "/")))

(defun agent-tdd--ensure-session-dir ()
  (let ((dir (agent-tdd--session-dir)))
    (unless (file-exists-p dir) (make-directory dir t))
    dir))

(defun agent-tdd--session-file (task)
  (let ((ts (format-time-string "%Y-%m-%d_%H-%M-%S"))
        (slug (replace-regexp-in-string "[^a-zA-Z0-9-_]+" "-"
                                        (truncate-string-to-width task 56 0 nil nil))))
    (expand-file-name (format "session-%s-%s.org" ts slug) (agent-tdd--ensure-session-dir))))

(defun agent-tdd--log (file section body)
  (with-current-buffer (find-file-noselect file)
    (goto-char (point-max))
    (insert (format "\n* %s :: %s\n" section (format-time-string "%Y-%m-%d %H:%M:%S")))
    (insert (string-trim-right (or body "")) "\n")
    (insert "\n")
    (save-buffer)))

(defun agent-tdd--append-console (fmt &rest args)
  (with-current-buffer (get-buffer-create agent-tdd--console-buffer)
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (apply #'format fmt args))
      (insert "\n"))))

(defun agent-tdd--string-non-empty (value)
  "Return VALUE when it is a non-empty string."
  (and (stringp value) (not (string-empty-p (string-trim value))) value))

(defun agent-tdd--call-ollama (system-prompt user-prompt)
  (let* ((payload (json-encode
                   `(("model" . ,agent-tdd-model)
                     ("stream" . :json-false)
                     ("options" . (("num_ctx" . ,agent-tdd-ollama-context-window)))
                     ("messages" .
                      [(("role" . "system") ("content" . ,system-prompt))
                       (("role" . "user") ("content" . ,user-prompt))]))))
         (tmp (make-temp-file "agent-tdd-ollama-payload-"))
         (buf (get-buffer-create " *agent-tdd-curl*"))
         (status 0)
         (json-raw nil)
         (command-json nil))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert payload))
          (with-current-buffer buf
            (erase-buffer)
            (setq status
                  (apply #'call-process
                         "curl" nil buf nil
                         (list "--silent" "--show-error" "--max-time" "300"
                               "-H" "Content-Type: application/json"
                               "-X" "POST"
                               "--data-binary" (concat "@" tmp)
                               agent-tdd-ollama-endpoint)))
            (setq json-raw (string-trim-right (buffer-string)))
            (if (not (eq status 0))
                (error "agent-tdd: codex command failed (exit %s): %s"
                       status json-raw))
            (setq command-json
                  (condition-case nil
                      (json-read-from-string json-raw)
                    (error nil)))))
      (ignore-errors (delete-file tmp))
      (and (buffer-name buf) (kill-buffer buf)))
    (let* ((msg (and command-json
                     (or (assoc-default "message" command-json nil #'string=)
                         (assoc-default 'message command-json))))
           (content (and msg
                         (agent-tdd--string-non-empty
                          (or (assoc-default "content" msg nil #'string=)
                              (assoc-default 'content msg)))))
           (thinking (and msg
                          (agent-tdd--string-non-empty
                           (or (assoc-default "thinking" msg nil #'string=)
                               (assoc-default 'thinking msg)))))
           (resp (and command-json
                      (or (assoc-default "response" command-json nil #'string=)
                          (assoc-default 'response command-json))))
           (err (and command-json
                      (or (assoc-default "error" command-json nil #'string=)
                          (assoc-default 'error command-json)))))
      (cond
       (content content)
       (thinking thinking)
       (resp resp)
       (err (format "ERROR: %s" err))
       (command-json "")
       ((and json-raw (stringp json-raw)) json-raw)
       (t "")))))

(defun agent-tdd--run-command-json (prompt command)
  (unless (stringp command)
    (user-error "agent-tdd-codex-command is not configured"))
  (let* ((tmp (make-temp-file "agent-tdd-prompt-"))
         (buf (get-buffer-create " *agent-tdd-codex*"))
         (default-directory (file-name-as-directory (agent-tdd--project-root)))
         (cmd (format "%s < %s" command (shell-quote-argument tmp)))
         (status 0))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert (or prompt "")))
          (with-current-buffer buf
            (erase-buffer)
            (setq status (call-process-shell-command cmd nil (current-buffer) nil))
            (when (not (eq status 0))
              (error "agent-tdd: codex command failed (exit %s): %s"
                     status (string-trim-right (buffer-string))))
            (string-trim-right (buffer-string))))
      (ignore-errors (delete-file tmp))
      (kill-buffer buf))))

(defun agent-tdd-smoke-test-ollama ()
  "Send a test prompt to Ollama and return the raw answer."
  (interactive)
  (let ((result
         (agent-tdd--call-ollama
          "Ты — строго короткий тестовый ассистент."
          "Ответь только одним словом: PONG.")))
    (if (string-empty-p result)
        (message "agent-tdd smoke-test: empty response from %s" agent-tdd-ollama-endpoint)
      (message "agent-tdd smoke-test output:\n%s" result))
    result))

(defun agent-tdd--git-diff ()
  (let ((default-directory (file-name-as-directory (agent-tdd--project-root))))
    (with-current-buffer (get-buffer-create " *agent-tdd-diff*")
      (erase-buffer)
      (call-process-shell-command "git diff --" nil (current-buffer) nil)
      (string-trim-right (buffer-string)))))

(defun agent-tdd--run-tests (command)
  (let ((default-directory (file-name-as-directory (agent-tdd--project-root)))
        (buf (get-buffer-create " *agent-tdd-tests*")))
    (with-current-buffer buf
      (erase-buffer)
      (let ((status (call-process-shell-command command nil buf nil)))
        (list :status status :output (string-trim-right (buffer-string)))))))

(defun agent-tdd--role-prompt (role)
  (pcase role
    ('architect
     "Ты — Architect. Формируй требования, API, file structure. Без кода, без правок файлов.")
    ('test-designer
     "Ты — Test Designer. По задаче и архитектуре сгенерируй unit и property тесты: happy path + edge cases + malformed.")
    ('coder
     "Ты — Coder. На основе задачи, архитектуры и тестов опиши конкретные изменения кода (без изменения тестов), чтобы тесты начали проходить.")
    ('failure-analyst
     "Ты — Failure Analyst. Анализируй output тестов + контекст изменений и давай root-cause и конкретные правки.")
    ('fixer
     "Ты — Fixer. Дай минимально достаточные правки кода, ничего лишнего, без изменения тестов.")
    (_ "")))

(defun agent-tdd--deepseek (role task architecture tests language context)
  (agent-tdd--call-ollama
   (agent-tdd--role-prompt role)
   (format "Task:\n%s\n\nLanguage:\n%s\n\nArchitecture:\n%s\n\nTests:\n%s\n\nContext:\n%s"
           task language architecture tests context)))

(defun agent-tdd--run-step-with-codex (role task architecture tests language context)
  (let* ((deepseek-output (agent-tdd--deepseek role task architecture tests language context))
         (before (agent-tdd--git-diff)))
    (agent-tdd--append-console "[%s] DeepSeek:\n%s\n" (symbol-name role) deepseek-output)
    (let ((codex-output
           (if (and agent-tdd-codex-command
                    (yes-or-no-p (format "Запустить codex для шага %s? " (symbol-name role))))
               (agent-tdd--run-command-json
                (concat "Роль: " (symbol-name role) "\n"
                        "Задача: " task "\n"
                        "Язык: " language "\n"
                        "Учитывай архитектуру и тесты.\n\n"
                        deepseek-output)
                agent-tdd-codex-command)
             "SKIPPED_BY_USER")))
      (list deepseek-output
            codex-output
            (let ((after (agent-tdd--git-diff)))
              (if (string= before after)
                  "No diff changes in working tree."
                (concat "DIFF (post):\n" after)))))))

(defun agent-tdd--open-console (session-file)
  (with-current-buffer (get-buffer-create agent-tdd--console-buffer)
    (erase-buffer)
    (insert "# Agent TDD console\n")
    (insert "Session: " session-file "\n\n")
    (agent-tdd-console-mode)
    (display-buffer (current-buffer) '(display-buffer-pop-up-window . nil))))

(define-derived-mode agent-tdd-console-mode special-mode "agent-tdd-console"
  "Mode for live agent-tdd logs.")

(defun agent-tdd-start (task &optional test-command max-iterations language)
  "Run one strict flow for TASK.
TDD roles are separate and sequential."
  (interactive
   (list
    (read-string "Task: ")
    (read-string (format "Test command (%s): " agent-tdd-default-test-command)
                 nil nil nil agent-tdd-default-test-command)
    (let ((n (read-string (format "Max iterations (%d): " agent-tdd-max-fix-iterations))))
      (if (string-empty-p n)
          agent-tdd-max-fix-iterations
        (string-to-number n)))
    (read-string "Language (clojure/typescript/agnostic): " "agnostic")))
  (let* ((test-cmd (or test-command agent-tdd-default-test-command))
         (max-iters (or max-iterations agent-tdd-max-fix-iterations))
         (language (or language "agnostic"))
         (session-file (agent-tdd--session-file task))
         (passed nil))
    (let ((architect (agent-tdd--deepseek 'architect task "" "" language
                                          "Выдай API и структуру файлов.")))
      (agent-tdd--open-console session-file)
      (agent-tdd--append-console "Task: %s" task)
      (agent-tdd--append-console "Language: %s" language)
      (agent-tdd--append-console "Test command: %s" test-cmd)
      (agent-tdd--append-console "Session file: %s" session-file)
      (agent-tdd--log session-file "Task" task)
      (agent-tdd--log session-file "Architect" architect)
      (agent-tdd--append-console "[architect] done")
      (let* ((tests (agent-tdd--deepseek 'test-designer task architect "" language "")))
        (agent-tdd--log session-file "Test Designer" tests)
        (agent-tdd--append-console "[test-designer] done")
        (let* ((coder-data (agent-tdd--run-step-with-codex 'coder task architect tests language
                                                          "Do not modify tests."))
               (coder-deepseek (nth 0 coder-data))
               (coder-codex (nth 1 coder-data))
               (coder-diff (nth 2 coder-data)))
          (agent-tdd--log session-file "Codex Implementation"
                           (format "DeepSeek:\n%s\n\nCodex:\n%s\n\n%s"
                                   coder-deepseek coder-codex coder-diff))
          (cl-loop for i from 1 to max-iters do
            (let* ((tests-result (agent-tdd--run-tests test-cmd))
                   (status (plist-get tests-result :status))
                   (output (plist-get tests-result :output)))
              (agent-tdd--log session-file (format "Test run #%d" i) output)
              (agent-tdd--append-console "[tests #%d] exit=%d" i status)
              (if (= status 0)
                  (progn
                    (setq passed t)
                    (cl-return))
                (let* ((analysis (agent-tdd--deepseek 'failure-analyst task architect tests
                                                      language
                                                      (format "status=%d\n%s" status output)))
                       (fix-data (agent-tdd--run-step-with-codex 'fixer task architect tests language
                                                                 (format "Failure output:\n%s\n\nAnalysis:\n%s"
                                                                         output analysis)))
                       (fixer-output (nth 0 fix-data))
                       (fixer-codex (nth 1 fix-data))
                       (fixer-diff (nth 2 fix-data)))
                  (agent-tdd--log session-file
                                   (format "Iteration %d: Failure Analyst + Fixer" i)
                                   (format "Failure Analyst:\n%s\n\nFixer DeepSeek:\n%s\n\nFixer Codex:\n%s\n\n%s"
                                           analysis fixer-output fixer-codex fixer-diff))))))))
        (if passed
            (progn
              (agent-tdd--log session-file "Result" "PASS: tests green.")
              (agent-tdd--append-console "Result: PASS")
              (message "agent-tdd: tests are green. %s" session-file))
          (agent-tdd--log session-file "Result" (format "FAIL after %d iterations." max-iters))
          (agent-tdd--append-console "Result: FAIL")
          (message "agent-tdd: tests still failing. %s" session-file)))))

(defun agent-tdd-open-wizard ()
  "Open wizard-like workflow buffer with session metadata and run button."
  (interactive)
  (let ((buf (get-buffer-create "*agent-tdd-wizard*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "# Agent TDD wizard\n\n")
      (insert "Task: \n\n")
      (insert "Test command: make test\n\n")
      (insert "Max fix iterations: 3\n\n")
      (insert "Language: agnostic\n\n")
      (insert "Press C-c C-c to start, q to quit.\n")
      (use-local-map (let ((map (make-sparse-keymap)))
                      (define-key map (kbd "C-c C-c")
                        (lambda ()
                          (interactive)
                          (let* ((task (string-trim (save-excursion
                                                     (goto-char (point-min))
                                                     (search-forward "Task: " nil t)
                                                     (buffer-substring-no-properties (point) (line-end-position)))))
                                 (test-cmd (string-trim (save-excursion
                                                         (search-forward "Test command: " nil t)
                                                         (buffer-substring-no-properties (point) (line-end-position)))))
                                 (iter-line (save-excursion
                                             (search-forward "Max fix iterations: " nil t)
                                             (string-trim (buffer-substring-no-properties (point) (line-end-position)))))
                                 (language (save-excursion
                                            (search-forward "Language: " nil t)
                                            (buffer-substring-no-properties (point) (line-end-position))))
                                 (test-cmd-final (if (string-empty-p test-cmd)
                                                     agent-tdd-default-test-command
                                                   test-cmd))
                                 (iters (if (string-empty-p iter-line)
                                            agent-tdd-max-fix-iterations
                                          (string-to-number iter-line))))
                            (if (string-empty-p task)
                                (message "Task is required")
                              (agent-tdd-start task test-cmd-final iters language))))
                        )
                      (define-key map (kbd "q") #'(lambda () (interactive) (kill-buffer)))
                      map))
      (agent-tdd-console-mode)
      (goto-char (point-min)))
    (display-buffer buf)))

(defvar agent-tdd-ollama-ollama-map (make-sparse-keymap)
  "Sub-map for Ollama actions under the agent leader tree.")

(defun agent-tdd--ensure-leader-prefix (parent-map prefix-char)
  "Ensure PARENT-MAP has PREFIX-CHAR as a prefix key and return it."
  (let ((existing (lookup-key parent-map (kbd prefix-char))))
    (if (keymapp existing)
        existing
      (let ((new-map (make-sparse-keymap)))
        (define-key parent-map (kbd prefix-char) new-map)
        new-map))))

(defun agent-tdd-ensure-shortcuts-fallback ()
  "Guarantee SPC a o s / SPC a o p work even if map! binding context is unstable."
  (let* ((leader-map (and (boundp 'doom-leader-map) (symbol-value 'doom-leader-map)))
         (leader-key (or (and (boundp 'doom-leader-key) (stringp doom-leader-key) doom-leader-key) "SPC")))
    (if (not (keymapp leader-map))
        (progn
          (message "agent-tdd: doom-leader-map not initialized; skip fallback shortcuts")
          nil)
      (let ((raw-a-map nil)
            (raw-o-map nil)
            (a-map nil)
            (o-map nil))
        (setq raw-a-map (or (agent-tdd--ensure-leader-prefix leader-map "a")
                            (lookup-key leader-map (kbd "a"))))
        (setq raw-o-map (and (keymapp raw-a-map)
                             (or (agent-tdd--ensure-leader-prefix raw-a-map "o")
                                 (lookup-key raw-a-map (kbd "o")))))
        (setq a-map (and (keymapp raw-a-map) raw-a-map)
              o-map (and (keymapp raw-o-map) raw-o-map))
        (when (and a-map o-map)
          (define-key o-map (kbd "s") #'agent-tdd-ollama-start-server)
          (define-key o-map (kbd "p") #'agent-tdd-ollama-stop-server)
          (define-key a-map (kbd "o") o-map)
          (define-key a-map (kbd "O") o-map)
          (define-key a-map (kbd "t") #'agent-tdd-start)
          (define-key a-map (kbd "w") #'agent-tdd-open-wizard)
          (define-key a-map (kbd "v")
            #'(lambda ()
                (interactive)
                (let* ((dir (agent-tdd--ensure-session-dir))
                       (files (directory-files dir t "session-.*\\.org$" t)))
                  (if files
                      (find-file (car (last files)))
                    (message "No agent sessions yet in %s" dir)))))
          (when (and (boundp 'which-key-mode) which-key-mode)
            (which-key-add-key-based-replacements
             (format "%s a" leader-key) "agent"
             (format "%s a o" leader-key) "ollama")))
        (define-key agent-tdd-ollama-ollama-map (kbd "s") #'agent-tdd-ollama-start-server)
        (define-key agent-tdd-ollama-ollama-map (kbd "p") #'agent-tdd-ollama-stop-server)
        (when (and (boundp 'which-key-mode) which-key-mode)
          (which-key-add-key-based-replacements
           (format "%s a o s" leader-key) "Start Ollama server"
           (format "%s a o p" leader-key) "Stop Ollama server"))
        t))))

(add-hook 'after-init-hook #'agent-tdd-ensure-shortcuts-fallback)
