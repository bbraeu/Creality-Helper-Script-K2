#!/bin/sh
# Creality K2 Helper Script (K2 / K2 Pro / K2 Plus - hardware is detected at runtime)
# https://bbraeu.github.io/Creality-Helper-Script-Wiki-K2-Base

SCRIPT_DIR=/mnt/UDISK/helper-script
SCRIPTS_DIR=$SCRIPT_DIR/scripts
FILES_DIR=$SCRIPT_DIR/files
PRINTER_DATA=/mnt/UDISK/printer_data
CONFIG_DIR=$PRINTER_DATA/config
LOGS_DIR=$PRINTER_DATA/logs

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BLUE='\033[1;34m'
NC='\033[0m'

print_header() {
    clear
    echo ""
    echo -e "${WHITE}======================================================${NC}"
    echo -e "${WHITE}   Creality K2 Helper Script${NC}"
    echo -e "${WHITE}======================================================${NC}"
    echo -e "${YELLOW}   https://bbraeu.github.io/Creality-Helper-Script-Wiki-K2-Base${NC}"
    echo -e "${WHITE}======================================================${NC}"
    echo -e "   Detected: ${CYAN}$(printer_summary)${NC}"
    echo ""
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}ERROR: This script must be run as root.${NC}"
        exit 1
    fi
}

check_printer() {
    if [ ! -f "$CONFIG_DIR/printer.cfg" ]; then
        echo -e "${RED}ERROR: printer.cfg not found at $CONFIG_DIR/printer.cfg${NC}"
        exit 1
    fi
}

main_menu() {
    print_header
    echo -e "  ${WHITE}[Install] Menu${NC}"
    echo -e "  ${CYAN}--- Step 1: Foundation (install first) ---${NC}"
    echo -e "    ${YELLOW}1)${NC} ${GREEN}Moonraker (extensions / updatable Moonraker)${NC} ${WHITE}[first]${NC}"
    echo ""
    echo -e "  ${CYAN}--- Step 2: Print macros ---${NC}"
    echo -e "    ${YELLOW}2)${NC} ${GREEN}Fans Control Macros${NC}"
    echo -e "    ${YELLOW}3)${NC} ${GREEN}Useful Macros (PID, leveling, warmup)${NC}"
    echo -e "    ${YELLOW}4)${NC} ${GREEN}Save Z-Offset Macros${NC}"
    echo -e "    ${YELLOW}5)${NC} ${GREEN}M600 Filament Change Support${NC}"
    echo ""
    echo -e "  ${CYAN}--- Step 3: Leveling & calibration ---${NC}"
    echo -e "    ${YELLOW}6)${NC} ${GREEN}Klipper Adaptive Meshing & Purging (KAMP-K2)${NC}"
    echo -e "    ${YELLOW}7)${NC} ${GREEN}Improved Shapers Calibrations${NC}"
    echo ""
    echo -e "  ${CYAN}--- Step 4: Web interface & camera ---${NC}"
    echo -e "    ${YELLOW}8)${NC} ${GREEN}Fluidd (install/update/repair — port 4408)${NC}"
    echo -e "    ${YELLOW}9)${NC} ${GREEN}Mainsail (install/update/repair — port 4409)${NC}"
    echo -e "   ${YELLOW}10)${NC} ${GREEN}Moonraker Timelapse${NC}"
    echo -e "   ${YELLOW}11)${NC} ${GREEN}Camera Support (Fluidd, Mainsail, Mobileraker)${NC}"
    echo -e "   ${YELLOW}12)${NC} ${GREEN}HelixScreen (touchscreen UI)${NC}"
    echo ""
    echo -e "  ${CYAN}--- Step 5: Remote access, notifications & backup ---${NC}"
    echo -e "   ${YELLOW}13)${NC} ${GREEN}Entware Package Manager${NC}             ${WHITE}[needed by 14-17]${NC}"
    echo -e "   ${YELLOW}14)${NC} ${GREEN}OctoEverywhere${NC}"
    echo -e "   ${YELLOW}15)${NC} ${GREEN}Mobileraker Companion${NC}"
    echo -e "   ${YELLOW}16)${NC} ${GREEN}OctoApp Companion${NC}"
    echo -e "   ${YELLOW}17)${NC} ${GREEN}Git Backup${NC}"
    echo -e "   ${YELLOW}18)${NC} ${GREEN}Klipper Gcode Shell Command${NC}"
    echo ""
    echo -e "  ${CYAN}--- Step 6: Power ---${NC}"
    echo -e "   ${YELLOW}19)${NC} ${GREEN}Auto Power Off (smart plug: Tapo, Tasmota, Shelly, ...)${NC}"
    echo ""
    echo -e "  ${WHITE}[Remove] Menu${NC}"
    echo -e "   ${YELLOW}20)${NC} ${GREEN}Remove a feature${NC}"
    echo ""
    echo -e "  ${WHITE}[Backup & Restore] Menu${NC}"
    echo -e "   ${YELLOW}21)${NC} ${GREEN}Backup Klipper configuration${NC}"
    echo -e "   ${YELLOW}22)${NC} ${GREEN}Restore Klipper configuration${NC}"
    echo -e "   ${YELLOW}23)${NC} ${GREEN}Backup Moonraker database${NC}"
    echo -e "   ${YELLOW}24)${NC} ${GREEN}Restore Moonraker database${NC}"
    echo ""
    echo -e "  ${WHITE}[Tools] Menu${NC}"
    echo -e "   ${YELLOW}25)${NC} ${GREEN}Restart Klipper${NC}"
    echo -e "   ${YELLOW}26)${NC} ${GREEN}Restart Moonraker${NC}"
    echo -e "   ${YELLOW}27)${NC} ${GREEN}Restart Nginx${NC}"
    echo -e "   ${YELLOW}28)${NC} ${GREEN}View Klipper log${NC}"
    echo -e "   ${YELLOW}29)${NC} ${GREEN}View Moonraker log${NC}"
    echo -e "   ${YELLOW}30)${NC} ${GREEN}Show installed features${NC}"
    echo -e "   ${YELLOW}31)${NC} ${GREEN}Update Entware packages${NC}"
    echo -e "   ${YELLOW}32)${NC} ${GREEN}Clear logs & cache${NC}"
    echo -e "   ${YELLOW}33)${NC} ${GREEN}System information${NC}"
    echo -e "   ${YELLOW}34)${NC} ${GREEN}Update helper script${NC}               ${WHITE}[installed: $(installed_version)]${NC}"
    echo ""
    echo -e "    ${YELLOW}0)${NC} ${RED}Exit${NC}"
    echo ""
    printf "  \033[0;32mEnter choice:\033[0m "
    read choice
    handle_choice "$choice"
}

confirm_install() {
    echo ""
    printf "  This will install %s. Continue? [y/n]: " "$1"
    read confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]
}

handle_choice() {
    case "$1" in
        1)  moonraker_menu ;;
        2)  confirm_install "Fans Control Macros" && sh "$SCRIPTS_DIR/fans.sh" install ;;
        3)  confirm_install "Useful Macros" && sh "$SCRIPTS_DIR/useful_macros.sh" install ;;
        4)  confirm_install "Save Z-Offset Macros" && sh "$SCRIPTS_DIR/z_offset.sh" install ;;
        5)  confirm_install "M600 Support" && sh "$SCRIPTS_DIR/m600.sh" install ;;
        6)  confirm_install "KAMP-K2" && sh "$SCRIPTS_DIR/kamp.sh" install ;;
        7)  confirm_install "Improved Shapers Calibrations" && sh "$SCRIPTS_DIR/shapers.sh" install ;;
        8)  confirm_install "Fluidd" && sh "$SCRIPTS_DIR/fluidd.sh" install ;;
        9)  confirm_install "Mainsail" && sh "$SCRIPTS_DIR/mainsail.sh" install ;;
        10) confirm_install "Moonraker Timelapse" && sh "$SCRIPTS_DIR/timelapse.sh" install ;;
        11) sh "$SCRIPTS_DIR/camera.sh" install ;;
        12) sh "$SCRIPTS_DIR/helixscreen.sh" install ;;
        13) sh "$SCRIPTS_DIR/entware.sh" install ;;
        14) sh "$SCRIPTS_DIR/octoeverywhere.sh" install ;;
        15) sh "$SCRIPTS_DIR/mobileraker.sh" install ;;
        16) sh "$SCRIPTS_DIR/octoapp.sh" install ;;
        17) sh "$SCRIPTS_DIR/git_backup.sh" install ;;
        18) confirm_install "Klipper Gcode Shell Command" && sh "$SCRIPTS_DIR/shell_command.sh" install ;;
        19) sh "$SCRIPTS_DIR/auto_power_off.sh" install ;;
        20) remove_menu; main_menu; return ;;
        21) sh "$SCRIPTS_DIR/backup.sh" backup ;;
        22) sh "$SCRIPTS_DIR/backup.sh" restore ;;
        23) sh "$SCRIPTS_DIR/backup.sh" backup_database ;;
        24) sh "$SCRIPTS_DIR/backup.sh" restore_database ;;
        25) sh "$SCRIPTS_DIR/system.sh" restart_klipper ;;
        26) sh "$SCRIPTS_DIR/system.sh" restart_moonraker ;;
        27) sh "$SCRIPTS_DIR/system.sh" restart_nginx ;;
        28) tail -50 "$LOGS_DIR/klippy.log" | less ;;
        29) tail -50 "$LOGS_DIR/moonraker.log" | less ;;
        30) sh "$SCRIPTS_DIR/system.sh" show_installed ;;
        31) sh "$SCRIPTS_DIR/system.sh" update_entware ;;
        32) sh "$SCRIPTS_DIR/system.sh" clear_logs_cache ;;
        33) sh "$SCRIPTS_DIR/system.sh" system_info ;;
        34) run_update ;;
        0)  echo ""; echo "Goodbye!"; echo ""; exit 0 ;;
        *)  echo -e "${RED}Invalid choice.${NC}"; sleep 1 ;;
    esac
    echo ""
    printf "Press Enter to return to main menu..."
    read dummy
    main_menu
}

# Option 1: extensions for Creality's Moonraker, or the updatable upstream one
moonraker_menu() {
    local current="Creality stock"
    moonraker_is_upstream && current="upstream (updatable)"
    echo ""
    echo -e "  ${WHITE}Moonraker${NC} - active: ${CYAN}${current}${NC}"
    echo ""
    echo -e "    ${YELLOW}1)${NC} ${GREEN}Moonraker Extensions${NC}  (persistent moonraker.conf for Creality's Moonraker)"
    echo -e "    ${YELLOW}2)${NC} ${GREEN}Updatable Moonraker${NC}   (current upstream Moonraker; Software Updates in Fluidd work)"
    echo -e "    ${YELLOW}0)${NC} ${RED}Back${NC}"
    echo ""
    printf "  Enter choice: "
    read subchoice
    case "$subchoice" in
        1) confirm_install "Moonraker Extensions" && sh "$SCRIPTS_DIR/moonraker.sh" install ;;
        2) sh "$SCRIPTS_DIR/moonraker_upstream.sh" install ;;
    esac
}

# ── Self-update ───────────────────────────────────────────────────────────────
# scripts/update.sh compares the commit SHA in .version with the latest commit
# on GitHub. HELPER_SKIP_UPDATE=1 skips the check at start (e.g. offline use).

# Installed release (e.g. v2.0.0); a git checkout may have been updated by Moonraker
installed_version() {
    sh "$SCRIPTS_DIR/update.sh" version 2>/dev/null || echo "unknown"
}

check_for_update() {
    [ "$HELPER_SKIP_UPDATE" = 1 ] && return 0
    echo "Checking for helper script updates..."
    local result old new answer
    result=$(sh "$SCRIPTS_DIR/update.sh" check 2>/dev/null)
    case "$result" in
        UPDATE*) ;;
        *) return 0 ;;
    esac
    old=$(echo "$result" | head -1 | cut -d' ' -f2)
    new=$(echo "$result" | head -1 | cut -d' ' -f3)
    echo ""
    echo -e "${YELLOW}Helper script update available:${NC} $old -> $new"
    echo "$result" | tail -n +2
    echo ""
    printf "Update now? [Y/n]: "
    read answer
    case "$answer" in
        n|N) return 0 ;;
    esac
    run_update
}

# Install the latest commit and restart helper.sh with the new files
run_update() {
    if sh "$SCRIPTS_DIR/update.sh" update; then
        log_success "Helper script updated - restarting..."
        sleep 1
        HELPER_SKIP_UPDATE=1 exec sh "$SCRIPT_DIR/helper.sh"
    else
        log_error "Update failed - keeping the installed version."
    fi
}

remove_menu() {
    print_header
    echo -e "  ${WHITE}[Remove] Menu${NC}"
    echo ""
    echo -e "    ${YELLOW}1)${NC}  ${GREEN}Moonraker Extensions / switch back to Creality's Moonraker${NC}"
    echo -e "    ${YELLOW}2)${NC}  ${GREEN}Fans Control Macros${NC}"
    echo -e "    ${YELLOW}3)${NC}  ${GREEN}Useful Macros${NC}"
    echo -e "    ${YELLOW}4)${NC}  ${GREEN}Save Z-Offset Macros${NC}"
    echo -e "    ${YELLOW}5)${NC}  ${GREEN}M600 Support${NC}"
    echo -e "    ${YELLOW}6)${NC}  ${GREEN}KAMP-K2${NC}"
    echo -e "    ${YELLOW}7)${NC}  ${GREEN}Improved Shapers Calibrations${NC}"
    echo -e "    ${YELLOW}8)${NC}  ${GREEN}Restore stock Fluidd${NC}"
    echo -e "    ${YELLOW}9)${NC}  ${GREEN}Mainsail${NC}"
    echo -e "   ${YELLOW}10)${NC}  ${GREEN}Moonraker Timelapse${NC}"
    echo -e "   ${YELLOW}11)${NC}  ${GREEN}Camera Support${NC}"
    echo -e "   ${YELLOW}12)${NC}  ${GREEN}HelixScreen${NC}"
    echo -e "   ${YELLOW}13)${NC}  ${GREEN}Entware Package Manager${NC}"
    echo -e "   ${YELLOW}14)${NC}  ${GREEN}OctoEverywhere${NC}"
    echo -e "   ${YELLOW}15)${NC}  ${GREEN}Mobileraker Companion${NC}"
    echo -e "   ${YELLOW}16)${NC}  ${GREEN}OctoApp Companion${NC}"
    echo -e "   ${YELLOW}17)${NC}  ${GREEN}Git Backup${NC}"
    echo -e "   ${YELLOW}18)${NC}  ${GREEN}Klipper Gcode Shell Command${NC}"
    echo -e "   ${YELLOW}19)${NC}  ${GREEN}Auto Power Off${NC}"
    echo -e "    ${YELLOW}0)${NC}  ${RED}Back to main menu${NC}"
    echo ""
    printf "  ${GREEN}Enter choice:${NC} "
    read choice
    case "$choice" in
        1)  if moonraker_is_upstream; then
                sh "$SCRIPTS_DIR/moonraker_upstream.sh" remove
            else
                sh "$SCRIPTS_DIR/moonraker.sh" remove
            fi ;;
        2)  sh "$SCRIPTS_DIR/fans.sh" remove ;;
        3)  sh "$SCRIPTS_DIR/useful_macros.sh" remove ;;
        4)  sh "$SCRIPTS_DIR/z_offset.sh" remove ;;
        5)  sh "$SCRIPTS_DIR/m600.sh" remove ;;
        6)  sh "$SCRIPTS_DIR/kamp.sh" remove ;;
        7)  sh "$SCRIPTS_DIR/shapers.sh" remove ;;
        8)  sh "$SCRIPTS_DIR/fluidd.sh" remove ;;
        9)  sh "$SCRIPTS_DIR/mainsail.sh" remove ;;
        10) sh "$SCRIPTS_DIR/timelapse.sh" remove ;;
        11) sh "$SCRIPTS_DIR/camera.sh" remove ;;
        12) sh "$SCRIPTS_DIR/helixscreen.sh" remove ;;
        13) sh "$SCRIPTS_DIR/entware.sh" remove ;;
        14) sh "$SCRIPTS_DIR/octoeverywhere.sh" remove ;;
        15) sh "$SCRIPTS_DIR/mobileraker.sh" remove ;;
        16) sh "$SCRIPTS_DIR/octoapp.sh" remove ;;
        17) sh "$SCRIPTS_DIR/git_backup.sh" remove ;;
        18) sh "$SCRIPTS_DIR/shell_command.sh" remove ;;
        19) sh "$SCRIPTS_DIR/auto_power_off.sh" remove ;;
        0)  return ;;
        *)  echo -e "${RED}Invalid choice.${NC}"; sleep 1; remove_menu; return ;;
    esac
    echo ""
    printf "Press Enter to return to Remove menu..."
    read dummy
    remove_menu
}


. "$SCRIPTS_DIR/system.sh"
check_root
if [ "$1" = "--update" ]; then
    # Non-interactive update (e.g. over SSH): sh helper.sh --update
    sh "$SCRIPTS_DIR/update.sh" update
    exit $?
fi
check_printer
check_for_update
check_entware_location
detect_printer
patch_stock_configs
ensure_addons
install_rc_local_patch
install_moonraker_include
main_menu
