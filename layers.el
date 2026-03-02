;;; layers.el --- Layer dependencies for Mojo layer -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Custom Implementation
;; Keywords: mojo, languages, lsp

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This file declares the dependencies for the Mojo layer.
;; The Mojo layer requires:
;; - lsp layer for language server protocol support
;; - syntax-checking layer for flycheck integration

;;; Code:

(configuration-layer/declare-layers
 '(lsp
   syntax-checking))

;;; layers.el ends here
