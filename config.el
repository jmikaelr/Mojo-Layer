;;; config.el --- Mojo layer configuration -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Richard Johnsson

;; Author: Richard Johnsson
;; Keywords: mojo, languages, configuration

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file contains configuration variables and settings for the Mojo layer.
;; Users can customize these variables in their dotspacemacs configuration.

;;; Code:

;; Layer configuration variables

(declare-function mojo-beginning-of-defun "mojo-mode")
(declare-function mojo-end-of-defun "mojo-mode")

(defgroup mojo-layer nil
  "Configuration variables for the Mojo layer."
  :group 'spacemacs
  :prefix "mojo-")

(defcustom mojo-lsp-enabled t
  "If non-nil, start LSP automatically in Mojo buffers.
Set to nil to disable LSP (useful when mojo-lsp-server is unstable)."
  :type 'boolean
  :group 'mojo-layer)

(defcustom mojo-format-on-save nil
  "If non-nil, format Mojo buffers on save using `mojo format`."
  :type 'boolean
  :group 'mojo-layer)

(defcustom mojo-stdlib-path nil
  "Path to the Mojo stdlib source tree.
When this directory exists, the layer uses it for fallback navigation
so definition lookup can jump into stdlib sources."
  :type '(choice (const :tag "Disabled" nil)
                 (string :tag "Path to stdlib/std"))
  :group 'mojo-layer)

(defcustom mojo-extra-source-paths nil
  "Additional Mojo source directories for navigation.
Each path is expanded and used by fallback definition/reference search."
  :type '(repeat string)
  :group 'mojo-layer)

(defcustom mojo-indent-offset 4
  "Number of spaces for each indentation step in Mojo mode."
  :type 'integer
  :group 'mojo-layer)

(defcustom mojo-repl-arguments '("repl")
  "Arguments to pass to the mojo command when starting the REPL."
  :type '(repeat string)
  :group 'mojo-layer)

(defcustom mojo-build-arguments '()
  "Default arguments to pass to `mojo build`."
  :type '(repeat string)
  :group 'mojo-layer)

(defcustom mojo-use-project-pixi t
  "If non-nil, run Mojo CLI commands through the current project's pixi setup.
Resolution order:
1. `pixi run [--no-progress] mojo` from project root
2. project-local `.pixi/envs/*/bin/mojo`"
  :type 'boolean
  :group 'mojo-layer)

(defcustom mojo-use-global-pixi t
  "If non-nil, prefer ~/.pixi-provided Mojo tools before generic PATH fallback."
  :type 'boolean
  :group 'mojo-layer)

(defcustom mojo-global-pixi-env-priority '("mojo" "default")
  "Preferred env names under ~/.pixi/envs for fallback tool resolution."
  :type '(repeat string)
  :group 'mojo-layer)

(defcustom mojo-pixi-no-progress nil
  "If non-nil, pass `--no-progress` when invoking `pixi run`."
  :type 'boolean
  :group 'mojo-layer)

(defcustom mojo-run-arguments '()
  "Default arguments to pass to `mojo run`."
  :type '(repeat string)
  :group 'mojo-layer)

(defcustom mojo-run-project-entrypoint nil
  "Entrypoint file for `mojo run` project execution.
When nil, the layer auto-detects an entrypoint from
`mojo-run-entrypoint-candidates`."
  :type '(choice (const :tag "Auto-detect" nil)
                 (string :tag "Entrypoint path (relative to project root)"))
  :group 'mojo-layer)

(defcustom mojo-run-entrypoint-candidates
  '("main.mojo" "src/main.mojo" "app.mojo" "bench.mojo")
  "Candidate files used to auto-detect a project entrypoint for `mojo run`."
  :type '(repeat string)
  :group 'mojo-layer)

(defcustom mojo-test-arguments '()
  "Default options passed before the test target when running `mojo run`."
  :type '(repeat string)
  :group 'mojo-layer)

(defcustom mojo-test-project-target nil
  "Path used by `mojo/test-project` with `mojo run`.
When nil, the layer auto-detects from `mojo-test-target-candidates`."
  :type '(choice (const :tag "Auto-detect" nil)
                 (string :tag "Path relative to project root"))
  :group 'mojo-layer)

(defcustom mojo-test-target-candidates
  '("tests" "test" "tests/main.mojo" "test/main.mojo")
  "Candidate targets used to auto-detect a project test target."
  :type '(repeat string)
  :group 'mojo-layer)

(defcustom mojo-test-add-project-include t
  "If non-nil, pass `-I <project-root>` for test runs."
  :type 'boolean
  :group 'mojo-layer)

(defcustom mojo-clean-command nil
  "Optional custom command used by `mojo/clean-project`.
When nil, the layer runs `pixi clean` for pixi projects when available."
  :type '(choice (const :tag "Use pixi clean when available" nil)
                 (string :tag "Custom clean command"))
  :group 'mojo-layer)

;; Spacemacs leader key bindings configuration

(spacemacs|define-jump-handlers mojo-mode)

;; Evil text objects (if evil is enabled)
(when (configuration-layer/layer-used-p 'spacemacs-evil)
  (with-eval-after-load 'evil
    (evil-define-text-object mojo-inner-function (count &optional beg end type)
      "Select inner Mojo function."
      (let ((b (save-excursion 
                 (mojo-beginning-of-defun 1)
                 (point)))
            (e (save-excursion
                 (mojo-end-of-defun 1)
                 (point))))
        (evil-range b e)))
    
    (evil-define-text-object mojo-outer-function (count &optional beg end type)
      "Select outer Mojo function (including decorators)."
      (let ((b (save-excursion
                 (mojo-beginning-of-defun 1)
                 ;; Go back to capture decorators
                 (while (and (not (bobp))
                            (progn (forward-line -1)
                                   (beginning-of-line)
                                   (looking-at "\\s-*@"))))
                 ;; The loop exited either at bobp or on a non-decorator line.
                 ;; If we're on a non-decorator line, advance to the first decorator.
                 (unless (or (bobp) (looking-at "\\s-*@"))
                   (forward-line 1))
                 (point)))
            (e (save-excursion
                 (mojo-end-of-defun 1)
                 (point))))
        (evil-range b e)))
    
    (evil-define-key '(visual operator) mojo-mode-map
      "if" #'mojo-inner-function
      "af" #'mojo-outer-function)))

;;; config.el ends here
