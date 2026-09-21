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
