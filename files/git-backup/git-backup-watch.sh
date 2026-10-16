#!/bin/sh
# git-backup-watch.sh - Commit and push the Klipper config folder on every change
# Based on the idea of gitwatch (https://github.com/gitwatch/gitwatch) as used by
# Guilouz's K1 helper script. Run by the procd service /etc/init.d/git-backup.
#
#   git-backup-watch.sh        watch forever
#   git-backup-watch.sh now    commit + push once and exit

CONFIG_DIR=/mnt/UDISK/printer_data/config
export PATH=/opt/bin:/opt/sbin:$PATH

backup() {
    cd "$CONFIG_DIR" || return 1
    [ -n "$(git status --porcelain)" ] || return 0
    git add -A
    git commit -q -m "Auto-commit by Git Backup ($(date '+%Y-%m-%d %H:%M:%S'))"
    # A failed push (offline) is retried with the next change
    git push -q origin HEAD
}

if [ "$1" = "now" ]; then
    backup
    exit $?
fi

backup
while true; do
    inotifywait -qq -r -e close_write,move,delete,create --exclude '/\.git(/|$)' "$CONFIG_DIR"
    # Let bursts of writes (SAVE_CONFIG, uploads) settle into one commit
    sleep 10
    backup
done
