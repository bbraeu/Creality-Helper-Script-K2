#!/bin/sh
# mobileraker.sh - Install/remove Mobileraker Companion on K2
# Push notifications for the Mobileraker app (https://github.com/Clon1998/mobileraker_companion).
# The upstream installer only knows the K1 (buildroot) and Sonic Pad, so it is
# installed by hand here: Entware python3 + pillow, a virtualenv and a procd service.
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

REPO_URL=https://github.com/Clon1998/mobileraker_companion.git
REPO_DIR=/mnt/UDISK/mobileraker_companion
VENV=/mnt/UDISK/mobileraker-env
MR_CONF=$CONFIG_DIR/mobileraker.conf
SERVICE=mobileraker

install_mobileraker() {
    if is_installed "mobileraker_companion"; then
        log_info "Mobileraker Companion is already installed."
        printf "  Update / repair it? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0
    else
        echo ""
        echo "======================================================"
        echo "  Mobileraker Companion"
        echo "======================================================"
        echo ""
        echo "  Push notifications (print progress, finish, errors)"
        echo "  for the Mobileraker app, even when the app is closed."
        echo ""
        echo "  For the camera in the app, install Camera Support"
        echo "  and answer 'y' to the MJPEG camera question."
        echo ""
        printf "  Continue? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    fi

    require_entware || return 1
    # No armv7 wheel for Pillow: take it from Entware and share it with the venv
    opkg_install git git-http python3 python3-pip python3-pillow || { log_error "Package install failed."; return 1; }
    /opt/bin/pip3 install -q --no-cache-dir virtualenv || { log_error "virtualenv install failed."; return 1; }

    if [ -d "$REPO_DIR/.git" ]; then
        log_info "Updating Mobileraker Companion..."
        git -C "$REPO_DIR" pull -q --ff-only
    else
        rm -rf "$REPO_DIR"
        log_info "Cloning $REPO_URL..."
        git clone -q --depth 1 "$REPO_URL" "$REPO_DIR" || { log_error "Clone failed."; return 1; }
    fi

    if [ ! -x "$VENV/bin/python3" ]; then
        log_info "Creating Python environment..."
        /opt/bin/virtualenv -q -p /opt/bin/python3 --system-site-packages "$VENV" || { log_error "virtualenv failed."; return 1; }
    fi
    log_info "Installing Python requirements (can take a few minutes)..."
    mkdir -p "$VENV/cache"
    if ! TMPDIR="$VENV/cache" "$VENV/bin/pip3" install -q --no-cache-dir -r "$REPO_DIR/scripts/mobileraker-requirements.txt"; then
        log_error "Installing requirements failed."
        return 1
    fi
    rm -rf "$VENV/cache"

    write_mobileraker_conf

    SERVICE_ENV="PYTHONPATH=$REPO_DIR" install_service "$SERVICE" "$VENV/bin/python3" "$REPO_DIR/mobileraker.py" -l "$LOGS_DIR" -c "$MR_CONF"

    # No [update_manager mobileraker]: Moonraker's update manager cannot load on
    # the K2's stock Moonraker (see install_moonraker_include in system.sh).
    # Update the companion by selecting this menu entry again.

    mark_installed "mobileraker_companion"
    echo ""
    log_success "Mobileraker Companion installed!"
    echo ""
    log_info "Open the Mobileraker app and connect to this printer by IP address."
    log_info "Config: $MR_CONF  |  Log: $LOGS_DIR/mobileraker.log"
    echo ""
}

write_mobileraker_conf() {
    if [ -f "$MR_CONF" ]; then
        log_info "Keeping existing $MR_CONF"
        return 0
    fi
    local tz
    tz=$(uci -q get 'system.@system[0].zonename' 2>/dev/null)
    if [ -z "$tz" ]; then
        printf "  Your timezone (e.g. Europe/Berlin) [Etc/UTC]: "
        read tz
        [ -z "$tz" ] && tz=Etc/UTC
    fi
    cat > "$MR_CONF" << EOF
# Mobileraker Companion - https://github.com/Clon1998/mobileraker_companion
# Managed by Creality Helper Script

[general]
timezone: $tz
include_snapshot: True

[printer K2]
moonraker_uri: ws://127.0.0.1:7125/websocket
moonraker_api_key: False
# Fallback when no snapshot webcam is chosen in the app (needs Camera Support)
snapshot_uri: http://127.0.0.1:1984/api/frame.jpeg?src=k2plus
EOF
    log_success "Created $MR_CONF (timezone: $tz)"
}

remove_mobileraker() {
    if ! is_installed "mobileraker_companion" && [ ! -d "$REPO_DIR" ]; then
        log_info "Mobileraker Companion is not installed."
        return 0
    fi
    echo -e "${YELLOW}WARNING: This will remove Mobileraker Companion.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    remove_service "$SERVICE"
    remove_moonraker_section "update_manager mobileraker"
    rm -rf "$REPO_DIR" "$VENV"
    rm -f "$MR_CONF"
    restart_moonraker force
    mark_removed "mobileraker_companion"
    log_success "Mobileraker Companion removed."
}

case "$1" in
    install) install_mobileraker ;;
    remove)  remove_mobileraker ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
