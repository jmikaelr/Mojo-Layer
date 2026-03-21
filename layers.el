;;; layers.el --- Layer dependencies for Mojo layer -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Richard Johnsson

;; Author: Richard Johnsson
;; Keywords: mojo, languages

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file declares the dependencies for the Mojo layer.
;; The Mojo layer requires:
;; - lsp layer for language server support
;; - syntax-checking layer for flycheck integration

;;; Code:

(configuration-layer/declare-layers
 '(lsp
   syntax-checking))

;;; layers.el ends here
