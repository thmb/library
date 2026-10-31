#!/usr/bin/env bash
# bash.sh - shell environment: apt CLI tools, font and dotfiles
#
# Usage: ./bash.sh
#
# Idempotent and safe to re-run: installs anything that is missing and
# rewrites the configuration in place. sudo is requested only when an apt
# package actually needs installing; nothing outside $HOME is touched.
# Target: Debian Trixie or later.
set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# Install only the apt packages that are missing (one sudo round when needed).
apt_install() {
  local missing=() pkg
  for pkg in "$@"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  [ ${#missing[@]} -eq 0 ] && return 0
  log "apt: installing ${missing[*]}"
  sudo apt-get update
  sudo apt-get install -y "${missing[@]}"
}

# Replace the file at $path with content from a quoted heredoc. Safe for the
# backslash- and dollar-heavy content below. Any symlink on the path -- the
# file itself or an ancestor directory left by the old stow layout -- is
# replaced with a real file/directory, so nothing is written into a checkout.
write_file() {
  local path="$1" t; shift
  # The caller tilde-expands "~" already, so $1 is absolute.
  [ -L "$path" ] && rm -f "$path"
  t="$(dirname "$path")"
  while [ "$t" != "$HOME" ] && [ "$t" != "/" ]; do
    [ -L "$t" ] && rm -f "$t"
    t="$(dirname "$t")"
  done
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}


# Packages, one line each. Installed only if missing (idempotent via apt_install).
apt_install fzf ripgrep fd-find bat eza zoxide direnv starship git-delta lazygit

# Debian renames two binaries (bat->batcat, fd->fdfind). Restore the upstream
# names so the fzf defaults and scripts find real executables.
log "linking ~/.local/bin shims (bat, fd)"
mkdir -p "$HOME/.local/bin"
ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"

# --- font (non-apt): MesloLGS Nerd Font Mono -------------------------------
# The Mono variant forces every glyph into one cell, which fixed-cell terminals
# need (the plain variant lets icons take double width and misalign text).
TERMINAL_FONT='MesloLGS Nerd Font Mono 12'
font_dir="$HOME/.local/share/fonts/MesloLGS"
if [ -f "$font_dir/MesloLGSNerdFontMono-Regular.ttf" ]; then
  log "MesloLGS Nerd Font Mono already installed"
else
  log "installing MesloLGS Nerd Font Mono"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/font.zip" \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip
  mkdir -p "$font_dir"
  unzip -o -j "$tmp/font.zip" \
    MesloLGSNerdFontMono-Regular.ttf MesloLGSNerdFontMono-Bold.ttf \
    MesloLGSNerdFontMono-Italic.ttf MesloLGSNerdFontMono-BoldItalic.ttf \
    -d "$font_dir" >/dev/null
  rm -rf "$tmp"
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null
fi

# Apply the font to gnome-terminal (no sudo; gsettings talks to dconf).
if command -v gsettings >/dev/null 2>&1; then
  # gsettings returns the profile as 'uuid'; strip the surrounding quotes.
  profile="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null)" || profile=""
  # shellcheck disable=SC2016  # backslash-quote below is a literal pattern, intentional
  profile="${profile#\'}"
  # shellcheck disable=SC2016
  profile="${profile%\'}"
  if [ -n "$profile" ]; then
    path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$profile/"
    log "setting gnome-terminal font"
    gsettings set "$path" use-system-font false
    gsettings set "$path" font "$TERMINAL_FONT"
  fi
fi

# --- configuration (written in place each run) -----------------------------
write_file ~/.bashrc <<'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
  *i*) ;;
  *) return ;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
#[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
  xterm-color | *-256color) color_prompt=yes ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    # We have color support; assume it's compliant with Ecma-48
    # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
    # a case would tend to support setf rather than setaf.)
    color_prompt=yes
  else
    color_prompt=
  fi
fi

if [ "$color_prompt" = yes ]; then
  PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
  xterm* | rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
  *)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
  alias ls='ls --color=auto'
  #alias dir='dir --color=auto'
  #alias vdir='vdir --color=auto'

  #alias grep='grep --color=auto'
  #alias fgrep='fgrep --color=auto'
  #alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
#alias ll='ls -l'
#alias la='ls -A'
#alias l='ls -CF'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

# ---------------------------------------------------------------------------
# Modular config, managed by tools/bash.sh
#
# Order matters:
#   env     first  - tools.sh reads $FZF_* and PATH
#   tools   next   - zoxide and direnv register their PROMPT_COMMAND hooks
#   prompt  last   - assembles the final PROMPT_COMMAND so the prompt renderer
#           runs FIRST (correct exit code) ahead of those hooks
# ---------------------------------------------------------------------------
for _rc in env aliases tools prompt; do
  [ -r "$HOME/.config/bash/$_rc.sh" ] && . "$HOME/.config/bash/$_rc.sh"
done
unset _rc

# Machine-local overrides, managed by you and never written by this script.
# Put per-machine aliases/env here so they survive re-runs of bash.sh.
if [ -r "$HOME/.bashrc.local" ]; then
    . "$HOME/.bashrc.local"
fi
EOF
write_file ~/.config/bash/env.sh <<'EOF'
# env.sh - exports, shell options, history. Sourced first.

# ~/.local/bin holds nvim plus the bat/fd shims (Debian ships batcat/fdfind).
# ~/.profile only adds this at *login* and only if it already exists, so set it
# here explicitly to survive a fresh install.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH

# Debian's ~/.profile sources ~/.bashrc (line 15) and only *then* prepends
# ~/.local/bin unconditionally (line 26), so login shells end up with it twice
# no matter what we check here. Dedupe instead, keeping first occurrence.
# Runs from PROMPT_COMMAND, i.e. after every startup file has run. Idempotent,
# so it can stay in the PROMPT_COMMAND chain and simply no-op after the first run.
__path_dedupe() {
    [ -n "${__path_deduped:-}" ] && return
    __path_deduped=1
    local IFS=: d seen=
    for d in $PATH; do
        [ -n "$d" ] || continue
        case ":$seen:" in
            *":$d:"*) continue ;;
        esac
        seen="${seen:+$seen:}$d"
    done
    PATH="$seen"
    export PATH
}

export EDITOR=nvim
export VISUAL=nvim
export MANPAGER='nvim +Man!'
export PAGER=less
export LESS='-R --mouse'

# History: big, deduplicated, append-only, timestamped.
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T  '
HISTIGNORE='ls:ll:la:cd:pwd:exit:clear:history'
shopt -s histappend    # append instead of overwriting
shopt -s cmdhist       # keep multi-line commands as one entry

shopt -s checkwinsize  # keep $LINES/$COLUMNS correct after each command
shopt -s globstar      # ** matches recursively
shopt -s autocd        # `cd` is optional for a bare directory
shopt -s cdspell       # fix small typos in cd targets
shopt -s dirspell
shopt -s no_empty_cmd_completion

export BAT_THEME='ansi'
EOF
write_file ~/.config/bash/aliases.sh <<'EOF'
# aliases.sh - deliberately does NOT shadow cat, grep, find or sed, so that
# scripts and muscle memory keep working. Use bat/rg/fd by their own names.

if command -v eza >/dev/null 2>&1; then
    alias ls='eza --group-directories-first'
    alias ll='eza -lah --git --group-directories-first --time-style=long-iso'
    alias la='eza -a --group-directories-first'
    alias lt='eza --tree --level=2 --group-directories-first'
else
    alias ls='ls --color=auto'
    alias ll='ls -lah'
fi

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

command -v lazygit >/dev/null 2>&1 && alias lzg='lazygit'

alias v='nvim'
alias df='df -h'
alias du='du -h'
alias mkdir='mkdir -p'
alias ip='ip --color=auto'

# Safety rails on destructive coreutils.
alias rm='rm -I --preserve-root'
alias cp='cp -i'
alias mv='mv -i'
EOF
write_file ~/.config/bash/tools.sh <<'EOF'
# tools.sh - integrations for fzf, zoxide and direnv.

# --- fzf -------------------------------------------------------------------
# fd (Debian: fdfind) backs every fzf source so .gitignore is respected.
if command -v fdfind >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fdfind --type d --hidden --follow --exclude .git'
fi

# Plain on purpose: reverse layout, inline info, no heavy chrome.
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline --cycle'
export FZF_CTRL_T_OPTS="--preview 'batcat --style=numbers --color=always --line-range=:200 {} 2>/dev/null || eza -la --color=always {}'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {}'"
export FZF_CTRL_R_OPTS='--reverse --no-preview'

# fzf >= 0.48 generates its own bash integration: C-t files, C-r history, M-c cd.
command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"

# --- zoxide ----------------------------------------------------------------
# `z <part-of-path>` jumps by frecency, `zi` picks interactively through fzf.
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"

# --- direnv ----------------------------------------------------------------
# Per-directory env. Remember to `direnv allow` each new .envrc.
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"

# --- helpers ---------------------------------------------------------------

# fv: fuzzy-pick file(s) and open in nvim.
fv() {
    local files
    IFS=$'\n' read -r -d '' -a files < <(fzf --multi --preview 'batcat --style=numbers --color=always --line-range=:200 {}' && printf '\0')
    [ ${#files[@]} -gt 0 ] && nvim "${files[@]}"
}

# fgb: fuzzy-pick a git branch (local or remote) and switch to it.
fgb() {
    local branch
    branch=$(git branch --all --color=never --sort=-committerdate \
        | grep -v HEAD | sed 's/^[* ]*//;s#^remotes/[^/]*/##' | awk '!seen[$0]++' \
        | fzf --preview 'git log --oneline --graph --color=always -20 {}') || return
    [ -n "$branch" ] && git switch "$branch"
}

# fkill: fuzzy-pick a process and terminate it.
fkill() {
    local pid
    pid=$(ps -eo pid,user,pcpu,pmem,comm --sort=-pcpu | sed 1d | fzf --multi --header='select process(es) to kill' | awk '{print $1}') || return
    [ -n "$pid" ] && echo "$pid" | xargs -r kill -"${1:-15}"
}

# wt: fuzzy-pick a git worktree and cd into it.
wt() {
    local dir
    dir=$(git worktree list --porcelain | awk '/^worktree /{print $2}' | fzf) || return
    [ -n "$dir" ] && cd "$dir" || return
}
EOF
write_file ~/.config/bash/prompt.sh <<'EOF'
# prompt.sh - starship prompt for bash, with a minimal __git_ps1 fallback when
# the binary is missing.
#
# Starship's own bash init handles PROMPT_COMMAND ordering for us: it saves
# whatever was already there (zoxide, direnv, VTE, the PATH dedupe) into
# STARSHIP_PROMPT_COMMAND, runs that after capturing the previous command's exit
# status, and only then renders PS1. So no hand-assembled hook order is needed.

# Append a command to the (scalar) PROMPT_COMMAND without duplicating it.
__pc_append() {
    case ";${PROMPT_COMMAND:-};" in
        *";$1;"*) return ;;
        ';;') PROMPT_COMMAND="$1" ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND%;};$1" ;;
    esac
}

# One-time PATH dedupe (see env.sh). Registered before starship so it is picked
# up into STARSHIP_PROMPT_COMMAND; it no-ops after the first run.
declare -F __path_dedupe >/dev/null 2>&1 && __pc_append __path_dedupe

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
else
    # Fallback: minimal git-aware prompt. __git_ps1 ships with the git package
    # (/usr/lib/git-core/git-sh-prompt), so no extra dependency.
    # Indicators: * unstaged  + staged  $ stashed  % untracked  </>/= vs upstream.
    if ! declare -F __git_ps1 >/dev/null 2>&1; then
        for _gp in /usr/lib/git-core/git-sh-prompt /etc/bash_completion.d/git-prompt; do
            [ -r "$_gp" ] && . "$_gp" && break
        done
        unset _gp
    fi
    # Read by __git_ps1, which shellcheck cannot see into.
    # shellcheck disable=SC2034
    GIT_PS1_SHOWDIRTYSTATE=1
    # shellcheck disable=SC2034
    GIT_PS1_SHOWSTASHSTATE=1
    # shellcheck disable=SC2034
    GIT_PS1_SHOWUNTRACKEDFILES=1
    # shellcheck disable=SC2034
    GIT_PS1_SHOWUPSTREAM=auto
    # shellcheck disable=SC2034
    GIT_PS1_SHOWCOLORHINTS=1

    __prompt() {
        local e=$? pre=''
        [ "$e" -ne 0 ] && pre="\[\e[1;31m\][$e]\[\e[0m\] "
        if declare -F __git_ps1 >/dev/null 2>&1; then
            # No colour escapes in the third argument: SHOWCOLORHINTS colours the
            # branch itself, and nesting our own \[..\] would corrupt wrapping.
            __git_ps1 "${pre}\[\e[1;34m\]\w\[\e[0m\]" " \\\$ " " (%s)"
        else
            PS1="${pre}\[\e[1;34m\]\w\[\e[0m\] \\\$ "
        fi
    }

    # Rebuild PROMPT_COMMAND with the renderer first (so it sees the real exit
    # code), then dedupe, VTE, zoxide and direnv.
    __prompt_assemble() {
        local parts=(__prompt)
        declare -F __path_dedupe >/dev/null 2>&1      && parts+=(__path_dedupe)
        declare -F __vte_prompt_command >/dev/null 2>&1 && parts+=(__vte_prompt_command)
        declare -F __zoxide_hook >/dev/null 2>&1      && parts+=(__zoxide_hook)
        declare -F _direnv_hook >/dev/null 2>&1       && parts+=(_direnv_hook)
        PROMPT_COMMAND="$(IFS=';'; printf '%s' "${parts[*]}")"
    }
    __prompt_assemble
    unset -f __prompt_assemble
fi

unset -f __pc_append
EOF
write_file ~/.config/starship.toml <<'EOF'
# ~/.config/starship.toml - minimal single-line prompt.
#
# Starship's default format mixes in language versions, username and hostname,
# which reads as clutter on a single-user machine. Keep just the essentials:
# directory, git branch/status and the prompt character.

format = '$directory$git_branch$git_status$character'

[directory]
truncation_length = 3

[character]
success_symbol = '[❯](bold green)'
error_symbol = '[❯](bold red)'
EOF
