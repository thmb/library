# prompt.sh - single-line, git-aware prompt.
#
# __git_ps1 ships with the git package (/usr/lib/git-core/git-sh-prompt) and is
# normally loaded by bash-completion, so this costs no extra dependency.
# Indicators: * unstaged  + staged  $ stashed  % untracked  </>/= vs upstream.

if ! declare -F __git_ps1 >/dev/null 2>&1; then
    for _gp in /usr/lib/git-core/git-sh-prompt /etc/bash_completion.d/git-prompt; do
        [ -r "$_gp" ] && . "$_gp" && break
    done
    unset _gp
fi

# These are read by __git_ps1, which shellcheck cannot see into.
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

# Note: __git_ps1 in PROMPT_COMMAND form assigns PS1 itself, so the exit code
# has to be injected into its "pre" argument rather than appended to PS1.
# $? is captured on function entry, before anything else can clobber it.
# Register __prompt without destroying anything already in PROMPT_COMMAND.
# zoxide and direnv prepend their own hooks to this variable; clobbering it
# would stop directory tracking and .envrc loading without any error message.
__prompt_register() {
    case "${PROMPT_COMMAND:-}" in
        *__prompt*) return ;;
        '') PROMPT_COMMAND='__prompt' ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND%;};__prompt" ;;
    esac
}

if declare -F __git_ps1 >/dev/null 2>&1; then
    __prompt() {
        local e=$? pre=''
        # Runs after every startup file, so this is where PATH can be deduped.
        if [ -z "${__path_deduped:-}" ] && declare -F __path_dedupe >/dev/null 2>&1; then
            __path_dedupe; __path_deduped=1
        fi
        [ "$e" -ne 0 ] && pre="\[\e[1;31m\][$e]\[\e[0m\] "
        # No colour escapes in the third argument: GIT_PS1_SHOWCOLORHINTS
        # already colours the branch, and nesting our own \[..\] markers inside
        # it miscalculates the prompt width and corrupts line wrapping.
        __git_ps1 "${pre}\[\e[1;34m\]\w\[\e[0m\]" " \\\$ " " (%s)"
    }
else
    __prompt() {
        local e=$? pre=''
        if [ -z "${__path_deduped:-}" ] && declare -F __path_dedupe >/dev/null 2>&1; then
            __path_dedupe; __path_deduped=1
        fi
        [ "$e" -ne 0 ] && pre="\[\e[1;31m\][$e]\[\e[0m\] "
        PS1="${pre}\[\e[1;34m\]\w\[\e[0m\] \\\$ "
    }
fi

__prompt_register
