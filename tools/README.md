# TOOLS

Workstation tooling: shell, editor, git and terminal multiplexer configuration.

Target platform: **Debian Trixie** (or later), GNOME/Wayland, bash, gnome-terminal.

## Layout

One self-contained script per tool. Each installs its apt dependencies, installs
or updates anything not shipped by Debian, and writes its configuration **in
place** with a fresh copy every run.

```
tools/
├── bash.sh        shell env: apt CLI tools, font, .bashrc, prompt
├── neovim.sh      Neovim (tarball, pinned) + full editor config
├── opencode.sh    OpenCode 2 binary + its config
└── tmux.sh        tmux + session persistence + systemd restore unit
```

## Usage

Run any script individually, or all of them:

```sh
for s in tools/*.sh; do bash "$s"; done
```

Every script is **idempotent**: safe to re-run many times, it only installs
what is missing and overwrites the configuration in place. Bump the `VERSION`
variable at the top of a script (Neovim, OpenCode) and re-run to upgrade;
non-apt git checkouts (TPM, tmux-resurrect, the Nerd Font) are refreshed with a
`git pull --ff-only` / re-download on every run.

`sudo` is requested **only** when an apt package is actually missing
(`apt_install` skips anything already installed). Nothing outside `$HOME` is
touched except apt.

After a fresh run:

```sh
exec bash            # pick up the new shell config
nvim                 # lazy.nvim bootstraps plugins on first launch
:MasonToolsInstall   # language servers + formatters
:checkhealth
```

## What each script owns

| Script | apt packages | Non-apt (updated on re-run) | Config written in place |
| --- | --- | --- | --- |
| `bash.sh` | fzf, ripgrep, fd-find, bat, eza, zoxide, direnv, starship, git-delta, lazygit | MesloLGS Nerd Font **Mono**, gnome-terminal font (via gsettings, no sudo) | `~/.bashrc`, `~/.config/bash/{env,aliases,tools,prompt}.sh`, `~/.config/starship.toml`, `~/.local/bin/{bat,fd}` shims |
| `neovim.sh` | make, clangd, clang-format, shellcheck, yamllint, python3-venv, fzf, fd-find, ripgrep | **Neovim** tarball → `~/.local/opt/nvim-$VERSION` | `~/.config/nvim/` (init.lua, lua/config/*, lua/plugins/*, lazy-lock.json) |
| `opencode.sh` | libnotify-bin (desktop notifications, optional) | **OpenCode 2** via the official installer | `~/.config/opencode/{cli.json,opencode.jsonc}` |
| `tmux.sh` | tmux, wl-clipboard, fzf | **TPM** + **tmux-resurrect** (git clone / pull) | `~/.tmux.conf`, `~/.config/systemd/user/tmux-persist.service` |

## Toolchain

| Concern | Tool |
| --- | --- |
| Fuzzy find | `fzf` (`C-t` files, `C-r` history, `M-c` cd) |
| Search | `ripgrep` |
| File listing | `eza`, `bat` |
| Directory jump | `zoxide` (`z`, `zi`) |
| Per-project env | `direnv` |
| Git TUI / diffs | `lazygit`, `delta` |
| Prompt | `starship`, `__git_ps1` fallback |
| Editor | Neovim (pinned tarball), installed to `~/.local/opt` |
| Multiplexer | `tmux`, prefix `C-Space`, resurrect for reboot persistence |

Debian renames two binaries (`bat`→`batcat`, `fd`→`fdfind`); `bash.sh` creates
`~/.local/bin` symlinks restoring the upstream names, because `FZF_DEFAULT_COMMAND`
and scripts need real executables rather than aliases.

## Notes and deliberate choices

- **Neovim is not the apt package.** Trixie ships 0.10.x; this config needs 0.12+
  for `vim.lsp.config`/`vim.lsp.enable`, `'autocomplete'` and `'winborder'`.
  `neovim.sh` removes the apt package and installs the pinned tarball to
  `~/.local/opt/nvim-$VERSION`. Bump `VERSION` to upgrade.
- **Removing apt neovim orphans `xclip`.** `neovim.sh` runs `apt-mark manual
  xclip` beforehand. Avoid `apt autoremove` immediately after a fresh run.
- **Git is applied once, not scripted.** `~/.config/git/{config,ignore}` are
  real files (written from the old `git/` package); `git config --global` is
  safe because `config` is no longer a symlink.
- **`~/.bashrc.local` is the machine-local escape hatch.** `bash.sh` sources it
  from the end of `~/.bashrc` and never touches it, so personal aliases and
  exports survive re-runs.
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
- **Clipboard is Wayland-first.** `copy-command` is `wl-copy`, so every copy
  path lands in the Wayland clipboard, and `prefix+v` pastes it (bracketed). Over
  SSH `wl-paste` isn't on the remote, so `prefix+v` pastes the tmux buffer.
- **`Ctrl+Shift+C`/`Ctrl+Shift+V` are terminal shortcuts, not tmux's.**
  gnome-terminal/VTE intercepts both before tmux sees them and also lacks OSC
  52 support, so `set-clipboard` is a no-op here.
- **The prompt is `starship`**, kept deliberately minimal (directory, git
  branch/status, prompt character only). If the binary is absent, `prompt.sh`
  falls back to a minimal `__git_ps1` prompt.
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
- **Plugin versions are pinned in `lazy-lock.json`** (embedded in `neovim.sh`);
  language servers are pinned by the `ensure_installed` list in `lsp.lua`.
- **OpenCode 2 is installed via `opencode.ai/v2/install`**, *not*
  `opencode.ai/install` (that is the V1 installer and would downgrade/break the
  V2 config). Re-running `opencode.sh` updates to the latest V2 release.

## tmux session persistence

`tmux.sh` installs TPM + `tmux-resurrect` and enables a systemd user unit
(`~/.config/systemd/user/tmux-persist.service`) that restores your sessions at
login and saves them at logout, so a reboot loses nothing:

- `prefix + C-s` — save now
- `prefix + C-r` — restore the last saved state

Snapshots live under `~/.local/share/tmux/resurrect/` (the XDG fallback used
when `~/.tmux/resurrect` doesn't exist).