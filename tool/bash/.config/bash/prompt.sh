# prompt.sh - PowerLevel10k-style prompt via oh-my-posh, with a __git_ps1
# fallback when the binary is missing.
#
# oh-my-posh's bash init *appends* its _omp_hook (and switches PROMPT_COMMAND to
# an array), while zoxide and direnv *prepend* their hooks (as a scalar), and
# VTE may have prepended __vte_prompt_command at login. Rather than let four
# mutation styles fight over scalars vs arrays (which silently drops hooks),
# this file assembles the final scalar PROMPT_COMMAND explicitly, putting the
# renderer FIRST so it captures the real exit code of the previous command.

# Append a command to the (scalar) PROMPT_COMMAND without duplicating it.
__pc_append() {
    case ";${PROMPT_COMMAND:-};" in
        *";$1;"*) return ;;
        ';;') PROMPT_COMMAND="$1" ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND%;};$1" ;;
    esac
}

# Final assembly: renderer first (correct $?), state-update hooks after.
__pc_assemble() {
    local parts=("$PROMPT_RENDERER")
    declare -f __path_dedupe >/dev/null 2>&1    && parts+=(__path_dedupe)
    declare -f __vte_prompt_command >/dev/null 2>&1 && parts+=(__vte_prompt_command)
    declare -f __zoxide_hook >/dev/null 2>&1    && parts+=(__zoxide_hook)
    declare -f _direnv_hook >/dev/null 2>&1     && parts+=(_direnv_hook)
    PROMPT_COMMAND="$(IFS=';'; printf '%s' "${parts[*]}")"
}

if command -v oh-my-posh >/dev/null 2>&1 && [ -f "$HOME/.config/oh-my-posh/powerlevel10k_rainbow.omp.json" ]; then
    # powerlevel10k_rainbow recreates the classic p10k look, on bash.
    eval "$(oh-my-posh init bash --config "$HOME/.config/oh-my-posh/powerlevel10k_rainbow.omp.json")"
    PROMPT_RENDERER=_omp_hook
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
    PROMPT_RENDERER=__prompt
fi

__pc_assemble
unset -f __pc_append __pc_assemble