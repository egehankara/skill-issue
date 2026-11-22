#!/usr/bin/env sh
# Installs skill-issue.
#   ./install.sh                 for your login shell
#   ./install.sh fish bash zsh   for the shells you name
set -e

dir="$(cd "$(dirname "$0")" && pwd)"
shells="$*"
[ -n "$shells" ] || shells="$(basename "${SHELL:-}")"
if [ -z "$shells" ]; then
    echo "Couldn't tell which shell you use. Name it: ./install.sh fish   (or bash, zsh)"
    exit 1
fi

command -v notify-send >/dev/null || {
    echo "notify-send not found. Install it first:"
    echo "  Arch / Fedora:   libnotify"
    echo "  Debian / Ubuntu: libnotify-bin"
    echo "  openSUSE:        libnotify-tools"
    exit 1
}

# Adds the source line to an rc file, once
add_source() {
    rc="$1"
    line="source \"$dir/skill-issue.sh\" # skill-issue"
    touch "$rc"
    if grep -qF "# skill-issue" "$rc"; then
        echo "$2: already in $rc"
    else
        # Start on a new line if the file doesn't end with one
        if [ -s "$rc" ] && [ -n "$(tail -c 1 "$rc")" ]; then
            echo >>"$rc"
        fi
        printf '%s\n' "$line" >>"$rc"
        echo "$2: added to the end of $rc"
    fi
}

for shell in $shells; do
    case "$shell" in
        fish)
            command -v fish >/dev/null || { echo "fish not found"; exit 1; }
            conf="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
            mkdir -p "$conf/conf.d" "$conf/completions"
            ln -sf "$dir/conf.d/skill-issue.fish" "$conf/conf.d/skill-issue.fish"
            ln -sf "$dir/completions/skill-issue.fish" "$conf/completions/skill-issue.fish"
            echo "fish: installed into $conf"
            ;;
        bash)
            add_source "$HOME/.bashrc" bash
            ;;
        zsh)
            add_source "${ZDOTDIR:-$HOME}/.zshrc" zsh
            ;;
        *)
            echo "Unsupported shell: '$shell'. Supported: fish, bash, zsh"
            echo "Pick one: ./install.sh fish"
            exit 1
            ;;
    esac
done

# Send a test notification to make sure they can actually show up
if notify-send -a skill-issue -i dialog-error "SKILL ISSUE" "skill-issue is installed" 2>/dev/null; then
    echo
    echo "You should see a test notification now."
    echo "Open a new terminal and run a failing command, like: ls does-not-exist"
else
    echo
    echo "Warning: couldn't show a notification. No notification daemon is running."
    echo "GNOME, KDE, XFCE and most desktops have one built in. On a tiling window"
    echo "manager (Hyprland, Sway, i3...) install one, for example mako, dunst or swaync."
fi
