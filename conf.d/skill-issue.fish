# skill-issue: a "SKILL ISSUE" notification every time a command fails.
# https://github.com/egehankara/skill-issue
#
# Settings (set them in config.fish or with `set -U`):
#   skill_issue_ignore   commands whose failures are normal (grep finding nothing, etc.)
#   SKILL_ISSUE_DRY      if set, print instead of sending the notification or playing sound (for tests)
#
# Sound: none by default. Pick one with `skill-issue sound FILE` or `skill-issue sound system`.
# Icon: the red error icon by default. Change it with `skill-issue icon FILE|NAME|none|default`.
# Messages: none by default. Add a text file with `skill-issue messages FILE`, one message per line.

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

# The sound setting: a file path, "system", or no file at all (no sound, the default).
# Shared with the bash/zsh version.
function __skill_issue_sound_file
    set -l dir $XDG_CONFIG_HOME
    test -n "$dir"; or set dir ~/.config
    echo $dir/skill-issue/sound
end

# Plays $1 ("system" or a file path) with the first player that can handle it.
# Written in sh so the bash/zsh version can share it word for word.
set -g __skill_issue_player '
s=$1
if [ "$s" = system ]; then
    command -v canberra-gtk-play >/dev/null 2>&1 && canberra-gtk-play -i dialog-error >/dev/null 2>&1 && exit 0
    # No libcanberra: look for a sound theme file ourselves. Names differ between
    # desktops (freedesktop: dialog-error.oga, KDE Ocean: dialog-error-serious.oga...)
    s=
    IFS=:
    for d in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
        for f in "$d"/sounds/freedesktop/stereo/dialog-error.* "$d"/sounds/*/stereo/dialog-error* \
            "$d"/sounds/*/stereo/dialog-warning* "$d"/sounds/*/stereo/bell*; do
            [ -r "$f" ] && s=$f && break 2
        done
    done
    unset IFS
    [ -n "$s" ] || exit 1
fi
for p in pw-play paplay "mpv --no-video --really-quiet"; do
    command -v ${p%% *} >/dev/null 2>&1 && $p "$s" >/dev/null 2>&1 </dev/null && exit 0
done
# ffplay says it worked even when the file is broken, so check with ffprobe first
if command -v ffplay >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1 &&
    [ "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$s" 2>/dev/null)" = audio ]; then
    ffplay -nodisp -autoexit -loglevel quiet "$s" >/dev/null 2>&1 </dev/null && exit 0
fi
# ALSA only, last resort: aplay plays every non-wav file as loud static, so wav only
case $s in
    *.wav | *.WAV) command -v aplay >/dev/null 2>&1 && aplay -q "$s" >/dev/null 2>&1 </dev/null && exit 0 ;;
esac
exit 1'

# Plays the chosen sound. With --wait it waits (up to 5s) and returns whether it played.
function __skill_issue_play
    set -l wait 0
    if test "$argv[1]" = --wait
        set wait 1
        set -e argv[1]
    end
    set -l sound $argv[1]
    if test -z "$sound"
        set -l conf (__skill_issue_sound_file)
        test -r $conf; or return 0
        read -l line <$conf
        set sound $line
    end
    test -n "$sound"; or return 0
    if set -q SKILL_ISSUE_DRY
        echo "PLAY $sound"
        return 0
    end
    if test $wait -eq 1
        timeout 5 sh -c $__skill_issue_player skill-issue $sound
        contains -- $status 0 124
    else
        sh -c $__skill_issue_player skill-issue $sound &
        disown
    end
end

# The icon setting: a file path, an icon name from the theme, or "none".
# No file means the default error icon. Shared with the bash/zsh version.
function __skill_issue_icon_file
    set -l dir $XDG_CONFIG_HOME
    test -n "$dir"; or set dir ~/.config
    echo $dir/skill-issue/icon
end

# Prints the notify-send options for the chosen icon, one per line
function __skill_issue_icon_opts
    set -l icon dialog-error
    set -l conf (__skill_issue_icon_file)
    if test -r $conf; and read -l line <$conf; and test -n "$line"
        set icon $line
    end
    test "$icon" = none; and return
    printf '%s\n' -i $icon
end

# Sends the notification right away, with the chosen icon
function __skill_issue_send
    set -l body (__skill_issue_escape (__skill_issue_next_message))
    if set -q SKILL_ISSUE_DRY
        echo "NOTIFY" (__skill_issue_icon_opts) (test -n "$body"; and echo "| $body")
        return 0
    end
    notify-send -a Terminal (__skill_issue_icon_opts) "SKILL ISSUE" $body 2>/dev/null
end

# The messages setting: path to a text file, one message per line.
# No setting means no message, just the title. Shared with the bash/zsh version.
function __skill_issue_messages_file
    set -l dir $XDG_CONFIG_HOME
    test -n "$dir"; or set dir ~/.config
    echo $dir/skill-issue/messages
end

# Which messages are left in this round. Shared with the bash/zsh version.
function __skill_issue_bag_file
    set -l dir $XDG_STATE_HOME
    test -n "$dir"; or set dir ~/.local/state
    echo $dir/skill-issue/bag
end

# Prints the usable lines of a messages file: no empty lines, no # comments
function __skill_issue_read_messages -a file
    test -f "$file" -a -r "$file"; or return 1
    string replace -r '\r$' '' <$file | string trim | string match -rv '^(#.*)?$'
end

# Prints the next message. Shuffle-bag random: every message is shown once
# before any repeats, and never the same one twice in a row.
function __skill_issue_next_message
    set -l conf (__skill_issue_messages_file)
    test -r $conf; or return 1
    read -l file <$conf; or return 1
    set -l msgs (__skill_issue_read_messages $file)
    set -l n (count $msgs)
    test $n -gt 0; or return 1

    # The bag file: a stamp of the messages file, the last message shown, then what's left.
    # If the messages file changed, the stamp doesn't match and a new round starts.
    set -l bagf (__skill_issue_bag_file)
    set -l stamp "$n:"(stat -c %Y:%s -- $file 2>/dev/null)":$file"
    set -l last 0
    set -l bag
    if test -r $bagf
        set -l lines
        while read -l line
            set -a lines $line
        end <$bagf
        if test "$lines[1]" = "$stamp"
            set last $lines[2]
            set bag $lines[3..-1]
        end
    end

    if not set -q bag[1]
        # New round: shuffle all messages (Fisher-Yates)
        set bag (seq $n)
        for i in (seq $n -1 2)
            set -l j (random 1 $i)
            set -l t $bag[$i]
            set bag[$i] $bag[$j]
            set bag[$j] $t
        end
        # Don't start the new round with the message that ended the last one
        if test $n -gt 1; and test "$bag[1]" = "$last"
            set bag $bag[2..-1] $bag[1]
        end
    end

    set -l idx $bag[1]
    set -e bag[1]
    if not string match -qr '^[0-9]+$' -- $idx; or test $idx -lt 1 -o $idx -gt $n
        set idx (random 1 $n)
        set bag
    end
    mkdir -p (string replace -r '/[^/]*$' '' -- $bagf)
    printf '%s\n' $stamp $idx $bag >$bagf
    echo $msgs[$idx]
end

# Notifications understand a bit of HTML, so "a < b" must be written as "a &lt; b"
function __skill_issue_escape
    # Without arguments string would read from the terminal, so stop here
    set -q argv[1]; or return 1
    string replace -a -- '&' '&amp;' $argv | string replace -a -- '<' '&lt;' | string replace -a -- '>' '&gt;'
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
        set -l body (__skill_issue_escape (__skill_issue_next_message))
        if test -n "$body"
            echo "SKILL ISSUE | $body"
        else
            echo "SKILL ISSUE"
        end
        __skill_issue_play
        return
    end
    test -e (__skill_issue_off_file); and return
    # No screen to show it on (SSH, TTY)
    set -q DISPLAY; or set -q WAYLAND_DISPLAY; or return
    __skill_issue_play
    # Missing notify-send or notification daemon: stay quiet instead of printing errors
    command -q notify-send; or return
    set -l body (__skill_issue_escape (__skill_issue_next_message))
    notify-send -a Terminal (__skill_issue_icon_opts) "SKILL ISSUE" $body 2>/dev/null &
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

function __skill_issue_sound_status
    set -l conf (__skill_issue_sound_file)
    if test -r $conf; and read -l line <$conf; and test -n "$line"
        if test "$line" = system
            echo "Sound: the system error sound"
        else
            echo "Sound: $line"
        end
    else
        echo "Sound: none. Pick one with: skill-issue sound /path/to/file.mp3  or  skill-issue sound system"
    end
end

function __skill_issue_sound -a choice
    set -l conf (__skill_issue_sound_file)
    set -l sound
    switch "$choice"
        case ''
            __skill_issue_sound_status
            return
        case off none
            rm -f $conf
            echo "Sound is off."
            return
        case system
            set sound system
        case '*'
            # Store an absolute path, so it works from any folder
            set -l file (string replace -r '^~' -- $HOME $choice)
            if not test -f "$file"
                echo "skill-issue: no such file: $choice" >&2
                return 1
            end
            if not test -r "$file"
                echo "skill-issue: can't read $choice" >&2
                return 1
            end
            set sound (realpath -- $file)
    end
    # Play it once first: only save a sound that actually plays
    if not __skill_issue_play --wait $sound
        if test "$sound" = system
            echo "skill-issue: couldn't find a system error sound. Install libcanberra or" >&2
            echo "sound-theme-freedesktop, or use your own file: skill-issue sound /path/to/file.mp3" >&2
        else
            echo "skill-issue: couldn't play $choice. wav, ogg, mp3, flac and opus work everywhere;" >&2
            echo "other formats need mpv or ffmpeg." >&2
        end
        echo "Nothing changed." >&2
        return 1
    end
    mkdir -p (string replace -r '/[^/]*$' '' -- $conf)
    echo $sound >$conf
    __skill_issue_sound_status
end

function __skill_issue_icon_status
    set -l conf (__skill_issue_icon_file)
    if test -r $conf; and read -l line <$conf; and test -n "$line"
        if test "$line" = none
            echo "Icon: none"
        else
            echo "Icon: $line"
        end
    else
        echo "Icon: the default error icon"
    end
end

# Is there an icon with this name in the installed icon themes?
function __skill_issue_icon_exists -a name
    set -l dirs $XDG_DATA_HOME
    test -n "$dirs"; or set dirs ~/.local/share
    set -l data $XDG_DATA_DIRS
    test -n "$data"; or set data /usr/local/share:/usr/share
    set -a dirs (string split : -- $data)
    set -l found ~/.icons/*/*/*/$name.* $dirs/icons/*/*/*/$name.* $dirs/icons/*/*/$name.* $dirs/pixmaps/$name.*
    set -q found[1]
end

function __skill_issue_icon -a choice
    set -l conf (__skill_issue_icon_file)
    set -l icon
    switch "$choice"
        case ''
            __skill_issue_icon_status
            return
        case default
            rm -f $conf
        case none off
            set icon none
        case '*'
            set -l file (string replace -r '^~' -- $HOME $choice)
            if string match -q -- '*/*' $choice; or test -e "$file"
                # A picture file
                if not test -f "$file"
                    echo "skill-issue: no such file: $choice" >&2
                    return 1
                end
                if not test -r "$file"
                    echo "skill-issue: can't read $choice" >&2
                    return 1
                end
                set -l is_image 0
                if command -q file
                    string match -q 'image/*' (file -b --mime-type -- $file); and set is_image 1
                else
                    string match -qir -- '\.(png|jpe?g|svgz?|gif|webp|bmp|ico|xpm|tiff?)$' $file; and set is_image 1
                end
                if test $is_image -eq 0
                    echo "skill-issue: $choice isn't a picture. Use a png, jpg, svg..." >&2
                    return 1
                end
                set icon (realpath -- $file)
            else
                # An icon name from the theme, like face-sad
                if string match -qr -- '[^A-Za-z0-9._-]' $choice; or not __skill_issue_icon_exists $choice
                    echo "skill-issue: no icon named '$choice' in your icon theme." >&2
                    echo "Use a picture file instead: skill-issue icon ~/pictures/clown.png" >&2
                    return 1
                end
                set icon $choice
            end
    end
    if test -n "$icon"
        mkdir -p (string replace -r '/[^/]*$' '' -- $conf)
        echo $icon >$conf
    end
    __skill_issue_icon_status
    # Show it once
    if __skill_issue_send
        echo "Sent a notification so you can see it."
    end
end

function __skill_issue_messages_status
    set -l conf (__skill_issue_messages_file)
    if test -r $conf; and read -l file <$conf; and test -n "$file"
        set -l n (count (__skill_issue_read_messages $file))
        if not test -f "$file"
            echo "Messages: $file (the file is missing, so no messages)"
        else if test $n -eq 1
            echo "Messages: $file (1 message)"
        else
            echo "Messages: $file ($n messages)"
        end
    else
        echo "Messages: none. Add some with: skill-issue messages /path/to/messages.txt"
    end
end

function __skill_issue_messages -a choice
    set -l conf (__skill_issue_messages_file)
    switch "$choice"
        case ''
            __skill_issue_messages_status
            return
        case off none
            rm -f $conf (__skill_issue_bag_file)
            echo "Messages are off. Just SKILL ISSUE."
            return
    end
    set -l file (string replace -r '^~' -- $HOME $choice)
    if not test -f "$file"
        echo "skill-issue: no such file: $choice" >&2
        return 1
    end
    if not test -r "$file"
        echo "skill-issue: can't read $choice" >&2
        return 1
    end
    if command -q file
        set -l mime (file -b --mime-type -- $file)
        if not string match -q 'text/*' $mime
            echo "skill-issue: $choice isn't a text file. Write one message per line in a .txt file." >&2
            return 1
        end
    end
    set -l found (__skill_issue_read_messages $file)
    if not set -q found[1]
        echo "skill-issue: no messages in $choice. Write one message per line." >&2
        echo "Empty lines and lines starting with # are skipped." >&2
        return 1
    end
    mkdir -p (string replace -r '/[^/]*$' '' -- $conf)
    realpath -- $file >$conf
    rm -f (__skill_issue_bag_file)
    __skill_issue_messages_status
    if __skill_issue_send
        echo "Sent a notification so you can see one."
    end
end

# Commands, grouped. Headings are bold in a terminal.
function __skill_issue_help
    set -l b ''
    set -l r ''
    if isatty stdout
        set b (set_color --bold)
        set r (set_color normal)
    end
    echo "skill-issue: a SKILL ISSUE notification every time a command fails"
    echo
    echo {$b}"General"{$r}""
    echo "  skill-issue on              turn notifications on"
    echo "  skill-issue off             turn them off, in every shell, until you turn them back on"
    echo "  skill-issue status          show the current settings"
    echo "  skill-issue test            send a test notification"
    echo "  skill-issue help            show this help"
    echo
    echo {$b}"Sound"{$r}"  (default: none)"
    echo "  skill-issue sound FILE      play FILE with every SKILL ISSUE (wav, ogg, mp3, flac, opus...)"
    echo "  skill-issue sound system    play your system's error sound"
    echo "  skill-issue sound off       no sound"
    echo "  skill-issue sound           show the current sound"
    echo
    echo {$b}"Icon"{$r}"  (default: the red error icon)"
    echo "  skill-issue icon FILE       show a picture of yours (png, jpg, svg, webp...)"
    echo "  skill-issue icon NAME       show an icon from your icon theme, like face-sad"
    echo "  skill-issue icon none       no icon"
    echo "  skill-issue icon default    back to the red error icon"
    echo "  skill-issue icon            show the current icon"
    echo
    echo {$b}"Messages"{$r}"  (default: none, just SKILL ISSUE)"
    echo "  skill-issue messages FILE   show a random line of FILE under SKILL ISSUE, one message per line"
    echo "  skill-issue messages off    back to just SKILL ISSUE"
    echo "  skill-issue messages        show the current file"
end

function __skill_issue_status
    if test -e (__skill_issue_off_file)
        echo "skill-issue is off. Turn it on with: skill-issue on"
    else
        echo "skill-issue is on. Turn it off with: skill-issue off"
    end
    __skill_issue_sound_status
    __skill_issue_icon_status
    __skill_issue_messages_status
end

function skill-issue -d "Turn SKILL ISSUE on or off, pick a sound, icon or messages"
    set -l off (__skill_issue_off_file)
    switch "$argv[1]"
        case off
            mkdir -p (string replace -r '/[^/]*$' '' -- $off); and touch $off
            echo "skill-issue is off. No more truth, in any shell."
        case on
            rm -f $off
            echo "skill-issue is on."
        case ''
            # Where things stand, then every command
            set -l b ''
            set -l r ''
            if isatty stdout
                set b (set_color --bold)
                set r (set_color normal)
            end
            echo $b"Now"$r
            __skill_issue_status | string replace -r '^' '  '
            echo
            __skill_issue_help | sed '1,2d'
        case status
            __skill_issue_status
        case sound
            __skill_issue_sound $argv[2]
        case icon
            __skill_issue_icon $argv[2]
        case messages
            __skill_issue_messages $argv[2]
        case test
            if test -e $off
                echo "skill-issue is off, so nothing will show up. Turn it on with: skill-issue on"
                return 1
            end
            __skill_issue_play
            if __skill_issue_send
                echo "Sent a test notification."
            else
                echo "Couldn't show a notification. Is a notification daemon running?"
                return 1
            end
        case help -h --help
            __skill_issue_help
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
