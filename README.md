# skill-issue

A **SKILL ISSUE** desktop notification every time a command fails. Works in fish, bash and zsh on Linux.

Out of the box it's just the title. Make it yours with your own sound, picture and messages.

## Install

```fish
fisher install egehankara/skill-issue
```

Or with the installer (fish, bash or zsh):

```sh
git clone https://github.com/egehankara/skill-issue ~/.local/share/skill-issue
~/.local/share/skill-issue/install.sh            # your login shell
~/.local/share/skill-issue/install.sh bash zsh   # or pick shells
```

Needs `notify-send` (package `libnotify`; `libnotify-bin` on Debian/Ubuntu, `libnotify-tools` on openSUSE) and a notification daemon. Desktops like GNOME and KDE have one; on Hyprland, Sway or i3 install `mako`, `dunst` or `swaync`.

## Customize

```sh
skill-issue sound ~/sounds/bruh.mp3    # or: system, off
skill-issue icon ~/pictures/clown.png  # or: an icon name, none, default
skill-issue messages ~/roasts.txt      # or: off
```

- **Sound:** none by default. Any wav, ogg, mp3, flac or opus file, or your desktop's error sound.
- **Icon:** the red error icon by default. Any picture, or an icon from your theme.
- **Messages:** none by default. A text file with one message per line; a random one shows under the title. Every message shows once before any repeats, never the same twice in a row.

Each setting is checked before it's saved, previewed right away, and shared by all your shells. Run `skill-issue` to see your settings and all commands.

## When it fires

Typos, missing files, forgotten sudo, failed builds and tests, git errors, crashes, and any other failing command.

It stays quiet when a failure is normal: `grep` finding nothing, `test` or `diff` returning false, Ctrl+C, `exit`, or commands you handle yourself with `&&` / `||`. Add your own quiet commands:

```sh
set -g skill_issue_ignore $skill_issue_ignore mycommand       # fish, in config.fish
SKILL_ISSUE_IGNORE="grep rg diff test [ [[ false mycommand"   # bash/zsh, before the source line
```

`skill-issue off` turns it off in every shell, `skill-issue on` brings it back. `skill-issue today` tells you how many SKILL ISSUEs you got today.

## Uninstall

```sh
fisher remove egehankara/skill-issue      # Fisher
~/.local/share/skill-issue/uninstall.sh   # installer
```

## License

[MIT](LICENSE)
