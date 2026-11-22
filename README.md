# skill-issue

Every time a command fails in your terminal, your computer tells you the truth:

> **SKILL ISSUE**

That's it. A desktop notification, nothing else.

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
| A check returned false | `test -f x`, `[ -d dir ]`, `diff a b` |
| You stopped it yourself | Ctrl+C |
| Pipe closed early | `yes \| head -1` |
| Leaving the shell | `exit` after a failed command |
| You handle errors yourself | `test -f x; and echo hi`, `cmd \|\| echo failed` (only crashes and missing commands count here) |

To add your own quiet commands, put this in `~/.config/fish/config.fish`:

```fish
set -g skill_issue_ignore $skill_issue_ignore mycommand
```

## Install

Requirements: [fish](https://fishshell.com) and `notify-send` (libnotify). Linux only for now.

```sh
git clone https://github.com/egehankara/skill-issue
cd skill-issue
./install.sh
```

Open a new terminal and try `ls does-not-exist`.

## Uninstall

```sh
rm ~/.config/fish/conf.d/skill-issue.fish
```

## Tests

```sh
fish tests/run.fish
```

## License

[MIT](LICENSE)
