complete -c skill-issue -f
complete -c skill-issue -n __fish_use_subcommand -a on -d "Turn notifications on"
complete -c skill-issue -n __fish_use_subcommand -a off -d "Turn notifications off"
complete -c skill-issue -n __fish_use_subcommand -a status -d "Show whether it's on"
complete -c skill-issue -n __fish_use_subcommand -a sound -d "Pick a sound"
complete -c skill-issue -n __fish_use_subcommand -a test -d "Send a test notification"
complete -c skill-issue -n __fish_use_subcommand -a help -d "Show help"
complete -c skill-issue -n "__fish_seen_subcommand_from sound" -F
complete -c skill-issue -n "__fish_seen_subcommand_from sound" -a system -d "Your system's error sound"
complete -c skill-issue -n "__fish_seen_subcommand_from sound" -a off -d "No sound"
complete -c skill-issue -n __fish_use_subcommand -a icon -d "Pick an icon"
complete -c skill-issue -n "__fish_seen_subcommand_from icon" -F
complete -c skill-issue -n "__fish_seen_subcommand_from icon" -a default -d "The red error icon"
complete -c skill-issue -n "__fish_seen_subcommand_from icon" -a none -d "No icon"
complete -c skill-issue -n __fish_use_subcommand -a messages -d "Show random messages from a file"
complete -c skill-issue -n "__fish_seen_subcommand_from messages" -F
complete -c skill-issue -n "__fish_seen_subcommand_from messages" -a off -d "No messages"
