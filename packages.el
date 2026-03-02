;;; packages.el --- Mojo layer packages and configuration -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Custom Implementation
;; Keywords: mojo, languages, lsp

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file defines the packages and configuration for the Mojo layer.
;; It includes:
;; - Custom mojo-mode for syntax highlighting
;; - LSP integration with mojo-lsp-server
;; - Flycheck integration for syntax checking
;; - YASnippet snippets for Mojo

;;; Code:

(defconst mojo-packages
  '(
    ;; Core mode (local package)
    (mojo-mode :location local)
    
    ;; LSP support
    lsp-mode
    lsp-ui
    
    ;; Syntax checking
    flycheck
    
    ;; Snippets
    yasnippet
    
    ;; REPL integration
    comint
    
    ;; Documentation
    eldoc
    
    ;; Navigation
    imenu
    which-func
    
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
      ;; Evil-style navigation bindings
      (with-eval-after-load 'evil
        (evil-define-key 'normal mojo-mode-map
          (kbd "gd") #'mojo/jump-to-definition
          (kbd "gD") #'mojo/jump-to-definition-fallback
          (kbd "gr") #'mojo/find-references)))))

;; LSP mode configuration
(defun mojo/post-init-lsp-mode ()
  "Initialize lsp-mode for Mojo."
  (add-hook 'mojo-mode-hook #'mojo//setup-lsp)
  
  ;; Register Mojo LSP client
  (with-eval-after-load 'lsp-mode
    (add-to-list 'lsp-language-id-configuration '(mojo-mode . "mojo"))
    
    (lsp-register-client
     (make-lsp-client
      :new-connection (lsp-stdio-connection #'mojo//lsp-server-command)
      :activation-fn (lsp-activate-on "mojo")
      :server-id 'mojo-lsp
      :priority -1
      :initialization-options '()
      :notification-handlers (ht ("mojo/status" #'ignore))
      :request-handlers (ht)
      :action-handlers (ht)
      :major-modes '(mojo-mode)
      :ignore-messages nil
      :ignore-regexps nil))))

(defun mojo//lsp-server-command ()
  "Return the command to start the Mojo LSP server.
Looks for mojo-lsp-server in the following locations:
1. Custom path if mojo-lsp-server-path is set
2. Project-local .pixi/envs/*/bin/mojo-lsp-server
3. Global ~/.pixi (bin and envs)
4. System PATH"
  (let ((server-path (mojo//find-lsp-server)))
    (if server-path
        (list server-path)
      (progn
        (message "Warning: mojo-lsp-server not found. LSP features will be disabled.")
        nil))))

(defun mojo//setup-lsp ()
  "Set up LSP for Mojo mode if enabled."
  (when (and mojo-enable-lsp
             (mojo//lsp-server-command))
    (require 'lsp-mode)
    ;; Reduce request pressure without disabling core LSP features.
    (setq-local lsp-auto-configure nil)
    (setq-local lsp-document-sync-method lsp--sync-full)
    (setq-local lsp-debounce-full-sync-notifications t)
    (setq-local lsp-debounce-full-sync-notifications-interval 2.0)
    (setq-local lsp-idle-delay 1.0)
    (setq-local lsp-enable-on-type-formatting nil)
    (setq-local lsp-enable-indentation nil)
    (setq-local lsp-signature-auto-activate nil)
    (setq-local lsp-before-save-edits nil)
    (setq-local lsp-modeline-code-actions-enable nil)
    (setq-local lsp-eldoc-enable-hover t)
    (setq-local lsp-enable-imenu nil)
    (setq-local lsp-headerline-breadcrumb-enable nil)
    (setq-local lsp-enable-symbol-highlighting nil)
    (setq-local lsp-enable-links nil)
    (setq-local lsp-lens-enable nil)
    (setq-local lsp-semantic-tokens-enable nil)
    (add-hook 'lsp-after-initialize-hook #'mojo/add-lsp-workspace-folders nil t)
    (add-hook 'lsp-configure-hook #'mojo//lsp-configure nil t)
    (when (boundp 'company-idle-delay)
      (setq-local company-idle-delay nil)
      (setq-local company-minimum-prefix-length 2))
    (when (boundp 'corfu-auto)
      (setq-local corfu-auto nil))
    (when (boundp 'corfu-auto-prefix)
      (setq-local corfu-auto-prefix 2))
    (lsp)))

;; LSP UI configuration
(defun mojo/post-init-lsp-ui ()
  "Initialize lsp-ui for Mojo."
  (with-eval-after-load 'lsp-ui
    (add-hook 'mojo-mode-hook #'mojo//setup-lsp-ui)))

(defun mojo//lsp-configure ()
  "Enable LSP completion for Mojo when auto-configure is disabled."
  (when (fboundp 'lsp-completion--enable)
    (lsp-completion--enable)))

(defun mojo//setup-lsp-ui ()
  "Disable lsp-ui noise in Mojo buffers to avoid server crashes."
  (setq-local lsp-ui-doc-enable nil)
  (setq-local lsp-ui-sideline-enable nil)
  (setq-local lsp-ui-sideline-show-hover nil)
  (setq-local lsp-ui-sideline-show-diagnostics nil))

;; Flycheck configuration
(defun mojo/post-init-flycheck ()
  "Initialize flycheck for Mojo."
  (with-eval-after-load 'flycheck
    ;; Add Mojo checker if not already defined
    (unless (flycheck-registered-checker-p 'mojo)
      (flycheck-define-checker mojo
        "A Mojo syntax checker using the mojo compiler."
        ;; Compile as object to avoid requiring a top-level `main`.
        ;; Use source-original to avoid flycheck_* temp files in project dirs.
        :command ("mojo" "build" "--emit" "object" "-o" (eval null-device) source-original)
        :error-patterns
        ((error line-start (file-name) ":" line ":" column ": error: " (message) line-end)
         (error line-start (file-name) ": error: " (message) line-end)
         (warning line-start (file-name) ":" line ":" column ": warning: " (message) line-end)
         (warning line-start (file-name) ": warning: " (message) line-end)
         (info line-start (file-name) ":" line ":" column ": note: " (message) line-end))
        :modes mojo-mode
        :predicate buffer-file-name)
      (add-to-list 'flycheck-checkers 'mojo))
    
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

;; Eldoc configuration
(defun mojo/post-init-eldoc ()
  "Initialize eldoc for Mojo."
  (add-hook 'mojo-mode-hook #'eldoc-mode))

;; Projectile configuration
(defun mojo/post-init-projectile ()
  "Initialize projectile for Mojo projects."
  (with-eval-after-load 'projectile
    ;; Register Mojo project type
    (projectile-register-project-type 
     'mojo 
     '(".pixi" "mojo.toml" "pyproject.toml")
     :compile "mojo build main.mojo"
     :test "mojo run tests -I ."
     :run "mojo run main.mojo"
     :test-suffix "_test"
     :test-prefix "test_")))

;; Comint configuration for REPL
(defun mojo/post-init-comint ()
  "Initialize comint for Mojo REPL."
  ;; Nothing special needed here - handled in mojo-mode
  )

;; Imenu configuration
(defun mojo/post-init-imenu ()
  "Initialize imenu for Mojo."
  (add-hook 'mojo-mode-hook 
            (lambda ()
              (setq imenu-create-index-function 'python-imenu-create-index)
              (imenu-add-menubar-index))))

;; Which-func configuration
(defun mojo/post-init-which-func ()
  "Initialize which-func for Mojo."
  (add-hook 'mojo-mode-hook #'which-function-mode))

;;; packages.el ends here
