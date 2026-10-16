#!/bin/sh
# octoeverywhere.sh - Install/remove OctoEverywhere on K2
# The upstream installer detects the K2 itself (OpenWrt "tina" + /usr/bin/webrtc)
# and installs its dependencies with Entware into /mnt/UDISK.
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

TITLE="OctoEverywhere"
BLURB="Free remote access, webcam, AI failure detection and notifications."
FEATURE=octoeverywhere
REPO_URL=https://github.com/QuinnDamerell/OctoPrint-OctoEverywhere.git
INSTALL_DIR=/mnt/UDISK/octoeverywhere

install_plugin() {
    if [ -d "$INSTALL_DIR" ]; then
        log_info "$TITLE is already installed. Running its installer again to update / repair..."
    else
        echo ""
        echo "======================================================"
        echo "  $TITLE"
        echo "======================================================"
        echo ""
        echo "  $BLURB"
        echo ""
        printf "  Continue? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    fi

    require_entware || return 1
    opkg_install git git-http bash || { log_error "Package install failed."; return 1; }

    if [ ! -d "$INSTALL_DIR/.git" ]; then
        rm -rf "$INSTALL_DIR"
        log_info "Cloning $REPO_URL..."
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" || { log_error "Clone failed."; return 1; }
    fi

    if (cd "$INSTALL_DIR" && bash ./install.sh); then
        mark_installed "$FEATURE"
        log_success "$TITLE installed. Follow the link printed above to connect your account."
    else
        log_error "$TITLE installer failed - see the output above."
    fi
}

remove_plugin() {
    if [ ! -d "$INSTALL_DIR" ] && ! is_installed "$FEATURE"; then
        log_info "$TITLE is not installed."
        return 0
    fi
    echo -e "${YELLOW}WARNING: This will remove $TITLE.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    export PATH=/opt/bin:/opt/sbin:$PATH
    [ -f "$INSTALL_DIR/uninstall.sh" ] && (cd "$INSTALL_DIR" && bash ./uninstall.sh)
    rm -rf "$INSTALL_DIR"
    mark_removed "$FEATURE"
    log_success "$TITLE removed."
}

case "$1" in
    install) install_plugin ;;
    remove)  remove_plugin ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
