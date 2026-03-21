;;; funcs.el --- Helper functions for Mojo layer -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Richard Johnsson

;; Author: Richard Johnsson
;; Keywords: mojo, languages, functions

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file contains helper functions used by the Mojo layer.
;; These functions provide additional functionality for working with
;; Mojo code, including project management, build commands, and more.

;;; Code:

(require 'cl-lib)
(require 'comint)
(require 'subr-x)
(require 'xref)

(declare-function mojo-beginning-of-defun "mojo-mode")
(declare-function mojo-end-of-defun "mojo-mode")

;; Layer variables are defined in config.el and read here.
(defvar mojo-format-on-save)
(defvar mojo-indent-offset)
(defvar mojo-repl-arguments)
(defvar mojo-build-arguments)
(defvar mojo-use-project-pixi)
(defvar mojo-use-global-pixi)
(defvar mojo-global-pixi-env-priority)
(defvar mojo-pixi-no-progress)
(defvar mojo-run-arguments)
(defvar mojo-run-project-entrypoint)
(defvar mojo-run-entrypoint-candidates)
(defvar mojo-test-arguments)
(defvar mojo-test-project-target)
(defvar mojo-test-target-candidates)
(defvar mojo-test-add-project-include)
(defvar mojo-clean-command)
(defvar mojo-stdlib-path)
(defvar mojo-extra-source-paths)

;; Project Management

(defun mojo//project-root ()
  "Find the root of the current Mojo project.
Looks for .pixi directory, mojo.toml, or pyproject.toml."
  (or (and (fboundp 'projectile-project-root)
           (ignore-errors (projectile-project-root)))
      (locate-dominating-file default-directory ".pixi")
      (locate-dominating-file default-directory "mojo.toml")
      (locate-dominating-file default-directory "pyproject.toml")
      default-directory))

(defun mojo//normalize-directory (path)
  "Expand and canonicalize PATH when it is an existing directory."
  (when (and path
             (not (string-empty-p path)))
    (let ((expanded (file-name-as-directory (expand-file-name path))))
      (when (file-directory-p expanded)
        (file-truename expanded)))))

(defun mojo//configured-source-paths ()
  "Return existing configured source paths for Mojo navigation."
  (let ((paths nil)
        (configured (append (when (boundp 'mojo-stdlib-path)
                              (list mojo-stdlib-path))
                            (when (boundp 'mojo-extra-source-paths)
                              mojo-extra-source-paths))))
    (dolist (path configured)
      (let ((normalized (mojo//normalize-directory path)))
        (when normalized
          (push normalized paths))))
    (delete-dups (nreverse paths))))

(defun mojo//definition-search-paths ()
  "Return project and configured source paths for fallback navigation."
  (let ((project-root (mojo//normalize-directory (mojo//project-root))))
    (delete-dups
     (delq nil (append (list project-root)
                       (mojo//configured-source-paths))))))

(defun mojo//file-in-project-p (file)
  "Check if FILE exists in the project root."
  (let ((root (mojo//project-root)))
    (and root (file-exists-p (expand-file-name file root)))))

;; Build Commands

(defun mojo//project-has-pixi-p ()
  "Return non-nil when current project appears to be a pixi project."
  (let ((root (mojo//project-root)))
    (and root
         (or (file-exists-p (expand-file-name "pixi.toml" root))
             (file-exists-p (expand-file-name "pixi.lock" root))
             (file-directory-p (expand-file-name ".pixi" root))))))

(defun mojo//first-executable-path (paths)
  "Return first executable path from PATHS, or nil."
  (cl-find-if #'file-executable-p paths))

(defun mojo//pixi-env-tool-candidates (envs-root tool-name &optional preferred-envs)
  "Return candidate TOOL-NAME paths under ENVS-ROOT.
PREFERRED-ENVS are env names to check first."
  (let ((candidates nil))
    (when (file-directory-p envs-root)
      (dolist (env preferred-envs)
        (push (expand-file-name (format "%s/bin/%s" env tool-name) envs-root)
              candidates))
      (dolist (env-dir (directory-files envs-root t "^[^.]" t))
        (when (file-directory-p env-dir)
          (push (expand-file-name (format "bin/%s" tool-name) env-dir)
                candidates))))
    (delete-dups (nreverse candidates))))

(defun mojo//project-pixi-tool-path (tool-name)
  "Return project-local pixi TOOL-NAME path if executable."
  (let ((root (mojo//project-root)))
    (when root
      (let* ((envs-root (expand-file-name ".pixi/envs" root))
             (candidates (append
                          (list (expand-file-name
                                 (format ".pixi/envs/default/bin/%s" tool-name)
                                 root))
                          (mojo//pixi-env-tool-candidates envs-root tool-name))))
        (mojo//first-executable-path candidates)))))

(defun mojo//project-pixi-mojo-path ()
  "Return project-local pixi mojo path if executable, otherwise nil."
  (mojo//project-pixi-tool-path "mojo"))

(defun mojo//global-pixi-tool-path (tool-name)
  "Return global pixi TOOL-NAME path if executable."
  (let* ((pixi-root (expand-file-name "~/.pixi"))
         (envs-root (expand-file-name "envs" pixi-root))
         (candidates (append
                      (list (expand-file-name (format "bin/%s" tool-name) pixi-root))
                      (mojo//pixi-env-tool-candidates
                       envs-root
                       tool-name
                       mojo-global-pixi-env-priority))))
    (mojo//first-executable-path candidates)))

(defun mojo//resolve-mojo-program ()
  "Return `(PROGRAM . ARGS)' used to invoke mojo CLI."
  (let ((project-pixi (and mojo-use-project-pixi
                           (mojo//project-has-pixi-p)))
        (project-mojo (and mojo-use-project-pixi
                           (mojo//project-pixi-mojo-path)))
        (global-mojo (and mojo-use-global-pixi
                          (mojo//global-pixi-tool-path "mojo")))
        (pixi-args (append '("run")
                           (when mojo-pixi-no-progress
                             '("--no-progress"))
                           '("mojo"))))
    (cond
     ((and project-pixi (executable-find "pixi"))
      (cons "pixi" pixi-args))
     (project-mojo
      (cons project-mojo nil))
     (global-mojo
      (cons global-mojo nil))
     (project-pixi
      (user-error "This project uses pixi but neither `pixi` nor project `.pixi` mojo is available"))
     ((executable-find "mojo")
      (cons "mojo" nil))
     (t
      (user-error "No `mojo` executable found")))))

(defun mojo//resolve-mojo-command ()
  "Return shell command prefix used to invoke mojo CLI."
  (pcase-let ((`(,program . ,prefix-args) (mojo//resolve-mojo-program)))
    (string-join
     (delq nil
           (list (shell-quote-argument program)
                 (let ((quoted (mojo//quoted-args prefix-args)))
                   (unless (string-empty-p quoted)
                     quoted))))
     " ")))

(defun mojo//quoted-args (arguments)
  "Return ARGUMENTS shell-quoted and joined by spaces."
  (mapconcat #'shell-quote-argument (or arguments '()) " "))

(defvar mojo--last-test-command nil
  "Last command executed by Mojo test helpers.")

(defun mojo//mojo-command (subcommand &optional arguments target)
  "Return a shell command for mojo SUBCOMMAND.
ARGUMENTS is a list of CLI arguments. TARGET is an optional file/path."
  (string-join
   (delq nil
         (list (mojo//resolve-mojo-command)
               subcommand
               (let ((quoted (mojo//quoted-args arguments)))
                 (unless (string-empty-p quoted)
                   quoted))
               (when target
                 (shell-quote-argument target))))
   " "))

(defun mojo//compile-command (subcommand &optional arguments target)
  "Run `compile' with mojo SUBCOMMAND.
ARGUMENTS and TARGET are passed to `mojo//mojo-command'."
  (let* ((default-directory (mojo//project-root))
         (command (mojo//mojo-command subcommand arguments target)))
    (compile command)
    command))

(defun mojo//project-entrypoint ()
  "Return project entrypoint path for `mojo run`, or nil.
Uses `mojo-run-project-entrypoint` when set, otherwise checks
`mojo-run-entrypoint-candidates`."
  (let ((project-root (mojo//project-root)))
    (when project-root
      (let ((explicit mojo-run-project-entrypoint))
        (cond
         ((and explicit (not (string-empty-p explicit)))
          (expand-file-name explicit project-root))
         (t
          (let ((candidate
                 (cl-find-if
                  (lambda (relative)
                    (file-regular-p (expand-file-name relative project-root)))
                  mojo-run-entrypoint-candidates)))
            (when candidate
              (expand-file-name candidate project-root)))))))))

(defun mojo//project-entrypoint-or-error (action)
  "Return project entrypoint path, or raise a user error for ACTION."
  (let ((entrypoint (mojo//project-entrypoint)))
    (if (and entrypoint (file-regular-p entrypoint))
        entrypoint
      (user-error
       "No project entrypoint found for `%s`. Set `mojo-run-project-entrypoint` or add one of: %s"
       action
       (if mojo-run-entrypoint-candidates
           (mapconcat #'identity mojo-run-entrypoint-candidates ", ")
         "<none configured>")))))

(defun mojo//project-test-target ()
  "Return project test target path for `mojo run`, or nil."
  (let ((project-root (mojo//project-root)))
    (when project-root
      (let ((explicit mojo-test-project-target))
        (cond
         ((and explicit (not (string-empty-p explicit)))
          (expand-file-name explicit project-root))
         (t
          (let ((candidate
                 (cl-find-if
                  (lambda (relative)
                    (file-exists-p (expand-file-name relative project-root)))
                  mojo-test-target-candidates)))
            (when candidate
              (expand-file-name candidate project-root)))))))))

(defun mojo//project-test-target-or-error ()
  "Return test target path for `mojo/test-project`, or raise a user error."
  (let ((target (mojo//project-test-target)))
    (if (and target (file-exists-p target))
        target
      (user-error
       "No project test target found. Set `mojo-test-project-target` or add one of: %s"
       (if mojo-test-target-candidates
           (mapconcat #'identity mojo-test-target-candidates ", ")
         "<none configured>")))))

(defun mojo//test-run-arguments ()
  "Return `mojo run` arguments used by test commands."
  (append (when (and mojo-test-add-project-include
                     (mojo//project-root))
            (list "-I" (mojo//project-root)))
          mojo-test-arguments))

(defun mojo//read-mojo-file (prompt &optional initial)
  "Read a Mojo file path using PROMPT.
INITIAL is the initial minibuffer value."
  (let ((file (read-file-name prompt nil initial t nil
                              (lambda (path)
                                (or (file-directory-p path)
                                    (string-match-p "\\(?:\\.mojo\\|\\.🔥\\)\\'" path))))))
    (when (file-directory-p file)
      (user-error "Expected a Mojo file, got directory: %s" file))
    (expand-file-name file)))

(defun mojo//current-buffer-file ()
  "Return current buffer file path, or signal a user error."
  (or (buffer-file-name)
      (user-error "Current buffer is not visiting a file")))

(defun mojo/build-project ()
  "Build the current Mojo project."
  (interactive)
  (mojo//compile-command
   "build"
   mojo-build-arguments
   (mojo//project-entrypoint-or-error "mojo build")))

(defun mojo/build-current-file ()
  "Build the current Mojo file."
  (interactive)
  (mojo/build-file (mojo//current-buffer-file)))

(defun mojo/build-file (file)
  "Build a specific Mojo FILE."
  (interactive (list (mojo//read-mojo-file "Mojo file to build: "
                                           (buffer-file-name))))
  (mojo//compile-command "build"
                         mojo-build-arguments
                         (expand-file-name file)))

(defun mojo/run-project ()
  "Run `mojo run' from the project root."
  (interactive)
  (mojo//compile-command
   "run"
   mojo-run-arguments
   (mojo//project-entrypoint-or-error "mojo run")))

(defun mojo/run-current-file ()
  "Run the current Mojo file."
  (interactive)
  (mojo/run-file (mojo//current-buffer-file)))

(defun mojo/run-file (file)
  "Run a specific Mojo FILE."
  (interactive (list (mojo//read-mojo-file "Mojo file to run: "
                                           (buffer-file-name))))
  (mojo//compile-command "run"
                         mojo-run-arguments
                         (expand-file-name file)))

(defun mojo/clean-project ()
  "Run the configured clean command from the project root."
  (interactive)
  (let* ((default-directory (mojo//project-root))
         (command
          (cond
           ((and mojo-clean-command
                 (not (string-empty-p mojo-clean-command)))
            mojo-clean-command)
           ((and mojo-use-project-pixi
                 (mojo//project-has-pixi-p)
                 (executable-find "pixi"))
            (string-join
             (append '("pixi" "clean")
                     (when mojo-pixi-no-progress
                       '("--no-progress")))
             " "))
           (t
            (user-error "No default clean command. Set `mojo-clean-command` or enable project pixi")))))
    (compile command)))

;; Testing

(defun mojo/test-project ()
  "Run tests for the current Mojo project."
  (interactive)
  (setq mojo--last-test-command
        (mojo//compile-command
         "run"
         (mojo//test-run-arguments)
         (mojo//project-test-target-or-error))))

(defun mojo/test-current-file ()
  "Run tests in the current Mojo file."
  (interactive)
  (mojo/test-file (mojo//current-buffer-file)))

(defun mojo/test-file (file)
  "Run tests in a specific Mojo FILE."
  (interactive (list (mojo//read-mojo-file "Mojo test file: "
                                           (buffer-file-name))))
  (setq mojo--last-test-command
        (mojo//compile-command "run"
                               (mojo//test-run-arguments)
                               (expand-file-name file))))

(defun mojo//test-file-p (file)
  "Return non-nil when FILE looks like a test file."
  (let ((name (file-name-nondirectory file))
        (directory (file-name-directory file)))
    (or (string-match-p "\\`test_.*\\(?:\\.mojo\\|\\.🔥\\)\\'" name)
        (string-match-p "\\(?:_test\\|_tests\\)\\(?:\\.mojo\\|\\.🔥\\)\\'" name)
        (and directory
             (string-match-p "/tests?/" directory)))))

(defun mojo/test-dwim ()
  "Run file tests when in a test file, otherwise run project tests."
  (interactive)
  (let ((file (buffer-file-name)))
    (if (and file (mojo//test-file-p file))
        (mojo/test-file file)
      (mojo/test-project))))

(defun mojo/retest ()
  "Re-run the last test command executed by this layer."
  (interactive)
  (if mojo--last-test-command
      (let ((default-directory (mojo//project-root)))
        (compile mojo--last-test-command))
    (user-error "No previous test command. Run `mojo/test-project` or `mojo/test-file` first")))

;; Formatting

(defun mojo/format-region (start end)
  "Format the region between START and END using mojo format."
  (interactive (if (use-region-p)
                   (list (region-beginning) (region-end))
                 (user-error "No active region")))
  (let ((status (shell-command-on-region
                 start end (format "%s format -" (mojo//resolve-mojo-command))
                 t t "*Mojo Format Errors*" t)))
    (when (and (integerp status)
               (not (zerop status)))
      (user-error "mojo format failed, see *Mojo Format Errors*"))))

(defun mojo/format-buffer ()
  "Format the current buffer using mojo format."
  (interactive)
  (mojo/format-region (point-min) (point-max)))

(defun mojo/format-file (file)
  "Format a specific Mojo FILE."
  (interactive (list (mojo//read-mojo-file "Mojo file to format: "
                                           (buffer-file-name))))
  (mojo//compile-command "format" nil (expand-file-name file)))

(defun mojo/format-project ()
  "Format all Mojo files from the project root."
  (interactive)
  (mojo//compile-command "format" nil "."))

;; REPL Integration

(defvar mojo-repl-buffer-name "*Mojo REPL*"
  "Name of the Mojo REPL buffer.")

(defun mojo//ensure-repl-process (&optional buffer)
  "Ensure BUFFER has a running Mojo REPL process and return it."
  (let ((target (or buffer (current-buffer))))
    (unless (comint-check-proc target)
      (pcase-let ((`(,program . ,prefix-args) (mojo//resolve-mojo-program)))
        (with-current-buffer target
          (apply #'make-comint-in-buffer
                 "Mojo REPL"
                 target
                 program
                 nil
                 (append prefix-args mojo-repl-arguments)))))
    (get-buffer-process target)))

(defun mojo/run-repl ()
  "Run a Mojo REPL interpreter."
  (interactive)
  (let ((buffer (get-buffer-create mojo-repl-buffer-name)))
    (mojo//ensure-repl-process buffer)
    (pop-to-buffer buffer)))

(defun mojo/switch-to-repl ()
  "Switch to the Mojo REPL buffer."
  (interactive)
  (if (get-buffer mojo-repl-buffer-name)
      (pop-to-buffer mojo-repl-buffer-name)
    (mojo/run-repl)))

(defun mojo/send-region (start end)
  "Send the region between START and END to the Mojo REPL."
  (interactive "r")
  (let ((code (buffer-substring-no-properties start end)))
    (with-current-buffer (get-buffer-create mojo-repl-buffer-name)
      (let ((proc (mojo//ensure-repl-process (current-buffer))))
        (goto-char (process-mark proc))
        (insert code)
        (comint-send-input)))))

(defun mojo/send-buffer ()
  "Send the entire buffer to the Mojo REPL."
  (interactive)
  (mojo/send-region (point-min) (point-max)))

(defun mojo/send-line ()
  "Send the current line to the Mojo REPL."
  (interactive)
  (mojo/send-region (line-beginning-position) (line-end-position)))

(defun mojo/send-defun ()
  "Send the current function/struct/trait definition to the Mojo REPL."
  (interactive)
  (save-excursion
    (mojo-beginning-of-defun 1)
    (let ((start (point)))
      (mojo-end-of-defun 1)
      (mojo/send-region start (point)))))

;; Navigation

(defun mojo//symbol-at-point ()
  "Return symbol at point as a string, or nil."
  (let ((symbol (thing-at-point 'symbol t)))
    (and symbol
         (not (string-empty-p symbol))
         symbol)))

(defun mojo//normalize-symbol (symbol)
  "Return SYMBOL when it is non-empty, otherwise nil."
  (and symbol
       (not (string-empty-p symbol))
       symbol))

(defun mojo//definition-regexp (symbol)
  "Return an Elisp regexp matching definition candidates for SYMBOL."
  (format "^\\s-*\\(?:fn\\|def\\|struct\\|trait\\|comptime\\|var\\)\\s-+%s\\_>"
          (regexp-quote symbol)))

(defun mojo//definition-rg-pattern (symbol)
  "Return a ripgrep regexp matching definition candidates for SYMBOL."
  (format "^\\s*(fn|def|struct|trait|comptime|var)\\s+%s\\b"
          (regexp-quote symbol)))

(defun mojo//make-definition-candidate (file line column context)
  "Build a definition candidate from FILE, LINE, COLUMN, and CONTEXT."
  (list :file file
        :line line
        :column column
        :context (string-trim context)))

(defun mojo//definition-candidates-with-rg (symbol search-paths)
  "Find definition candidates for SYMBOL in SEARCH-PATHS using ripgrep.
Returns a list (possibly empty) when rg is available, or nil when rg is not."
  (when (and (executable-find "rg")
             search-paths)
    (let* ((pattern (mojo//definition-rg-pattern symbol))
           (args (append (list "--line-number"
                               "--column"
                               "--no-heading"
                               "--color" "never"
                               "--glob" "*.mojo"
                               "--glob" "!.pixi"
                               "--glob" "!.git"
                               pattern)
                         search-paths))
           (lines (ignore-errors (apply #'process-lines "rg" args))))
      ;; Return a list (may be empty) to distinguish "rg ran, no results"
      ;; from "rg not available" — the caller uses this to skip the slow
      ;; Elisp fallback when rg is present.
      (cl-loop for line in lines
               for matched = (string-match
                              "^\\(.*\\):\\([0-9]+\\):\\([0-9]+\\):\\(.*\\)$"
                              line)
               when matched
               collect (mojo//make-definition-candidate
                        (match-string 1 line)
                        (string-to-number (match-string 2 line))
                        (string-to-number (match-string 3 line))
                        (match-string 4 line))))))

(defun mojo//definition-candidates-with-elisp (symbol search-paths)
  "Find definition candidates for SYMBOL in SEARCH-PATHS using Emacs search."
  (let ((regexp (mojo//definition-regexp symbol))
        (candidates nil))
    (dolist (path search-paths)
      (dolist (file (directory-files-recursively path "\\.mojo\\'" t))
        (with-temp-buffer
          (condition-case nil
              (insert-file-contents file)
            (error nil))
          (goto-char (point-min))
          (while (re-search-forward regexp nil t)
            (push
             (mojo//make-definition-candidate
              file
              (line-number-at-pos)
              (1+ (- (match-beginning 0) (line-beginning-position)))
              (buffer-substring-no-properties (line-beginning-position)
                                              (line-end-position)))
             candidates)))))
    (nreverse candidates)))

(defun mojo//definition-candidates (symbol)
  "Find definition candidates for SYMBOL in project and configured source paths."
  (let ((search-paths (mojo//definition-search-paths)))
    ;; Use rg when available; only use the Elisp fallback when rg is not on PATH.
    ;; Never check the rg result for truthiness — an empty list and nil are
    ;; identical in Elisp, so `(or rg-result elisp-fallback)` wrongly recurses
    ;; into .pixi/ whenever rg finds no matches.
    (if (executable-find "rg")
        (mojo//definition-candidates-with-rg symbol search-paths)
      (mojo//definition-candidates-with-elisp symbol search-paths))))

;; Xref backend — makes fallback search work with standard M-. / xref
(defun mojo//xref-backend () "Return mojo xref backend." 'mojo)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql 'mojo)))
  "Return identifier at point for mojo xref backend."
  (mojo//symbol-at-point))

(cl-defmethod xref-backend-definitions ((_backend (eql 'mojo)) identifier)
  "Return xref definitions for IDENTIFIER using project/stdlib search."
  (let ((candidates (mojo//definition-candidates identifier)))
    (mapcar (lambda (c)
              (xref-make
               (plist-get c :context)
               (xref-make-file-location
                (plist-get c :file)
                (plist-get c :line)
                (plist-get c :column))))
            candidates)))

(defun mojo//format-definition-candidate (candidate)
  "Return a display string for definition CANDIDATE."
  (let ((file (plist-get candidate :file))
        (line (plist-get candidate :line))
        (context (plist-get candidate :context)))
    (format "%s:%d: %s"
            (abbreviate-file-name file)
            line
            context)))

(defun mojo//read-definition-candidate (symbol candidates)
  "Select one definition candidate for SYMBOL from CANDIDATES."
  (if (= (length candidates) 1)
      (car candidates)
    (let* ((entries (mapcar (lambda (candidate)
                              (cons (mojo//format-definition-candidate candidate)
                                    candidate))
                            candidates))
           (selection (completing-read
                       (format "Definitions for %s: " symbol)
                       entries
                       nil
                       t)))
      (cdr (assoc selection entries)))))

(defun mojo//visit-definition-candidate (candidate)
  "Open and jump to definition CANDIDATE."
  (let ((file (plist-get candidate :file))
        (line (plist-get candidate :line))
        (column (plist-get candidate :column)))
    (find-file file)
    (goto-char (point-min))
    (forward-line (max 0 (1- line)))
    (move-to-column (max 0 (1- column)))))

(defun mojo/jump-to-definition-fallback (&optional symbol)
  "Jump to SYMBOL definition by searching project and configured source paths.
Returns non-nil when a location is found."
  (interactive)
  (let* ((default-symbol (mojo//symbol-at-point))
         (target-symbol (mojo//normalize-symbol
                         (or symbol
                             default-symbol
                             (read-string "Symbol: "))))
         (candidates (and target-symbol
                          (mojo//definition-candidates target-symbol))))
    (if (and target-symbol candidates)
        (progn
          (mojo//visit-definition-candidate
           (mojo//read-definition-candidate target-symbol candidates))
          t)
      (message "No definition found for %s in project/stdlib paths."
               (or target-symbol "<symbol>"))
      nil)))

(defun mojo/jump-to-definition (&optional force-fallback)
  "Jump to the definition of the symbol at point.
Use xref/LSP first and fall back to project+stdlib search.
With FORCE-FALLBACK (prefix arg), skip xref/LSP."
  (interactive "P")
  (let ((symbol (mojo//symbol-at-point)))
    (if force-fallback
        (mojo/jump-to-definition-fallback symbol)
      (condition-case err
          (if symbol
              (xref-find-definitions symbol)
            (call-interactively 'xref-find-definitions))
        (error
         (unless (mojo/jump-to-definition-fallback symbol)
           (signal (car err) (cdr err))))))))

(defun mojo/search-symbol-references (&optional symbol)
  "Search for SYMBOL references in project and configured source paths."
  (interactive)
  (let* ((default-symbol (mojo//symbol-at-point))
         (target-symbol (mojo//normalize-symbol
                         (or symbol
                             default-symbol
                             (read-string "Find references for: "))))
         (search-paths (mojo//definition-search-paths)))
    (if (and target-symbol (executable-find "rg") search-paths)
        (let ((command (format
                        "rg --line-number --no-heading --color never --glob '*.mojo' %s %s"
                        (shell-quote-argument
                         (format "\\b%s\\b" (regexp-quote target-symbol)))
                        (mapconcat #'shell-quote-argument search-paths " "))))
          (compilation-start command 'grep-mode
                             (lambda (_)
                               (format "*Mojo References: %s*" target-symbol))))
      (message "No reference search paths found for Mojo."))))

(defun mojo/find-references ()
  "Find references to the symbol at point using ripgrep."
  (interactive)
  (mojo/search-symbol-references))

(defun mojo/open-stdlib-directory ()
  "Open the configured stdlib directory in dired."
  (interactive)
  (let ((stdlib (mojo//normalize-directory mojo-stdlib-path)))
    (if stdlib
        (dired stdlib)
      (message "mojo-stdlib-path is not set to an existing directory."))))

(defvar mojo--eldoc-descriptions)

(defun mojo/show-documentation ()
  "Show eldoc description for the symbol at point."
  (interactive)
  (let ((symbol (thing-at-point 'symbol t)))
    (if symbol
        (let ((desc (cdr (assoc symbol mojo--eldoc-descriptions))))
          (if desc
              (message "%s — %s" symbol desc)
            (message "No documentation available for %s" symbol)))
      (message "No symbol at point"))))

(defun mojo/rename-symbol (new-name)
  "Rename the symbol at point to NEW-NAME using query-replace."
  (interactive "sNew name: ")
  (let ((old-name (thing-at-point 'symbol t)))
    (if old-name
        (progn
          (goto-char (point-min))
          (query-replace-regexp (format "\\_<%s\\_>" (regexp-quote old-name))
                                new-name))
      (message "No symbol at point"))))

;; Code Generation

(defun mojo/insert-function-template (name)
  "Insert a Mojo function template with NAME."
  (interactive "sFunction name: ")
  (insert (format "def %s():\n    \"\"\"TODO: Document %s.\"\"\"\n    pass"
                  name name)))

(defun mojo/insert-struct-template (name)
  "Insert a Mojo struct template with NAME."
  (interactive "sStruct name: ")
  (insert (format "@fieldwise_init\nstruct %s(Copyable, Movable, Writable):\n    \"\"\"TODO: Document %s.\"\"\"\n    var field: Int"
                  name name)))

(defun mojo/insert-trait-template (name)
  "Insert a Mojo trait template with NAME."
  (interactive "sTrait name: ")
  (insert (format "trait %s:\n    \"\"\"TODO: Document %s.\"\"\"\n    def method(self): ..."
                  name name)))

;; Utility Functions

(defun mojo/what-version ()
  "Display the installed Mojo version."
  (interactive)
  (message "Mojo version: %s"
           (string-trim-right
            (shell-command-to-string
             (format "%s --version" (mojo//resolve-mojo-command))))))

(defun mojo/check-health ()
  "Check the health of the Mojo development environment."
  (interactive)
  (let ((mojo-exe (executable-find "mojo"))
        (project-root (mojo//project-root))
        (source-paths (mojo//configured-source-paths)))
    (with-output-to-temp-buffer "*Mojo Health Check*"
      (princ "Mojo Development Environment Health Check\n")
      (princ "==========================================\n\n")

      (princ "Mojo CLI: ")
      (if mojo-exe
          (princ (format "Found at %s\n" mojo-exe))
        (princ "Not found in PATH\n"))

      (princ "Project Root: ")
      (if project-root
          (princ (format "%s\n" project-root))
        (princ "Not in a project\n"))

      (princ "\nConfiguration:\n")
      (princ (format "  mojo-format-on-save: %s\n" mojo-format-on-save))
      (princ (format "  mojo-indent-offset: %s\n" mojo-indent-offset))
      (princ (format "  mojo-use-project-pixi: %s\n" mojo-use-project-pixi))
      (princ (format "  mojo-use-global-pixi: %s\n" mojo-use-global-pixi))
      (princ (format "  resolved-mojo-command: %s\n"
                     (condition-case err
                         (mojo//resolve-mojo-command)
                       (error
                        (format "ERROR: %s" (error-message-string err))))))
      (princ (format "  mojo-stdlib-path: %s\n"
                     (or mojo-stdlib-path "nil")))
      (princ (format "  mojo-extra-source-paths: %s\n"
                     (if mojo-extra-source-paths
                         (mapconcat #'identity mojo-extra-source-paths ", ")
                       "nil")))

      (princ "\nResolved Source Paths:\n")
      (if source-paths
          (dolist (path source-paths)
            (princ (format "  %s\n" path)))
        (princ "  None (set mojo-stdlib-path or mojo-extra-source-paths)\n"))

      (princ "\nPixi Environment:\n")
      (let ((pixi-dirs '(".pixi" "~/.pixi")))
        (dolist (dir pixi-dirs)
          (let ((expanded (expand-file-name dir)))
            (princ (format "  %s: %s\n"
                           dir
                           (if (file-directory-p expanded)
                               "Found"
                             "Not found")))))))))

;; Spacemacs Leader Key Bindings

(defun mojo/set-leader-keys ()
  "Set up Spacemacs leader key bindings for Mojo mode."
  (spacemacs/declare-prefix-for-mode 'mojo-mode "mc" "compile")
  (spacemacs/declare-prefix-for-mode 'mojo-mode "mf" "format")
  (spacemacs/declare-prefix-for-mode 'mojo-mode "mg" "goto")
  (spacemacs/declare-prefix-for-mode 'mojo-mode "mh" "help")
  (spacemacs/declare-prefix-for-mode 'mojo-mode "mi" "insert")
  (spacemacs/declare-prefix-for-mode 'mojo-mode "mr" "refactor")
  (spacemacs/declare-prefix-for-mode 'mojo-mode "ms" "send/repl")
  (spacemacs/declare-prefix-for-mode 'mojo-mode "mt" "test")

  (spacemacs/set-leader-keys-for-major-mode 'mojo-mode
    ;; Formatting
    "=" 'mojo/format-buffer
    "fb" 'mojo/format-buffer
    "ff" 'mojo/format-file
    "fp" 'mojo/format-project
    "fr" 'mojo/format-region

    ;; Compile and run
    "cc" 'mojo/build-project
    "c=" 'mojo/format-buffer
    "cb" 'mojo/build-current-file
    "cf" 'mojo/build-file
    "ck" 'kill-compilation
    "cl" 'mojo/clean-project
    "cp" 'mojo/run-project
    "cr" 'mojo/run-current-file
    "cR" 'mojo/run-file

    ;; Navigation
    "gg" 'mojo/jump-to-definition
    "gG" 'mojo/jump-to-definition-fallback
    "gr" 'mojo/find-references
    "gR" 'mojo/search-symbol-references

    ;; Help
    "hh" 'mojo/show-documentation
    "hv" 'mojo/what-version
    "hS" 'mojo/open-stdlib-directory
    "h?" 'mojo/check-health

    ;; Refactoring
    "rr" 'mojo/rename-symbol

    ;; REPL
    "sb" 'mojo/send-buffer
    "sd" 'mojo/send-defun
    "sl" 'mojo/send-line
    "sr" 'mojo/send-region
    "ss" 'mojo/switch-to-repl
    "sS" 'mojo/run-repl
    "'" 'mojo/run-repl

    ;; Testing
    "ta" 'mojo/test-dwim
    "tt" 'mojo/test-project
    "tb" 'mojo/test-current-file
    "tf" 'mojo/test-file
    "tr" 'mojo/retest

    ;; Templates
    "if" 'mojo/insert-function-template
    "is" 'mojo/insert-struct-template
    "it" 'mojo/insert-trait-template))

;;; funcs.el ends here
