# skill-issue for bash and zsh: a "SKILL ISSUE" notification every time a command fails.
# https://github.com/egehankara/skill-issue
#
# Source this at the END of ~/.bashrc or ~/.zshrc (after prompt tools like starship):
#   source /path/to/skill-issue/skill-issue.sh
#
# Settings (set them before sourcing):
#   SKILL_ISSUE_IGNORE   space-separated commands whose failures are normal (grep finding nothing, etc.)
#   SKILL_ISSUE_DRY      if set, print instead of sending the notification (for tests)

[ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ] || return 0

: "${SKILL_ISSUE_IGNORE=grep egrep fgrep zgrep rg ag ack diff cmp test [ [[ false pgrep pidof which type command read exit hash}"

__skill_issue_last_cmd=
__skill_issue_last_time=0

# Sets __skill_issue_cmdname to the command name, skipping wrappers like sudo, env, time and VAR=value
__skill_issue_name() {
    local p=$1 w
    while :; do
        p=${p#"${p%%[![:space:]]*}"}
        w=${p%%[[:space:]]*}
        case $w in
            sudo | doas | run0 | env | time | command | builtin | exec | nice | nohup | -* | *=*)
                p=${p#"$w"}
                ;;
            *)
                __skill_issue_cmdname=$w
                return 0
                ;;
        esac
    done
}

__skill_issue_notify() {
    if [ -n "${SKILL_ISSUE_DRY:-}" ]; then
        echo "SKILL ISSUE"
        return 0
    fi
    # Turned off with `skill-issue off` (shared with the fish version)
    [ -e "${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/off" ] && return 0
    # No screen to show it on (SSH, TTY)
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 0
    # Missing notify-send or notification daemon: stay quiet instead of printing errors
    command -v notify-send >/dev/null 2>&1 || return 0
    (notify-send -a Terminal -i dialog-error "SKILL ISSUE" >/dev/null 2>&1 &)
}

# Usage: __skill_issue_handle CMDLINE "PIPESTATUS CODES" STATUS
__skill_issue_handle() {
    local cmd=$1 codes=$2 st=$3 failed=0 re c part prest crest rest n_parts=1 n_codes=0

    # Flatten and trim the command line
    cmd=${cmd//$'\n'/ }
    cmd=${cmd#"${cmd%%[![:space:]]*}"}
    cmd=${cmd%"${cmd##*[![:space:]]}"}
    [ -n "$cmd" ] || return 0

    re='(;|&&|\|\||&$|(^|[[:space:]])(if|while|until|for|case|select|!)[[:space:]])'
    if [[ $cmd =~ $re ]]; then
        # The line has its own error handling, so only count the unmistakable failures:
        # command not found, not executable, crashes
        if [ "$st" -ge 126 ] && [ "$st" != 130 ] && [ "$st" != 141 ]; then
            failed=1
        fi
    else
        # A plain command or pipeline: check each part
        rest=$cmd
        while [ "${rest#*|}" != "$rest" ]; do
            rest=${rest#*|}
            n_parts=$((n_parts + 1))
        done
        rest=$codes
        while [ -n "$rest" ]; do
            n_codes=$((n_codes + 1))
            case $rest in
                *' '*) rest=${rest#* } ;;
                *) rest= ;;
            esac
        done
        [ "$n_parts" = "$n_codes" ] || codes=$st

        prest=$cmd
        crest=$codes
        while [ -n "$crest" ]; do
            case $crest in
                *' '*) c=${crest%% *} crest=${crest#* } ;;
                *) c=$crest crest= ;;
            esac
            case $prest in
                *'|'*) part=${prest%%|*} prest=${prest#*|} ;;
                *) part=$prest prest= ;;
            esac
            # 0 = fine, 130 = Ctrl+C, 141 = pipe closed early (yes | head)
            case $c in 0 | 130 | 141) continue ;; esac
            if [ "$c" -lt 126 ]; then
                __skill_issue_name "$part"
                case " $SKILL_ISSUE_IGNORE " in
                    *" $__skill_issue_cmdname "*) continue ;;
                esac
            fi
            failed=1
            break
        done
    fi

    if [ "$failed" = 1 ]; then
        __skill_issue_last_cmd=$cmd
        __skill_issue_last_time=$SECONDS
        __skill_issue_notify
        return 0
    fi

    # Failed, then re-ran it with sudo and it worked: forgot sudo
    if [ "$st" = 0 ] && [ -n "$__skill_issue_last_cmd" ] &&
        [ "$cmd" = "sudo $__skill_issue_last_cmd" ] &&
        [ $((SECONDS - __skill_issue_last_time)) -lt 120 ]; then
        __skill_issue_notify
    fi
    __skill_issue_last_cmd=
    return 0
}

skill-issue() {
    local off="${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/off"
    case ${1:-status} in
        off)
            mkdir -p "${off%/*}" && : >"$off"
            echo "skill-issue is off. No more truth, in any shell."
            ;;
        on)
            rm -f "$off"
            echo "skill-issue is on."
            ;;
        status)
            if [ -e "$off" ]; then
                echo "skill-issue is off. Turn it on with: skill-issue on"
            else
                echo "skill-issue is on. Turn it off with: skill-issue off"
            fi
            ;;
        test)
            if [ -e "$off" ]; then
                echo "skill-issue is off, so nothing will show up. Turn it on with: skill-issue on"
                return 1
            fi
            if notify-send -a Terminal -i dialog-error "SKILL ISSUE" 2>/dev/null; then
                echo "Sent a test notification."
            else
                echo "Couldn't show a notification. Is a notification daemon running?"
                return 1
            fi
            ;;
        help | -h | --help)
            echo "Usage: skill-issue [on | off | status | test]"
            echo
            echo "  on       turn notifications on"
            echo "  off      turn them off (in every shell, until you turn them back on)"
            echo "  status   show whether it's on (default)"
            echo "  test     send a test notification"
            ;;
        *)
            echo "skill-issue: unknown command '$1'. Try: skill-issue help" >&2
            return 1
            ;;
    esac
}

# Hooks: only in interactive shells
case $- in *i*) ;; *) return 0 ;; esac

if [ -n "${BASH_VERSION:-}" ]; then
    # Needs PS0, added in bash 4.4
    if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" = 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
        return 0
    fi
    __skill_issue_ran=0

    __skill_issue_precmd() {
        # Both must be read first, before anything else changes them
        local st=$? codes="${PIPESTATUS[*]}" cmd
        # Only after a command actually ran (not an empty Enter)
        if [ "$__skill_issue_ran" = 1 ]; then
            __skill_issue_ran=0
            cmd=$(HISTTIMEFORMAT= builtin history 1)
            # Drop the history number in front: "  123  cmd" or "  123* cmd"
            cmd=${cmd#"${cmd%%[![:space:]]*}"}
            cmd=${cmd#"${cmd%%[![:digit:]]*}"}
            cmd=${cmd#\*}
            __skill_issue_handle "$cmd" "$codes" "$st"
        fi
        # Hand the original status on to the next prompt hooks
        return $st
    }

    case ";${PROMPT_COMMAND:-};" in
        *';__skill_issue_precmd;'*) ;;
        *) PROMPT_COMMAND="__skill_issue_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
    esac
    # PS0 is expanded right before a command runs, never on an empty Enter.
    # The array subscript sets the flag without printing anything.
    case ${PS0:-} in
        *__skill_issue_ran=1*) ;;
        *) PS0="${PS0:-}"'${__skill_issue_z[__skill_issue_ran=1]}' ;;
    esac

elif [ -n "${ZSH_VERSION:-}" ]; then
    __skill_issue_cmd=

    __skill_issue_preexec() {
        # $3 is the full command with aliases expanded, $1 is what was typed
        __skill_issue_cmd=${3:-$1}
    }

    __skill_issue_precmd() {
        # Both must be read first, before anything else changes them
        local st=$? codes="${pipestatus[*]}" cmd
        if [ -n "$__skill_issue_cmd" ]; then
            cmd=$__skill_issue_cmd
            __skill_issue_cmd=
            __skill_issue_handle "$cmd" "$codes" "$st"
        fi
        return $st
    }

    # Run first, so other prompt hooks can't change the status before we read it
    precmd_functions=(__skill_issue_precmd ${precmd_functions:#__skill_issue_precmd})
    preexec_functions=(${preexec_functions:#__skill_issue_preexec} __skill_issue_preexec)
fi
