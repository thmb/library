# TOOL

Workstation tooling: shell, editor, git and terminal multiplexer configuration.

Target platform: **Debian Trixie**, GNOME/Wayland, bash, gnome-terminal.

## Layout

Each of `bash/`, `neovim/`, `git/` and `tmux/` is a [GNU stow](https://www.gnu.org/software/stow/)
package whose internal structure mirrors `$HOME`.

```
tool/
├── setup.sh        reproduces the whole toolchain on a fresh machine
├── packages.txt    apt package list consumed by setup.sh
├── bash/           .bashrc + .config/bash/{env,aliases,tools,prompt}.sh,
│                   .config/oh-my-posh/ (p10k-style theme)
├── neovim/         .config/nvim/  (Neovim >= 0.12)
├── git/            .config/git/{tracked.conf,ignore}
└── tmux/           .tmux.conf
```

## Install

```sh
./setup.sh              # apt packages, Neovim tarball, font, stow
./setup.sh --no-sudo    # skip the apt steps
./setup.sh --stow       # only re-link the dotfiles
```

Then:

```sh
exec bash
nvim                    # lazy.nvim bootstraps plugins on first launch
:MasonToolsInstall      # language servers and formatters
:checkhealth
```

Linking by hand is equivalent to:

```sh
stow --dir /opt/github/thmb/library/tool --target "$HOME" bash neovim git tmux
```

## Toolchain

| Concern | Tool |
| --- | --- |
| Fuzzy find | `fzf` (`C-t` files, `C-r` history, `M-c` cd) |
| Search | `ripgrep` |
| File listing | `eza`, `bat` |
| Directory jump | `zoxide` (`z`, `zi`) |
| Per-project env | `direnv` |
| Git TUI / diffs | `lazygit`, `delta` |
| Prompt | `oh-my-posh` (powerlevel10k_lean), `__git_ps1` fallback |
| Editor | Neovim 0.12.5, installed to `~/.local/opt` |
| Multiplexer | `tmux`, prefix `C-Space` |

Debian renames two binaries (`bat`→`batcat`, `fd`→`fdfind`); `setup.sh` creates
`~/.local/bin` symlinks restoring the upstream names, because
`FZF_DEFAULT_COMMAND` and scripts need real executables rather than aliases.

## Notes and deliberate choices

- **Neovim is not the apt package.** Trixie ships 0.10.4; this config needs 0.12
  for `vim.lsp.config`/`vim.lsp.enable`, `'autocomplete'` and `'winborder'`.
  `setup.sh` removes the apt package and installs the pinned tarball to
  `~/.local/opt/nvim-$NVIM_VERSION`. Bump `NVIM_VERSION` to upgrade.
- **Removing apt neovim orphans `xclip`.** `setup.sh` runs `apt-mark manual
  xclip` beforehand. Avoid `apt autoremove` immediately after a fresh run.
- **`~/.config/git/config` is intentionally a real file**, not a stow symlink.
  `git config --global` rewrites via lockfile+rename and would replace a symlink
  with a regular file; it therefore only `include`s `tracked.conf`.
- **No completion plugin.** Neovim 0.12's `'autocomplete'` plus
  `vim.lsp.completion.enable()` covers it.
- **No statusline plugin.** The 0.12 default statusline already shows
  diagnostics, LSP progress and `'busy'`; the git branch is added from
  `b:gitsigns_head`.
- **`diffview.nvim` is deliberately absent** (no upstream commits since
  2024-08). Branch review uses `lazygit`, fzf-lua's `git_commits`/`git_bcommits`,
  `gitsigns.diffthis` and Neovim 0.12's built-in `:DiffTool`.
- **`nvim-treesitter-textobjects` is present as a query provider only.**
  `mini.ai` reads its `textobjects.scm` files; treesitter core ships none.
- **`tmux` prefix is `C-Space`**, which costs only readline's unused `set-mark`.
  The default `C-b` would shadow `backward-char` in bash and `<C-b>` in Neovim.
- **Pane navigation is `M-hjkl`, not `C-hjkl`**, because `C-h` is backspace and
  `C-l` is clear-screen in readline.
- **The prompt is PowerLevel10k-style, not powerlevel10k.** p10k is a zsh
  theme; on bash the equivalent look comes from `oh-my-posh` running its
  `powerlevel10k_lean` theme (tracked in `bash/.config/oh-my-posh/`). If the
  binary is absent, `prompt.sh` falls back to a minimal `__git_ps1` prompt.
- **The terminal font is the Nerd Font *Mono* variant, using MesloLGS.** The
  plain `Meslo Nerd Font` (and `JetBrainsMono Nerd Font`) lets icon glyphs take
  their natural (often double) width, which misaligns text in a fixed-cell
  terminal and reads as excessive horizontal spacing. `...NerdFontMono` forces
  every glyph into one cell; Meslo is also tighter than JetBrainsMono.
- **`.tf` is pinned to the `terraform` filetype.** Neovim's `.tf` detection is
  content-sensitive: a new or comment-only file is classified as `tf`, which is
  TinyFugue (a MUD scripting language), so it would get neither terraformls nor
  a formatter until real HCL was typed. `options.lua` pins the extension.
- **Terraform formatting runs `tofu`, not `terraform`.** conform's builtin
  `terraform_fmt` hardcodes the `terraform` binary; this machine has OpenTofu,
  so `plugins/lsp.lua` overrides the command.
- **`python3-venv` is required** for mason's PyPI installer (`ensurepip`); without
  it `basedpyright` fails with an opaque `spawn: python3 failed`.
- Plugin versions are pinned in `neovim/.config/nvim/lazy-lock.json`; language
  servers are pinned by the `ensure_installed` list in `plugins/lsp.lua`.
- **`document_color` and `linked_editing_range` are enabled globally, not
  per-buffer.** Requiring `vim.lsp.document_color` *is* the enable call (it
  self-enables on load), whereas `linked_editing_range` needs an explicit
  `enable()`. Both take a filter *table*, not a buffer number - passing a
  bufnr raises `filter: expected table, got number` on every buffer open.

## Reverting

```sh
stow --dir /opt/github/thmb/library/tool --target "$HOME" -D bash neovim git tmux
sudo apt install neovim          # restore Debian's 0.10.4
```
