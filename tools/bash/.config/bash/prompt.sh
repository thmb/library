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