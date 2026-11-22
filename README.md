# skill-issue

Every time a command fails in your terminal, your computer tells you the truth:

> **SKILL ISSUE**

That's it. A desktop notification, nothing else. Works in fish, bash and zsh.

## Install

### fish, with [Fisher](https://github.com/jorgebucaran/fisher)

```fish
fisher install egehankara/skill-issue
```

### fish, bash or zsh, with the installer

```sh
git clone https://github.com/egehankara/skill-issue ~/.local/share/skill-issue
~/.local/share/skill-issue/install.sh
```

This installs it for your login shell. To pick shells yourself: `./install.sh fish bash zsh`.

For bash and zsh, the installer adds one line to the end of `~/.bashrc` or `~/.zshrc`. If you'd rather do it yourself, add this line **at the end** of the file, after prompt tools like starship or oh-my-zsh:

```sh
source ~/.local/share/skill-issue/skill-issue.sh
```

The installer sends a test notification. If it can't, it tells you what's missing. Then open a new terminal and try `ls does-not-exist`.

## Turning it off

```sh
skill-issue off      # no more notifications, in every shell, until you turn it back on
skill-issue on
skill-issue status
skill-issue test     # send a test notification
```

Handy when you're sharing your screen.

## When you get a SKILL ISSUE

| Situation | Example |
|---|---|
| Typo / command doesn't exist | `gti status`, `sl`, `cd..`, `:wq` |
| File or folder doesn't exist | `cat missing.txt`, `cd nowhere`, `ls /nope` |
| Script isn't executable | `./script.sh` without `chmod +x` |
| Forgot sudo | `pacman -Syu`, `mount /dev/sdb1 /mnt` |
| Forgot sudo, then fixed it | `pacman -S vim` fails, `sudo pacman -S vim` works: still a skill issue |
| Build or tests failed | `cargo build`, `make`, `npm test` |
| Git said no | `git push` rejected, merge conflict, nothing to commit |
| Program crashed | segfault, abort, killed by the OOM killer |
| One part of a pipeline failed | `cat missing.txt \| wc -l` |
| Any other failing command | exit code other than 0 |

## When it stays quiet

Some commands "fail" on purpose. These don't count:

| Situation | Example |
|---|---|
| Search found nothing | `grep`, `rg`, `pgrep` with no matches |
| A check returned false | `test -f x`, `[ -d dir ]`, `[[ -n $x ]]`, `diff a b` |
| You stopped it yourself | Ctrl+C |
| Pipe closed early | `yes \| head -1` |
| Leaving the shell | `exit` after a failed command |
| You handle errors yourself | `test -f x && echo hi`, `cmd \|\| echo failed` (only crashes and missing commands count here) |
| You just pressed Enter | an empty line |

To add your own quiet commands:

```fish
# fish: in ~/.config/fish/config.fish
set -g skill_issue_ignore $skill_issue_ignore mycommand
```

```sh
# bash / zsh: in ~/.bashrc or ~/.zshrc, before the source line
SKILL_ISSUE_IGNORE="grep rg diff test [ [[ false mycommand"
```

## Requirements

- **Linux.** macOS and Windows/WSL aren't supported yet.
- **fish, bash 4.4+ or zsh.** Any terminal works (Kitty, Alacritty, Ghostty, Konsole, GNOME Terminal, VS Code, tmux...).
- **notify-send**: package `libnotify` on Arch and Fedora, `libnotify-bin` on Debian and Ubuntu. Usually already installed.
- **A notification daemon.** GNOME, KDE Plasma, XFCE, Cinnamon, MATE and most other desktops have one built in. On a tiling window manager (Hyprland, Sway, i3, bspwm...) you need to install one, for example `mako`, `dunst` or `swaync`.

Over SSH or in a TTY there's no screen to show the notification on, so it stays quiet. Same if notify-send or the daemon is missing: no error spam in your terminal.

Flatpak terminals and distrobox/toolbox containers need notify-send available inside the sandbox or container.

**bash only:** bash reads the command from your history. A command you start with a space (with `HISTCONTROL=ignorespace`, the Ubuntu default) isn't saved there, so it can be judged as the command before it.

## Uninstall

```fish
fisher remove egehankara/skill-issue    # if you used Fisher
```

```sh
~/.local/share/skill-issue/uninstall.sh  # if you used the installer
```

## Tests

```sh
fish tests/run.fish
bash tests/run.sh
zsh tests/run.sh
```

## License

[MIT](LICENSE)
