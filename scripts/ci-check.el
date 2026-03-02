;;; ci-check.el --- CI checks for Mojo layer -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;;; Commentary:

;; Runs basic static checks and ERT tests for this layer.

;;; Code:

(require 'bytecomp)
(require 'cl-lib)

(defconst mojo-ci-root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))
  "Repository root used by CI checks.")

;; Minimal stubs for Spacemacs-specific helpers referenced by layer files.
(unless (fboundp 'configuration-layer/layer-used-p)
  (defun configuration-layer/layer-used-p (&rest _args)
    "Stub used in CI context."
    nil))

(unless (fboundp 'configuration-layer/get-layer-path)
  (defun configuration-layer/get-layer-path (&rest _args)
    "Stub used in CI context."
    mojo-ci-root))

(unless (fboundp 'spacemacs/declare-prefix-for-mode)
  (defun spacemacs/declare-prefix-for-mode (&rest _args)
    "Stub used in CI context."
    nil))

(unless (fboundp 'spacemacs/set-leader-keys-for-major-mode)
  (defun spacemacs/set-leader-keys-for-major-mode (&rest _args)
    "Stub used in CI context."
    nil))

(unless (fboundp 'spacemacs|define-jump-handlers)
  (defmacro spacemacs|define-jump-handlers (&rest _args)
    "Stub used in CI context."
    nil))

(unless (fboundp 'evil-define-text-object)
  (defmacro evil-define-text-object (&rest _args)
    "Stub used in CI context."
    nil))

(unless (fboundp 'evil-range)
  (defun evil-range (&rest _args)
    "Stub used in CI context."
    nil))

(defvar evil-inner-text-objects-map (make-sparse-keymap))
(defvar evil-outer-text-objects-map (make-sparse-keymap))

(defun mojo-ci--check-parens (file)
  "Run `check-parens' on FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)
    (check-parens)))

(defun mojo-ci--byte-compile (file)
  "Byte-compile FILE."
  (let ((byte-compile-error-on-warn nil))
    (byte-compile-file file)))

(defun mojo-ci--path (&rest segments)
  "Build path under `mojo-ci-root' from SEGMENTS."
  (expand-file-name (mapconcat #'identity segments "/") mojo-ci-root))

(let ((files (list (mojo-ci--path "config.el")
                   (mojo-ci--path "funcs.el")
                   (mojo-ci--path "packages.el")
                   (mojo-ci--path "local" "mojo-mode" "mojo-mode.el")
                   (mojo-ci--path "test" "mojo-layer-tests.el"))))
  (dolist (file files)
    (mojo-ci--check-parens file))
  (dolist (file (list (mojo-ci--path "config.el")
                      (mojo-ci--path "funcs.el")
                      (mojo-ci--path "local" "mojo-mode" "mojo-mode.el")))
    (mojo-ci--byte-compile file)))

(load-file (mojo-ci--path "test" "mojo-layer-tests.el"))
(ert-run-tests-batch-and-exit t)

;;; ci-check.el ends here
