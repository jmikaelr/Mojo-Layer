;;; mojo-mode.el --- Major mode for Mojo programming language -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Richard Johnsson

;; Author: Richard Johnsson
;; Version: 1.0
;; Keywords: languages, mojo, ai, systems
;; URL: https://www.modular.com/mojo

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Standalone major mode for editing Mojo source code.  Derives from
;; `prog-mode' (not `python-mode') to avoid inheriting Python LSP
;; clients, eldoc, hooks, and minor modes.
;;
;; Features:
;; - Syntax highlighting for keywords, types, decorators, and operators
;; - Triple-quoted string support via syntax-propertize
;; - Indentation (block openers, dedenter keywords, paren alignment)
;; - Navigation via xref and ripgrep-based fallback search
;; - Flycheck integration, REPL, snippets, projectile support

;;; Code:

(require 'cl-lib)

(declare-function mojo/format-buffer "funcs")
(declare-function mojo/run-repl "funcs")
(declare-function mojo/send-region "funcs" (start end))
(declare-function mojo/send-buffer "funcs")
(defvar flycheck-checkers)
(declare-function flycheck-registered-checker-p "flycheck" (checker))
(declare-function comint-check-proc "comint" (buffer))
(declare-function comint-send-input "comint")
(declare-function make-comint-in-buffer "comint")

;; Variables defined via defcustom in the Spacemacs layer's config.el.
;; Declare here so mojo-mode.el byte-compiles cleanly standalone.
(defvar mojo-indent-offset 4
  "Number of spaces for each indentation step in Mojo mode.")
(defvar mojo-format-on-save nil
  "Non-nil to format buffer on save using mojo format.")

;; Group definitions
(defgroup mojo nil
  "Major mode for editing Mojo code."
  :group 'languages
  :prefix "mojo-")

;; ---- Font lock constants ------------------------------------------------

(defconst mojo-keywords
  '("def" "struct" "trait" "var" "comptime"
    "read" "mut" "out" "deinit" "ref"
    "raises" "with" "as"
    "return" "pass" "break" "continue" "raise" "try" "except" "finally"
    "if" "elif" "else" "for" "while"
    "import" "from"
    "and" "or" "not" "in" "is" "del"
    "where"
    "__init__" "__del__"
    "__enter__" "__exit__" "__getitem__" "__setitem__"
    "__getattr__" "__setattr__" "__call__" "__iter__" "__next__"
    "__len__" "__contains__" "__eq__" "__ne__" "__lt__" "__le__" "__gt__" "__ge__"
    "__add__" "__sub__" "__mul__" "__truediv__" "__floordiv__" "__mod__"
    "__and__" "__or__" "__xor__" "__lshift__" "__rshift__"
    "__bool__" "__int__" "__float__" "__repr__"
    "__hash__" "__sizeof__" "__ref__"
    ;; Deprecated — kept for backward-compat highlighting of legacy code
    "fn" "let" "alias" "inout" "borrowed" "owned"
    "__copyinit__" "__moveinit__" "__str__")
  "Mojo keywords for font-locking.")

(defconst mojo-types
  '("Bool" "Int" "Int8" "Int16" "Int32" "Int64" "Int128"
    "UInt" "UInt8" "UInt16" "UInt32" "UInt64" "UInt128"
    "Float16" "Float32" "Float64" "BFloat16"
    "String" "StaticString" "StringLiteral" "StringSlice" "Char" "Codepoint"
    "List" "Dict" "Set" "Tuple" "Optional" "Result"
    "SIMD" "DType" "Scalar" "Layout" "Origin"
    "MutOrigin" "ImmutOrigin" "MutAnyOrigin" "ImmutAnyOrigin"
    "MutExternalOrigin" "ImmutExternalOrigin" "StaticConstantOrigin"
    "Pointer" "UnsafePointer" "OwnedPointer" "ArcPointer"
    "Span" "Slice" "Range"
    "Variant" "InlineArray" "InlineList"
    "Error" "StopIteration" "Never" "NoneType"
    "AnyType" "Movable" "Copyable" "ImplicitlyCopyable"
    "ImplicitlyDestructible"
    "RegisterPassable" "TrivialRegisterPassable"
    "Writable" "Writer" "Some" "Readable" "Hashable" "Equatable" "Comparable"
    "Sized" "Iterable" "Iterator" "Sequence" "Collection"
    "ContextManager" "TestSuite"
    "FloatLiteral" "IntLiteral" "StringLiteral"
    "Coroutine" "Task"
    "DeviceContext" "TargetInfo")
  "Mojo built-in types for font-locking.")

(defconst mojo-decorators
  '("@fieldwise_init" "@implicit" "@deprecated"
    "@always_inline" "@no_inline" "@export"
    "@parameter" "@unroll"
    "@property" "@staticmethod" "@final"
    "@explicit_destroy" "@doc_hidden"
    "@test" "@benchmark")
  "Mojo decorators for font-locking.")

(defconst mojo-constants
  '("True" "False" "None" "..." "Self"
    "__name__" "__file__" "__line__"
    "__mlir_attr" "__mlir_op" "__mlir_type"
    "__type_of" "__origin_of" "origin_of" "rebind")
  "Mojo constants and special values.")

;; ---- Regexp patterns ----------------------------------------------------

(defconst mojo-keyword-regexp
  (regexp-opt mojo-keywords 'symbols)
  "Regular expression for matching Mojo keywords.")

(defconst mojo-type-regexp
  (regexp-opt mojo-types 'symbols)
  "Regular expression for matching Mojo types.")

(defconst mojo-decorator-regexp
  "^\\s-*\\(@[a-zA-Z_][a-zA-Z0-9_]*\\)"
  "Regular expression for matching any Mojo decorator.")

(defconst mojo-constant-regexp
  (regexp-opt mojo-constants 'symbols)
  "Regular expression for matching Mojo constants.")

(defconst mojo-function-def-regexp
  "^\\s-*\\(fn\\|def\\)\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)"
  "Regexp to match Mojo function definitions.")

(defconst mojo-struct-def-regexp
  "^\\s-*\\(struct\\|trait\\)\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)"
  "Regexp to match Mojo struct and trait definitions.")

(defconst mojo-parameter-regexp
  "\\[\\s-*\\([a-zA-Z_][a-zA-Z0-9_]*\\)\\s-*:"
  "Regexp to match parameter declarations in square brackets.")

(defconst mojo-argument-convention-regexp
  "\\(read\\|mut\\|out\\|deinit\\|ref\\|var\\|inout\\|borrowed\\|owned\\)\\s-+"
  "Regexp to match argument convention annotations.")

(defconst mojo-number-regexp
  (concat
   "\\_<"
   "\\(?:"
   "0[xX][0-9a-fA-F_]*\\(?:\\.[0-9a-fA-F_]+\\)?\\(?:[pP][+-]?[0-9]+\\)?"
   "\\|"
   "0[bB][01_]+"
   "\\|"
   "0[oO][0-7_]+"
   "\\|"
   "[0-9][0-9_]*\\(?:\\.[0-9_]+\\)?\\(?:[eE][+-]?[0-9]+\\)?"
   "\\|"
   "\\.[0-9][0-9_]*\\(?:[eE][+-]?[0-9]+\\)?"
   "\\)"
   "\\(?:[ui][0-9]*\\|f[0-9]*\\)?"
   "\\_>")
  "Regexp to match Mojo numeric literals.")

;; ---- Font lock specification --------------------------------------------

(defconst mojo-font-lock-keywords
  `(
    (,mojo-decorator-regexp 1 font-lock-preprocessor-face)
    (,mojo-function-def-regexp 2 font-lock-function-name-face)
    (,mojo-struct-def-regexp 2 font-lock-type-face)
    (,mojo-parameter-regexp 1 font-lock-variable-name-face)
    (,mojo-argument-convention-regexp 1 font-lock-keyword-face)
    (,mojo-keyword-regexp . font-lock-keyword-face)
    (,mojo-type-regexp . font-lock-type-face)
    (,mojo-constant-regexp . font-lock-constant-face)
    (,mojo-number-regexp . font-lock-constant-face)
    ("\\(->\\|\\.\\.\\.\\)" . font-lock-keyword-face)
    ("raises\\s-+\\([A-Z][a-zA-Z0-9_]*\\)" 1 font-lock-type-face)
    ("where\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1 font-lock-variable-name-face)
    ("\\(struct\\|trait\\)\\s-+[a-zA-Z_][a-zA-Z0-9_]*\\s-*(\\([^)]*\\))"
     2 font-lock-type-face)
    ("comptime\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)"
     1 font-lock-variable-name-face)
    ("var\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)"
     1 font-lock-variable-name-face)
    (":\\s-*\\([A-Z][a-zA-Z0-9_]*\\)" 1 font-lock-type-face)
    )
  "Font lock keywords for Mojo mode.")

;; ---- Syntax table -------------------------------------------------------

(defvar mojo-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Comments: # to end of line
    (modify-syntax-entry ?# "<" table)
    (modify-syntax-entry ?\n ">" table)

    ;; Strings
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?' "\"" table)

    ;; Punctuation
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?= "." table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?* "." table)
    (modify-syntax-entry ?/ "." table)
    (modify-syntax-entry ?% "." table)
    (modify-syntax-entry ?& "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?^ "." table)
    (modify-syntax-entry ?~ "." table)
    (modify-syntax-entry ?! "." table)

    ;; @ is symbol constituent (thing-at-point includes it, word motion stops)
    (modify-syntax-entry ?@ "_" table)

    ;; _ is word constituent (snake_case)
    (modify-syntax-entry ?_ "w" table)

    ;; Paired brackets
    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    (modify-syntax-entry ?\{ "(}" table)
    (modify-syntax-entry ?\} "){" table)

    table)
  "Syntax table for Mojo mode.")

;; ---- Triple-quoted string support ---------------------------------------

(defun mojo--syntax-stringify ()
  "Put string-fence syntax on triple-quoted string delimiters."
  (let* ((ppss (save-excursion
                 (backward-char 3)
                 (syntax-ppss)))
         (in-string (nth 3 ppss)))
    (cond
     ;; Not in a string — this is an opening triple quote
     ((not in-string)
      (put-text-property (- (point) 3) (- (point) 2)
                         'syntax-table (string-to-syntax "|")))
     ;; In a string — this is the closing triple quote.
     ;; String-fence "|" syntax makes (nth 3 ppss) return t, not the
     ;; quote character, so we just check for any active string.
     (in-string
      (put-text-property (1- (point)) (point)
                         'syntax-table (string-to-syntax "|"))))))

(defconst mojo--syntax-propertize-function
  (syntax-propertize-rules
   ((rx (or "\"\"\"" "'''"))
    (0 (ignore (mojo--syntax-stringify)))))
  "Syntax-propertize rules for triple-quoted strings.")

;; ---- Helper functions ---------------------------------------------------

(defun mojo--current-line-empty-p ()
  "Return non-nil if the current line is empty or whitespace-only."
  (save-excursion
    (beginning-of-line)
    (looking-at "^\\s-*$")))

(defun mojo--current-line-comment-p ()
  "Return non-nil if the current line is a comment-only line."
  (save-excursion
    (beginning-of-line)
    (looking-at "^\\s-*#")))

(defun mojo--in-string-p ()
  "Return non-nil if point is inside a string."
  (nth 3 (syntax-ppss)))

(defun mojo--in-comment-p ()
  "Return non-nil if point is inside a comment."
  (nth 4 (syntax-ppss)))

(defun mojo--paren-depth ()
  "Return the paren nesting depth at the beginning of the current line."
  (car (syntax-ppss (line-beginning-position))))

(defun mojo--innermost-paren-pos ()
  "Return position of innermost enclosing paren, or nil."
  (nth 1 (syntax-ppss (line-beginning-position))))

;; ---- Indentation --------------------------------------------------------

(defconst mojo--dedenter-regexp
  (rx symbol-start (or "elif" "else" "except" "finally") symbol-end)
  "Regexp matching Mojo dedenter keywords.")

(defun mojo--line-ends-with-colon-p ()
  "Return non-nil if the current line ends with a colon (ignoring comments)."
  (save-excursion
    (end-of-line)
    (forward-comment -1)
    (skip-chars-backward " \t")
    (eq (char-before) ?:)))

(defun mojo--line-opens-block-p ()
  "Return non-nil if current line opens a Mojo block.
A line opens a block when it ends with `:` (ignoring comments).
This covers single-line definitions (`def foo():`) and the closing
line of multiline signatures (`):`)."
  (mojo--line-ends-with-colon-p))

(defun mojo--previous-code-line-pos ()
  "Return point of the previous non-empty, non-comment line."
  (save-excursion
    (let ((found nil))
      (while (and (not found) (not (bobp)))
        (forward-line -1)
        (unless (or (mojo--current-line-empty-p)
                    (mojo--current-line-comment-p))
          (setq found (point))))
      found)))

(defun mojo--current-line-dedenter-p ()
  "Return non-nil if the current line starts with a dedenter keyword."
  (save-excursion
    (back-to-indentation)
    (looking-at mojo--dedenter-regexp)))

(defun mojo--current-line-closing-paren-p ()
  "Return non-nil if current line starts with a closing bracket."
  (save-excursion
    (back-to-indentation)
    (looking-at "[])}]")))

(defun mojo--indent-inside-paren (paren-pos)
  "Compute indentation for a line inside parens opening at PAREN-POS."
  (let* ((paren-line-indent (save-excursion
                              (goto-char paren-pos)
                              (current-indentation)))
         (content-col (save-excursion
                        (goto-char (1+ paren-pos))
                        (skip-chars-forward " \t")
                        (unless (or (eolp) (looking-at "#"))
                          (current-column)))))
    (cond
     ;; Closing bracket: align with the line that has the opening bracket
     ((mojo--current-line-closing-paren-p)
      paren-line-indent)
     ;; Content after opening paren on same line: align with it
     (content-col
      content-col)
     ;; Nothing after opening paren: indent one level from its line
     (t
      (+ paren-line-indent mojo-indent-offset)))))

(defun mojo-indent-line ()
  "Indent current line as Mojo code."
  (interactive)
  (let* ((ppss (save-excursion (beginning-of-line) (syntax-ppss)))
         (in-string (nth 3 ppss))
         (paren-pos (nth 1 ppss))
         (pos (- (point-max) (point)))
         indentation)
    (cond
     ;; Inside a string: leave indentation alone
     (in-string nil)
     ;; Inside parens
     (paren-pos
      (setq indentation (mojo--indent-inside-paren paren-pos)))
     ;; Dedenter keyword: dedent one level from previous code line
     ((mojo--current-line-dedenter-p)
      (let ((prev-pos (mojo--previous-code-line-pos)))
        (setq indentation
              (if prev-pos
                  (max 0 (- (save-excursion
                              (goto-char prev-pos)
                              (current-indentation))
                            mojo-indent-offset))
                0))))
     ;; Normal: if previous line opens a block, indent; else same level
     (t
      (let ((prev-pos (mojo--previous-code-line-pos)))
        (when prev-pos
          (save-excursion
            (goto-char prev-pos)
            (setq indentation
                  (if (mojo--line-opens-block-p)
                      (+ (current-indentation) mojo-indent-offset)
                    (current-indentation))))))))
    ;; Apply indentation
    (when indentation
      (indent-line-to indentation)
      (when (> (- (point-max) pos) (point))
        (goto-char (- (point-max) pos))))))

;; ---- Navigation ---------------------------------------------------------

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

(defun mojo--end-of-block ()
  "Move to the end of the current indented block."
  (let ((initial-indent (current-indentation)))
    (forward-line 1)
    (while (and (not (eobp))
                (or (mojo--current-line-empty-p)
                    (mojo--current-line-comment-p)
                    (> (current-indentation) initial-indent)))
      (forward-line 1))
    ;; Back up past trailing empty lines to last content line
    (forward-line -1)
    (while (and (not (bobp))
                (mojo--current-line-empty-p))
      (forward-line -1))
    (end-of-line)))

(defun mojo-end-of-defun (&optional arg)
  "Move to end of Mojo function/struct/trait.
With positive ARG, move forward that many definitions.
With negative ARG, move backward."
  (interactive "p")
  (let ((arg (or arg 1)))
    (when (mojo-beginning-of-defun arg)
      (mojo--end-of-block))))

;; ---- Imenu --------------------------------------------------------------

(defvar mojo-imenu-generic-expression
  `(("Trait" "^\\s-*trait\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1)
    ("Struct" "^\\s-*struct\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1)
    ("Function" "^\\s-*\\(?:fn\\|def\\)\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)" 1))
  "Imenu expression for Mojo mode.")

;; ---- Which-func ---------------------------------------------------------

(defun mojo-which-function ()
  "Return the name of the Mojo function at point."
  (save-excursion
    (when (mojo-beginning-of-defun 1)
      (when (looking-at "^\\s-*\\(?:fn\\|def\\|struct\\|trait\\)\\s-+\\([a-zA-Z_][a-zA-Z0-9_]*\\)")
        (match-string-no-properties 1)))))

;; ---- Compilation --------------------------------------------------------

(defvar mojo-compilation-error-regexp-alist
  `((,(concat "^\\([^:]+\\):\\([0-9]+\\):\\([0-9]+\\):\\s-*"
             "error:\\s-*\\(.+\\)$")
     1 2 3 2)
    (,(concat "^\\([^:]+\\):\\([0-9]+\\):\\([0-9]+\\):\\s-*"
             "warning:\\s-*\\(.+\\)$")
     1 2 3 1)
    (,(concat "^\\([^:]+\\):\\([0-9]+\\):\\([0-9]+\\):\\s-*"
             "note:\\s-*\\(.+\\)$")
     1 2 3 0))
  "Regexp to match Mojo compiler errors, warnings, and notes.")

;; ---- Formatting ---------------------------------------------------------

(defun mojo-format-buffer ()
  "Format the current buffer using mojo format."
  (interactive)
  (if (fboundp 'mojo/format-buffer)
      (mojo/format-buffer)
    (when (buffer-file-name)
      (shell-command-on-region (point-min) (point-max)
                               "mojo format -" nil t))))

;; ---- REPL ---------------------------------------------------------------

(defvar mojo-repl-buffer-name "*Mojo REPL*"
  "Name of the Mojo REPL buffer.")

(defun mojo-run-repl ()
  "Run a Mojo REPL interpreter."
  (interactive)
  (if (fboundp 'mojo/run-repl)
      (mojo/run-repl)
    (require 'comint)
    (let ((buffer (get-buffer-create mojo-repl-buffer-name)))
      (unless (comint-check-proc buffer)
        (apply #'make-comint-in-buffer "Mojo REPL" buffer "mojo" nil '("repl")))
      (pop-to-buffer buffer))))

(defun mojo-send-region (start end)
  "Send the region between START and END to the Mojo REPL."
  (interactive "r")
  (if (fboundp 'mojo/send-region)
      (mojo/send-region start end)
    (require 'comint)
    (let ((code (buffer-substring-no-properties start end)))
      (with-current-buffer (get-buffer-create mojo-repl-buffer-name)
        (unless (comint-check-proc (current-buffer))
          (apply #'make-comint-in-buffer "Mojo REPL" (current-buffer)
                 "mojo" nil '("repl")))
        (goto-char (process-mark (get-buffer-process (current-buffer))))
        (insert code)
        (comint-send-input)))))

(defun mojo-send-buffer ()
  "Send the entire buffer to the Mojo REPL."
  (interactive)
  (if (fboundp 'mojo/send-buffer)
      (mojo/send-buffer)
    (mojo-send-region (point-min) (point-max))))

;; ---- Flycheck -----------------------------------------------------------

(defun mojo-flycheck-setup ()
  "Setup flycheck for Mojo if available."
  (when (require 'flycheck nil t)
    ;; Only define the basic checker when the layer hasn't already registered
    ;; a pixi-aware one.
    (unless (flycheck-registered-checker-p 'mojo)
      (eval
       '(flycheck-define-checker mojo
          "A Mojo syntax checker using the mojo compiler."
          :command ("mojo" "build" "--emit" "object" "-o" (eval null-device) source-original)
          :error-patterns
          ((error line-start (file-name) ":" line ":" column ": error: " (message) line-end)
           (error line-start (file-name) ": error: " (message) line-end)
           (warning line-start (file-name) ":" line ":" column ": warning: " (message) line-end)
           (warning line-start (file-name) ": warning: " (message) line-end)
           (info line-start (file-name) ":" line ":" column ": note: " (message) line-end))
          :modes mojo-mode))
      (add-to-list 'flycheck-checkers 'mojo))))

;; ---- Eldoc --------------------------------------------------------------

(defconst mojo--eldoc-descriptions
  '(;; Keywords
    ("def"       . "function definition")
    ("struct"    . "value type definition")
    ("trait"     . "interface/protocol definition")
    ("var"       . "mutable variable binding")
    ("comptime"  . "compile-time constant or expression")
    ("read"      . "immutable borrow convention (default, rarely written)")
    ("mut"       . "mutable reference convention")
    ("out"       . "uninitialized output convention (constructors)")
    ("deinit"    . "consuming/destroying convention")
    ("ref"       . "reference with origin tracking")
    ("raises"    . "function may raise an error")
    ("where"     . "parametric constraint clause")
    ("fn"        . "[deprecated] use def instead")
    ("let"       . "[removed] use var instead")
    ("alias"     . "[removed] use comptime instead")
    ("inout"     . "[deprecated] use mut instead")
    ("borrowed"  . "[deprecated] use read instead")
    ("owned"     . "[deprecated] use var (arg) or deinit instead")
    ;; Decorators
    ("@fieldwise_init" . "generate constructor from fields")
    ("@implicit"       . "allow implicit type conversion")
    ("@always_inline"  . "force function inlining")
    ("@no_inline"      . "prevent function inlining")
    ("@staticmethod"   . "static method (no self)")
    ("@deprecated"     . "mark as deprecated with message")
    ("@explicit_destroy" . "linear type — no implicit destruction")
    ;; Types
    ("Pointer"     . "safe non-nullable pointer, deref with p[]")
    ("UnsafePointer" . "raw pointer, requires manual free()")
    ("OwnedPointer"  . "unique ownership (like Rust Box)")
    ("ArcPointer"    . "reference-counted shared ownership")
    ("Span"        . "non-owning contiguous view")
    ("Some"        . "builtin existential type wrapper")
    ("Origin"      . "reference provenance tracker")
    ("Writable"    . "trait for write_to() — replaces Stringable")
    ("Writer"      . "output sink for Writable types")
    ("Self"        . "current type — qualify params as Self.T inside structs"))
  "Brief descriptions for Mojo symbols shown by eldoc.")

(defun mojo-eldoc-function (_callback)
  "Return eldoc documentation for the symbol at point.
CALLBACK is ignored; the docstring is returned directly."
  (let ((symbol (thing-at-point 'symbol t)))
    (when symbol
      (let ((desc (cdr (assoc symbol mojo--eldoc-descriptions))))
        (cond
         (desc (format "%s — %s" symbol desc))
         ((member symbol mojo-keywords)
          (format "%s — keyword" symbol))
         ((member symbol mojo-types)
          (format "%s — type" symbol))
         ((member symbol mojo-constants)
          (format "%s — constant" symbol)))))))

;; ---- Major mode definition ----------------------------------------------

;;;###autoload
(define-derived-mode mojo-mode prog-mode "Mojo"
  "Major mode for editing Mojo source code.

Standalone mode derived from `prog-mode'.  Does not inherit
any `python-mode' hooks, LSP clients, or minor modes.

Key bindings:
\\{mojo-mode-map}"
  :group 'mojo
  :syntax-table mojo-mode-syntax-table

  ;; Font lock
  (setq-local font-lock-defaults '(mojo-font-lock-keywords nil nil nil nil))

  ;; Triple-quoted strings
  (setq-local syntax-propertize-function mojo--syntax-propertize-function)

  ;; Indentation
  (setq-local indent-line-function #'mojo-indent-line)
  (setq-local tab-width mojo-indent-offset)
  (setq-local electric-indent-inhibit t)

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
  (add-hook 'eldoc-documentation-functions #'mojo-eldoc-function nil t)

  ;; Compilation
  (setq-local compilation-error-regexp-alist mojo-compilation-error-regexp-alist)

  ;; Format on save
  (when mojo-format-on-save
    (add-hook 'before-save-hook #'mojo-format-buffer nil t))

  ;; Flycheck
  (mojo-flycheck-setup))

;; ---- Key bindings -------------------------------------------------------

(define-key mojo-mode-map (kbd "C-c C-z") #'mojo-run-repl)
(define-key mojo-mode-map (kbd "C-c C-c") #'mojo-send-buffer)
(define-key mojo-mode-map (kbd "C-c C-r") #'mojo-send-region)
(define-key mojo-mode-map (kbd "C-c C-f") #'mojo-format-buffer)

;; ---- Auto-mode-alist ----------------------------------------------------

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.mojo\\'" . mojo-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.🔥\\'" . mojo-mode))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.mojo\\'" . mojo-mode))
;;;###autoload
(add-to-list 'interpreter-mode-alist '("mojo" . mojo-mode))

(provide 'mojo-mode)

;;; mojo-mode.el ends here
