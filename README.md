# skill-issue

Every time a command fails in your terminal, your computer tells you the truth:

> **SKILL ISSUE**

A desktop notification for every failed command, in fish, bash and zsh. Out of the box it's just those two words. **Then you make it yours:** your own sound, your own picture, your own roasts.

```
  Out of the box                      Made yours
┌──────────────────────────┐        ┌───────────────────────────────────┐
│ (x)  SKILL ISSUE         │        │ [your pic]  SKILL ISSUE           │
│                          │        │             bro thought it would  │
│                          │        │             work                  │
└──────────────────────────┘        └───────────────────────────────────┘
                                       ♪ your sound plays
```

## Make it yours

Everything is optional and off until you turn it on. Three commands:

```sh
skill-issue sound ~/sounds/sad-trombone.mp3   # play your sound
skill-issue icon ~/pictures/clown.png         # show your picture
skill-issue messages ~/roasts.txt             # show a random roast from your file
```

| What | Default | Make it yours with | Take it back with |
|---|---|---|---|
| 🔊 **Sound** | none | `skill-issue sound FILE` or `skill-issue sound system` | `skill-issue sound off` |
| 🖼️ **Icon** | red error icon | `skill-issue icon FILE` or `skill-issue icon NAME` | `skill-issue icon default` or `skill-issue icon none` |
| 💬 **Messages** | none, just the title | `skill-issue messages FILE` | `skill-issue messages off` |
| 🤫 **Quiet commands** | grep, test, diff... | add your own to the ignore list | remove them from the list |
| ⏸️ **On / off** | on | `skill-issue off` | `skill-issue on` |

- **It checks before it saves.** A sound that won't play, a file that isn't a picture, a text file with no messages: refused, and your old setting stays.
- **It shows you right away.** Setting a sound plays it once, setting an icon or messages sends a notification.
- **One setup for every shell.** Your settings are shared by fish, bash and zsh. Change them in one, the others follow.

Run `skill-issue` to see your current settings and every command.

### 🔊 Sound

```sh
skill-issue sound ~/sounds/bruh.mp3   # your own file
skill-issue sound system              # your desktop's error sound
skill-issue sound off                 # silence again (default)
skill-issue sound                     # show the current sound
```

- **Your own file:** wav, ogg, mp3, flac and opus work everywhere. Other formats (m4a...) need `mpv` or `ffmpeg`. It's played with whatever you have: `pw-play` (PipeWire), `paplay` (PulseAudio), `mpv`, `ffplay`, or `aplay` (plain ALSA, wav only).
- **System sound:** your desktop's sound theme through libcanberra if it's installed. Without it, it looks for the error sound in your installed sound themes (freedesktop, KDE's Ocean...).

### 🖼️ Icon

```sh
skill-issue icon ~/pictures/clown.png   # a picture of yours (png, jpg, svg, webp...)
skill-issue icon face-sad               # an icon from your icon theme
skill-issue icon none                   # no icon
skill-issue icon default                # the red error icon again (default)
skill-issue icon                        # show the current icon
```

How big the icon is and where it shows up is up to your notification daemon. GNOME, KDE, mako and dunst all show it, unless you turned icons off in their settings.

### 💬 Messages

Write your roasts in a text file, one per line:

```text
# lines starting with # are skipped, so are empty lines
git gud
bro thought it would work
have you tried being better
```

```sh
skill-issue messages ~/roasts.txt   # use this file
skill-issue messages off            # just SKILL ISSUE again (default)
skill-issue messages                # show the current file and how many messages it has
```

Every failure shows a random line under **SKILL ISSUE**. It's **shuffle-bag random**: every message shows up once before any of them repeats, and you never get the same one twice in a row, even across fish, bash and zsh. Edit the file whenever you like: the next notification starts a new round with your changes.

### 🤫 Quiet commands

Some commands fail on purpose, like `grep` finding nothing. Those never get a SKILL ISSUE ([full list below](#when-it-stays-quiet)). Add your own:

```fish
# fish: in ~/.config/fish/config.fish
set -g skill_issue_ignore $skill_issue_ignore mycommand
```

```sh
# bash / zsh: in ~/.bashrc or ~/.zshrc, before the source line
SKILL_ISSUE_IGNORE="grep rg diff test [ [[ false mycommand"
```

### ⏸️ On / off

```sh
skill-issue off      # no more notifications, in every shell, until you turn it back on
skill-issue on
skill-issue status   # show your settings
skill-issue test     # send a test notification
```

Handy when you're sharing your screen.

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

The installer sends a test notification. If it can't, it tells you what's missing. Then open a new terminal, try `ls does-not-exist`, and [make it yours](#make-it-yours).

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
| Anything on your own quiet list | see "Quiet commands" under [Make it yours](#make-it-yours) |

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

The installer's uninstall also removes the on/off state. Your sound, icon and messages settings stay in `~/.config/skill-issue/` in case you come back; delete that folder to remove them too.

## Tests

```sh
fish tests/run.fish
bash tests/run.sh
zsh tests/run.sh
```

## License

[MIT](LICENSE)
