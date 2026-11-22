#!/usr/bin/env sh
# Installs the skill-issue hook for fish
set -e
command -v fish >/dev/null || { echo "fish not found"; exit 1; }
command -v notify-send >/dev/null || { echo "notify-send not found (install libnotify)"; exit 1; }
dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.config/fish/conf.d"
ln -sf "$dir/skill-issue.fish" "$HOME/.config/fish/conf.d/skill-issue.fish"
echo "Installed. Open a new fish shell and run a failing command to test."
