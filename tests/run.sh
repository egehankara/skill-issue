# Run with both shells: bash tests/run.sh && zsh tests/run.sh
SKILL_ISSUE_DRY=1
. "$(dirname "$0")/../skill-issue.sh"
fails=0

# check yes|no DESCRIPTION CMDLINE "PIPESTATUS" STATUS
check() {
    local out got=no
    out=$(__skill_issue_handle "$3" "$4" "$5")
    [ "$out" = "SKILL ISSUE" ] && got=yes
    # The subshell above loses state, so run it again for real (sudo retry needs it)
    __skill_issue_handle "$3" "$4" "$5" >/dev/null
    if [ "$got" = "$1" ]; then
        echo "ok    $2"
    else
        echo "FAIL  $2 (wanted notification: $1, got: $got)"
        fails=$((fails + 1))
    fi
}

check no  "success"                    "ls" "0" 0
check no  "ctrl+c"                     "sleep 10" "130" 130
check no  "grep finds nothing"         "grep foo bar.txt" "1" 1
check no  "test returns false"         "test -f x" "1" 1
check no  "[[ ]] returns false"        "[[ -f x ]]" "1" 1
check no  "yes | head"                 "yes | head -1" "141 0" 0
check no  "user handles errors"        "test -f x && echo hi" "1" 1
check no  "exit carries old status"    "exit" "2" 2
check no  "empty line"                 "" "0" 0
check yes "command not found"          "gti status" "127" 127
check yes "not executable"             "./script.sh" "126" 126
check yes "segfault"                   "./a.out" "139" 139
check yes "plain failure"              "ls /nope" "2" 2
check yes "git push failed"            "git push" "1" 1
check yes "build failed"               "cargo build" "101" 101
check yes "env prefix not ignored"     "RUST_LOG=1 cargo build" "101" 101
check no  "sudo grep is still grep"    "sudo grep x /etc/shadow" "1" 1
check yes "pipeline first part failed" "cat missing.txt | wc -l" "1 0" 0
check no  "pipeline grep part"         "echo hi | grep zzz" "0 1" 1
check yes "not found inside &&"        "gti status && echo hi" "127" 127
check yes "failed before sudo"         "pacman -S vim" "1" 1
check yes "worked with sudo"           "sudo pacman -S vim" "0" 0
check no  "sudo roast only once"       "ls" "0" 0

echo
if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
