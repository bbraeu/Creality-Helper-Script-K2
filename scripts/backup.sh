#!/bin/sh
# backup.sh - Backup and restore Klipper configuration for K2
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

BACKUP_DIR=/mnt/UDISK/helper-script/backups

PRINTER_DATA=/mnt/UDISK/printer_data

# backup_archive <prefix> <folder in printer_data> <label>
backup_archive() {
    printf "Backup %s? [y/n]: " "$3"
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    echo ""
    log_info "Backing up $3..."
    mkdir -p "$BACKUP_DIR"

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/${1}_${TIMESTAMP}.tar.gz"

    if tar -czf "$BACKUP_FILE" -C "$PRINTER_DATA" "$2/"; then
        echo ""
        log_success "Backup saved to: $BACKUP_FILE"
        SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
        log_info "Backup size: $SIZE"
        echo ""

        # Keep only last 5 backups of this kind
        ls -t "$BACKUP_DIR"/${1}_*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
        log_info "Keeping last 5 backups. Older backups removed."
    else
        log_error "Backup failed."
    fi
    echo ""
}

# restore_archive <prefix> <label>; sets RESTORED_FILE on success
restore_archive() {
    RESTORED_FILE=""
    echo ""
    log_info "Available $2 backups:"
    echo ""

    if [ -z "$(ls "$BACKUP_DIR"/${1}_*.tar.gz 2>/dev/null)" ]; then
        log_warn "No $2 backups found in $BACKUP_DIR"
        return 1
    fi

    i=1
    for f in $(ls -t "$BACKUP_DIR"/${1}_*.tar.gz 2>/dev/null); do
        SIZE=$(du -sh "$f" | cut -f1)
        DATE=$(basename "$f" .tar.gz | sed "s/^${1}_//" | sed 's/_/ /')
        echo "  $i) $DATE  [$SIZE]"
        eval "BACKUP_$i=$f"
        i=$((i+1))
    done

    echo "  0) Cancel"
    echo ""
    printf "  Select backup to restore: "
    read choice

    if [ "$choice" = "0" ] || [ -z "$choice" ]; then
        log_info "Cancelled."
        return 1
    fi

    eval "SELECTED=\$BACKUP_$choice"
    if [ -z "$SELECTED" ]; then
        log_error "Invalid selection."
        return 1
    fi

    echo ""
    echo -e "${YELLOW}WARNING: This will overwrite your current $2.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled."
        return 1
    fi
    RESTORED_FILE=$SELECTED
}

restore_config() {
    restore_archive klipper_config "Klipper configuration" || return 0
    log_info "Restoring from: $(basename "$RESTORED_FILE")..."
    if tar -xzf "$RESTORED_FILE" -C "$PRINTER_DATA/"; then
        log_success "Config restored successfully."
        restart_klipper force
    else
        log_error "Restore failed."
    fi
    echo ""
}

# Moonraker database: print history, job queue, UI settings, webcams, ...
restore_database() {
    restore_archive moonraker_database "Moonraker database" || return 0
    log_info "Stopping Moonraker..."
    for pid in $(ps aux | grep moonraker.py | grep -v grep | awk '{print $1}'); do
        kill "$pid" 2>/dev/null
    done
    sleep 2
    rm -rf "$PRINTER_DATA/database"
    if tar -xzf "$RESTORED_FILE" -C "$PRINTER_DATA/"; then
        log_success "Moonraker database restored."
    else
        log_error "Restore failed."
    fi
    restart_moonraker force
    echo ""
}

case "$1" in
    backup)           backup_archive klipper_config config "Klipper configuration" ;;
    restore)          restore_config ;;
    backup_database)  backup_archive moonraker_database database "Moonraker database" ;;
    restore_database) restore_database ;;
    *)                echo "Usage: $0 [backup|restore|backup_database|restore_database]" ;;
esac
