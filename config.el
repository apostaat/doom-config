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
         ;; Reload agent-jail.core first so on-disk fixes (e.g. resolving prompts
         ;; from tasks/) take effect without manually re-evaluating core.clj in a
         ;; long-running REPL. core is file-state-backed, so reload is cheap/safe.
         (form (format "(do (require 'agent-jail.core :reload) (jail/run-job-md-claude! %s config))"
                       kw)))
    (agent-jail--eval form)
    (message "agent-jail run: %s" kw)))

(defun agent-jail-run-with-screens ()
  "SPC e r f — run the current .md buffer as a claude job like `SPC e r r', but
also attach every screenshot (jpg/png/…) sitting in the .md's folder into the
jail's files/ as significant visual context (the agent is told to view them).
For tasks whose meaning lives in the images and the .md only comments on them.
`(jail/run-md-with-screens! :name config)'."
  (interactive)
  (unless (and buffer-file-name
               (string= (file-name-extension buffer-file-name) "md"))
    (user-error "Not visiting a .md file"))
  (when (buffer-modified-p) (save-buffer))
  (let* ((kw (concat ":" (file-name-base buffer-file-name)))
         (form (format "(do (require 'agent-jail.core :reload) (jail/run-md-with-screens! %s config))"
                       kw)))
    (agent-jail--eval form)
    (message "agent-jail run+screens: %s" kw)))

(defun agent-jail-sequentially-execute (folder &optional start-from)
  "SPC e r s — sequentially execute every prompt .md in FOLDER in one jail.

Opens a `seq-<folder>' tmux tab running
`(agent-jail.sequence/open-sequence! FOLDER)': prompts are natural-sorted
(README/overview/results excluded) and run one by one — deliver prompt, wait
for the agent's done-marker (`touch'), judge (local deepseek by default),
ship on :ship / re-judge after :revise, continue past :escalate. The agent's
chat context is /clear-ed before each new prompt so a long folder doesn't run
out of context. Defaults to the visited buffer's directory. (To attach the
folder's screenshots to a SINGLE .md run, use `SPC e r f' instead.)

With \\[universal-argument] also asks for START-FROM — a filename substring
to RESUME the series from (already-done prompts are skipped)."
  (interactive
   (list (read-directory-name
          "Prompt folder: "
          (and buffer-file-name (file-name-directory buffer-file-name)))
         (when current-prefix-arg
           (read-string "Start from prompt (filename substring): "))))
  (let ((path (directory-file-name (expand-file-name folder))))
    (agent-jail--eval
     (format "(do (require 'agent-jail.sequence :reload) (agent-jail.sequence/open-sequence! \"config.edn\" %S %S))"
             path (or start-from "")))
    (message "agent-jail sequence: %s%s" path
             (if (and start-from (not (string-empty-p start-from)))
                 (format " (from %s)" start-from) ""))))

(defun agent-jail-cleanup-job ()
  "SPC e d — wipe the jail named after the current .md buffer from local data,
preserving accumulated knowledge, and archive the .md into done/.
`~/Work/agent-jail/docs.md' becomes `(jail/cleanup! \"docs\")': the jail's
Claude memory is exported back to its knowledge source, then its job dir
(workspace/state), docker stack and tmux window are removed from
~/.local/share/agent-jail; finally `(jail/archive-md! \"docs\")' moves the
prompt file into a sibling done/ folder. The buffer is killed — its visited
path no longer exists once the file moves."
  (interactive)
  (unless (and buffer-file-name
               (string= (file-name-extension buffer-file-name) "md"))
    (user-error "Not visiting a .md file"))
  (let ((id (file-name-base buffer-file-name)))
    (when (yes-or-no-p (format "Cleanup jail %s (workspace удалится, знание экспортируется, md → done/)? " id))
      (when (buffer-modified-p) (save-buffer))
      ;; cleanup! itself archives the .md into done/; reload core first so the
      ;; on-disk version runs even in a long-lived REPL that predates it.
      (agent-jail--eval
       (format "(do (require 'agent-jail.core :reload) (jail/cleanup! %S))" id))
      (kill-buffer)
      (message "agent-jail cleanup: %s (md → done/)" id))))

(defun agent-jail-execute-in-jail (id)
  "SPC e x — deliver the current .md task into an ALREADY-OPEN jail as a
follow-up prompt, instead of spinning up a new jail (which `SPC e r r' does).

Pick one of the currently open jails; the visited .md is resolved by name and
run in it via `(jail/execute-in-jail! ID NAME)'. For multi-prompt workflows
where a single jail handles several tasks in sequence, all in one workspace."
  (interactive
   (let ((ids (agent-jail--ids)))
     (unless ids (user-error "No open jails"))
     (list (completing-read "Execute in jail: " ids nil t))))
  (unless (and buffer-file-name
               (string= (file-name-extension buffer-file-name) "md"))
    (user-error "Not visiting a .md file"))
  (when (buffer-modified-p) (save-buffer))
  ;; Pass the buffer's ABSOLUTE path (not its basename): execute-in-jail! uses a
  ;; real file verbatim, so any .md on disk works — not only ones under the
  ;; repo's cwd/tasks that the bare-name resolver can find.
  (let ((path (expand-file-name buffer-file-name)))
    ;; Reload core first so the on-disk execute-in-jail! runs even in a
    ;; long-lived REPL that predates it (same pattern as the run/cleanup verbs).
    (agent-jail--eval
     (format "(do (require 'agent-jail.core :reload) (jail/execute-in-jail! %S %S))"
             id path))
    (message "agent-jail execute: %s → jail %s"
             (file-name-base path) id)))

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

;;; agent-jail: remote tracker tasks -> prompts --------------------------------
;; All HTTP/auth/env plumbing lives in `agent-jail.tracker' (Clojure): it reads
;; the envs straight out of deployments/scripts/github_actions.edn and targets
;; napulse.co — so nothing needs configuring here and there are no env vars to
;; set. The commands pick a PROJECT, then a task within it, and drive the Clojure
;; side over the same nREPL used by the other agent-jail verbs. Clojure returns
;; elisp-readable EDN (vectors/strings only, no maps/keywords).

(defun agent-jail--tracker-eval (form)
  "Eval FORM in `agent-jail.work' and return the parsed EDN value.

Auto-loads `agent-jail.tracker' (so it works even if a long-running REPL
predates the work.clj require) and surfaces REPL-side errors instead of
hiding them behind a generic \"no value\" message."
  (let* ((wrapped (format "(do (require 'agent-jail.tracker :reload) %s)" form))
         ;; The first call chains several blocking HTTPS round-trips to
         ;; napulse.co (login -> projects -> tasks); CIDER's default 10s sync
         ;; timeout is too tight for that, so give it room.
         (nrepl-sync-request-timeout 60)
         (res (cider-nrepl-sync-request:eval wrapped nil "agent-jail.work"))
         (val (nrepl-dict-get res "value"))
         (err (nrepl-dict-get res "err"))
         (ex  (or (nrepl-dict-get res "root-ex") (nrepl-dict-get res "ex"))))
    (cond
     (val (car (read-from-string val)))
     ((or err ex)
      (user-error "agent-jail.tracker error: %s" (string-trim (or err ex))))
     (t (user-error "No REPL value (is CIDER connected to agent-jail?)")))))

(defun agent-jail--tracker-alist (form)
  "Eval FORM (returns [[LABEL ID]…]) and turn it into a (LABEL . ID) alist."
  (mapcar (lambda (v) (cons (aref v 0) (aref v 1)))
          (append (agent-jail--tracker-eval form) nil)))

(defun agent-jail--tracker-pick (verb)
  "Pick a PROJECT, then a «к выполнению» task in it.
Returns a plist (:project-id P :task-id T) for VERB (shown in the prompts)."
  (let* ((projects (agent-jail--tracker-alist "(agent-jail.tracker/projects-edn)"))
         (_ (unless projects (user-error "No projects visible")))
         (pname (completing-read (format "%s — project: " verb) projects nil t))
         (pid (cdr (assoc pname projects)))
         (tasks (agent-jail--tracker-alist
                 (format "(agent-jail.tracker/todo-tasks-edn %S)" pid)))
         (_ (unless tasks
              (user-error "No «к выполнению» tasks in %s" pname)))
         (tname (completing-read (format "%s — task: " verb) tasks nil t)))
    (list :project-id pid :task-id (cdr (assoc tname tasks)))))

(defvar agent-jail-tracker-base-url "https://napulse.co"
  "Base URL of the task tracker, used to open a task's discussion.")

(defun agent-jail-plan-remote-task (project-id id)
  "SPC e t p — «plan remote task».
Pick a project, then navigate its «к выполнению» tasks; Enter opens the task's
discussion in the browser and launches (in ~/Work) a claude session that
develops the ideal prompt into agent-jail/tasks/<slug>.md — it does NOT run the
task. Refine/run the result afterwards."
  (interactive (let ((s (agent-jail--tracker-pick "Plan")))
                 (list (plist-get s :project-id) (plist-get s :task-id))))
  (browse-url (format "%s/tasks?projectId=%s&taskId=%s"
                      agent-jail-tracker-base-url project-id id))
  (agent-jail--eval
   (format "(do (require 'agent-jail.tracker :reload) (agent-jail.tracker/plan! %S %S config))"
           project-id id))
  (message "agent-jail: prompt-development session started for task %s" id))

(defun agent-jail-execute-remote-task (project-id id)
  "SPC e t e — «execute remote task».
Pick a project, then a «к выполнению» task, and run its text as a prompt
immediately as a claude job (like SPC e r does for a local .md)."
  (interactive (let ((s (agent-jail--tracker-pick "Execute")))
                 (list (plist-get s :project-id) (plist-get s :task-id))))
  (agent-jail--eval
   (format "(do (require 'agent-jail.tracker :reload) (agent-jail.tracker/execute! %S %S config))"
           project-id id))
  (message "agent-jail execute remote task: %s" id))

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

;; Clear prior single-key bindings on `e s`/`e j`/`e r` (from an earlier reload)
;; so they can be turned into sub-prefixes without "starts with non-prefix key"
;; errors.
(map! :leader :prefix "e" "s" nil "j" nil "r" nil)

(map! :leader
      :prefix ("e" . "Clojure Command Center")
      :desc "Persist Scope Macro" "p" #'persist-scope
      :desc "Quick Bench Current Expression" "b" #'clj-insert-quick-bench
      :desc "agent-jail: execute in open jail" "x" #'agent-jail-execute-in-jail
      :desc "agent-jail: abort (stop) job"  "a" #'agent-jail-stop-job
      :desc "agent-jail: cleanup jail (keep knowledge)" "d" #'agent-jail-cleanup-job
      :desc "agent-jail: fix CI/CD"         "f" #'agent-jail-fix-ci-cd
      :desc "agent-jail: check lint+test"   "c" #'agent-jail-check-lint-test
      :desc "agent-jail: reclaim disk"      "R" #'agent-jail-reclaim
      (:prefix ("r" . "agent-jail: run")
       :desc "run job (claude)"        "r" #'agent-jail-run-job-claude
       :desc "sequentially execute folder" "s" #'agent-jail-sequentially-execute
       :desc "run md + folder screens" "f" #'agent-jail-run-with-screens)
      (:prefix ("j" . "agent-jail: judge")
       :desc "local (deepseek-r1:32b)" "l" #'agent-jail-judge-local
       :desc "claude"                  "c" #'agent-jail-judge-claude)
      (:prefix ("s" . "agent-jail: ship")
       :desc "ship local"     "l" #'agent-jail-ship-job
       :desc "ship and ship"  "s" #'agent-jail-ship-push-job)
      (:prefix ("t" . "agent-jail: remote task")
       :desc "plan remote task"    "p" #'agent-jail-plan-remote-task
       :desc "execute remote task" "e" #'agent-jail-execute-remote-task))

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
               '(elixir-mode . ("/Users/artemapostatov/elixir-ls/release/language_server.sh")))
  ;; TypeScript 7+ (нативный, tsgo) несёт LSP в самом tsc (`tsc --lsp`);
  ;; typescript-language-server с ним несовместим — используем его только
  ;; как фолбэк для проектов на TS <7.
  (defun my/ts-lsp-contact (&optional _interactive)
    (let* ((root (or (when-let ((proj (project-current)))
                       (project-root proj))
                     default-directory))
           (tsc (expand-file-name "node_modules/.bin/tsc" root)))
      (if (and (file-executable-p tsc)
               (with-temp-buffer
                 (ignore-errors (call-process tsc nil t nil "--version"))
                 (goto-char (point-min))
                 (re-search-forward "Version \\([0-9]+\\)" nil t)
                 (>= (string-to-number (match-string 1)) 7)))
          (list tsc "--lsp" "--stdio")
        '("typescript-language-server" "--stdio"))))
  (add-to-list 'eglot-server-programs
               '((js-mode js-ts-mode typescript-mode typescript-ts-mode tsx-ts-mode) . my/ts-lsp-contact)))

;; Подсветка стандартной библиотеки CL: font-lock-cl (пакет cl-font-lock) знает
;; все символы ANSI CL — функции, переменные, типы, декларации; регистрирует
;; keywords для lisp-mode на загрузке, minor-mode у него нет.
;; lisp-extra-font-lock дополнительно красит квотированные формы и связанные
;; переменные (let/lambda/destructuring-bind).
(use-package! font-lock-cl
  :after lisp-mode)

(use-package! lisp-extra-font-lock
  :hook (lisp-mode . lisp-extra-font-lock-mode))

(after! lisp-mode
  (add-to-list 'auto-mode-alist '("\\.opmo\\'" . lisp-mode)))

(after! sly
  ;; Флекс-комплишен символов от живого SBCL: "mvb" → multiple-value-bind,
  ;; "w-o-t-s" → with-output-to-string. Работает при подключённом REPL (M-x sly).
  (setq sly-complete-symbol-function #'sly-flex-completions))

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

;;; hyperbole: implicit buttons, HyRolo, HyControl, Koutliner ------------------

(use-package! hyperbole
  ;; Load after startup on first keypress; `hyperbole-mode' is a global minor
  ;; mode whose keymap holds all default bindings (M-RET, C-h h, C-h A ...).
  :hook (doom-first-input . hyperbole-mode)
  :init
  ;; In org buffers M-RET stays `org-meta-return' everywhere EXCEPT on
  ;; Hyperbole buttons and org links, where the Action Key takes over.
  ;; Set to t to let the Action Key handle all org contexts instead.
  (setq hsys-org-enable-smart-keys 'buttons))

(map! :leader
      (:prefix ("y" . "hyperbole")
       :desc "Action Key at point"        "y" #'action-key
       :desc "Assist Key at point"        "u" #'assist-key
       :desc "Main menu (C-h h)"          "m" #'hyperbole
       :desc "Act on named button"        "a" #'hui:hbut-act
       :desc "Create explicit button"     "c" #'hui:ebut-create
       :desc "Create global button"       "g" #'hui:gbut-create
       :desc "Create implicit button"     "i" #'hui:ibut-create
       :desc "Select thing (grow region)" "." #'hui-select-thing
       :desc "Search web"                 "/" #'hui-search-web
       (:prefix ("r" . "hyrolo")
        :desc "Search (fgrep)"     "r" #'hyrolo-fgrep
        :desc "Search (regexp)"    "g" #'hyrolo-grep
        :desc "Search word"        "w" #'hyrolo-word
        :desc "Add entry"          "a" #'hyrolo-add
        :desc "Edit entry"         "e" #'hyrolo-edit
        :desc "Search org files"   "o" #'hyrolo-org
        :desc "Search org-roam"    "R" #'hyrolo-org-roam)
       (:prefix ("w" . "hycontrol")
        :desc "Windows control mode" "w" #'hycontrol-enable-windows-mode
        :desc "Frames control mode"  "f" #'hycontrol-enable-frames-mode
        :desc "Windows grid"         "g" #'hycontrol-windows-grid
        :desc "Grid by major mode"   "m" #'hycontrol-windows-grid-by-major-mode)
       (:prefix ("k" . "koutliner")
        :desc "Find/create koutline" "k" #'kfile:find
        :desc "Insert klink"         "l" #'klink:create
        :desc "Import file to kotl"  "i" #'kimport:file
        :desc "Example koutline"     "e" #'kotl-mode:example)))
