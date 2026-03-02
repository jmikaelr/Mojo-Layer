;;; mojo-mode.el --- Major mode for Mojo programming language -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Custom Implementation
;; Version: 0.26.1
;; Keywords: languages, mojo, ai, systems
;; URL: https://www.modular.com/mojo

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This package provides a major mode for editing Mojo source code.
;; Mojo is a programming language designed for AI development that
;; combines Python's usability with systems programming capabilities.
;;
;; This mode supports Mojo v0.26.1 and includes:
;; - Syntax highlighting for keywords, types, and operators
;; - Font-lock support for decorators and docstrings
;; - Indentation based on Python mode
;; - Integration with LSP for code completion and navigation

;;; Code:

(require 'cl-lib)
(require 'python)

(declare-function mojo/format-buffer "funcs")
(declare-function mojo/run-repl "funcs")
(declare-function mojo/send-region "funcs" (start end))
(declare-function mojo/send-buffer "funcs")
(defvar flycheck-checkers)

;; Group definitions
(defgroup mojo nil
  "Major mode for editing Mojo code."
  :group 'languages
  :prefix "mojo-")

(defvar mojo-indent-offset 4
  "Number of spaces for each indentation step in Mojo mode.")

(defvar mojo-format-on-save nil
  "Non-nil to format buffer on save using mojo format.")

;; Font lock keywords - organized by category for Mojo v0.26.1

;; Core keywords that define code structure
(defconst mojo-keywords
  '("fn" "def" "struct" "trait" "var" "let" "alias" "comptime"
    "inout" "borrowed" "owned" "read" "mut" "out" "var"
    "async" "await" "raises" "with" "as"
    "return" "pass" "break" "continue" "raise" "try" "except" "finally"
    "if" "elif" "else" "for" "while" "match" "case"
    "import" "from" "module" "export"
    "and" "or" "not" "in" "is" "del"
    "static" "dynamic" "inline" "no_inline"
    "constrained" "where" "parameter" "always_inline"
    "__copyinit__" "__moveinit__" "__init__" "__del__"
    "__enter__" "__exit__" "__getitem__" "__setitem__"
    "__getattr__" "__setattr__" "__call__" "__iter__" "__next__"
    "__len__" "__contains__" "__eq__" "__ne__" "__lt__" "__le__" "__gt__" "__ge__"
    "__add__" "__sub__" "__mul__" "__truediv__" "__floordiv__" "__mod__"
    "__and__" "__or__" "__xor__" "__lshift__" "__rshift__"
    "__bool__" "__int__" "__float__" "__str__" "__repr__"
    "__hash__" "__sizeof__" "__ref__")
  "Mojo keywords for font-locking.")

;; Built-in types
(defconst mojo-types
  '("Bool" "Int" "Int8" "Int16" "Int32" "Int64" "Int128"
    "UInt" "UInt8" "UInt16" "UInt32" "UInt64" "UInt128"
    "Float16" "Float32" "Float64" "BFloat16"
    "String" "StringLiteral" "StringSlice" "Char"
    "List" "Dict" "Set" "Tuple" "Optional" "Result"
    "SIMD" "DType" "Scalar" "Layout" "Origin"
    "Pointer" "UnsafePointer" "OwnedPointer"
    "Span" "Slice" "Range"
    "Variant" "InlineArray" "InlineList"
    "Error" "Never" "NoneType"
    "AnyType" "Movable" "Copyable" "ImplicitlyCopyable"
    "ImplicitlyDestructible" "UnknownDestructibility"
    "Writable" "Readable" "Hashable" "Equatable" "Comparable"
    "Sized" "Iterable" "Iterator" "Sequence" "Collection"
    "ContextManager" "TestSuite"
    "FloatLiteral" "IntLiteral" "StringLiteral" "BoolLiteral"
    "Elementwise" "Stochastic" "Autotune"
    "DeviceContext" "TargetInfo"
    "Tensor" "TensorShape" "TensorSpec"
    "Buffer" "NDBuffer"
    "MatmulConfig" "ConvConfig")
  "Mojo built-in types for font-locking.")

;; Decorators
(defconst mojo-decorators
  '("@value" "@fieldwise_init" "@register_passable"
    "@implicit" "@deprecated" "@always_inline"
    "@no_inline" "@export" "@parameter"
    "@adaptive" "@tile" "@vectorize" "@parallel"
    "@unroll" "@static" "@dynamic"
    "@raising" "@contextmanager"
    "@property" "@staticmethod" "@classmethod"
    "@abstractmethod" "@final" "@sealed"
    "@traceable" "@jit" "@aot"
    "@requires" "@constraints"
    "@gpu" "@cpu" "@target"
    "@test" "@benchmark"
    "@doc" "@doc_group"
    "@category" "@visibility")
  "Mojo decorators for font-locking.")

;; Special values
(defconst mojo-constants
  '("True" "False" "None" "..." "__name__" "__file__" "__line__"
    "__mlir_attr" "__mlir_op" "__mlir_type"
    "__address_of" "__type_of" "__origin_of"
    "__mlir_i1" "__mlir_i8" "__mlir_i16" "__mlir_i32" "__mlir_i64"
    "__mlir_f16" "__mlir_f32" "__mlir_f64"
    "__register_passable" "__trivial")
  "Mojo constants and special values.")

;; Create optimized regex patterns
(defconst mojo-keyword-regexp
  (regexp-opt mojo-keywords 'symbols)
  "Regular expression for matching Mojo keywords.")

(defconst mojo-type-regexp
  (regexp-opt mojo-types 'symbols)
  "Regular expression for matching Mojo types.")

(defconst mojo-decorator-regexp
  (concat "^\\s-*" (regexp-opt mojo-decorators t))
  "Regular expression for matching Mojo decorators with optional indentation.")

(defconst mojo-constant-regexp
  (regexp-opt mojo-constants 'symbols)
  "Regular expression for matching Mojo constants.")

;; Function/struct/trait definition patterns
(defconst mojo-function-def-regexp
  "^\\s-*\\(fn\\|def\\)\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)"
  "Regexp to match Mojo function definitions.")

(defconst mojo-struct-def-regexp
  "^\\s-*\\(struct\\|trait\\)\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)"
  "Regexp to match Mojo struct and trait definitions.")

;; Parameter and generic patterns
(defconst mojo-parameter-regexp
  "\\[\\s-*\\([a-zA-Z_][a-zA-Z0-9_]*\\)\\s-*:"
  "Regexp to match parameter declarations in square brackets.")

;; Argument convention annotations
(defconst mojo-argument-convention-regexp
  "\\(read\\|mut\\|out\\|owned\\|var\\|inout\\|borrowed\\)\\s-+"
  "Regexp to match argument convention annotations.")

;; Docstring pattern (triple-quoted strings)
(defconst mojo-docstring-regexp
  "\"\"\"[^\"]*\"\"\""
  "Regexp to match Mojo docstrings.")

;; Number patterns
(defconst mojo-number-regexp
  (concat
   "\\_<"
   "\\(?:"
   ;; Hexadecimal
   "0[xX][0-9a-fA-F_]*\\(?:\\.[0-9a-fA-F_]+\\)?\\(?:[pP][+-]?[0-9]+\\)?"
   "\\|"
   ;; Binary
   "0[bB][01_]+"
   "\\|"
   ;; Octal
   "0[oO][0-7_]+"
   "\\|"
   ;; Decimal (integer or float)
   "[0-9][0-9_]*\\(?:\\.[0-9_]+\\)?\\(?:[eE][+-]?[0-9]+\\)?"
   "\\|"
   ;; Float starting with dot
   "\\.[0-9][0-9_]*\\(?:[eE][+-]?[0-9]+\\)?"
   "\\)"
   ;; Type suffixes
   "\\(?:[ui][0-9]*\\|f[0-9]*\\)?"
   "\\_>")
  "Regexp to match Mojo numeric literals.")

;; Font lock keywords specification
(defconst mojo-font-lock-keywords
  `(
    ;; Docstrings (triple-quoted)
    (,mojo-docstring-regexp . font-lock-doc-face)
    
    ;; Decorators at beginning of line
    (,mojo-decorator-regexp . font-lock-preprocessor-face)
    
    ;; Function definitions - highlight the name
    (,mojo-function-def-regexp 2 font-lock-function-name-face)
    
    ;; Struct/trait definitions - highlight the name
    (,mojo-struct-def-regexp 2 font-lock-type-face)
    
    ;; Parameter declarations
    (,mojo-parameter-regexp 1 font-lock-variable-name-face)
    
    ;; Argument conventions
    (,mojo-argument-convention-regexp 1 font-lock-keyword-face)
    
    ;; Keywords
    (,mojo-keyword-regexp . font-lock-keyword-face)
    
    ;; Types
    (,mojo-type-regexp . font-lock-type-face)
    
    ;; Constants
    (,mojo-constant-regexp . font-lock-constant-face)
    
    ;; Numbers
    (,mojo-number-regexp . font-lock-constant-face)
    
    ;; Special operators and syntax
    ("\\(->\\|=>\\|\\.\\.\\.\\)" . font-lock-keyword-face)
    
    ;; Type annotations (after colon in parameter lists)
    (":\\s-*\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1 font-lock-type-face)
    
    ;; raises clause
    ("raises\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1 font-lock-type-face)
    
    ;; where clause constraints
    ("where\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1 font-lock-variable-name-face)
    
    ;; Trait conformance
    ("\\(struct\\|trait\\)\\s-+[a-zA-Z_][a-zA-Z0-9_]*\\s-*(\\([^)]*\\))" 
     2 font-lock-type-face)
    
    ;; comptime/alias declarations
    ("\\(comptime\\|alias\\)\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 
     2 font-lock-variable-name-face)
    
    ;; var/let declarations
    ("\\(var\\|let\\)\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 
     2 font-lock-variable-name-face)
    
    ;; fn/def parameters
    ("\\(fn\\|def\\)\\s-+[a-zA-Z_][a-zA-Z0-9_]*\\s-*[^(]*\\s-*(\\([^)]*\\))" 
     1 font-lock-variable-name-face)
    )
  "Font lock keywords for Mojo mode.")

;; Syntax table
(defvar mojo-mode-syntax-table
  (let ((table (make-syntax-table python-mode-syntax-table)))
    ;; Mojo-specific syntax modifications
    ;; The arrow -> is used for return types
    (modify-syntax-entry ?- ". 12" table)
    (modify-syntax-entry ?> "." table)
    
    ;; @ is part of decorators
    (modify-syntax-entry ?@ "w" table)
    
    ;; _ is part of words (for snake_case)
    (modify-syntax-entry ?_ "w" table)
    
    ;; Comments use # like Python
    (modify-syntax-entry ?# "<" table)
    (modify-syntax-entry ?\n ">" table)
    
    ;; String quotes
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?' "\"" table)
    
    table)
  "Syntax table for Mojo mode.")

;; Indentation
(defconst mojo--block-start-regexp
  (rx symbol-start
      (or "fn" "def" "struct" "trait"
          "if" "elif" "else" "for" "while" "with"
          "try" "except" "finally" "match" "case")
      symbol-end)
  "Regexp matching Mojo block-start keywords.")

(defconst mojo--dedenter-regexp
  (rx symbol-start (or "elif" "else" "except" "finally" "case") symbol-end)
  "Regexp matching Mojo dedenter keywords.")

(defun mojo--line-ends-with-colon-p ()
  "Return non-nil if the current line ends with a block colon."
  (save-excursion
    (end-of-line)
    (python-util-forward-comment -1)
    (skip-chars-backward " \t")
    (eq (char-before) ?:)))

(defun mojo--line-opens-block-p ()
  "Return non-nil if current line starts a Mojo block."
  (save-excursion
    (back-to-indentation)
    (and (looking-at mojo--block-start-regexp)
         (mojo--line-ends-with-colon-p))))

(defun mojo--previous-code-line-pos ()
  "Return point of the previous non-empty, non-comment line."
  (save-excursion
    (let ((found nil))
      (while (and (not found) (not (bobp)))
        (forward-line -1)
        (unless (or (python-info-current-line-empty-p)
                    (python-info-current-line-comment-p))
          (setq found (point))))
      found)))

(defun mojo--current-line-dedenter-p ()
  "Return non-nil if the current line starts with a dedenter keyword."
  (save-excursion
    (back-to-indentation)
    (looking-at mojo--dedenter-regexp)))

(defun mojo-indent-line ()
  "Indent current line as Mojo code."
  (interactive)
  (let ((pos (- (point-max) (point)))
        (indentation nil))
    (cond
     ((python-syntax-context 'paren)
      (python-indent-line-function))
     ((mojo--current-line-dedenter-p)
      (python-indent-line-function))
     (t
      (let ((prev-pos (mojo--previous-code-line-pos)))
        (when prev-pos
          (save-excursion
            (goto-char prev-pos)
            (when (mojo--line-opens-block-p)
              (setq indentation (+ (current-indentation) mojo-indent-offset))))))
      (if indentation
          (progn
            (indent-line-to indentation)
            (when (> (- (point-max) pos) (point))
              (goto-char (- (point-max) pos))))
        (python-indent-line-function))))))

;; Navigation functions
(defun mojo-beginning-of-defun (&optional arg)
  "Move to beginning of Mojo function/struct/trait.
With positive ARG, move backward that many definitions.
With negative ARG, move forward."
  (interactive "p")
  (let ((arg (or arg 1)))
    (if (> arg 0)
        (re-search-backward "^\\s-*\\(fn\\|def\\|struct\\|trait\\)\\s-+" 
                            nil t arg)
      (re-search-forward "^\\s-*\\(fn\\|def\\|struct\\|trait\\)\\s-+" 
                         nil t (- arg)))))

(defun mojo-end-of-defun (&optional arg)
  "Move to end of Mojo function/struct/trait.
With positive ARG, move forward that many definitions.
With negative ARG, move backward."
  (interactive "p")
  (let ((arg (or arg 1)))
    (when (mojo-beginning-of-defun arg)
      (python-nav-end-of-block))))

;; Imenu integration
(defvar mojo-imenu-generic-expression
  `(("Trait" "^\\s-*trait\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1)
    ("Struct" "^\\s-*struct\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1)
    ("Function" "^\\s-*fn\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1)
    ("Definition" "^\\s-*def\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1))
  "Imenu expression for Mojo mode.")

;; Which-func integration
(defun mojo-which-function ()
  "Return the name of the Mojo function at point."
  (save-excursion
    (when (mojo-beginning-of-defun 1)
      (when (looking-at "^\\s-*\\(fn\\|def\\|struct\\|trait\\)\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)")
        (match-string-no-properties 2)))))

;; Compilation
(defvar mojo-compilation-error-regexp-alist
  `((,(concat "^\\([^:]+\\):\\([0-9]+\\):\\([0-9]+\\):\\s-*"
             "\\(?:error\\|warning\\|note\\):\\s-*\\(.+\\)$")
     1 2 3 nil 1))
  "Regexp to match Mojo compiler errors.")

;; Formatting
(defun mojo-format-buffer ()
  "Format the current buffer using mojo format."
  (interactive)
  (if (fboundp 'mojo/format-buffer)
      (mojo/format-buffer)
    (when (buffer-file-name)
      (let ((command "mojo format -"))
        (shell-command-on-region (point-min) (point-max)
                                 command nil t)))))

;; REPL integration
(defvar mojo-repl-buffer-name "*Mojo REPL*"
  "Name of the Mojo REPL buffer.")

(defun mojo-run-repl ()
  "Run a Mojo REPL interpreter."
  (interactive)
  (if (fboundp 'mojo/run-repl)
      (mojo/run-repl)
    (let ((buffer (get-buffer-create mojo-repl-buffer-name)))
      (unless (comint-check-proc buffer)
        (apply 'make-comint-in-buffer "Mojo REPL" buffer "mojo" nil '("repl")))
      (pop-to-buffer buffer))))

(defun mojo-send-region (start end)
  "Send the region between START and END to the Mojo REPL."
  (interactive "r")
  (if (fboundp 'mojo/send-region)
      (mojo/send-region start end)
    (let ((code (buffer-substring-no-properties start end)))
      (with-current-buffer (get-buffer-create mojo-repl-buffer-name)
        (unless (comint-check-proc (current-buffer))
          (apply 'make-comint-in-buffer "Mojo REPL" (current-buffer) "mojo" nil '("repl")))
        (goto-char (process-mark (get-buffer-process (current-buffer))))
        (insert code)
        (comint-send-input)))))

(defun mojo-send-buffer ()
  "Send the entire buffer to the Mojo REPL."
  (interactive)
  (if (fboundp 'mojo/send-buffer)
      (mojo/send-buffer)
    (mojo-send-region (point-min) (point-max))))

;; Flycheck integration (if available)
(defun mojo-flycheck-setup ()
  "Setup flycheck for Mojo if available."
  (when (require 'flycheck nil t)
    ;; `flycheck-define-checker` is a macro, so use `eval` when flycheck is
    ;; loaded to avoid compile-time dependency in minimal environments.
    (eval
     '(flycheck-define-checker mojo
        "A Mojo syntax checker using the mojo compiler."
        ;; Avoid creating flycheck_* temp files next to source files.
        ;; Compile as object so checker works for library files without `main`.
        :command ("mojo" "build" "--emit" "object" "-o" (eval null-device) source-original)
        :error-patterns
        ((error line-start (file-name) ":" line ":" column ": error: " (message) line-end)
         (error line-start (file-name) ": error: " (message) line-end)
         (warning line-start (file-name) ":" line ":" column ": warning: " (message) line-end)
         (warning line-start (file-name) ": warning: " (message) line-end))
        :modes mojo-mode))
    (add-to-list 'flycheck-checkers 'mojo)))

;; Eldoc integration
(defun mojo-eldoc-function ()
  "Return eldoc documentation for the symbol at point."
  (let ((symbol (thing-at-point 'symbol t)))
    (when symbol
      (cond
       ((member symbol mojo-keywords)
        (format "Mojo keyword: %s" symbol))
       ((member symbol mojo-types)
        (format "Mojo type: %s" symbol))
       ((member symbol mojo-decorators)
        (format "Mojo decorator: %s" symbol))
       ((member symbol mojo-constants)
        (format "Mojo constant: %s" symbol))))))

;; Major mode definition
;;;###autoload
(define-derived-mode mojo-mode python-mode "Mojo"
  "Major mode for editing Mojo source code.

This mode provides:
- Syntax highlighting for Mojo keywords, types, and operators
- Font-lock support for decorators and docstrings
- Indentation based on Python mode
- Integration with LSP for code completion and navigation

Key bindings:
\\{mojo-mode-map}"
  :group 'mojo
  :syntax-table mojo-mode-syntax-table
  
  ;; Font lock
  (setq-local font-lock-defaults '(mojo-font-lock-keywords nil nil nil nil))
  
  ;; Indentation
  (setq-local indent-line-function #'mojo-indent-line)
  (setq-local python-indent-offset mojo-indent-offset)
  (setq-local tab-width mojo-indent-offset)
  
  ;; Comments
  (setq-local comment-start "# ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "#+\\s-*")
  
  ;; Navigation
  (setq-local beginning-of-defun-function #'mojo-beginning-of-defun)
  (setq-local end-of-defun-function #'mojo-end-of-defun)
  
  ;; Imenu
  (setq-local imenu-generic-expression mojo-imenu-generic-expression)
  
  ;; Which-func
  (setq-local which-func-functions '(mojo-which-function))
  
  ;; Eldoc
  (setq-local eldoc-documentation-function #'mojo-eldoc-function)
  
  ;; Compilation
  (setq-local compilation-error-regexp-alist mojo-compilation-error-regexp-alist)
  
  ;; Format on save
  (when mojo-format-on-save
    (add-hook 'before-save-hook #'mojo-format-buffer nil t))
  
  ;; Setup integrations
  (mojo-flycheck-setup))

;; Key map
(define-key mojo-mode-map (kbd "C-c C-z") #'mojo-run-repl)
(define-key mojo-mode-map (kbd "C-c C-c") #'mojo-send-buffer)
(define-key mojo-mode-map (kbd "C-c C-r") #'mojo-send-region)
(define-key mojo-mode-map (kbd "C-c C-f") #'mojo-format-buffer)

;; Auto-mode-alist
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.mojo\\'" . mojo-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.🔥\\'" . mojo-mode))

;; Magic mode detection for shebang
;;;###autoload
(add-to-list 'interpreter-mode-alist '("mojo" . mojo-mode))

(provide 'mojo-mode)

;;; mojo-mode.el ends here
