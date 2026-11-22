# skill-issue: a "SKILL ISSUE" notification every time a command fails.
#
# Settings (set them in config.fish or with `set -U`):
#   skill_issue_ignore   commands whose failures are normal (grep finding nothing, etc.)
#   SKILL_ISSUE_DRY      if set, print instead of sending the notification (for tests)

set -q skill_issue_ignore
or set -g skill_issue_ignore grep egrep fgrep zgrep rg ag ack diff cmp test [ false pgrep pidof \
    which type string set functions contains read command builtin abbr exit

set -g __skill_issue_last_cmd ""
set -g __skill_issue_last_time 0

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
    notify-send -a Terminal -i dialog-error "SKILL ISSUE" &
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
