# Run: fish tests/run.fish
set -gx SKILL_ISSUE_DRY 1
set -gx XDG_CONFIG_HOME (mktemp -d)
set -gx XDG_STATE_HOME $XDG_CONFIG_HOME/state
source (status dirname)/../conf.d/skill-issue.fish
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

# expect DESCRIPTION EXPECTED_SUBSTRING COMMAND...
function expect -a desc want
    set -l out (eval $argv[3..-1] 2>&1 | string collect)
    if string match -q -- "*$want*" "$out"
        echo "ok    $desc"
    else
        echo "FAIL  $desc (wanted: $want, got: $out)"
        set -g fails (math $fails + 1)
    end
end

set -l conf $XDG_CONFIG_HOME/skill-issue/sound
set -l snd "$XDG_CONFIG_HOME/my sound.wav"
touch $snd
expect "no sound by default"        "Sound: none"           skill-issue sound
expect "failure plays nothing"      "SKILL ISSUE"           __skill_issue_handle ls 2 2
expect "missing file is refused"    "no such file"          skill-issue sound /nope.mp3
expect "own file is saved"          "Sound: $snd"           skill-issue sound "'$snd'"
expect "own file previews"          "PLAY $snd"             skill-issue sound "'$snd'"
expect "failure plays own file"     "PLAY $snd"             __skill_issue_handle ls 2 2
expect "success plays nothing"      ""                      __skill_issue_handle ls 0 0
set -l here $PWD
cd $XDG_CONFIG_HOME
expect "relative path becomes full" "Sound: $snd"           skill-issue sound "'my sound.wav'"
cd $here
expect "system sound is saved"      "system error sound"    skill-issue sound system
expect "failure plays system sound" "PLAY system"           __skill_issue_handle ls 2 2
expect "status shows the sound"     "system error sound"    skill-issue status
expect "sound off"                  "Sound is off"          skill-issue sound off
test -e $conf; and begin; echo "FAIL  sound off removes the setting"; set -g fails (math $fails + 1); end
expect "off again: none"            "Sound: none"           skill-issue sound

# Icons. A tiny fake icon theme, so the tests don't depend on this computer
set -gx XDG_DATA_DIRS $XDG_CONFIG_HOME/data
mkdir -p $XDG_DATA_DIRS/icons/hicolor/48x48/apps
touch $XDG_DATA_DIRS/icons/hicolor/48x48/apps/skill-test-icon.png
set -l pic "$XDG_CONFIG_HOME/my clown.png"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89' >$pic
echo "not a picture" >$XDG_CONFIG_HOME/fake.png
expect "default icon"               "Icon: the default error icon" skill-issue icon
expect "default icon is sent"       "NOTIFY -i dialog-error"  __skill_issue_send
expect "missing picture refused"    "no such file"            skill-issue icon /nope.png
expect "non-picture refused"        "isn't a picture"         skill-issue icon "'$XDG_CONFIG_HOME/fake.png'"
expect "own picture is saved"       "Icon: $pic"              skill-issue icon "'$pic'"
expect "own picture is sent"        "NOTIFY -i $pic"          __skill_issue_send
cd $XDG_CONFIG_HOME
expect "relative path becomes full" "Icon: $pic"              skill-issue icon "'my clown.png'"
cd $here
expect "theme icon name is saved"   "Icon: skill-test-icon"   skill-issue icon skill-test-icon
expect "unknown icon name refused"  "no icon named"           skill-issue icon no-such-icon-anywhere
expect "refusal keeps the old one"  "Icon: skill-test-icon"   skill-issue icon
expect "status shows the icon"      "Icon: skill-test-icon"   skill-issue status
expect "no icon"                    "Icon: none"              skill-issue icon none
set -l out (__skill_issue_send)
if test "$out" = NOTIFY
    echo "ok    no icon: nothing is sent"
else
    echo "FAIL  no icon: nothing is sent (got: $out)"
    set -g fails (math $fails + 1)
end
expect "back to default"            "Icon: the default error icon" skill-issue icon default
expect "default sent again"         "NOTIFY -i dialog-error"  __skill_issue_send
rm -rf $XDG_CONFIG_HOME

# Messages
set -gx XDG_CONFIG_HOME (mktemp -d)
set -gx XDG_STATE_HOME $XDG_CONFIG_HOME/state
set -l bagf $XDG_STATE_HOME/skill-issue/bag
set -l mf "$XDG_CONFIG_HOME/my messages.txt"
printf '%s\n' "one" "" "# a comment" "  two  " "three"\r "four & <five>" "six" >$mf
printf '\x00\x01\x02binary' >$XDG_CONFIG_HOME/bin.txt
printf '\n# only a comment\n\n' >$XDG_CONFIG_HOME/empty.txt
expect "no messages by default"     "Messages: none"          skill-issue messages
expect "no messages: just title"    "SKILL ISSUE"             __skill_issue_handle ls 2 2
expect "missing file refused"       "no such file"            skill-issue messages /nope.txt
expect "binary file refused"        "isn't a text file"       skill-issue messages $XDG_CONFIG_HOME/bin.txt
expect "file without lines refused" "no messages in"          skill-issue messages $XDG_CONFIG_HOME/empty.txt
expect "file is saved, lines count" "(5 messages)"            skill-issue messages "'$mf'"
expect "markup is escaped"          "four &amp; &lt;five&gt;" "for i in (seq 5); __skill_issue_handle ls 2 2; end"

# The shuffle bag: every round of 5 shows all 5 once, never the same twice in a row
rm -f $bagf
set -l seen
for i in (seq 40)
    set -a seen (__skill_issue_handle ls 2 2 | string replace 'SKILL ISSUE | ' '')
end
set -l bad 0
for r in (seq 0 7)
    set -l round $seen[(math $r \* 5 + 1)..(math $r \* 5 + 5)]
    test (count (printf '%s\n' $round | sort -u)) -eq 5; or set bad 1
end
for i in (seq 2 40)
    set -l prev (math $i - 1)
    test "$seen[$i]" = "$seen[$prev]"; and set bad 1
end
if test $bad -eq 0
    echo "ok    shuffle bag: 8 rounds, all 5 each round, no repeats in a row"
else
    echo "FAIL  shuffle bag (got: $seen)"
    set -g fails (math $fails + 1)
end
test (count (printf '%s\n' $seen | string match -v -- one | string match -v -- two | string match -v -- three | string match -v -- 'four &amp; &lt;five&gt;' | string match -v -- six)) -eq 0
and echo "ok    blank lines, comments and spaces are dropped"
or begin; echo "FAIL  unexpected messages: $seen"; set -g fails (math $fails + 1); end

# Editing the file starts a new round with the new lines
sleep 1
echo "seven" >>$mf
set -l seen2
for i in (seq 6)
    set -a seen2 (__skill_issue_handle ls 2 2 | string replace 'SKILL ISSUE | ' '')
end
if contains -- seven $seen2
    echo "ok    edited file: new message shows up in the next round"
else
    echo "FAIL  edited file (got: $seen2)"
    set -g fails (math $fails + 1)
end

printf 'only one\n' >$XDG_CONFIG_HOME/one.txt
skill-issue messages $XDG_CONFIG_HOME/one.txt >/dev/null
expect "one message, every time"    "SKILL ISSUE | only one"  "__skill_issue_handle ls 2 2; __skill_issue_handle ls 2 2"
expect "status shows messages"      "(1 message)"             skill-issue status
expect "messages off"               "Messages are off"        skill-issue messages off
expect "off again: just the title"  "SKILL ISSUE"             __skill_issue_handle ls 2 2
test -e $bagf; and begin; echo "FAIL  messages off removes the bag"; set -g fails (math $fails + 1); end
rm -rf $XDG_CONFIG_HOME

expect "help has categories"        "Messages  (default: none" skill-issue help
expect "bare command shows settings" "Now"                     skill-issue
expect "bare command shows help"    "skill-issue sound FILE"  skill-issue

echo
test $fails -eq 0; and echo "all passed"; or begin; echo "$fails failed"; exit 1; end
