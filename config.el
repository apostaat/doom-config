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

(setq doom-theme 'doom-vibrant)

;; (setq doom-theme 'doom-solarized-light)
;; (setq doom-font (font-spec :family "Hack Nerd Font Mono"))



;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

(setq org-roam-directory "~/Downloads/MyOrgRoam")

;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

(after! clojure
  (add-hook 'clojure-mode-hook #'enable-paredit-mode)
  (add-hook 'clojurescript-mode-hook #'enable-paredit-mode))

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

;; (after! org
;;   (require 'ob-clojure)
;;   (org-babel-do-load-languages
;;    'org-babel-load-languages
;;    '((emacs-lisp . t)
;;      (clojure . t))))


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
