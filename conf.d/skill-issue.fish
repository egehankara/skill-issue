# skill-issue: a "SKILL ISSUE" notification every time a command fails.
# https://github.com/egehankara/skill-issue
#
# Settings (set them in config.fish or with `set -U`):
#   skill_issue_ignore   commands whose failures are normal (grep finding nothing, etc.)
#   SKILL_ISSUE_DRY      if set, print instead of sending the notification (for tests)

set -q skill_issue_ignore
or set -g skill_issue_ignore grep egrep fgrep zgrep rg ag ack diff cmp test [ false pgrep pidof \
    which type string set functions contains read command builtin abbr exit

set -g __skill_issue_last_cmd ""
set -g __skill_issue_last_time 0

# Shared with the bash/zsh version, so `skill-issue off` works in every shell
function __skill_issue_off_file
    set -l dir $XDG_STATE_HOME
    test -n "$dir"; or set dir ~/.local/state
    echo $dir/skill-issue/off
end

function __skill_issue_on_postexec --on-event fish_postexec
    # Both must be read on the same line, before anything else changes them
    set -l codes $pipestatus $status
    __skill_issue_handle "$argv[1]" $codes
end

# Prints the command name, skipping wrappers like sudo, env, time and VAR=value
function __skill_issue_name
    set -l words (string split -n ' ' -- (string trim -- $argv[1]))
    while set -q words[1]
        switch $words[1]
            case sudo doas run0
                set -e words[1]
                while string match -q -- '-*' $words[1]
                    set -e words[1]
                end
            case env time command builtin exec nice nohup '*=*'
                set -e words[1]
            case '*'
                echo $words[1]
                return
        end
    end
end

function __skill_issue_notify
    if set -q SKILL_ISSUE_DRY
        echo "SKILL ISSUE"
        return
    end
    test -e (__skill_issue_off_file); and return
    # No screen to show it on (SSH, TTY)
    set -q DISPLAY; or set -q WAYLAND_DISPLAY; or return
    # Missing notify-send or notification daemon: stay quiet instead of printing errors
    command -q notify-send; or return
    notify-send -a Terminal -i dialog-error "SKILL ISSUE" 2>/dev/null &
    disown
end

# Usage: __skill_issue_handle CMDLINE PIPESTATUS... STATUS
function __skill_issue_handle -a cmdline
    set -l codes $argv[2..-1]
    set -l st $codes[-1]
    set -e codes[-1]
    set cmdline (string trim -- $cmdline | string join ' ')
    test -z "$cmdline"; and return
    set -l now (date +%s)

    set -l failed 0
    if string match -qr -- ';|&&|\|\||&$|(^|\s)(and|or|not|if|while|for|begin|switch)\s' $cmdline
        # The line has its own error handling, so only count the unmistakable failures:
        # command not found, not executable, crashes
        if test $st -ge 126; and not contains -- $st 130 141
            set failed 1
        end
    else
        # A plain command or pipeline: check each part
        set -l parts (string split '|' -- $cmdline)
        if test (count $parts) -ne (count $codes)
            set parts $cmdline
            set codes $st
        end
        for i in (seq (count $parts))
            set -l c $codes[$i]
            # 0 = fine, 130 = Ctrl+C, 141 = pipe closed early (yes | head)
            contains -- $c 0 130 141; and continue
            if test $c -lt 126; and contains -- (__skill_issue_name $parts[$i]) $skill_issue_ignore
                continue
            end
            set failed 1
            break
        end
    end

    if test $failed -eq 1
        set -g __skill_issue_last_cmd $cmdline
        set -g __skill_issue_last_time $now
        __skill_issue_notify
        return
    end

    # Failed, then re-ran it with sudo and it worked: forgot sudo
    if test $st -eq 0; and test "$cmdline" = "sudo $__skill_issue_last_cmd"
        and test (math $now - $__skill_issue_last_time) -lt 120
        __skill_issue_notify
    end
    set -g __skill_issue_last_cmd ""
end

function skill-issue -d "Turn SKILL ISSUE notifications on or off"
    set -l off (__skill_issue_off_file)
    switch "$argv[1]"
        case off
            mkdir -p (path dirname $off); and touch $off
            echo "skill-issue is off. No more truth, in any shell."
        case on
            rm -f $off
            echo "skill-issue is on."
        case status ''
            if test -e $off
                echo "skill-issue is off. Turn it on with: skill-issue on"
            else
                echo "skill-issue is on. Turn it off with: skill-issue off"
            end
        case test
            if test -e $off
                echo "skill-issue is off, so nothing will show up. Turn it on with: skill-issue on"
                return 1
            end
            if notify-send -a Terminal -i dialog-error "SKILL ISSUE" 2>/dev/null
                echo "Sent a test notification."
            else
                echo "Couldn't show a notification. Is a notification daemon running?"
                return 1
            end
        case help -h --help
            echo "Usage: skill-issue [on | off | status | test]"
            echo
            echo "  on       turn notifications on"
            echo "  off      turn them off (in every shell, until you turn them back on)"
            echo "  status   show whether it's on (default)"
            echo "  test     send a test notification"
        case '*'
            echo "skill-issue: unknown command '$argv[1]'. Try: skill-issue help" >&2
            return 1
    end
end

# Fisher install hooks
function __skill_issue_fisher_install --on-event skill-issue_install
    skill-issue test >/dev/null
end

function __skill_issue_fisher_uninstall --on-event skill-issue_uninstall
    functions -e (functions -a | string match -- '__skill_issue*') skill-issue
    set -e skill_issue_ignore
end
