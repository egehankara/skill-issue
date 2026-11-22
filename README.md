# skill-issue

Every time a command fails in your terminal, your computer tells you the truth:

> **skill issue**

A desktop notification pops up with the failed command and its exit code.

## Install

Requirements: `fish` shell and `notify-send` (libnotify). Linux only for now.

```sh
git clone https://github.com/egehankara/skill-issue
cd skill-issue
./install.sh
```

Open a new terminal and try `ls does-not-exist`.

Commands you cancel with Ctrl+C don't count. That one's on purpose.

## Uninstall

```sh
rm ~/.config/fish/conf.d/skill-issue.fish
```

## License

MIT
