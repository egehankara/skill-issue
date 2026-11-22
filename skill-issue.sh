# skill-issue for bash and zsh: a "SKILL ISSUE" notification every time a command fails.
# https://github.com/egehankara/skill-issue
#
# Source this at the END of ~/.bashrc or ~/.zshrc (after prompt tools like starship):
#   source /path/to/skill-issue/skill-issue.sh
#
# Settings (set them before sourcing):
#   SKILL_ISSUE_IGNORE   space-separated commands whose failures are normal (grep finding nothing, etc.)
#   SKILL_ISSUE_DRY      if set, print instead of sending the notification or playing sound (for tests)
#
# Sound: none by default. Pick one with `skill-issue sound FILE` or `skill-issue sound system`.
# Icon: the red error icon by default. Change it with `skill-issue icon FILE|NAME|none|default`.
# Messages: none by default. Add a text file with `skill-issue messages FILE`, one message per line.

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

# Plays $1 ("system" or a file path) with the first player that can handle it.
# Same script as in the fish version.
__skill_issue_player='
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

# The sound setting: a file path, "system", or no file at all (no sound, the default)
__skill_issue_sound_file() {
    __skill_issue_conf="${XDG_CONFIG_HOME:-$HOME/.config}/skill-issue/sound"
}

# Plays the chosen sound. With --wait it waits (up to 5s) and returns whether it played.
__skill_issue_play() {
    local wait=0 sound
    if [ "${1:-}" = --wait ]; then
        wait=1
        shift
    fi
    sound=${1:-}
    if [ -z "$sound" ]; then
        __skill_issue_sound_file
        [ -r "$__skill_issue_conf" ] || return 0
        IFS= read -r sound <"$__skill_issue_conf" || [ -n "$sound" ] || return 0
    fi
    [ -n "$sound" ] || return 0
    if [ -n "${SKILL_ISSUE_DRY:-}" ]; then
        echo "PLAY $sound"
        return 0
    fi
    if [ "$wait" = 1 ]; then
        timeout 5 sh -c "$__skill_issue_player" skill-issue "$sound"
        case $? in 0 | 124) return 0 ;; *) return 1 ;; esac
    else
        (sh -c "$__skill_issue_player" skill-issue "$sound" >/dev/null 2>&1 &)
    fi
}

# The icon setting: a file path, an icon name from the theme, or "none".
# No file means the default error icon. Shared with the fish version.
__skill_issue_icon_file() {
    __skill_issue_iconf="${XDG_CONFIG_HOME:-$HOME/.config}/skill-issue/icon"
}

# Sets __skill_issue_icon_args to the notify-send options for the chosen icon
__skill_issue_icon_opts() {
    local icon=dialog-error line=
    __skill_issue_icon_file
    if [ -r "$__skill_issue_iconf" ]; then
        IFS= read -r line <"$__skill_issue_iconf" || :
        [ -n "$line" ] && icon=$line
    fi
    if [ "$icon" = none ]; then
        __skill_issue_icon_args=()
    else
        __skill_issue_icon_args=(-i "$icon")
    fi
}

# The messages setting: path to a text file, one message per line.
# No setting means no message, just the title. Shared with the fish version.
__skill_issue_messages_file() {
    __skill_issue_msgconf="${XDG_CONFIG_HOME:-$HOME/.config}/skill-issue/messages"
}

# Sets __skill_issue_msgs to the usable lines of a messages file: no empty lines, no # comments
__skill_issue_read_messages() {
    local line
    __skill_issue_msgs=()
    [ -f "$1" ] && [ -r "$1" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        case $line in '' | '#'*) continue ;; esac
        __skill_issue_msgs+=("$line")
    done <"$1"
    [ "${#__skill_issue_msgs[@]}" -gt 0 ]
}

# Sets __skill_issue_message to the next message. Shuffle-bag random: every message
# is shown once before any repeats, and never the same one twice in a row.
# No subshell here: zsh wouldn't move $RANDOM forward in one.
__skill_issue_next_message() {
    # Count arrays from 0 in zsh too, like bash
    [ -n "${ZSH_VERSION:-}" ] && setopt localoptions ksharrays
    local file= n stamp bagf last=0 i j t idx line
    local -a bag lines
    __skill_issue_message=
    __skill_issue_messages_file
    [ -r "$__skill_issue_msgconf" ] || return 1
    IFS= read -r file <"$__skill_issue_msgconf" || [ -n "$file" ] || return 1
    __skill_issue_read_messages "$file" || return 1
    n=${#__skill_issue_msgs[@]}

    # The bag file: a stamp of the messages file, the last message shown, then what's left.
    # If the messages file changed, the stamp doesn't match and a new round starts.
    bagf="${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/bag"
    stamp="$n:$(stat -c %Y:%s -- "$file" 2>/dev/null):$file"
    if [ -r "$bagf" ]; then
        while IFS= read -r line; do
            lines+=("$line")
        done <"$bagf"
        if [ "${lines[0]:-}" = "$stamp" ]; then
            last=${lines[1]:-0}
            bag=("${lines[@]:2}")
        fi
    fi

    if [ "${#bag[@]}" = 0 ]; then
        # New round: shuffle all messages (Fisher-Yates)
        i=1
        while [ "$i" -le "$n" ]; do
            bag+=("$i")
            i=$((i + 1))
        done
        i=$((n - 1))
        while [ "$i" -gt 0 ]; do
            j=$((RANDOM % (i + 1)))
            t=${bag[i]}
            bag[i]=${bag[j]}
            bag[j]=$t
            i=$((i - 1))
        done
        # Don't start the new round with the message that ended the last one
        if [ "$n" -gt 1 ] && [ "${bag[0]}" = "$last" ]; then
            bag=("${bag[@]:1}" "${bag[0]}")
        fi
    fi

    idx=${bag[0]}
    bag=("${bag[@]:1}")
    case $idx in '' | *[!0-9]*) idx=0 ;; esac
    if [ "$idx" -lt 1 ] || [ "$idx" -gt "$n" ]; then
        idx=$((RANDOM % n + 1))
        bag=()
    fi
    mkdir -p "${bagf%/*}"
    printf '%s\n' "$stamp" "$idx" "${bag[@]}" >"$bagf"
    __skill_issue_message=${__skill_issue_msgs[idx - 1]}
}

# Sets __skill_issue_body_args to the message for notify-send, if there is one.
# Notifications understand a bit of HTML, so "a < b" must be written as "a &lt; b".
__skill_issue_body() {
    local m
    __skill_issue_body_args=()
    __skill_issue_next_message || return 0
    m=$__skill_issue_message
    m=${m//'&'/'&amp;'}
    m=${m//'<'/'&lt;'}
    m=${m//'>'/'&gt;'}
    __skill_issue_body_args=("$m")
}

# Sends the notification right away, with the chosen icon
__skill_issue_send() {
    __skill_issue_icon_opts
    __skill_issue_body
    if [ -n "${SKILL_ISSUE_DRY:-}" ]; then
        echo "NOTIFY ${__skill_issue_icon_args[*]}${__skill_issue_body_args[*]:+ | ${__skill_issue_body_args[*]}}"
        return 0
    fi
    notify-send -a Terminal "${__skill_issue_icon_args[@]}" "SKILL ISSUE" "${__skill_issue_body_args[@]}" 2>/dev/null
}

__skill_issue_notify() {
    if [ -n "${SKILL_ISSUE_DRY:-}" ]; then
        __skill_issue_body
        echo "SKILL ISSUE${__skill_issue_body_args[*]:+ | ${__skill_issue_body_args[*]}}"
        __skill_issue_play
        return 0
    fi
    # Turned off with `skill-issue off` (shared with the fish version)
    [ -e "${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/off" ] && return 0
    # No screen to show it on (SSH, TTY)
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 0
    __skill_issue_play
    # Missing notify-send or notification daemon: stay quiet instead of printing errors
    command -v notify-send >/dev/null 2>&1 || return 0
    __skill_issue_icon_opts
    __skill_issue_body
    (notify-send -a Terminal "${__skill_issue_icon_args[@]}" "SKILL ISSUE" "${__skill_issue_body_args[@]}" >/dev/null 2>&1 &)
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

__skill_issue_sound_status() {
    local line=
    __skill_issue_sound_file
    if [ -r "$__skill_issue_conf" ]; then
        IFS= read -r line <"$__skill_issue_conf" || :
    fi
    if [ -z "$line" ]; then
        echo "Sound: none. Pick one with: skill-issue sound /path/to/file.mp3  or  skill-issue sound system"
    elif [ "$line" = system ]; then
        echo "Sound: the system error sound"
    else
        echo "Sound: $line"
    fi
}

__skill_issue_sound() {
    local choice=${1:-} sound file
    __skill_issue_sound_file
    case $choice in
        '')
            __skill_issue_sound_status
            return 0
            ;;
        off | none)
            rm -f "$__skill_issue_conf"
            echo "Sound is off."
            return 0
            ;;
        system)
            sound=system
            ;;
        *)
            # Store an absolute path, so it works from any folder
            file=$choice
            case $file in "~"*) file=$HOME${file#"~"} ;; esac
            if [ ! -f "$file" ]; then
                echo "skill-issue: no such file: $choice" >&2
                return 1
            fi
            if [ ! -r "$file" ]; then
                echo "skill-issue: can't read $choice" >&2
                return 1
            fi
            sound=$(realpath -- "$file")
            ;;
    esac
    # Play it once first: only save a sound that actually plays
    if ! __skill_issue_play --wait "$sound"; then
        if [ "$sound" = system ]; then
            echo "skill-issue: couldn't find a system error sound. Install libcanberra or" >&2
            echo "sound-theme-freedesktop, or use your own file: skill-issue sound /path/to/file.mp3" >&2
        else
            echo "skill-issue: couldn't play $choice. wav, ogg, mp3, flac and opus work everywhere;" >&2
            echo "other formats need mpv or ffmpeg." >&2
        fi
        echo "Nothing changed." >&2
        return 1
    fi
    mkdir -p "${__skill_issue_conf%/*}"
    printf '%s\n' "$sound" >"$__skill_issue_conf"
    __skill_issue_sound_status
}

__skill_issue_icon_status() {
    local line=
    __skill_issue_icon_file
    if [ -r "$__skill_issue_iconf" ]; then
        IFS= read -r line <"$__skill_issue_iconf" || :
    fi
    if [ -z "$line" ]; then
        echo "Icon: the default error icon"
    elif [ "$line" = none ]; then
        echo "Icon: none"
    else
        echo "Icon: $line"
    fi
}

# Is there an icon with this name in the installed icon themes?
__skill_issue_icon_exists() {
    local name=$1 d f rest="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    [ -n "${ZSH_VERSION:-}" ] && setopt localoptions nonomatch
    while [ -n "$rest" ]; do
        d=${rest%%:*}
        case $rest in
            *:*) rest=${rest#*:} ;;
            *) rest= ;;
        esac
        [ -n "$d" ] || continue
        for f in "$HOME"/.icons/*/*/*/"$name".* "$d"/icons/*/*/*/"$name".* "$d"/icons/*/*/"$name".* "$d"/pixmaps/"$name".*; do
            [ -e "$f" ] && return 0
        done
    done
    return 1
}

__skill_issue_icon() {
    local choice=${1:-} icon= file mime choice_ok
    __skill_issue_icon_file
    case $choice in
        '')
            __skill_issue_icon_status
            return 0
            ;;
        default)
            rm -f "$__skill_issue_iconf"
            ;;
        none | off)
            icon=none
            ;;
        *)
            file=$choice
            case $file in "~"*) file=$HOME${file#"~"} ;; esac
            case $choice in */*) ;; *) [ -e "$file" ] || file= ;; esac
            if [ -n "$file" ]; then
                # A picture file
                if [ ! -f "$file" ]; then
                    echo "skill-issue: no such file: $choice" >&2
                    return 1
                fi
                if [ ! -r "$file" ]; then
                    echo "skill-issue: can't read $choice" >&2
                    return 1
                fi
                if command -v file >/dev/null 2>&1; then
                    mime=$(command file -b --mime-type -- "$file")
                else
                    case $file in
                        *.[pP][nN][gG] | *.[jJ][pP][gG] | *.[jJ][pP][eE][gG] | *.[sS][vV][gG] | *.[sS][vV][gG][zZ] | \
                            *.[gG][iI][fF] | *.[wW][eE][bB][pP] | *.[bB][mM][pP] | *.[iI][cC][oO] | *.[xX][pP][mM] | \
                            *.[tT][iI][fF] | *.[tT][iI][fF][fF]) mime=image/ ;;
                        *) mime= ;;
                    esac
                fi
                case $mime in
                    image/*) ;;
                    *)
                        echo "skill-issue: $choice isn't a picture. Use a png, jpg, svg..." >&2
                        return 1
                        ;;
                esac
                icon=$(realpath -- "$file")
            else
                # An icon name from the theme, like face-sad
                case $choice in
                    *[!A-Za-z0-9._-]*) choice_ok=0 ;;
                    *) choice_ok=1 ;;
                esac
                if [ "$choice_ok" = 0 ] || ! __skill_issue_icon_exists "$choice"; then
                    echo "skill-issue: no icon named '$choice' in your icon theme." >&2
                    echo "Use a picture file instead: skill-issue icon ~/pictures/clown.png" >&2
                    return 1
                fi
                icon=$choice
            fi
            ;;
    esac
    if [ -n "$icon" ]; then
        mkdir -p "${__skill_issue_iconf%/*}"
        printf '%s\n' "$icon" >"$__skill_issue_iconf"
    fi
    __skill_issue_icon_status
    # Show it once
    if __skill_issue_send; then
        echo "Sent a notification so you can see it."
    fi
}

__skill_issue_messages_status() {
    local file=
    __skill_issue_messages_file
    if [ -r "$__skill_issue_msgconf" ]; then
        IFS= read -r file <"$__skill_issue_msgconf" || :
    fi
    if [ -z "$file" ]; then
        echo "Messages: none. Add some with: skill-issue messages /path/to/messages.txt"
    elif [ ! -f "$file" ]; then
        echo "Messages: $file (the file is missing, so no messages)"
    else
        __skill_issue_read_messages "$file" || :
        if [ "${#__skill_issue_msgs[@]}" = 1 ]; then
            echo "Messages: $file (1 message)"
        else
            echo "Messages: $file (${#__skill_issue_msgs[@]} messages)"
        fi
    fi
}

__skill_issue_messages() {
    local choice=${1:-} file mime
    __skill_issue_messages_file
    case $choice in
        '')
            __skill_issue_messages_status
            return 0
            ;;
        off | none)
            rm -f "$__skill_issue_msgconf" "${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/bag"
            echo "Messages are off. Just SKILL ISSUE."
            return 0
            ;;
    esac
    file=$choice
    case $file in "~"*) file=$HOME${file#"~"} ;; esac
    if [ ! -f "$file" ]; then
        echo "skill-issue: no such file: $choice" >&2
        return 1
    fi
    if [ ! -r "$file" ]; then
        echo "skill-issue: can't read $choice" >&2
        return 1
    fi
    if command -v file >/dev/null 2>&1; then
        mime=$(command file -b --mime-type -- "$file")
        case $mime in
            text/*) ;;
            *)
                echo "skill-issue: $choice isn't a text file. Write one message per line in a .txt file." >&2
                return 1
                ;;
        esac
    fi
    if ! __skill_issue_read_messages "$file"; then
        echo "skill-issue: no messages in $choice. Write one message per line." >&2
        echo "Empty lines and lines starting with # are skipped." >&2
        return 1
    fi
    mkdir -p "${__skill_issue_msgconf%/*}"
    realpath -- "$file" >"$__skill_issue_msgconf"
    rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/bag"
    __skill_issue_messages_status
    if __skill_issue_send; then
        echo "Sent a notification so you can see one."
    fi
}

# Commands, grouped. Headings are bold in a terminal.
__skill_issue_help() {
    local b= r=
    if [ -t 1 ]; then
        b=$'\033[1m'
        r=$'\033[0m'
    fi
    echo "skill-issue: a SKILL ISSUE notification every time a command fails"
    echo
    echo "${b}General${r}"
    echo "  skill-issue on              turn notifications on"
    echo "  skill-issue off             turn them off, in every shell, until you turn them back on"
    echo "  skill-issue status          show the current settings"
    echo "  skill-issue test            send a test notification"
    echo "  skill-issue help            show this help"
    echo
    echo "${b}Sound${r}  (default: none)"
    echo "  skill-issue sound FILE      play FILE with every SKILL ISSUE (wav, ogg, mp3, flac, opus...)"
    echo "  skill-issue sound system    play your system's error sound"
    echo "  skill-issue sound off       no sound"
    echo "  skill-issue sound           show the current sound"
    echo
    echo "${b}Icon${r}  (default: the red error icon)"
    echo "  skill-issue icon FILE       show a picture of yours (png, jpg, svg, webp...)"
    echo "  skill-issue icon NAME       show an icon from your icon theme, like face-sad"
    echo "  skill-issue icon none       no icon"
    echo "  skill-issue icon default    back to the red error icon"
    echo "  skill-issue icon            show the current icon"
    echo
    echo "${b}Messages${r}  (default: none, just SKILL ISSUE)"
    echo "  skill-issue messages FILE   show a random line of FILE under SKILL ISSUE, one message per line"
    echo "  skill-issue messages off    back to just SKILL ISSUE"
    echo "  skill-issue messages        show the current file"
}

__skill_issue_status() {
    if [ -e "${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/off" ]; then
        echo "skill-issue is off. Turn it on with: skill-issue on"
    else
        echo "skill-issue is on. Turn it off with: skill-issue off"
    fi
    __skill_issue_sound_status
    __skill_issue_icon_status
    __skill_issue_messages_status
}

skill-issue() {
    local off="${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/off"
    case ${1:-} in
        off)
            mkdir -p "${off%/*}" && : >"$off"
            echo "skill-issue is off. No more truth, in any shell."
            ;;
        on)
            rm -f "$off"
            echo "skill-issue is on."
            ;;
        '')
            # Where things stand, then every command
            local b= r=
            if [ -t 1 ]; then
                b=$'\033[1m'
                r=$'\033[0m'
            fi
            echo "${b}Now${r}"
            __skill_issue_status | sed 's/^/  /'
            echo
            __skill_issue_help | sed '1,2d'
            ;;
        status)
            __skill_issue_status
            ;;
        sound)
            __skill_issue_sound "${2:-}"
            ;;
        icon)
            __skill_issue_icon "${2:-}"
            ;;
        messages)
            __skill_issue_messages "${2:-}"
            ;;
        test)
            if [ -e "$off" ]; then
                echo "skill-issue is off, so nothing will show up. Turn it on with: skill-issue on"
                return 1
            fi
            __skill_issue_play
            if __skill_issue_send; then
                echo "Sent a test notification."
            else
                echo "Couldn't show a notification. Is a notification daemon running?"
                return 1
            fi
            ;;
        help | -h | --help)
            __skill_issue_help
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
