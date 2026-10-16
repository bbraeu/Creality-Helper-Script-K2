#!/bin/sh
# shell_command.sh - Install/remove Klipper Gcode Shell Command for K2
# Adds [gcode_shell_command] / RUN_SHELL_COMMAND (Arksine, GPLv3), used by
# Git Backup macros and handy for your own macros.
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

KLIPPER_EXTRAS=/usr/share/klipper/klippy/extras
SRC=$SCRIPT_DIR/files/klipper/gcode_shell_command.py
DST=$KLIPPER_EXTRAS/gcode_shell_command.py

install_shell_command() {
    if is_installed "gcode_shell_command"; then
        log_info "Klipper Gcode Shell Command is already installed."
        return 0
    fi
    echo ""
    if [ -f "$DST" ] && ! cmp -s "$SRC" "$DST"; then
        log_info "This firmware already ships gcode_shell_command.py - keeping the stock file."
    else
        ensure_shell_command
        restart_klipper force
    fi
    mark_installed "gcode_shell_command"
    echo ""
    log_success "Klipper Gcode Shell Command installed!"
    echo ""
    echo "  Example:"
    echo "    [gcode_shell_command hello]"
    echo "    command: echo Hello from the K2"
    echo "    timeout: 5."
    echo ""
    echo "    [gcode_macro HELLO]"
    echo "    gcode: RUN_SHELL_COMMAND CMD=hello"
    echo ""
}

# Copy the extra into Klipper if missing (a firmware update replaces
# /usr/share/klipper). Returns 2 when the file was (re)installed.
ensure_shell_command() {
    [ -f "$DST" ] && return 0
    cp "$SRC" "$DST" && chmod 644 "$DST"
    log_success "Installed $DST"
    return 2
}

remove_shell_command() {
    if ! is_installed "gcode_shell_command"; then
        log_info "Klipper Gcode Shell Command is not installed."
        return 0
    fi
    if grep -qs "^\[gcode_shell_command" $(cfg_loaded_files); then
        log_warn "These configs still use [gcode_shell_command] and would stop Klipper from starting:"
        grep -ls "^\[gcode_shell_command" $(cfg_loaded_files) | sed 's/^/    /'
        log_warn "Remove those features (e.g. Git Backup) first."
        return 1
    fi
    echo -e "${YELLOW}WARNING: This will remove Klipper Gcode Shell Command.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    # Only delete our copy, never a file the firmware shipped
    if cmp -s "$SRC" "$DST"; then
        rm -f "$DST" "${DST}c"
        restart_klipper force
    fi
    mark_removed "gcode_shell_command"
    log_success "Klipper Gcode Shell Command removed."
}

case "$1" in
    install) install_shell_command ;;
    remove)  remove_shell_command ;;
    ensure)  ensure_shell_command ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
