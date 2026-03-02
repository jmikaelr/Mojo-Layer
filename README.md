# Mojo Layer for Spacemacs

Spacemacs layer providing support for the [Mojo language](https://www.modular.com/mojo).

## Features

- `mojo-mode` major mode with syntax highlighting and indentation
- LSP support via `mojo-lsp-server`
- Build/run/test/format commands (`mojo` + `pixi` aware)
- REPL helpers and send-region/buffer commands
- Fallback definition/reference search in project + configured source roots
- Flycheck and YASnippet integration

## Install

1. Clone this repository somewhere on disk:

```sh
git clone <your-repo-url> ~/code/spacemacs-layers/mojo
```

2. Point Spacemacs at your external layer path:

```elisp
(setq-default dotspacemacs-configuration-layer-path
              '("~/code/spacemacs-layers/"))
```

3. Enable the layer:

```elisp
(setq-default dotspacemacs-configuration-layers
              '(mojo))
```

4. Restart Emacs or press `SPC f e R`.

## Requirements

- Spacemacs
- Mojo CLI (`mojo`) available in `PATH` or via `pixi`
- Optional: `mojo-lsp-server`

## Validation

Run checks locally:

```sh
emacs -Q --batch -l scripts/ci-check.el
```

## Documentation

Full documentation and configuration options are in `README.org`.

## License

MIT (see `LICENSE`).
