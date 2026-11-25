# TOOLS

Workstation tooling: terminal, shell, editor, tmux and OpenCode.

Target platform: **Debian Trixie** (or later), GNOME/Wayland, bash, Alacritty.

## Layout

One self-contained script per tool. Each installs its apt dependencies, installs
or updates anything not shipped by Debian, and writes its configuration **in
place** with a fresh copy every run.

```
tools/
├── terminal.sh   Alacritty + shell env: packages, font, dotfiles
├── neovim.sh     Neovim (tarball, pinned) + full editor config
├── opencode.sh   OpenCode 2 binary + its config
└── tmux.sh       tmux + session persistence + OSC 52 clipboard wiring
```

## Usage

Run any script individually, or all of them:

```sh
for s in tools/*.sh; do bash "$s"; done
```

Every script is **idempotent**: safe to re-run many times, it only installs
what is missing and overwrites the configuration in place. Bump the `VERSION`
variable at the top of a script (Neovim, OpenCode) and re-run to upgrade; the
non-apt install (the Nerd Font) is refreshed with a re-download on every run.

`sudo` is used for apt and for setting the default terminal
(`update-alternatives`); everything else is per-user and stays inside `$HOME`.

After a fresh run:

```sh
exec bash            # pick up the new shell config
nvim                 # vim.pack installs plugins at pinned revisions
:MasonToolsInstall   # language servers + formatters
:checkhealth
```

## What each script owns

| Script | apt packages | Non-apt (updated on re-run) | Config written in place |
| --- | --- | --- | --- |
| `terminal.sh` | alacritty, bat, direnv, eza, fd-find, fzf, git-delta, lazygit, ripgrep, starship, zoxide | MesloLGS Nerd Font **Mono** (used by alacritty.toml) | `~/.config/alacritty/alacritty.toml`, `~/.bashrc` (stock + hooks), `~/.bashrc.custom`, `~/.config/starship.toml`, `~/.local/bin/{bat,fd}` shims |
| `neovim.sh` | make, gcc, clangd, clang-format, shellcheck, yamllint, python3-venv, fzf, fd-find, ripgrep, wl-clipboard | **Neovim** tarball → `~/.local/opt/nvim-$VERSION`; **tree-sitter** CLI binary → `~/.local/opt/tree-sitter-$TS_VERSION`; tree-sitter-jsonc checkout → `~/.local/opt/grammars/` (both pinned) | `~/.config/nvim/` (init.lua, lua/config/*, lua/plugins/*, queries/jsonc/*) |
| `opencode.sh` | libnotify-bin (desktop notifications, optional) | **OpenCode 2** via the official installer | `~/.config/opencode/{cli.json,opencode.jsonc}` |
| `tmux.sh` | tmux | **TPM** + **tmux-resurrect** (git clone / pull) | `~/.tmux.conf`, `~/.config/systemd/user/tmux-persist.service` |

## Toolchain

| Concern | Tool |
| --- | --- |
| Terminal | Alacritty (apt), F11 fullscreen, OSC 52 clipboard; tmux for tabs/splits |
| Terminal font | MesloLGS Nerd Font **Mono** |
| Fuzzy find | `fzf` (`C-t` files, `C-r` history, `M-c` cd) |
| Search | `ripgrep` |
| File listing | `eza`, `bat` |
| Directory jump | `zoxide` (`z`, `zi`) |
| Per-project env | `direnv` |
| Git TUI / diffs | `lazygit`, `delta` |
| Prompt | `starship` |
| Editor | Neovim (pinned tarball), installed to `~/.local/opt` |

Debian renames two binaries (`bat`→`batcat`, `fd`→`fdfind`); `terminal.sh`
creates `~/.local/bin` symlinks restoring the upstream names, because
`FZF_DEFAULT_COMMAND` and scripts need real executables rather than aliases.

## Notes and deliberate choices

- **Shell config is split in two.** `~/.bashrc` is stock Debian plus two hooks;
  `~/.bashrc.custom` is rewritten by `terminal.sh` every run, and
  `~/.bashrc.personal` is yours and never touched.
- **Neovim is not the apt package.** Trixie ships 0.10.x; this config needs 0.12+
  for `vim.lsp.config`/`vim.lsp.enable`, `'autocomplete'` and `'winborder'`.
  `neovim.sh` removes the apt package and installs the pinned tarball to
  `~/.local/opt/nvim-$VERSION`. Bump `VERSION` to upgrade.
- **Clipboard: OSC 52 for writes, wl-paste/xclip for reads.** Alacritty accepts
  OSC 52 copies (`terminal.osc52 = "OnlyCopy"`). tmux forwards yanks to the
  terminal via OSC 52 (`set-clipboard on`), and OpenCode's OSC 52 writes reach
  the terminal through tmux passthrough (`allow-passthrough on`); no helper
  tools there. Neovim yanks over OSC 52 too, but `"+` paste reads the desktop
  clipboard with `wl-paste`/`xclip` because OSC 52 reads do not round-trip
  through tmux. That read path is the only reason `neovim.sh` installs
  `wl-clipboard`.
- **gnome-terminal stays installed as a fallback, with stock configuration.**
  VTE has no OSC 52, so the clipboard integration needs Alacritty.
- **Removing apt neovim orphans `xclip`.** `neovim.sh` runs `apt-mark manual
  xclip` beforehand. Avoid `apt autoremove` immediately after a fresh run.
- **Git is applied once, not scripted.** `~/.config/git/{config,ignore}` are
  real files (written from the old `git/` package); `git config --global` is
  safe because `config` is no longer a symlink.
- **No completion plugin.** Neovim 0.12's `'autocomplete'` plus
  `vim.lsp.completion.enable()` covers it.
- **No statusline plugin.** The 0.12 default statusline already shows
  diagnostics, LSP progress and `'busy'`; the git branch is added from
  `b:gitsigns_head`.
- **The tabline is `barbar.nvim`.** Each tab shows two state layers: gitsigns
  git marks (`+` added, `~` changed, `-` deleted versus HEAD) and the unsaved
  `●` marker, so "what have I altered?" and "what needs saving?" are both
  answered at a glance. `bufferline.nvim` shows only unsaved + LSP counts and
  has been dormant upstream since 2025-01; `mini.tabline` has no git state.
- **`diffview.nvim` is deliberately absent** (no upstream commits since
  2024-08). Branch review uses `lazygit`, fzf-lua's `git_commits`/`git_bcommits`,
  `gitsigns.diffthis` and Neovim 0.12's built-in `:DiffTool`.
- **The plugin manager is `vim.pack`** (Neovim 0.12's built-in). `packer.nvim`
  is unmaintained (2024-03) and `lazy.nvim`, while current, is still a plugin;
  the accepted cost is no lazy-loading (everything loads at startup).
  `nvim-pack-lock.json` is written and owned by Nvim; the pins live in
  `neovim.sh`.
- **`leap.nvim`, `vim-tmux-navigator`, `nvim-treesitter-textobjects` and
  mini's `surround`/`ai`/`pairs` were dropped as unused** (usage audit). In
  Nvim, pane movement is now plain `<C-w>hjkl`; `M-hjkl` moves tmux panes (the
  `tmux.sh` binding).
- **Treesitter is `nvim-treesitter` on its `main` branch** (the maintained
  rewrite for 0.12). The frozen `master` branch is EOL: its query directives
  crash on 0.12 (`attempt to call method 'range'`) and its queries shadow the
  runtime's. Parsers install to `~/.local/share/nvim/site/`; upgrade with a
  plugin pin bump, `:packupdate`, then `:TSUpdate`. The `tree-sitter` CLI is
  a pinned release binary (Debian's 0.22.6 predates main's >= 0.26.1 floor),
  and `jsonc` compiles from a pinned local checkout because its grammar's
  GitLab tarball endpoint is broken; its queries live in
  `~/.config/nvim/queries/jsonc/` and inherit json's.
- **The terminal font is the Nerd Font *Mono* variant, using MesloLGS.** The
  plain variant lets icon glyphs take natural (often double) width, which
  misaligns text in a fixed-cell terminal.
- **`.tf` is pinned to the `terraform` filetype.** Neovim's `.tf` detection is
  content-sensitive and misclassifies new/comment-only files as TinyFugue.
- **Terraform formatting runs `tofu`, not `terraform`.** conform's builtin
  hardcodes `terraform`; this machine has OpenTofu, so `plugins/lsp.lua`
  overrides the command.
- **`python3-venv` is required** for mason's PyPI installer (`ensurepip`);
  without it `basedpyright` fails with an opaque `spawn: python3 failed`.
- **Plugin versions are pinned as commit hashes** in the `vim.pack.add()`
  manifest in `config/plugins.lua` (embedded in `neovim.sh`). To upgrade: bump
  the hash, re-run `neovim.sh`, restart Nvim, then `:packupdate` and confirm.
  Language servers are pinned by the `ensure_installed` list in `lsp.lua`.
- **OpenCode 2 is installed via `opencode.ai/v2/install`**, *not*
  `opencode.ai/install` (that is the V1 installer and would downgrade/break the
  V2 config). Re-running `opencode.sh` updates to the latest V2 release.
