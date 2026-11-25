#!/usr/bin/env bash
# terminal.sh - Alacritty terminal and shell environment
#
# Usage: ./terminal.sh
#
# Idempotent and safe to re-run: apt skips installed packages and the
# configuration is rewritten in place. Target: Debian Trixie or later
# (GNOME/Wayland).
set -euo pipefail

# --- packages: one per line -------------------------------------------------
sudo apt-get update
sudo apt-get install -y alacritty   # terminal emulator
sudo apt-get install -y bat         # cat with syntax highlighting (shim: bat -> batcat)
sudo apt-get install -y direnv      # per-directory environment
sudo apt-get install -y eza         # modern ls
sudo apt-get install -y fd-find     # fast find (shim: fd -> fdfind)
sudo apt-get install -y fzf         # fuzzy finder (C-t files, C-r history, M-c cd)
sudo apt-get install -y git-delta   # git diff pager
sudo apt-get install -y lazygit     # git TUI
sudo apt-get install -y ripgrep     # fast grep
sudo apt-get install -y starship    # prompt
sudo apt-get install -y zoxide      # smart cd (z, zi)

# --- font: MesloLGS Nerd Font Mono (one cell per glyph) ---------------------
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/font.zip" \
  https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip
mkdir -p ~/.local/share/fonts/MesloLGS
unzip -o -j "$tmp/font.zip" 'MesloLGSNerdFontMono-*.ttf' \
  -d ~/.local/share/fonts/MesloLGS >/dev/null
rm -rf "$tmp"
fc-cache -f ~/.local/share/fonts >/dev/null

# --- shims: Debian ships batcat/fdfind --------------------------------------
mkdir -p ~/.local/bin
ln -sf /usr/bin/batcat ~/.local/bin/bat
ln -sf /usr/bin/fdfind ~/.local/bin/fd

# --- configuration: rewritten every run -------------------------------------
mkdir -p ~/.config/alacritty
cat > ~/.config/alacritty/alacritty.toml <<'EOF'
# ~/.config/alacritty/alacritty.toml

[window]
padding = { x = 4, y = 4 }
dynamic_padding = true

[scrolling]
history = 50000

[font]
size = 12.0

[font.normal]
family = "MesloLGS Nerd Font Mono"   # installed by this script
style = "Regular"

[selection]
save_to_clipboard = true       # select-to-copy -> primary clipboard

[terminal]
osc52 = "OnlyCopy"             # OSC 52 copies reach the desktop clipboard

[mouse]
hide_when_typing = true

# F11 is unbound by default; all other default bindings remain.
[[keyboard.bindings]]
key = "F11"
action = "ToggleFullscreen"
EOF

# ~/.bashrc stays stock Debian; the hooks at the end source the two files below.
cp /etc/skel/.bashrc ~/.bashrc
cat >> ~/.bashrc <<'EOF'

# shell config: ~/.bashrc.custom is managed by tools/terminal.sh;
# ~/.bashrc.personal is yours and never overwritten.
[ -r ~/.bashrc.custom ] && . ~/.bashrc.custom
[ -r ~/.bashrc.personal ] && . ~/.bashrc.personal
EOF

cat > ~/.bashrc.custom <<'EOF'
# ~/.bashrc.custom - shell config, rewritten by tools/terminal.sh.

# --- env ---------------------------------------------------------------------
# ~/.local/bin holds nvim and the bat/fd shims (Debian ships batcat/fdfind).
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH="$HOME/.opencode/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

export EDITOR=nvim VISUAL=nvim PAGER=less
export MANPAGER='nvim +Man!' LESS='-R --mouse' BAT_THEME='ansi'

HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T  '
HISTIGNORE='ls:ll:la:cd:pwd:exit:clear:history'
shopt -s histappend cmdhist checkwinsize globstar autocd cdspell dirspell no_empty_cmd_completion

# --- aliases -----------------------------------------------------------------
alias ls='eza --group-directories-first'
alias ll='eza -lah --git --group-directories-first --time-style=long-iso'
alias la='eza -a --group-directories-first'
alias lt='eza --tree --level=2 --group-directories-first'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias g='git'
alias gs='git status -sb'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git lg'          # graph log, defined in the git config
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gco='git switch'
alias lzg='lazygit'

alias v='nvim'
alias df='df -h'
alias du='du -h'
alias mkdir='mkdir -p'
alias ip='ip --color=auto'

alias rm='rm -I --preserve-root'
alias cp='cp -i'
alias mv='mv -i'

# --- tools -------------------------------------------------------------------
# fd (Debian: fdfind) backs every fzf source so .gitignore is respected.
export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fdfind --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline --cycle'
export FZF_CTRL_T_OPTS="--preview 'batcat --style=numbers --color=always --line-range=:200 {} 2>/dev/null || eza -la --color=always {}'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {}'"
export FZF_CTRL_R_OPTS='--reverse --no-preview'

command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"     # C-t files, C-r history, M-c cd
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"

# --- prompt ------------------------------------------------------------------
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
EOF

cat > ~/.config/starship.toml <<'EOF'
# ~/.config/starship.toml - minimal single-line prompt.

add_newline = false
format = '$directory$git_branch$git_status$character'

[directory]
truncation_length = 3

[character]
success_symbol = '[❯](bold green)'
error_symbol = '[❯](bold red)'
EOF

# --- default terminal -------------------------------------------------------
sudo update-alternatives --set x-terminal-emulator /usr/bin/alacritty
gsettings set org.gnome.desktop.default-applications.terminal exec /usr/bin/alacritty
gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'

echo "terminal.sh: done (Alacritty reloads live; F11 toggles fullscreen)"
