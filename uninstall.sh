#!/usr/bin/env sh
# Removes skill-issue from fish, bash and zsh.
set -e

conf="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
rm -f "$conf/conf.d/skill-issue.fish" "$conf/completions/skill-issue.fish"

for rc in "$HOME/.bashrc" "${ZDOTDIR:-$HOME}/.zshrc"; do
    if [ -f "$rc" ] && grep -qF "# skill-issue" "$rc"; then
        sed -i '/# skill-issue$/d' "$rc"
        echo "Removed from $rc"
    fi
done

rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/skill-issue"
echo "skill-issue is uninstalled. Open a new terminal to finish."
