# Komut hata verince "skill issue" bildirimi gönderir
function __skill_issue --on-event fish_postexec
    set -l st $status
    # Boş komut, başarılı komut veya Ctrl+C (130) ise bildirme
    if test $st -eq 0 -o $st -eq 130; or test -z (string trim -- $argv[1])
        return
    end
    notify-send -a "Terminal" -i dialog-error "skill issue" "$argv[1]  (exit $st)" &; disown
end
