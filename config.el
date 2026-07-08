;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
(setq user-full-name "Artem Apostatov"
      user-mail-address "alexeevdev@yahoo.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-unicode-font' -- for unicode glyphs
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:

(setq doom-theme 'doom-old-hope)
(setq display-line-numbers-type t)
(setq org-directory "~/org/")

(setq org-roam-directory "~/org/roam")

(map! (:leader
       (:map (clojure-mode-map clojurescript-mode-map emacs-lisp-mode-map)
             (:prefix ("k" . "lisp")
                      "j" #'paredit-join-sexps
                      "c" #'paredit-split-sexp
                      "D" #'paredit-kill
                      "d" #'sp-kill-sexp
                      "<" #'paredit-backward-slurp-sexp
                      ">" #'paredit-backward-barf-sexp
                      "s" #'paredit-forward-slurp-sexp
                      "b" #'paredit-forward-barf-sexp
                      "r" #'paredit-raise-sexp
                      "R" #'sp-rewrap-sexp
                      "w" #'paredit-wrap-sexp
                      "'" #'paredit-meta-doublequote
                      "y" #'sp-copy-sexp
                      "k" #'browse-kill-ring))))

(setq enable-local-variables 'always)

;; Enable evaluation of Clojure code blocks

(after! cua-base
  (cua-mode t)
  (setq cua-auto-tabify-rectangles nil)
  (setq cua-keep-region-after-copy t))

;; Enable transient mark mode
(transient-mark-mode 1)

(when (memq window-system '(x pgtk))
  (require 'exec-path-from-shell)
  ;; Import common environment variables
  (dolist (var '("PATH" "MANPATH" "JAVA_HOME"))
    (add-to-list 'exec-path-from-shell-variables var))
  (exec-path-from-shell-initialize))

(defun clj-insert-persist-scope-macro ()
  (interactive)
  (insert
   "(defmacro persist-scope
              \"Takes local scope vars and defines them in the global scope. Useful for RDD\"
              []
              `(do ~@(map (fn [v] `(def ~v ~v))
                  (keys (cond-> &env (contains? &env :locals) :locals)))))"))

(defun clj-insert-quick-bench ()
  (interactive)
  (let* ((current-ns (cider-current-ns))
         (form (cider-last-sexp))
         (clj-cmd (format "(do (require 'criterium.core) (criterium.core/quick-bench %s))" form)))
    (cider-interactive-eval clj-cmd nil nil `(("ns" ,current-ns)))))

(defun persist-scope ()
  (interactive)
  (let ((beg (point)))
    (clj-insert-persist-scope-macro)
    (cider-eval-region beg (point))
    (delete-region beg (point))
    (insert "(persist-scope)")
    (cider-eval-defun-at-point)
    (delete-region beg (point))))

;;; agent-jail: drive jobs from the agent-jail.work nREPL namespace ------------

(defun agent-jail--eval (form)
  "Eval FORM (a string) in the `agent-jail.work' namespace on the current REPL.

Sends an EXPLICIT ns so it works from any buffer — including a .md file, where
`cider-interactive-eval' would fall back to `cider-current-ns' (\"user\") and
fail to resolve the `jail'/`judge' aliases and `config', so the form would
silently never run. Results and errors are shown in the echo area."
  (cider-nrepl-request:eval
   form
   (cider-interactive-eval-handler nil)
   "agent-jail.work"))

(defun agent-jail--ids ()
  "Return the list of currently open jail ids from the REPL (via `get-ids')."
  (let* ((res (cider-nrepl-sync-request:eval
               "(agent-jail.core/get-ids)" nil "agent-jail.work"))
         (val (nrepl-dict-get res "value")))
    (unless val
      (user-error "No REPL value from get-ids (is CIDER connected?)"))
    (append (car (read-from-string val)) nil)))

(defun agent-jail-run-job-claude ()
  "Turn the current .md buffer into a keyword and run it as a claude job.
`~/Work/agent-jail/receipts-own-llm.md' becomes
`(jail/run-job-md-claude! :receipts-own-llm config)'."
  (interactive)
  (unless (and buffer-file-name
               (string= (file-name-extension buffer-file-name) "md"))
    (user-error "Not visiting a .md file"))
  (let* ((kw (concat ":" (file-name-base buffer-file-name)))
         (form (format "(jail/run-job-md-claude! %s config)" kw)))
    (agent-jail--eval form)
    (message "agent-jail run: %s" kw)))

(defun agent-jail-stop-job (id)
  "Pick one of the open jails and stop it via `(jail/stop! ID)'."
  (interactive
   (let ((ids (agent-jail--ids)))
     (unless ids (user-error "No open jails"))
     (list (completing-read "Stop jail: " ids nil t))))
  (agent-jail--eval (format "(jail/stop! %S)" id))
  (message "agent-jail stop: %s" id))

(defun agent-jail-ship-job (id)
  "Pick one of the open jails and ship it locally via `(jail/ship! ID)'."
  (interactive
   (let ((ids (agent-jail--ids)))
     (unless ids (user-error "No open jails"))
     (list (completing-read "Ship (local) jail: " ids nil t))))
  (agent-jail--eval (format "(jail/ship! %S)" id))
  (message "agent-jail ship (local): %s" id))

(defun agent-jail-ship-push-job (id)
  "Pick one of the open jails and ship+push it via `(jail/ship-push! ID)'."
  (interactive
   (let ((ids (agent-jail--ids)))
     (unless ids (user-error "No open jails"))
     (list (completing-read "Ship+push jail: " ids nil t))))
  (agent-jail--eval (format "(jail/ship-push! %S)" id))
  (message "agent-jail ship+push: %s" id))

;; Clear any prior single-key binding on `e s` (from an earlier reload) so it
;; can be turned into a sub-prefix without "starts with non-prefix key" errors.
(defun agent-jail-judge-claude (id)
  "Pick an open jail and judge it once with Claude as the oracle, in its own
tmux tab via `(judge/open-judge-once! \"config.edn\" ID \"claude\")'."
  (interactive
   (let ((ids (agent-jail--ids)))
     (unless ids (user-error "No open jails"))
     (list (completing-read "Judge (claude) jail: " ids nil t))))
  (agent-jail--eval (format "(judge/open-judge-once! \"config.edn\" %S \"claude\")" id))
  (message "agent-jail judge (claude) tab: judge-%s" id))

(defun agent-jail-judge-local (id)
  "Pick an open jail and judge it once with the local ollama model
(deepseek-r1:32b) in its own tmux tab via
`(judge/open-judge-once! \"config.edn\" ID \"local\")'. Starts `ollama serve'
first if the server is down."
  (interactive
   (let ((ids (agent-jail--ids)))
     (unless ids (user-error "No open jails"))
     (list (completing-read "Judge (local) jail: " ids nil t))))
  (agent-jail--eval (format "(judge/open-judge-once! \"config.edn\" %S \"local\")" id))
  (message "agent-jail judge (local) tab: judge-%s" id))

(defun agent-jail-fix-ci-cd (url)
  "Spin up a job that diagnoses and fixes a failing CI/CD run.
With a GitHub Actions run URL, point the agent straight at it; leave it
empty to let the agent find the latest failed run itself via gh."
  (interactive "sGitHub Actions run URL (empty = latest failed): ")
  (let* ((url (string-trim url))
         (form (if (string-empty-p url)
                   "(jail/fix-ci-cd! config)"
                 (format "(jail/fix-ci-cd! config %S)" url))))
    (agent-jail--eval form)
    (message "agent-jail fix-ci-cd: %s" (if (string-empty-p url) "latest failed" url))))

(defun agent-jail-check-lint-test ()
  "Run the local quality gate (make test/lint/type-check in LeadForgeAI, make
test in robots-clj). If everything is green nothing happens; on any failure a
jail fix-job is spun up with the captured output as its prompt."
  (interactive)
  (agent-jail--eval "(jail/check-lint-test! config)")
  (message "agent-jail check-lint-test: running local gate..."))

(defvar agent-jail-reclaim-classes '("jails" "orphans" "docker" "caches")
  "Disk-reclaim classes offered by `agent-jail-reclaim'.
jails   - delete every FINISHED jail's workspace (running jails spared)
orphans - kill ownerless `docker run' containers + their anon volumes
docker  - global `docker system prune -a --volumes' + build cache
caches  - regenerable ~/.cache children (huggingface spared)")

(defun agent-jail-reclaim (&optional classes)
  "Free disk space via `(jail/reclaim!)' on the REPL.

Deletes finished jails, kills ownerless docker containers (leaked test DBs),
prunes docker globally, and clears regenerable caches. Source repos are never
touched, so deployments/.localdata and deployments/training* stay safe, and
deliberately named standalone containers are spared.

With a prefix argument, prompt for a subset of `agent-jail-reclaim-classes' to
sweep; otherwise sweep everything. Confirms first — this is destructive."
  (interactive
   (list (when current-prefix-arg
           (completing-read-multiple
            "Reclaim classes (comma-separated): " agent-jail-reclaim-classes))))
  (when (yes-or-no-p
         (if classes
             (format "Reclaim %s? " (string-join classes ", "))
           "Reclaim ALL (finished jails, orphan containers, docker, caches)? "))
    ;; Selecting a subset means turning the others OFF (reclaim! defaults all on),
    ;; so build the full toggle map explicitly.
    (let ((form (if classes
                    (format "(jail/reclaim! {%s})"
                            (mapconcat
                             (lambda (c)
                               (format ":%s? %s" c
                                       (if (member c classes) "true" "false")))
                             agent-jail-reclaim-classes " "))
                  "(jail/reclaim!)")))
      (agent-jail--eval form)
      (message "agent-jail reclaim: %s"
               (if classes (string-join classes ", ") "all")))))

;; Clear prior single-key bindings on `e s`/`e j` (from an earlier reload) so they
;; can be turned into sub-prefixes without "starts with non-prefix key" errors.
(map! :leader :prefix "e" "s" nil "j" nil)

(map! :leader
      :prefix ("e" . "Clojure Command Center")
      :desc "Persist Scope Macro" "p" #'persist-scope
      :desc "Quick Bench Current Expression" "b" #'clj-insert-quick-bench
      :desc "agent-jail: run job (claude)" "r" #'agent-jail-run-job-claude
      :desc "agent-jail: abort (stop) job"  "a" #'agent-jail-stop-job
      :desc "agent-jail: fix CI/CD"         "f" #'agent-jail-fix-ci-cd
      :desc "agent-jail: check lint+test"   "c" #'agent-jail-check-lint-test
      :desc "agent-jail: reclaim disk"      "R" #'agent-jail-reclaim
      (:prefix ("j" . "agent-jail: judge")
       :desc "local (deepseek-r1:32b)" "l" #'agent-jail-judge-local
       :desc "claude"                  "c" #'agent-jail-judge-claude)
      (:prefix ("s" . "agent-jail: ship")
       :desc "ship local"     "l" #'agent-jail-ship-job
       :desc "ship and ship"  "s" #'agent-jail-ship-push-job))

(after! cc-mode
  (defun my/cpp-run-current-file-in-term ()
    "Open ansi-term in a split window and run `make run <filename>`."
    (interactive)
    (let* ((filename (file-name-nondirectory (buffer-file-name)))
           (cmd (format "make run %s\n" filename)))
      ;; открыть новый сплит снизу (1/3 высоты)
      (split-window-below -10)
      (other-window 1)
      ;; запуск shell через ansi-term
      (ansi-term "/bin/zsh") ;; поменяй на /bin/bash если нужно
      (sit-for 0.2)
      ;; вставляем команду
      (term-send-raw-string cmd)))

  (map! :map c++-mode-map
        :localleader
        :desc "Make run current file"
        "r" #'my/cpp-run-current-file-in-term))

(map! :after elixir-mode
      :localleader
      :map elixir-mode-map
      :prefix ("i" . "inf-elixir")
      "i" 'inf-elixir
      "p" 'inf-elixir-project
      "l" 'inf-elixir-send-line
      "r" 'inf-elixir-send-region
      "b" 'inf-elixir-send-buffer
      "R" 'inf-elixir-reload-module)

(defun my/inf-elixir-clean-output (output)
  (replace-regexp-in-string
   "\\(\\.\\.\\.([0-9]+)> \\)\\{5,\\}"
   "[:repeated_prompt_omitted]\n" output))

(add-hook 'inf-elixir-mode-hook #'visual-line-mode)
(add-hook 'inf-elixir-mode-hook (lambda ()
                                  (add-hook 'comint-preoutput-filter-functions
                                            #'my/inf-elixir-clean-output nil t)))

(after! elixir-mode
  (require 'yafolding)
  (add-hook 'elixir-mode-hook #'yafolding-mode)
  (setq yafolding-mode-alist
        '((elixir-mode . "^\\(defmodule\\|defp?\\|defmacro\\|test\\|describe\\)\\b")))
  (with-eval-after-load
      'elixir-mode
    (map! :map elixir-mode-map :n "za" #'yafolding-toggle-element :n "zA" #'yafolding-toggle-all)))

(setq org-clock-sound "/home/apostaat/Downloads/pause1.mp3")

(defun start-work-session ()
  (interactive)
  (org-timer-set-timer "0:45:00"))

(defun start-rest-session ()
  (interactive)
  (org-timer-set-timer "0:15:00"))

(map! :leader
      :prefix ("S" . "org-pomodorro-timer")
      "w" #'start-work-session
      "r" #'start-rest-session)

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(elixir-mode . ("/Users/artemapostatov/elixir-ls/release/language_server.sh"))))

(after! lisp-extra-font-lock
  (lisp-extra-font-lock-global-mode 1))

(after! lisp-mode
  (add-to-list 'auto-mode-alist '("\\.opmo\\'" . lisp-mode)))

(after! prog-mode
  (add-hook! 'lisp-mode-hook
             #'rainbow-identifiers-mode))

(add-hook 'prog-mode-hook #'rainbow-delimiters-mode)

;; indentation
(setq typescript-indent-level 2)

(set-language-environment "UTF-8")
(prefer-coding-system 'utf-8-unix)
(set-default-coding-systems 'utf-8-unix)
(set-selection-coding-system 'utf-8)
(set-clipboard-coding-system 'utf-8)
(setq select-enable-clipboard t)
(setq-default buffer-file-coding-system 'utf-8-unix)

(when (and (eq system-type 'gnu/linux)
           (getenv "WAYLAND_DISPLAY")
           (executable-find "wl-copy")
           (executable-find "wl-paste"))
  (defun my/wl-copy-text (text)
    (let ((coding-system-for-write 'utf-8-unix)
          (process-connection-type nil))
      (with-temp-buffer
        (insert text)
        (call-process-region
         (point-min) (point-max)
         "wl-copy" nil 0 nil
         "--type" "text/plain;charset=utf-8"))))

  (defun my/wl-paste-text ()
    (let ((coding-system-for-read 'utf-8-unix)
          (process-connection-type nil))
      (with-temp-buffer
        (when (zerop (call-process "wl-paste" nil t nil "--no-newline"))
          (buffer-string)))))

  (setq interprogram-cut-function #'my/wl-copy-text
        interprogram-paste-function #'my/wl-paste-text))

;; Forge configuration
;; Remember to create a GitHub token and add it to ~/.authinfo or ~/.authinfo.gpg:
;; machine api.github.com login <your-github-username>^forge password <your-token>
(setq auth-sources '("~/.authinfo"))

;; Ollama context window (token budget for each request)
(defvar my/ollama-max-context-tokens 131072
  "Maximum context window (in tokens) to request from local Ollama models.")

(setenv "OLLAMA_CONTEXT_LENGTH" (number-to-string my/ollama-max-context-tokens))
(setenv "OLLAMA_NUM_CTX" (number-to-string my/ollama-max-context-tokens))

;; ECA + local Ollama
(defvar my/eca-ollama-host
  (let ((host (or (getenv "OLLAMA_HOST") "http://localhost:11434")))
    (if (or (string-prefix-p "http://" host) (string-prefix-p "https://" host))
        host
      (concat "http://" host))))

(defvar my/eca-ollama-api-base
  (replace-regexp-in-string "/+$" "" my/eca-ollama-host)
  "Base host URL used by Ollama server (without trailing slash).")

(defvar my/eca-ollama-api-url
  (concat (replace-regexp-in-string "/+$" "" my/eca-ollama-host) "/v1")
  "OpenAI-compatible base URL for ECA provider config (without trailing slash).")

(defvar my/eca-ollama-model "deepseek-r1:32b")
(defvar my/eca-ollama-process nil
  "Process object for local `ollama serve' started from Emacs.")

(defun my/eca-ollama-installed-models ()
  "Return local Ollama model names from `ollama list`.
If the command is unavailable or no models are installed, return nil."
  (when (executable-find "ollama")
    (let ((lines (cdr (split-string (string-trim (shell-command-to-string "ollama list 2>/dev/null")) "\n" t)))
          (models '()))
      (dolist (line lines)
        (let ((name (car (split-string line " " t))))
          (unless (string-empty-p name)
            (setq models (cons name models)))))
      (nreverse models))))

(defun my/eca--ollama-base-model (model)
  (if (string-match "^.+/\\(.+\\)$" model)
      (match-string 1 model)
    model))

(defun my/eca-set-ollama-model-from-installed ()
  "Set `my/eca-ollama-model` to a local Ollama model and refresh ECA config."
  (interactive)
  (let* ((models (my/eca-ollama-installed-models))
         (selection (if (and models (= 1 (length models)))
                        (car models)
                      (completing-read "Select Ollama model: " models nil t))))
    (unless models
      (user-error "No local Ollama models available"))
    (unless selection
      (user-error "No local Ollama model selected"))
    (setq my/eca-ollama-model (my/eca--ollama-base-model selection))
    (setq eca-chat-custom-model my/eca-ollama-model)
    (message "ECA model set to %s" my/eca-ollama-model)))

(defun my/eca-ollama-running-p ()
  "Return non-nil when local Ollama API responds."
  (and (executable-find "curl")
       (zerop (call-process "curl" nil nil nil
                            "-fsS"
                            (concat my/eca-ollama-host "/api/tags")))))

(defun my/eca-start-ollama-server ()
  "Start local Ollama server in background if it is not running."
  (interactive)
  (if (my/eca-ollama-running-p)
      (message "Ollama is already running at %s" my/eca-ollama-host)
    (unless (executable-find "ollama")
      (user-error "Ollama executable not found"))
    (when (process-live-p my/eca-ollama-process)
      (delete-process my/eca-ollama-process))
    (let ((process-environment (cons (format "OLLAMA_HOST=%s" my/eca-ollama-host)
                                     process-environment)))
      (setq my/eca-ollama-process
            (start-process
             "eca-ollama"
             " *eca-ollama-server*"
             (executable-find "ollama")
             "serve")))
    (message "Starting Ollama: %s" my/eca-ollama-host)
    (run-at-time "0.8 sec" nil
                 (lambda ()
                   (message (if (my/eca-ollama-running-p)
                                "Ollama server started."
                              "Ollama server didn't become available yet. Check `*eca-ollama-server*`."))))))

(defun my/eca-stop-ollama-server ()
  "Stop local Ollama server started by `my/eca-start-ollama-server`."
  (interactive)
  (if (and my/eca-ollama-process (process-live-p my/eca-ollama-process))
      (progn
        (delete-process my/eca-ollama-process)
        (setq my/eca-ollama-process nil)
        (message "Ollama server process stopped."))
    (message "No managed Ollama process found in Emacs.")))

(defun my/eca-chat-with-ollama ()
  "Start Ollama if needed and launch ECA chat."
  (interactive)
  (unless (my/eca-ollama-running-p)
    (my/eca-start-ollama-server))
  (eca))

(defun my/eca-ensure-leader-a-prefix ()
  "Ensure `doom-leader-map` has a keymap at `a` and return it."
  (let ((current (lookup-key doom-leader-map (kbd "a"))))
    (cond
     ((keymapp current) current)
     (t
      (let ((prefix (make-sparse-keymap)))
        (define-key doom-leader-map (kbd "a") prefix)
        (when current
          (define-key prefix (kbd "a") current))
        prefix)))))

(defun my/eca-install-leader-binds ()
  "Force ECA keybinds under `SPC a` safely."
  (when (boundp 'doom-leader-map)
    (let ((a-map (my/eca-ensure-leader-a-prefix)))
      (define-key a-map (kbd "e") #'my/eca-chat-with-ollama)
      (define-key a-map (kbd "O") #'my/eca-start-ollama-server)
      (define-key a-map (kbd "x") #'my/eca-stop-ollama-server)
      (define-key a-map (kbd "s") #'eca-stop)
      (define-key a-map (kbd "r") #'eca-restart)
      (define-key a-map (kbd "w") #'eca-chat-toggle-window)
      (define-key a-map (kbd "c") #'eca-switch-to-chat)
      (define-key a-map (kbd "p") #'eca-switch-to-project-chat)
      (define-key a-map (kbd "n") #'eca-chat-new)
      (define-key a-map (kbd "m") #'eca-chat-select-model)
      (define-key a-map (kbd "a") #'eca-chat-select-agent)
      (define-key a-map (kbd "R") #'eca-chat-reset)
      (define-key a-map (kbd "C") #'eca-chat-clear)
      (define-key a-map (kbd "g") #'eca-workspaces)
      (define-key a-map (kbd "S") #'eca-settings)
      (define-key a-map (kbd "o") #'eca-open-global-config))))

(after! eca
  (setenv "OLLAMA_HOST" my/eca-ollama-host)
  (setenv "OLLAMA_API_BASE" my/eca-ollama-api-base)
  (setenv "OLLAMA_API_URL" my/eca-ollama-api-url)
  (setenv "OLLAMA_CONTEXT_LENGTH" (number-to-string my/ollama-max-context-tokens))
  (setenv "OLLAMA_NUM_CTX" (number-to-string my/ollama-max-context-tokens))
  (let* ((installed (my/eca-ollama-installed-models))
         (installed-base (my/eca--ollama-base-model my/eca-ollama-model))
         (matched (and installed (member installed-base installed))))
    (unless matched
      (if (and installed (= 1 (length installed)))
          (progn
            (setq my/eca-ollama-model (car installed))
            (setq eca-chat-custom-model my/eca-ollama-model)
            (message "ECA model auto-set from installed Ollama model: %s" my/eca-ollama-model))
        (when installed
          (message "ECA model %S not found among local models: %S" my/eca-ollama-model installed)))))
  (setq eca-chat-use-side-window t
        eca-chat-window-side 'right
        eca-chat-window-width 80
        eca-chat-focus-on-open t
        eca-chat-custom-model my/eca-ollama-model
        eca-completion-idle-delay 0.15)
  (my/eca-install-leader-binds))

(add-hook 'doom-after-init-hook #'my/eca-install-leader-binds)

(defun my/eca-verify-runtime ()
  "Show ECA + Doom binding/runtime status in *Messages*.

This prints:
1. Which commands are bound to `SPC a e`, `SPC a O`, `SPC a x`.
2. Current `my/eca-ollama-model`.
3. Current `OLLAMA_HOST` value.
4. Whether `ollama` endpoint responds.
5. Local Ollama models discovered in this session.
"
  (interactive)
  (let ((expected (list (cons (kbd "a e") #'my/eca-chat-with-ollama)
                        (cons (kbd "a O") #'my/eca-start-ollama-server)
                        (cons (kbd "a x") #'my/eca-stop-ollama-server))))
    (if (not (boundp 'doom-leader-map))
        (if (called-interactively-p 'interactive)
            (user-error "doom-leader-map is not initialized yet (run after Doom startup)")
          (error "doom-leader-map is not initialized yet (run after Doom startup)"))
      (my/eca-install-leader-binds)
      (let ((report
             (list :ok t
                   :prefix "SPC a"
                   :model my/eca-ollama-model
                   :ollama-host (getenv "OLLAMA_HOST")
                   :ollama-live (my/eca-ollama-running-p)
                   :installed-models (my/eca-ollama-installed-models)
                   :bindings
                   (mapcar
                    (lambda (item)
                      (let* ((key (car item))
                             (expected-cmd (cdr item))
                             (current (lookup-key doom-leader-map key))
                             (status (eq current expected-cmd)))
                        (list :key (key-description key)
                              :expected expected-cmd
                              :current current
                              :status (if status "ok" "overridden"))))
                    expected))))
        (message "ECA keybinds (SPC a ...): e=%S O=%S x=%S"
                 (where-is-internal 'my/eca-chat-with-ollama doom-leader-map nil t)
                 (where-is-internal 'my/eca-start-ollama-server doom-leader-map nil t)
                 (where-is-internal 'my/eca-stop-ollama-server doom-leader-map nil t))
        (message "ECA model=%S ollama-host=%S" my/eca-ollama-model (getenv "OLLAMA_HOST"))
        (message "ollama endpoint: %s" (if (plist-get report :ollama-live) "live" "not reachable"))
        (dolist (bind (plist-get report :bindings))
          (message "SPC %S -> %S (%s)"
                   (plist-get bind :key)
                   (plist-get bind :current)
                   (plist-get bind :status)))
        report))))
