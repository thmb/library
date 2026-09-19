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
