;;; packages.el --- Mojo layer packages and configuration -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Richard Johnsson

;; Author: Richard Johnsson
;; Keywords: mojo, languages

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file defines the packages and configuration for the Mojo layer.
;; It includes:
;; - Custom mojo-mode for syntax highlighting
;; - Flycheck integration for syntax checking
;; - YASnippet snippets for Mojo
;; - Company completion (dabbrev-code)
;; - Projectile project support

;;; Code:

(defconst mojo-packages
  '(
    ;; Core mode (local package)
    (mojo-mode :location local)

    ;; LSP (uses lsp-mode's built-in Mojo client)
    lsp-mode

    ;; Completion (dabbrev-code for keyword/symbol completion without LSP)
    company

    ;; Syntax checking
    flycheck

    ;; Snippets
    yasnippet

    ;; Project support
    projectile
    )
  "The list of Lisp packages required by the Mojo layer.")

;; Local mojo-mode package
(defun mojo/init-mojo-mode ()
  "Initialize mojo-mode package."
  (use-package mojo-mode
    :mode ("\\.mojo\\'" . mojo-mode)
    :mode ("\\.🔥\\'" . mojo-mode)
    :interpreter "mojo"
    :config
    (progn
      ;; Set up key bindings
      (mojo/set-leader-keys)
      ;; Register xref backend for M-. / gd navigation (ripgrep-based search).
      (add-hook 'mojo-mode-hook
                (lambda ()
                  (add-hook 'xref-backend-functions #'mojo//xref-backend nil t)
                  (setq-local xref-show-definitions-function
                              #'mojo//xref-show-defs-other-window)))
      ;; Eldoc and imenu (built-in, no separate package entry needed)
      (add-hook 'mojo-mode-hook #'eldoc-mode)
      (add-hook 'mojo-mode-hook #'imenu-add-menubar-index)
      ;; Evil-style navigation bindings
      (with-eval-after-load 'evil
        (evil-define-key 'normal mojo-mode-map
          (kbd "gd") #'mojo/jump-to-definition
          (kbd "gD") #'mojo/jump-to-definition-fallback
          (kbd "gr") #'mojo/find-references)))))

;; LSP configuration
(defun mojo/post-init-lsp-mode ()
  "Auto-start lsp-mode's built-in Mojo client in mojo buffers."
  ;; Disable LSP features that crash the nightly mojo-lsp-server:
  ;; hover, signature help, and completion (server returns "invalid request").
  (add-hook 'mojo-mode-hook
            (lambda ()
              (setq-local lsp-completion-provider :none)
              (setq-local lsp-eldoc-enable-hover nil)
              (setq-local lsp-ui-doc-enable nil)
              (setq-local lsp-ui-sideline-enable nil)
              (setq-local lsp-signature-auto-activate nil)))
  ;; After LSP initializes, strip out any hover-related eldoc functions
  ;; it registered, since the nightly server crashes on hover+didChange.
  (add-hook 'lsp-configure-hook
            (lambda ()
              (when (derived-mode-p 'mojo-mode)
                (setq-local eldoc-documentation-functions
                            (remq 'lsp-eldoc-function
                                  eldoc-documentation-functions))
                (when (fboundp 'lsp-ui-doc-mode)
                  (lsp-ui-doc-mode -1))
                (when (fboundp 'lsp-ui-sideline-mode)
                  (lsp-ui-sideline-mode -1)))))
  (add-hook 'mojo-mode-hook #'mojo//maybe-start-lsp))

(defun mojo//maybe-start-lsp ()
  "Start LSP only when enabled and the buffer is inside a project, not in stdlib."
  (when (and mojo-lsp-enabled
             (buffer-file-name))
    (let ((file (buffer-file-name)))
      (unless (and (boundp 'mojo-stdlib-path)
                   mojo-stdlib-path
                   (not (string-empty-p mojo-stdlib-path))
                   (string-prefix-p
                    (file-truename (expand-file-name mojo-stdlib-path))
                    (file-truename file)))
        (lsp)))))

;; Company configuration
(defun mojo/post-init-company ()
  "Register company backends for Mojo mode."
  (spacemacs|add-company-backends
    :backends (company-dabbrev-code company-keywords)
    :modes mojo-mode)
  ;; Prevent Spacemacs from re-adding company-capf (which sends broken
  ;; completion requests to the nightly mojo-lsp-server).
  ;; Limit dabbrev-code to current buffer only (no cross-buffer pollution).
  (add-hook 'mojo-mode-local-vars-hook
            (lambda ()
              (setq-local company-backends
                          '((company-dabbrev-code company-keywords)))
              (setq-local company-dabbrev-code-other-buffers nil))
            90))

;; Flycheck configuration

(defun mojo//flycheck-pixi-prefix-args ()
  "Return pixi prefix args for flycheck, or nil for plain mojo.
When pixi is used, returns e.g. (\"run\" \"mojo\") which flycheck splices
into the command list between the executable and \"build\"."
  (condition-case nil
      (pcase-let ((`(,_program . ,prefix-args) (mojo//resolve-mojo-program)))
        prefix-args)
    (error nil)))

(defun mojo//flycheck-executable ()
  "Return the program name for the flycheck mojo checker."
  (condition-case nil
      (car (mojo//resolve-mojo-program))
    (error "mojo")))

(defun mojo/post-init-flycheck ()
  "Initialize flycheck for Mojo."
  (with-eval-after-load 'flycheck
    ;; Add Mojo checker if not already defined
    (unless (flycheck-registered-checker-p 'mojo)
      (flycheck-define-checker mojo
        "A Mojo syntax checker using the mojo compiler."
        ;; Compile as object to avoid requiring a top-level `main`.
        ;; Use source-original to avoid flycheck_* temp files in project dirs.
        ;; The (eval ...) form splices pixi prefix args (e.g. "run" "mojo")
        ;; when using pixi, or nothing for plain mojo invocation.
        :command ("mojo"
                  (eval (mojo//flycheck-pixi-prefix-args))
                  "build" "--emit" "object" "-o" (eval null-device)
                  source-original)
        :error-patterns
        ((error line-start (file-name) ":" line ":" column ": error: " (message) line-end)
         (error line-start (file-name) ": error: " (message) line-end)
         (warning line-start (file-name) ":" line ":" column ": warning: " (message) line-end)
         (warning line-start (file-name) ": warning: " (message) line-end)
         (info line-start (file-name) ":" line ":" column ": note: " (message) line-end))
        :modes mojo-mode
        :predicate buffer-file-name)
      (add-to-list 'flycheck-checkers 'mojo))

    ;; Set the flycheck executable buffer-locally to the resolved program
    ;; (e.g. "pixi" or "/path/to/mojo") so flycheck finds the right binary.
    (add-hook 'mojo-mode-hook
              (lambda ()
                (setq-local flycheck-mojo-executable
                            (mojo//flycheck-executable))))

    ;; Enable flycheck in mojo-mode
    (add-hook 'mojo-mode-hook #'flycheck-mode)))

;; YASnippet configuration
(defun mojo/post-init-yasnippet ()
  "Initialize yasnippet for Mojo."
  (with-eval-after-load 'yasnippet
    ;; Add Mojo snippets directory
    (let ((snippets-dir (expand-file-name "snippets" 
                                          (configuration-layer/get-layer-path 'mojo))))
      (when (file-directory-p snippets-dir)
        (add-to-list 'yas-snippet-dirs snippets-dir)))
    
    ;; Enable yas-minor-mode in mojo-mode
    (add-hook 'mojo-mode-hook #'yas-minor-mode)))

;; Projectile configuration

(defun mojo//projectile-mojo-cmd ()
  "Return mojo command prefix for projectile, falling back to plain mojo."
  (condition-case nil
      (mojo//resolve-mojo-command)
    (error "mojo")))

(defun mojo//projectile-compile-command ()
  "Return compile command for projectile."
  (let ((cmd (mojo//projectile-mojo-cmd))
        (entry (mojo//project-entrypoint)))
    (format "%s build %s" cmd
            (if entry (shell-quote-argument entry) "main.mojo"))))

(defun mojo//projectile-test-command ()
  "Return test command for projectile."
  (let ((cmd (mojo//projectile-mojo-cmd))
        (target (mojo//project-test-target)))
    (if target
        (format "%s run -I %s %s" cmd
                (shell-quote-argument (mojo//project-root))
                (shell-quote-argument target))
      (format "%s run tests -I ." cmd))))

(defun mojo//projectile-run-command ()
  "Return run command for projectile."
  (let ((cmd (mojo//projectile-mojo-cmd))
        (entry (mojo//project-entrypoint)))
    (format "%s run %s" cmd
            (if entry (shell-quote-argument entry) "main.mojo"))))

(defun mojo/post-init-projectile ()
  "Initialize projectile for Mojo projects."
  (with-eval-after-load 'projectile
    ;; Register Mojo project type with dynamic commands that respect pixi.
    (projectile-register-project-type
     'mojo
     '(".pixi" "mojo.toml" "pyproject.toml")
     :compile #'mojo//projectile-compile-command
     :test #'mojo//projectile-test-command
     :run #'mojo//projectile-run-command
     :test-suffix "_test"
     :test-prefix "test_")))

;;; packages.el ends here
