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
# Called once from PROMPT_COMMAND, i.e. after every startup file has run.
__path_dedupe() {
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
