# Run: fish tests/run.fish
set -gx SKILL_ISSUE_DRY 1
source (status dirname)/../skill-issue.fish
set -g fails 0

# yes/no DESCRIPTION CMDLINE CODES...
function check -a want desc
    set -l out (__skill_issue_handle $argv[3..-1])
    set -l got no
    test "$out" = "SKILL ISSUE"; and set got yes
    if test $got = $want
        echo "ok    $desc"
    else
        echo "FAIL  $desc (wanted notification: $want, got: $got)"
        set -g fails (math $fails + 1)
    end
end

check no  "success"                    "ls" 0 0
check no  "ctrl+c"                     "sleep 10" 130 130
check no  "grep finds nothing"         "grep foo bar.txt" 1 1
check no  "test returns false"         "test -f x" 1 1
check no  "yes | head"                 "yes | head -1" 141 0 0
check no  "user handles errors"        "test -f x; and echo hi" 1 1
check no  "exit carries old status"    "exit" 2 2
check no  "empty line"                 "" 0 0
check yes "command not found"          "gti status" 127 127
check yes "not executable"             "./script.sh" 126 126
check yes "segfault"                   "./a.out" 139 139
check yes "plain failure"              "ls /nope" 2 2
check yes "git push failed"            "git push" 1 1
check yes "build failed"               "cargo build" 101 101
check yes "env prefix not ignored"     "RUST_LOG=1 cargo build" 101 101
check yes "pipeline first part failed" "cat missing.txt | wc -l" 1 0 0
check no  "pipeline grep part"         "echo hi | grep zzz" 0 1 1
check yes "not found inside and/or"    "gti status; and echo hi" 127 127
check yes "failed before sudo"         "pacman -S vim" 1 1
check yes "worked with sudo"           "sudo pacman -S vim" 0 0
check no  "sudo roast only once"       "ls" 0 0

echo
test $fails -eq 0; and echo "all passed"; or begin; echo "$fails failed"; exit 1; end
