#!/bin/sh
# auto_power_off.sh - Install/remove Auto Power Off for K2
# Switches the printer off with a smart plug once a print has finished and
# nozzle and bed have cooled down. Macros after tinntbg/auto-power-off-klipper
# (https://github.com/tinntbg/auto-power-off-klipper).
#
# Plugs become a Moonraker power device [power printer_plug]. Newer Kasa (and
# Tapo) plugs speak the encrypted KLAP protocol, which Moonraker cannot switch;
# those are switched by scripts/kasa.py through [gcode_shell_command].
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

APO_CFG=$CONFIG_DIR/auto_power_off.cfg
KASA_PY=$SCRIPT_DIR/scripts/kasa.py
KASA_CONF=$SCRIPT_DIR/.kasa.json
DEVICE=printer_plug
TAB=$(printf '\t')

yes_no() {
    # yes_no "question" <default y|n>
    local answer
    printf "  %s [%s]: " "$1" "$([ "$2" = y ] && echo Y/n || echo y/N)"
    read -r answer
    [ -z "$answer" ] && answer=$2
    [ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

ask() {
    # ask "prompt" [default] - prints the answer
    local answer
    if [ -n "$2" ]; then
        printf "  %s [%s]: " "$1" "$2" >&2
    else
        printf "  %s: " "$1" >&2
    fi
    read -r answer
    echo "${answer:-$2}"
}

# ── TP-Link Kasa (and Tapo) ───────────────────────────────────────────────────

# Sets KASA_IP / KASA_PROTO from a network search, empty if none was picked
kasa_search() {
    KASA_IP=
    KASA_PROTO=
    yes_no "Search the network for Kasa plugs?" y || return 0
    log_info "Searching for Kasa / Tapo devices (5 s)..."
    local list count n line
    list=$(python3 "$KASA_PY" discover 5)
    if [ -z "$list" ]; then
        log_warn "No Kasa devices found. The plug must be in the same network as the printer."
        return 0
    fi
    count=$(echo "$list" | wc -l)
    echo ""
    echo "$list" | {
        n=0
        while IFS="$TAB" read -r ip model name mac proto; do
            n=$((n + 1))
            case "$proto" in
                legacy) proto="no login needed" ;;
                KLAP)   proto="needs TP-Link account" ;;
                *)      proto="'$proto' encryption - not supported" ;;
            esac
            printf "    ${YELLOW}%d)${NC} %-15s  %-10s %-22s %s
" "$n" "$ip" "$model" "$name" "$proto"
        done
    }
    echo ""
    n=$(ask "Choose a device [1-$count], or Enter to type the IP address")
    case "$n" in
        ''|*[!0-9]*) return 0 ;;
    esac
    line=$(echo "$list" | sed -n "${n}p")
    KASA_IP=$(echo "$line" | cut -f1)
    KASA_PROTO=$(echo "$line" | cut -f5)
}

setup_kasa() {
    echo ""
    echo "  Classic Kasa plugs (HS100, HS110, KP105, KP115, ...) are switched by"
    echo "  Moonraker. Newer models / firmware (KP125M, EP25, ...) need your"
    echo "  TP-Link account and are switched by the helper (kasa.py)."
    echo ""
    kasa_search
    while :; do
        if [ -z "$KASA_IP" ]; then
            KASA_IP=$(ask "IP address of the Kasa plug (fixed / DHCP-reserved)")
            [ -z "$KASA_IP" ] && { log_info "Cancelled."; return 1; }
            KASA_PROTO=$(python3 "$KASA_PY" probe "$KASA_IP")
        fi
        case "$KASA_PROTO" in
            legacy) setup_moonraker_device kasa; return $? ;;
            KLAP)   setup_kasa_klap; return $? ;;
            none)   log_warn "No Kasa plug answers at $KASA_IP." ;;
            *)      log_warn "$KASA_IP uses '$KASA_PROTO' encryption, which is not supported - update the plug's firmware in the app." ;;
        esac
        KASA_IP=
        yes_no "Try another address?" y || return 1
    done
}

# Newer Kasa (and Tapo) plugs: KLAP protocol, switched by kasa.py from Klipper
setup_kasa_klap() {
    echo ""
    echo "  This plug needs the TP-Link account it is registered to. Only a"
    echo "  hash of the password is stored, in $KASA_CONF"
    echo "  (not in the printer config / Git Backup)."
    echo ""
    local tries=0 rc
    while :; do
        python3 "$KASA_PY" setup "$KASA_IP"
        rc=$?
        [ $rc -eq 0 ] && break
        tries=$((tries + 1))
        [ $rc -eq 2 ] && log_warn "Check e-mail and password (both case-sensitive). For Tapo plugs, enable 'Third-Party Compatibility' in the Tapo app."
        [ $tries -lt 3 ] && yes_no "Try again?" y || return 1
    done

    # kasa.py runs from Klipper via RUN_SHELL_COMMAND
    sh "$SCRIPT_DIR/scripts/shell_command.sh" ensure
    mark_installed "gcode_shell_command"
    USES_KASA_PY=1
    POWER_OFF_GCODE="RUN_SHELL_COMMAND CMD=kasa_power_off"
    SHELL_SECTION="
[gcode_shell_command kasa_power_off]
command: python3 $KASA_PY off
timeout: 20.
verbose: True
"
    log_success "Kasa plug $KASA_IP configured."
}

# ── Moonraker power devices ───────────────────────────────────────────────────

# Sets POWER_SECTION (the [power printer_plug] block) for the chosen plug type
moonraker_power_section() {
    local ip user pw entity token port
    case "$1" in
        tasmota)
            ip=$(ask "IP address of the Tasmota plug")
            pw=$(ask "Web password (Enter if none)")
            POWER_SECTION="type: tasmota
address: $ip${pw:+
password: $pw}"
            ;;
        shelly)
            ip=$(ask "IP address of the Shelly plug")
            user=$(ask "Login user (Enter if none)")
            [ -n "$user" ] && pw=$(ask "Login password")
            POWER_SECTION="type: shelly
address: $ip${user:+
user: $user}${pw:+
password: $pw}"
            ;;
        kasa)
            ip=$KASA_IP
            POWER_SECTION="type: tplink_smartplug
address: $ip"
            ;;
        homeassistant)
            ip=$(ask "Home Assistant address (IP or host name)")
            port=$(ask "Home Assistant port" 8123)
            entity=$(ask "Entity ID of the plug (e.g. switch.printer)")
            token=$(ask "Long-lived access token (HA profile -> Security)")
            POWER_SECTION="type: homeassistant
address: $ip
port: $port
device: $entity
token: $token"
            ;;
    esac
    [ -n "$ip" ] || return 1
    POWER_SECTION="[power $DEVICE]
$POWER_SECTION
# Refuse to switch off while printing
locked_while_printing: True"
}

# Print the [power ...] device names Moonraker knows from its config
existing_power_devices() {
    grep -hos "^\[power [^]]*\]" "$MOONRAKER_CONF" /usr/share/moonraker/moonraker.conf 2>/dev/null \
        | sed 's/^\[power //; s/\]$//' | grep -vx "$DEVICE" | sort -u
}

# Print Moonraker's state of a power device (on/off/error/...) or nothing
moonraker_device_state() {
    python3 - "$1" << 'PYEOF'
import json, sys, time, urllib.request
url = 'http://127.0.0.1:7125/machine/device_power/device?device=' + sys.argv[1]
for _ in range(15):
    try:
        state = json.load(urllib.request.urlopen(url, timeout=3))['result'][sys.argv[1]]
        if state != 'init':
            print(state)
            break
    except Exception:
        pass
    time.sleep(1)
PYEOF
}

setup_moonraker_device() {
    local name state
    if [ ! -f "$MOONRAKER_CONF" ]; then
        log_error "$MOONRAKER_CONF not found - install Moonraker Extensions (menu 1) first."
        return 1
    fi
    if [ "$1" = existing ]; then
        local devices
        devices=$(existing_power_devices)
        if [ -n "$devices" ]; then
            echo "  Power devices in moonraker.conf:"
            echo "$devices" | sed 's/^/    /'
        fi
        name=$(ask "Name of the Moonraker power device")
        [ -z "$name" ] && { log_info "Cancelled."; return 1; }
        remove_own_power_device && restart_moonraker force
    else
        moonraker_power_section "$1" || { log_info "Cancelled."; return 1; }
        name=$DEVICE
        remove_own_power_device
        add_moonraker_section "power $DEVICE" "$POWER_SECTION"
        restart_moonraker force
    fi
    state=$(moonraker_device_state "$name")
    case "$state" in
        on|off) log_success "Moonraker reports power device '$name': $state" ;;
        error)  log_warn "Moonraker cannot reach power device '$name' - check the address. See $LOGS_DIR/moonraker.log" ;;
        *)      log_warn "Power device '$name' is not known to Moonraker (yet). See $LOGS_DIR/moonraker.log" ;;
    esac
    POWER_OFF_GCODE="{action_call_remote_method(\"set_device_power\", device=\"$name\", state=\"off\")}"
    SHELL_SECTION=
}

# Drop the [power printer_plug] section this script created earlier
remove_own_power_device() {
    if grep -q "^\[power $DEVICE\]" "$MOONRAKER_CONF" 2>/dev/null; then
        remove_moonraker_section "power $DEVICE"
        return 0
    fi
    return 1
}

# ── Klipper macros ────────────────────────────────────────────────────────────

write_apo_cfg() {
    cat > "$APO_CFG" << EOF
# Auto Power Off - switch the printer off after a print, once it has cooled down
# After https://github.com/tinntbg/auto-power-off-klipper
# Managed by Creality Helper Script - re-run the installer to change the plug.
#
#   ACTIVATE_POWER_OFF          power off after the running print (or now, once cool)
#   DEACTIVATE_POWER_OFF        cancel a pending power off
#   AUTO_POWER_OFF ENABLE=1|0   arm it for every print (until Klipper restarts;
#                               the default is variable_every_print below)

[gcode_macro _POWER_OFF_PRINTER]
description: Switch the smart plug off
gcode:
  {action_respond_info("Auto power off: switching the printer off now.")}
  $POWER_OFF_GCODE
$SHELL_SECTION
[gcode_macro ACTIVATE_POWER_OFF]
description: Power off once the print has finished and nozzle and bed have cooled down
variable_every_print: $EVERY_PRINT
variable_max_temp: $MAX_TEMP
variable_armed: 0
variable_skip_print: 0
gcode:
  SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=armed VALUE=1
  SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=skip_print VALUE=0
  UPDATE_DELAYED_GCODE ID=_POWER_OFF_WAIT_COOL DURATION=0
  UPDATE_DELAYED_GCODE ID=_POWER_OFF_WAIT_PRINT DURATION=5
  {action_respond_info("Auto power off armed: the printer turns off after the print, once nozzle and bed are below %d C." % max_temp)}
EOF
    cat >> "$APO_CFG" << 'EOF'

[gcode_macro DEACTIVATE_POWER_OFF]
description: Cancel a pending automatic power off
gcode:
  UPDATE_DELAYED_GCODE ID=_POWER_OFF_WAIT_PRINT DURATION=0
  UPDATE_DELAYED_GCODE ID=_POWER_OFF_WAIT_COOL DURATION=0
  SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=armed VALUE=0
  {% if printer.print_stats.state in ["printing", "paused"] %}
    # Keep AUTO_POWER_OFF from re-arming it for this print
    SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=skip_print VALUE=1
  {% endif %}
  {action_respond_info("Auto power off cancelled.")}

[gcode_macro AUTO_POWER_OFF]
description: Power off after every print - AUTO_POWER_OFF ENABLE=1|0
gcode:
  {% set apo = printer["gcode_macro ACTIVATE_POWER_OFF"] %}
  {% set enable = params.ENABLE|default(apo.every_print)|int %}
  SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=every_print VALUE={1 if enable else 0}
  {% if not enable and apo.armed %}
    DEACTIVATE_POWER_OFF
  {% endif %}
  {action_respond_info("Auto power off after every print: %s" % ("on" if enable else "off"))}

# Arm ACTIVATE_POWER_OFF for every print while every_print is set
[delayed_gcode _POWER_OFF_WATCH]
initial_duration: 15
gcode:
  {% set apo = printer["gcode_macro ACTIVATE_POWER_OFF"] %}
  {% if printer.print_stats.state in ["printing", "paused"] %}
    {% if apo.every_print and not apo.armed and not apo.skip_print %}
      ACTIVATE_POWER_OFF
    {% endif %}
  {% elif apo.skip_print %}
    SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=skip_print VALUE=0
  {% endif %}
  UPDATE_DELAYED_GCODE ID=_POWER_OFF_WATCH DURATION=30

# Wait for the print to finish (a paused print keeps waiting)
[delayed_gcode _POWER_OFF_WAIT_PRINT]
gcode:
  {% set state = printer.print_stats.state %}
  {% if state in ["printing", "paused"] %}
    UPDATE_DELAYED_GCODE ID=_POWER_OFF_WAIT_PRINT DURATION=30
  {% elif state in ["cancelled", "error"] %}
    SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=armed VALUE=0
    {action_respond_info("Auto power off cancelled: the print was %s." % state)}
  {% else %}
    {action_respond_info("Auto power off: waiting for nozzle and bed to cool down.")}
    UPDATE_DELAYED_GCODE ID=_POWER_OFF_WAIT_COOL DURATION=30
  {% endif %}

# Wait for nozzle and bed to cool down; heating up or a new print cancels it
[delayed_gcode _POWER_OFF_WAIT_COOL]
gcode:
  {% set apo = printer["gcode_macro ACTIVATE_POWER_OFF"] %}
  {% set e = printer.extruder %}
  {% set bed = printer.heater_bed %}
  {% if printer.print_stats.state in ["printing", "paused"] %}
    SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=armed VALUE=0
    {action_respond_info("Auto power off cancelled: a new print was started.")}
  {% elif e.target > 0 or bed.target > 0 %}
    SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=armed VALUE=0
    {action_respond_info("Auto power off cancelled: a heater was turned on.")}
  {% elif e.temperature < apo.max_temp and bed.temperature < apo.max_temp %}
    SET_GCODE_VARIABLE MACRO=ACTIVATE_POWER_OFF VARIABLE=armed VALUE=0
    _POWER_OFF_PRINTER
  {% else %}
    UPDATE_DELAYED_GCODE ID=_POWER_OFF_WAIT_COOL DURATION=10
  {% endif %}
EOF
}

# ── Install / remove ──────────────────────────────────────────────────────────

install_apo() {
    if is_installed "auto_power_off"; then
        log_info "Auto Power Off is already installed."
        yes_no "Reconfigure it (plug, every print, temperature)?" n || return 0
    fi
    echo ""
    echo "======================================================"
    echo "  Auto Power Off"
    echo "======================================================"
    echo ""
    echo "  Switches the K2 off with a smart plug after a print, once"
    echo "  nozzle and bed are cool. Starting a print or heating up"
    echo "  cancels it. Switch the printer on again in the plug's app."
    echo ""
    echo "  Which smart plug switches the printer?"
    echo -e "    ${YELLOW}1)${NC} TP-Link Kasa (with network search; also Tapo)"
    echo -e "    ${YELLOW}2)${NC} Tasmota"
    echo -e "    ${YELLOW}3)${NC} Shelly"
    echo -e "    ${YELLOW}4)${NC} Home Assistant entity"
    echo -e "    ${YELLOW}5)${NC} Power device already in moonraker.conf"
    echo -e "    ${YELLOW}0)${NC} Cancel"
    echo ""
    USES_KASA_PY=0
    case "$(ask "Enter choice")" in
        1) setup_kasa || return 1 ;;
        2) setup_moonraker_device tasmota || return 1 ;;
        3) setup_moonraker_device shelly || return 1 ;;
        4) setup_moonraker_device homeassistant || return 1 ;;
        5) setup_moonraker_device existing || return 1 ;;
        *) log_info "Cancelled."; return 0 ;;
    esac
    if [ "$USES_KASA_PY" = 1 ]; then
        # Switched from a Moonraker plug: drop the old Moonraker device
        remove_own_power_device && restart_moonraker force
    else
        rm -f "$KASA_CONF"
    fi

    echo ""
    if yes_no "Power off automatically after every print? (otherwise run ACTIVATE_POWER_OFF)" y; then
        EVERY_PRINT=1
    else
        EVERY_PRINT=0
    fi
    MAX_TEMP=$(to_int "$(ask "Power off when nozzle and bed are below (C)" 50)" 50)
    [ "$MAX_TEMP" -lt 30 ] || [ "$MAX_TEMP" -gt 100 ] && MAX_TEMP=50

    write_apo_cfg
    log_success "Created $APO_CFG"
    add_include_to_printer_cfg "auto_power_off.cfg"
    restart_klipper force
    mark_installed "auto_power_off"
    echo ""
    log_success "Auto Power Off installed!"
    echo ""
    if [ "$EVERY_PRINT" = 1 ]; then
        log_info "Armed for every print. AUTO_POWER_OFF ENABLE=0 turns it off until Klipper restarts."
    else
        log_info "Run ACTIVATE_POWER_OFF during a print (or add it to the slicer's end G-code)."
    fi
    log_info "DEACTIVATE_POWER_OFF cancels a pending power off."
    echo ""
}

remove_apo() {
    if ! is_installed "auto_power_off"; then
        log_info "Auto Power Off is not installed."
        return 0
    fi
    echo -e "${YELLOW}WARNING: This will remove Auto Power Off.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    remove_include_from_printer_cfg "auto_power_off.cfg"
    rm -f "$APO_CFG" "$KASA_CONF"
    remove_own_power_device && restart_moonraker force
    restart_klipper force
    mark_removed "auto_power_off"
    log_success "Auto Power Off removed."
}

case "$1" in
    install) install_apo ;;
    remove)  remove_apo ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
