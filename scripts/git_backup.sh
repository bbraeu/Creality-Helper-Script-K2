#!/bin/sh
# git_backup.sh - Back up the Klipper config folder to a GitHub repository
# Every change in printer_data/config is committed and pushed by a procd
# service (files/git-backup/git-backup-watch.sh). Requires Entware.
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

WATCHER=$SCRIPT_DIR/files/git-backup/git-backup-watch.sh
CREDENTIALS=$SCRIPT_DIR/.git-credentials
GIT_BACKUP_CFG=$CONFIG_DIR/git_backup.cfg
SERVICE=git-backup

prompt() {
    # prompt <variable> <text>: re-ask until non-empty
    local value=""
    while [ -z "$value" ]; do
        printf "  %s: " "$2"
        read value
    done
    eval "$1=\$value"
}

install_git_backup() {
    if is_installed "git_backup"; then
        manage_git_backup
        return 0
    fi

    echo ""
    echo "======================================================"
    echo "  Git Backup"
    echo "======================================================"
    echo ""
    echo "  Pushes every change in printer_data/config to GitHub."
    echo ""
    echo "  You need:"
    echo "    - an EMPTY private GitHub repository (no README)"
    echo "    - a personal access token with 'repo' scope"
    echo "      (github.com/settings/tokens)"
    echo ""
    printf "  Continue? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }

    require_entware || return 1
    opkg_install git git-http inotifywait || { log_error "Package install failed."; return 1; }

    if [ -d "$CONFIG_DIR/.git" ]; then
        log_error "$CONFIG_DIR is already a git repository. Remove $CONFIG_DIR/.git first."
        return 1
    fi

    echo ""
    prompt GH_USER "GitHub username"
    prompt GH_MAIL "GitHub email address"
    prompt GH_REPO "Repository name"
    printf "  Branch [main]: "
    read GH_BRANCH
    [ -z "$GH_BRANCH" ] && GH_BRANCH=main
    stty -echo 2>/dev/null
    prompt GH_TOKEN "Personal access token (hidden)"
    stty echo 2>/dev/null
    echo ""

    # The token lives outside the config folder (which the web UIs serve),
    # readable by root only
    umask 077
    echo "https://$GH_USER:$GH_TOKEN@github.com" > "$CREDENTIALS"
    umask 022

    cd "$CONFIG_DIR" || return 1
    cat > .gitignore << 'EOF'
# Managed by Creality Helper Script (Git Backup)
backups/
*.tar.gz
*.bkp
.moonraker.conf.bkp
*.pyc
__pycache__/
EOF
    git init -q
    git config user.name "$GH_USER"
    git config user.email "$GH_MAIL"
    git config credential.helper "store --file=$CREDENTIALS"
    git remote add origin "https://github.com/$GH_USER/$GH_REPO.git"
    git checkout -q -b "$GH_BRANCH"
    git add -A
    git commit -q -m "Initial Backup"

    log_info "Pushing initial backup..."
    if ! out=$(git push -u origin "$GH_BRANCH" 2>&1); then
        echo "$out" | sed 's/^/    /'
        case "$out" in
            *"Repository not found"*)   log_error "Repository not found - check username / repository name / token scope." ;;
            *"Authentication failed"*)  log_error "Authentication failed - check the access token." ;;
            *GH007*)                    log_error "GitHub blocks pushes that publish a private email - use your noreply address." ;;
            *"fetch first"*|*rejected*) log_error "The repository is not empty - use a new empty repository." ;;
            *)                          log_error "Push failed." ;;
        esac
        rm -rf "$CONFIG_DIR/.git" "$CONFIG_DIR/.gitignore" "$CREDENTIALS"
        return 1
    fi

    install_service "$SERVICE" /bin/sh "$WATCHER"
    write_git_backup_macros
    mark_installed "git_backup"
    echo ""
    log_success "Git Backup installed - backing up to github.com/$GH_USER/$GH_REPO ($GH_BRANCH)"
    echo ""
}

# Macros need Gcode Shell Command; skipped (with a hint) without it
write_git_backup_macros() {
    if ! is_installed "gcode_shell_command"; then
        log_info "Install 'Klipper Gcode Shell Command' and reinstall Git Backup to get GIT_BACKUP_* macros."
        return 0
    fi
    cat > "$GIT_BACKUP_CFG" << EOF
# Git Backup macros - Managed by Creality Helper Script

[gcode_shell_command git_backup_now]
command: sh $WATCHER now
timeout: 120.
verbose: True

[gcode_shell_command git_backup_stop]
command: /etc/init.d/$SERVICE stop
timeout: 10.
verbose: True

[gcode_shell_command git_backup_start]
command: /etc/init.d/$SERVICE start
timeout: 10.
verbose: True

[gcode_macro GIT_BACKUP_NOW]
description: Commit and push the config folder to GitHub now
gcode:
  RUN_SHELL_COMMAND CMD=git_backup_now

[gcode_macro GIT_BACKUP_PAUSE]
description: Stop automatic backups until GIT_BACKUP_RESUME or the next reboot
gcode:
  RUN_SHELL_COMMAND CMD=git_backup_stop

[gcode_macro GIT_BACKUP_RESUME]
description: Resume automatic backups
gcode:
  RUN_SHELL_COMMAND CMD=git_backup_start
EOF
    add_include_to_printer_cfg "git_backup.cfg"
    restart_klipper force
}

manage_git_backup() {
    echo ""
    log_info "Git Backup is installed."
    echo ""
    echo "  1) Back up now"
    echo "  2) Pause automatic backups (until reboot)"
    echo "  3) Resume automatic backups"
    echo "  0) Back"
    echo ""
    printf "  Enter choice: "
    read choice
    case "$choice" in
        1) export PATH=/opt/bin:/opt/sbin:$PATH; sh "$WATCHER" now && log_success "Backed up." ;;
        2) /etc/init.d/$SERVICE stop && log_success "Paused." ;;
        3) /etc/init.d/$SERVICE start && log_success "Resumed." ;;
    esac
}

remove_git_backup() {
    if ! is_installed "git_backup"; then
        log_info "Git Backup is not installed."
        return 0
    fi
    echo -e "${YELLOW}WARNING: This will stop Git Backup. Your GitHub repository is not touched.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    remove_service "$SERVICE"
    if [ -f "$GIT_BACKUP_CFG" ]; then
        remove_include_from_printer_cfg "git_backup.cfg"
        rm -f "$GIT_BACKUP_CFG"
        restart_klipper force
    fi
    printf "Also delete the local git history (%s/.git)? [y/n]: " "$CONFIG_DIR"
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm -rf "$CONFIG_DIR/.git" "$CONFIG_DIR/.gitignore"
    fi
    rm -f "$CREDENTIALS"
    mark_removed "git_backup"
    log_success "Git Backup removed."
}

case "$1" in
    install) install_git_backup ;;
    remove)  remove_git_backup ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
