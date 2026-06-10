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

(setq doom-theme 'doom-sourcerer)
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

(map! :leader
      :prefix ("e" . "Clojure Command Center")
      :desc "Persist Scope Macro" "p" #'persist-scope
      :desc "Quick Bench Current Expression" "b" #'clj-insert-quick-bench)

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

(defvar my/eca-ollama-model "deepseek-r1:32b")
(defvar my/eca-ollama-process nil
  "Process object for local `ollama serve' started from Emacs.")

(defun my/eca-ollama-running-p ()
  "Return non-nil when local Ollama API responds."
  (and (executable-find "curl")
       (zerop (call-process "curl" nil nil nil
                            "-fsS"
                            (concat my/eca-ollama-host "/api/tags")))))

(defun my/eca-start-ollama-server ()
  "Start local Ollama server in background if it is not running."
  (interactive)
  (if my/eca-ollama-running-p
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

(after! eca
  (setenv "OLLAMA_HOST" my/eca-ollama-host)
  (setenv "OLLAMA_CONTEXT_LENGTH" (number-to-string my/ollama-max-context-tokens))
  (setenv "OLLAMA_NUM_CTX" (number-to-string my/ollama-max-context-tokens))
  (setq eca-chat-use-side-window t
        eca-chat-window-side 'right
        eca-chat-window-width 80
        eca-chat-focus-on-open t
        eca-chat-custom-model my/eca-ollama-model
        eca-completion-idle-delay 0.15)
  (when (boundp 'doom-leader-map)
    (define-key doom-leader-map (kbd "a e") #'my/eca-chat-with-ollama)
    (define-key doom-leader-map (kbd "a O") #'my/eca-start-ollama-server)
    (define-key doom-leader-map (kbd "a x") #'my/eca-stop-ollama-server)
    (define-key doom-leader-map (kbd "a s") #'eca-stop)
    (define-key doom-leader-map (kbd "a r") #'eca-restart)
    (define-key doom-leader-map (kbd "a w") #'eca-chat-toggle-window)
    (define-key doom-leader-map (kbd "a c") #'eca-switch-to-chat)
    (define-key doom-leader-map (kbd "a p") #'eca-switch-to-project-chat)
    (define-key doom-leader-map (kbd "a n") #'eca-chat-new)
    (define-key doom-leader-map (kbd "a m") #'eca-chat-select-model)
    (define-key doom-leader-map (kbd "a a") #'eca-chat-select-agent)
    (define-key doom-leader-map (kbd "a t") #'eca-chat-send-prompt-at-chat)
    (define-key doom-leader-map (kbd "a R") #'eca-chat-reset)
    (define-key doom-leader-map (kbd "a C") #'eca-chat-clear)
    (define-key doom-leader-map (kbd "a g") #'eca-workspaces)
    (define-key doom-leader-map (kbd "a S") #'eca-settings)
    (define-key doom-leader-map (kbd "a o") #'eca-open-global-config)))


(load! "lisp/agent-tdd-workflow.el")

;; Agent TDD workflow defaults
(setq agent-tdd-codex-command "codex")
(setq agent-tdd-default-test-command "make test")
