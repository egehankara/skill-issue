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

# Globals the functions below fill in. Declared here so zsh's warn_create_global stays quiet.
# Files are written with ">|" so noclobber (set -C) doesn't block them.
__skill_issue_last_cmd=
__skill_issue_last_time=0
__skill_issue_cmdname=
__skill_issue_conf=
__skill_issue_iconf=
__skill_issue_msgconf=
__skill_issue_message=
__skill_issue_today_n=0
__skill_issue_countf=
__skill_issue_icon_args=()
__skill_issue_body_args=()

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

# Picks messages. Written in sh so the bash/zsh version can share it word for word.
#   count FILE        prints how many messages FILE has
#   next FILE BAG     prints the next message. Shuffle-bag random: every message is shown
#                     once before any repeats, never the same one twice in a row.
# BAG holds a stamp of FILE, the last message shown, then what's left of the round.
# If FILE changes, the stamp doesn't match and a new round starts.
__skill_issue_picker='
[ -f "$2" ] && [ -r "$2" ] || exit 1
# One message per line: trim spaces, skip empty lines and # comments.
# Bytes that are not valid UTF-8 are dropped: notifications refuse them.
utf8() { if command -v iconv >/dev/null 2>&1; then iconv -f UTF-8 -t UTF-8 -c; else cat; fi; }
list=$(tr -d "\r" <"$2" | utf8 | sed "s/^[[:space:]]*//; s/[[:space:]]*\$//" | grep -a -v -e "^\$" -e "^#")
n=0
[ -n "$list" ] && n=$(printf "%s\n" "$list" | wc -l)
if [ "$1" = count ]; then
    echo "$n"
    exit 0
fi
[ "$n" -gt 0 ] || exit 1
bag=$3
stamp="$n:$(stat -c %Y:%s -- "$2" 2>/dev/null):$2"
last=0
rest=
if [ -r "$bag" ] && [ "$(head -n 1 "$bag")" = "$stamp" ]; then
    last=$(sed -n 2p "$bag")
    rest=$(tail -n +3 "$bag")
fi
if [ -z "$rest" ]; then
    # New round: every message once, in random order
    rest=$(seq "$n" | shuf)
    # Do not start it with the message that ended the last round
    if [ "$n" -gt 1 ] && [ "$(printf "%s\n" "$rest" | head -n 1)" = "$last" ]; then
        rest=$(printf "%s\n" "$rest" | tail -n +2; echo "$last")
    fi
fi
idx=$(printf "%s\n" "$rest" | head -n 1)
rest=$(printf "%s\n" "$rest" | tail -n +2)
case $idx in "" | *[!0-9]*) idx=0 ;; esac
if [ "$idx" -lt 1 ] || [ "$idx" -gt "$n" ]; then
    idx=$(shuf -i "1-$n" -n 1)
    rest=
fi
mkdir -p "${bag%/*}"
{
    printf "%s\n%s\n" "$stamp" "$idx"
    if [ -n "$rest" ]; then printf "%s\n" "$rest"; fi
} >"$bag.$$" && mv -f "$bag.$$" "$bag"
printf "%s\n" "$list" | sed -n "${idx}p"'

# Sets __skill_issue_message to the next message, if there's a messages file
__skill_issue_next_message() {
    local file=
    __skill_issue_message=
    __skill_issue_messages_file
    [ -r "$__skill_issue_msgconf" ] || return 1
    IFS= read -r file <"$__skill_issue_msgconf" || [ -n "$file" ] || return 1
    __skill_issue_message=$(sh -c "$__skill_issue_picker" skill-issue next "$file" \
        "${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/bag" 2>/dev/null)
    [ -n "$__skill_issue_message" ]
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
        printf '%s\n' "NOTIFY ${__skill_issue_icon_args[*]}${__skill_issue_body_args[*]:+ | ${__skill_issue_body_args[*]}}"
        return 0
    fi
    notify-send -a skill-issue "${__skill_issue_icon_args[@]}" "SKILL ISSUE" "${__skill_issue_body_args[@]}" 2>/dev/null
}

__skill_issue_notify() {
    if [ -n "${SKILL_ISSUE_DRY:-}" ]; then
        __skill_issue_body
        printf '%s\n' "SKILL ISSUE${__skill_issue_body_args[*]:+ | ${__skill_issue_body_args[*]}}"
        __skill_issue_count_up
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
    __skill_issue_count_up
    __skill_issue_icon_opts
    __skill_issue_body
    (notify-send -a skill-issue "${__skill_issue_icon_args[@]}" "SKILL ISSUE" "${__skill_issue_body_args[@]}" >/dev/null 2>&1 &)
}

# Today's count lives in count-YYYY-MM-DD: one byte per SKILL ISSUE, so the count is the
# file size. Appending a byte is atomic, so terminals failing at the same moment never lose
# one. Shared with the fish version.
__skill_issue_count_file() {
    __skill_issue_countf="${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/count-$(date +%F)"
}

# Sets __skill_issue_today_n to how many SKILL ISSUEs there were today
__skill_issue_today() {
    local n
    __skill_issue_count_file
    __skill_issue_today_n=0
    if [ -f "$__skill_issue_countf" ]; then
        n=$(wc -c <"$__skill_issue_countf")
        __skill_issue_today_n=$((n + 0))
    fi
}

# One more for today. The first one of a new day clears the old days.
__skill_issue_count_up() {
    __skill_issue_count_file
    if [ ! -f "$__skill_issue_countf" ]; then
        mkdir -p "${__skill_issue_countf%/*}"
        # find, not a glob: no error with nomatch / failglob when there's nothing to clear
        find "${__skill_issue_countf%/*}" -maxdepth 1 -name 'count-*' -delete
    fi
    # In sh: zsh's noclobber won't let >> create a file, and bash has no >>| to override it
    sh -c 'printf x >>"$1"' skill-issue "$__skill_issue_countf"
}

# "No SKILL ISSUE today", "1 SKILL ISSUE today", "7 SKILL ISSUEs today"
__skill_issue_today_text() {
    __skill_issue_today
    case $__skill_issue_today_n in
        0) echo "No SKILL ISSUE today. Suspicious." ;;
        1) echo "1 SKILL ISSUE today." ;;
        *) echo "$__skill_issue_today_n SKILL ISSUEs today." ;;
    esac
}

# Usage: __skill_issue_handle CMDLINE "PIPESTATUS CODES" STATUS
__skill_issue_handle() {
    local cmd=$1 codes=$2 st=$3 failed=0 re c part prest crest rest n_parts=1 n_codes=0
    local MATCH MBEGIN MEND
    local -a match mbegin mend

    # Fast path: everything worked and there's no earlier failure to compare with
    if [ -z "$__skill_issue_last_cmd" ]; then
        case "$codes $st" in *[!0\ ]*) ;; *) return 0 ;; esac
    fi

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

# Is $1 a readable file? Prints why not. $2 is the name the user typed.
__skill_issue_check_file() {
    if [ -d "$1" ]; then
        echo "skill-issue: $2 is a folder, not a file" >&2
        return 1
    fi
    if [ ! -f "$1" ]; then
        echo "skill-issue: no such file: $2" >&2
        return 1
    fi
    if [ ! -r "$1" ]; then
        echo "skill-issue: can't read $2" >&2
        return 1
    fi
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
    elif [ ! -f "$line" ]; then
        echo "Sound: $line (the file is missing, so no sound)"
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
            __skill_issue_check_file "$file" "$choice" || return 1
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
    printf '%s\n' "$sound" >|"$__skill_issue_conf"
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
    elif [ "${line#/}" != "$line" ] && [ ! -f "$line" ]; then
        echo "Icon: $line (the file is missing, so no picture)"
    else
        echo "Icon: $line"
    fi
}

# Is there an icon with this name in the installed icon themes?
# Runs in sh, so glob options like failglob or nullglob in your shell don't get in the way.
__skill_issue_icon_exists() {
    sh -c '
        name=$1
        IFS=:
        for d in "$2" $3; do
            [ -n "$d" ] || continue
            for f in "$HOME"/.icons/*/*/*/"$name".* "$d"/icons/*/*/*/"$name".* "$d"/icons/*/*/"$name".* "$d"/pixmaps/"$name".*; do
                [ -e "$f" ] && exit 0
            done
        done
        exit 1' skill-issue "$1" "${XDG_DATA_HOME:-$HOME/.local/share}" "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
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
                __skill_issue_check_file "$file" "$choice" || return 1
                if command -v file >/dev/null 2>&1; then
                    mime=$(command file -L -b --mime-type -- "$file")
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
        printf '%s\n' "$icon" >|"$__skill_issue_iconf"
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
        local n
        n=$(sh -c "$__skill_issue_picker" skill-issue count "$file" 2>/dev/null)
        if [ "$n" = 0 ]; then
            echo "Messages: $file (no messages in it, so just SKILL ISSUE)"
        elif [ "$n" = 1 ]; then
            echo "Messages: $file (1 message)"
        else
            echo "Messages: $file ($n messages)"
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
    __skill_issue_check_file "$file" "$choice" || return 1
    if [ ! -s "$file" ]; then
        echo "skill-issue: $choice is empty. Write one message per line." >&2
        return 1
    fi
    if command -v file >/dev/null 2>&1; then
        mime=$(command file -L -b --mime-type -- "$file")
        case $mime in
            text/*) ;;
            *)
                echo "skill-issue: $choice isn't a text file. Write one message per line in a .txt file." >&2
                return 1
                ;;
        esac
        case $(command file -L -b --mime-encoding -- "$file") in
            us-ascii | utf-8) ;;
            *)
                echo "skill-issue: $choice isn't saved as UTF-8, so letters like ç or ğ would come out broken." >&2
                echo "Save it as UTF-8 (most editors have this in \"Save as\") and try again." >&2
                return 1
                ;;
        esac
    fi
    if [ "$(sh -c "$__skill_issue_picker" skill-issue count "$file" 2>/dev/null)" = 0 ]; then
        echo "skill-issue: no messages in $choice. Write one message per line." >&2
        echo "Empty lines and lines starting with # are skipped." >&2
        return 1
    fi
    mkdir -p "${__skill_issue_msgconf%/*}"
    realpath -- "$file" >|"$__skill_issue_msgconf"
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
    echo "  skill-issue today           how many SKILL ISSUEs you got today"
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
    echo "Today: $(__skill_issue_today_text)"
    __skill_issue_sound_status
    __skill_issue_icon_status
    __skill_issue_messages_status
}

skill-issue() {
    local off="${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue/off"
    case ${1:-} in
        off)
            mkdir -p "${off%/*}" && : >|"$off"
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
        today)
            __skill_issue_today_text
            if [ -e "$off" ]; then
                echo "skill-issue is off right now, so nothing is being counted."
            fi
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
            # Everything worked and there's nothing to compare with: skip reading history
            if [ -z "$__skill_issue_last_cmd" ]; then
                case "$codes $st" in *[!0\ ]*) ;; *) return $st ;; esac
            fi
            cmd=$(HISTTIMEFORMAT= builtin history 1)
            # Drop the history number in front: "  123  cmd" or "  123* cmd"
            cmd=${cmd#"${cmd%%[![:space:]]*}"}
            cmd=${cmd#"${cmd%%[![:digit:]]*}"}
            cmd=${cmd#\*}
            # History turned off (set +o history): we can't see the command, so judge by the
            # exit status alone rather than staying silent
            [ -n "$cmd" ] || cmd="?"
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
    # The array subscript sets the flag without printing anything ("-": safe with set -u).
    case ${PS0:-} in
        *__skill_issue_ran=1*) ;;
        *) PS0="${PS0:-}"'${__skill_issue_z[__skill_issue_ran=1]-}' ;;
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

    # Run first, so other prompt hooks can't change the status before we read it.
    # typeset first: with nounset, using a hook array nobody created yet is an error.
    # [@]: with ksharrays, a bare $array would only be its first element.
    typeset -ga precmd_functions preexec_functions
    precmd_functions=(__skill_issue_precmd "${(@)precmd_functions[@]:#__skill_issue_precmd}")
    preexec_functions=("${(@)preexec_functions[@]:#__skill_issue_preexec}" __skill_issue_preexec)
fi
