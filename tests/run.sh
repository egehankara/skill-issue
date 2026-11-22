# Run with both shells: bash tests/run.sh && zsh tests/run.sh
SKILL_ISSUE_DRY=1
XDG_CONFIG_HOME=$(mktemp -d)
XDG_STATE_HOME=$XDG_CONFIG_HOME/state
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

# expect DESCRIPTION EXPECTED_SUBSTRING COMMAND...
expect() {
    local desc=$1 want=$2 out
    shift 2
    out=$("$@" 2>&1)
    case $out in
        *"$want"*) echo "ok    $desc" ;;
        *) echo "FAIL  $desc (wanted: $want, got: $out)"; fails=$((fails + 1)) ;;
    esac
}

conf=$XDG_CONFIG_HOME/skill-issue/sound
snd="$XDG_CONFIG_HOME/my sound.wav"
: >"$snd"
expect "no sound by default"        "Sound: none"           skill-issue sound
expect "failure plays nothing"      "SKILL ISSUE"           __skill_issue_handle ls 2 2
expect "missing file is refused"    "no such file"          skill-issue sound /nope.mp3
expect "own file is saved"          "Sound: $snd"           skill-issue sound "$snd"
expect "own file previews"          "PLAY $snd"             skill-issue sound "$snd"
expect "failure plays own file"     "PLAY $snd"             __skill_issue_handle ls 2 2
here=$PWD
cd "$XDG_CONFIG_HOME"
expect "relative path becomes full" "Sound: $snd"           skill-issue sound "my sound.wav"
cd "$here"
expect "system sound is saved"      "system error sound"    skill-issue sound system
expect "failure plays system sound" "PLAY system"           __skill_issue_handle ls 2 2
expect "status shows the sound"     "system error sound"    skill-issue status
expect "sound off"                  "Sound is off"          skill-issue sound off
if [ -e "$conf" ]; then echo "FAIL  sound off removes the setting"; fails=$((fails + 1)); fi
expect "off again: none"            "Sound: none"           skill-issue sound

# Icons. A tiny fake icon theme, so the tests don't depend on this computer
XDG_DATA_DIRS=$XDG_CONFIG_HOME/data
mkdir -p "$XDG_DATA_DIRS/icons/hicolor/48x48/apps"
: >"$XDG_DATA_DIRS/icons/hicolor/48x48/apps/skill-test-icon.png"
pic="$XDG_CONFIG_HOME/my clown.png"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89' >"$pic"
echo "not a picture" >"$XDG_CONFIG_HOME/fake.png"
expect "default icon"               "Icon: the default error icon" skill-issue icon
expect "default icon is sent"       "NOTIFY -i dialog-error"  __skill_issue_send
expect "missing picture refused"    "no such file"            skill-issue icon /nope.png
expect "non-picture refused"        "isn't a picture"         skill-issue icon "$XDG_CONFIG_HOME/fake.png"
expect "own picture is saved"       "Icon: $pic"              skill-issue icon "$pic"
expect "own picture is sent"        "NOTIFY -i $pic"          __skill_issue_send
cd "$XDG_CONFIG_HOME"
expect "relative path becomes full" "Icon: $pic"              skill-issue icon "my clown.png"
cd "$here"
expect "theme icon name is saved"   "Icon: skill-test-icon"   skill-issue icon skill-test-icon
expect "unknown icon name refused"  "no icon named"           skill-issue icon no-such-icon-anywhere
expect "refusal keeps the old one"  "Icon: skill-test-icon"   skill-issue icon
expect "status shows the icon"      "Icon: skill-test-icon"   skill-issue status
expect "no icon"                    "Icon: none"              skill-issue icon none
out=$(__skill_issue_send)
if [ "$out" = "NOTIFY " ]; then
    echo "ok    no icon: nothing is sent"
else
    echo "FAIL  no icon: nothing is sent (got: $out)"
    fails=$((fails + 1))
fi
expect "back to default"            "Icon: the default error icon" skill-issue icon default
expect "default sent again"         "NOTIFY -i dialog-error"  __skill_issue_send
rm -rf "$XDG_CONFIG_HOME"

# Messages
XDG_CONFIG_HOME=$(mktemp -d)
XDG_STATE_HOME=$XDG_CONFIG_HOME/state
bagf=$XDG_STATE_HOME/skill-issue/bag
mf="$XDG_CONFIG_HOME/my messages.txt"
printf '%s\n' "one" "" "# a comment" "  two  " "three"$'\r' "four & <five>" "six" >"$mf"
printf '\000\001\002binary' >"$XDG_CONFIG_HOME/bin.txt"
printf '\n# only a comment\n\n' >"$XDG_CONFIG_HOME/empty.txt"
five() { local i; for i in 1 2 3 4 5; do __skill_issue_handle ls 2 2; done; }
twice() { __skill_issue_handle ls 2 2; __skill_issue_handle ls 2 2; }
expect "no messages by default"     "Messages: none"          skill-issue messages
expect "no messages: just title"    "SKILL ISSUE"             __skill_issue_handle ls 2 2
expect "missing file refused"       "no such file"            skill-issue messages /nope.txt
expect "binary file refused"        "isn't a text file"       skill-issue messages "$XDG_CONFIG_HOME/bin.txt"
expect "file without lines refused" "no messages in"          skill-issue messages "$XDG_CONFIG_HOME/empty.txt"
expect "file is saved, lines count" "(5 messages)"            skill-issue messages "$mf"
expect "markup is escaped"          "four &amp; &lt;five&gt;" five

# The shuffle bag: every round of 5 shows all 5 once, never the same twice in a row.
# No subshells: zsh wouldn't move $RANDOM forward in them.
rm -f "$bagf"
seen=
prev=
bad=0
r=0
while [ $r -lt 8 ]; do
    round=
    k=0
    while [ $k -lt 5 ]; do
        __skill_issue_handle ls 2 2 >/dev/null
        m=$__skill_issue_message
        [ "$m" = "$prev" ] && bad=1
        case "|$round|" in *"|$m|"*) bad=1 ;; esac
        case $m in one | two | three | "four & <five>" | six) ;; *) bad=2 ;; esac
        round="$round|$m"
        seen="$seen, $m"
        prev=$m
        k=$((k + 1))
    done
    r=$((r + 1))
done
if [ $bad = 0 ]; then
    echo "ok    shuffle bag: 8 rounds, all 5 each round, no repeats in a row"
    echo "ok    blank lines, comments and spaces are dropped"
else
    echo "FAIL  shuffle bag (got:$seen)"
    fails=$((fails + 1))
fi

# Editing the file starts a new round with the new lines
sleep 1
echo "seven" >>"$mf"
found=0
for k in 1 2 3 4 5 6; do
    __skill_issue_handle ls 2 2 >/dev/null
    [ "$__skill_issue_message" = seven ] && found=1
done
if [ $found = 1 ]; then
    echo "ok    edited file: new message shows up in the next round"
else
    echo "FAIL  edited file: seven never showed up"
    fails=$((fails + 1))
fi

printf 'only one\n' >"$XDG_CONFIG_HOME/one.txt"
skill-issue messages "$XDG_CONFIG_HOME/one.txt" >/dev/null
expect "one message, every time"    "SKILL ISSUE | only one"  twice
expect "status shows messages"      "(1 message)"             skill-issue status
expect "messages off"               "Messages are off"        skill-issue messages off
expect "off again: just the title"  "SKILL ISSUE"             __skill_issue_handle ls 2 2
if [ -e "$bagf" ]; then echo "FAIL  messages off removes the bag"; fails=$((fails + 1)); fi
rm -rf "$XDG_CONFIG_HOME"

expect "help has categories"        "Messages  (default: none" skill-issue help
expect "bare command shows settings" "Now"                     skill-issue
expect "bare command shows help"    "skill-issue sound FILE"  skill-issue

echo
if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
