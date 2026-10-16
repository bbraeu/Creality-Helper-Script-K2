#!/bin/sh
# system.sh - Service management and system utilities for K2 Helper Script

SCRIPT_DIR=/mnt/UDISK/helper-script
CONFIG_DIR=/mnt/UDISK/printer_data/config
LOGS_DIR=/mnt/UDISK/printer_data/logs
INSTALLED_FILE=$SCRIPT_DIR/.installed

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }

# ── Service restarts ──────────────────────────────────────────────────────────

restart_klipper() {
    if [ "$1" != "force" ]; then
        printf "Restart Klipper? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    fi
    log_info "Restarting Klipper..."
    /etc/rc.d/S55klipper restart
    sleep 3
    if pgrep -f "klippy.py" > /dev/null; then
        log_success "Klipper restarted successfully."
    else
        log_error "Klipper failed to restart. Check $LOGS_DIR/klippy.log"
    fi
}

restart_moonraker() {
    if [ "$1" != "force" ]; then
        printf "Restart Moonraker? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    fi
    log_info "Restarting Moonraker..."
    # Kill ALL running moonraker instances (stock + helper script)
    for pid in $(ps aux | grep moonraker.py | grep -v grep | awk '{print $1}'); do
        kill "$pid" 2>/dev/null
    done
    sleep 2
    /etc/init.d/moonraker start
    sleep 3
    if pgrep -f "moonraker.py" > /dev/null; then
        log_success "Moonraker restarted successfully."
    else
        log_error "Moonraker failed to restart. Check $LOGS_DIR/moonraker.log"
    fi
}

restart_nginx() {
    if [ "$1" != "force" ]; then
        printf "Restart Nginx? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    fi
    log_info "Restarting Nginx..."
    /etc/rc.d/S80nginx restart
    sleep 2
    if pgrep -f "nginx" > /dev/null; then
        log_success "Nginx restarted successfully."
    else
        log_error "Nginx failed to restart."
    fi
}

restart_camera() {
    log_info "Restarting WebRTC camera service..."
    /etc/rc.d/S97webrtc restart
    sleep 2
    log_success "Camera service restarted."
}

# ── Entware / services ────────────────────────────────────────────────────────

# Fail unless Entware is installed; puts /opt/bin first on PATH
require_entware() {
    if [ ! -x /opt/bin/opkg ]; then
        log_error "Entware is required. Install it first: [Install] Menu → Entware Package Manager."
        return 1
    fi
    export PATH=/opt/bin:/opt/sbin:$PATH
}

opkg_install() {
    log_info "Installing packages: $*"
    /opt/bin/opkg update > /dev/null 2>&1
    /opt/bin/opkg install "$@"
}

# Write, enable and start an OpenWrt procd service: install_service <name> <command...>
# procd restarts the command if it exits. Extra environment: SERVICE_ENV="A=1 B=2"
install_service() {
    local name="$1"
    shift
    cat > "/etc/init.d/$name" << EOF
#!/bin/sh /etc/rc.common
# Managed by Creality Helper Script
START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param env HOME=/root PATH=/opt/bin:/opt/sbin:/usr/sbin:/usr/bin:/sbin:/bin ${SERVICE_ENV}
    procd_set_param command $*
    procd_set_param respawn 3600 10 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
    chmod +x "/etc/init.d/$name"
    "/etc/init.d/$name" enable
    "/etc/init.d/$name" restart
}

remove_service() {
    if [ -x "/etc/init.d/$1" ]; then
        "/etc/init.d/$1" stop
        "/etc/init.d/$1" disable
    fi
    rm -f "/etc/init.d/$1"
}

# ── Tools ─────────────────────────────────────────────────────────────────────

update_entware() {
    require_entware || return 1
    log_info "Updating Entware packages..."
    opkg update && opkg upgrade
    log_success "Entware packages updated."
}

clear_logs_cache() {
    printf "Clear old logs and caches? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    local before after
    before=$(df -k /mnt/UDISK | awk 'NR==2 {print $4}')
    # Rotated logs can go; live logs are truncated, not deleted - Klipper and
    # Moonraker keep them open and would stop logging until restarted
    rm -f "$LOGS_DIR"/*.log.* "$LOGS_DIR"/*.gz
    for f in "$LOGS_DIR"/*.log; do
        [ -f "$f" ] && : > "$f"
    done
    rm -f /tmp/go2rtc.log /tmp/watchdog.log /tmp/camera_startup.log
    rm -rf /root/.cache /mnt/UDISK/.cache
    [ -x /opt/bin/pip3 ] && /opt/bin/pip3 cache purge > /dev/null 2>&1
    after=$(df -k /mnt/UDISK | awk 'NR==2 {print $4}')
    log_success "Logs and caches cleared ($(( (after - before) / 1024 )) MB freed on /mnt/UDISK)."
}

system_info() {
    detect_printer
    local ip
    ip=$(ip route get 1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')
    echo ""
    echo -e "  ${GREEN}Printer:${NC}    $(printer_summary)"
    echo -e "  ${GREEN}Hostname:${NC}   $(cat /proc/sys/kernel/hostname)"
    echo -e "  ${GREEN}IP address:${NC} ${ip:-unknown}"
    echo -e "  ${GREEN}OS:${NC}         $(. /etc/openwrt_release 2>/dev/null; echo "${DISTRIB_DESCRIPTION:-unknown}")"
    echo -e "  ${GREEN}Kernel:${NC}     $(uname -r) ($(uname -m))"
    echo -e "  ${GREEN}Uptime:${NC}     $(uptime | sed 's/.*up \([^,]*\),.*/\1/')"
    echo -e "  ${GREEN}Load:${NC}       $(cut -d' ' -f1-3 /proc/loadavg)"
    echo -e "  ${GREEN}Memory:${NC}     $(free -m | awk '/^Mem:/ {print $3 " MB used / " $2 " MB"}')"
    echo -e "  ${GREEN}UDISK:${NC}      $(df -h /mnt/UDISK | awk 'NR==2 {print $3 " used / " $2 " (" $5 ")"}')"
    echo -e "  ${GREEN}Entware:${NC}    $([ -x /opt/bin/opkg ] && echo installed || echo "not installed")"
    echo ""
}

# ── Feature tracking ──────────────────────────────────────────────────────────

mark_installed() {
    local feature="$1"
    touch "$INSTALLED_FILE" 2>/dev/null
    if ! grep -q "^$feature$" "$INSTALLED_FILE" 2>/dev/null; then
        echo "$feature" >> "$INSTALLED_FILE"
    fi
}

mark_removed() {
    local feature="$1"
    if [ -f "$INSTALLED_FILE" ]; then
        sed -i "/^$feature$/d" "$INSTALLED_FILE"
    fi
}

is_installed() {
    local feature="$1"
    [ -f "$INSTALLED_FILE" ] && grep -q "^$feature$" "$INSTALLED_FILE"
}

show_installed() {
    echo ""
    echo "Installed features:"
    if [ -f "$INSTALLED_FILE" ] && [ -s "$INSTALLED_FILE" ]; then
        while IFS= read -r line; do
            echo -e "  ${GREEN}✓${NC} $line"
        done < "$INSTALLED_FILE"
    else
        echo "  None installed yet."
    fi
    echo ""
}

# ── printer.cfg include management ───────────────────────────────────────────

# Add an [include filename.cfg] line to printer.cfg if not already present
add_include_to_printer_cfg() {
    local include_file="$1"
    local printer_cfg="$CONFIG_DIR/printer.cfg"

    if grep -q "^\[include ${include_file}\]" "$printer_cfg" 2>/dev/null; then
        log_info "[include ${include_file}] already present in printer.cfg"
        return 0
    fi

    # Insert after the last existing [include ...] line, or at top if none
    if grep -q "^\[include " "$printer_cfg"; then
        # Find line number of last include and insert after it
        last_include=$(grep -n "^\[include " "$printer_cfg" | tail -1 | cut -d: -f1)
        sed -i "${last_include}a [include ${include_file}]" "$printer_cfg"
    else
        # No includes yet - add after the first comment block
        sed -i "1s/^/[include ${include_file}]\n/" "$printer_cfg"
    fi

    log_success "Added [include ${include_file}] to printer.cfg"
}

# Remove an [include filename.cfg] line from printer.cfg
remove_include_from_printer_cfg() {
    local include_file="$1"
    local printer_cfg="$CONFIG_DIR/printer.cfg"

    if grep -q "^\[include ${include_file}\]" "$printer_cfg" 2>/dev/null; then
        sed -i "\|^\[include ${include_file}\]$|d" "$printer_cfg"
        log_success "Removed [include ${include_file}] from printer.cfg"
    fi
}

# ── Printer hardware detection ────────────────────────────────────────────────
# The K2 family (K2 / K2 Pro / K2 Plus) shares firmware and stock macros but
# differs in bed size, chamber heater and fans. Read the hardware from the
# stock Klipper config instead of hard-coding one model.

# Print an option of a config section: cfg_option <section> <option> [file]
cfg_option() {
    awk -v s="[$1]" -v o="$2" '
        { sub(/[ \t\r]+$/, "") }
        $0 == s { f = 1; next }
        /^\[/   { f = 0 }
        f && index($0, o) == 1 && substr($0, length(o) + 1) ~ /^[ \t]*[:=]/ {
            sub(/^[^:=]*[:=][ \t]*/, ""); sub(/[ \t]*#.*$/, ""); print; exit
        }' "${3:-$CONFIG_DIR/printer.cfg}" 2>/dev/null
}

# Print the config files Klipper actually loads: printer.cfg and its [include]
# tree. Not *.cfg - the folder also holds SAVE_CONFIG backups (printer-<date>.cfg)
# and other leftovers that would fake sections.
cfg_loaded_files() {
    local queue="$CONFIG_DIR/printer.cfg" seen=" " f inc g
    while [ -n "$queue" ]; do
        set -- $queue
        f=$1
        shift
        queue="$*"
        case "$seen" in *" $f "*) continue ;; esac
        [ -f "$f" ] || continue
        seen="$seen$f "
        echo "$f"
        for inc in $(sed -n 's/^\[include[[:space:]]\{1,\}\([^]]*\)\].*/\1/p' "$f"); do
            # Includes are relative to the including file and may be globs
            for g in "$(dirname "$f")"/$inc; do
                queue="$queue $g"
            done
        done
    done
}

# True if a loaded config file defines [section]
cfg_has_section() {
    grep -qs "^\[$1\]" $(cfg_loaded_files)
}

# Print the name of the first "[<type> <name>]" section whose name contains "chamber"
cfg_chamber_object() {
    grep -hos "^\[$1 [^]]*chamber[^]]*\]" $(cfg_loaded_files) | head -1 | sed "s/^\[$1 //; s/\]\$//"
}

# Print the integer part of $1, or $2 if $1 is not a number
to_int() {
    local v="${1%.*}"
    case "$v" in ''|-|*[!0-9-]*) echo "$2" ;; *) echo "$v" ;; esac
}

# Sets PRINTER_MODEL, X_TRAVEL_MAX, MESH_X/Y_MIN/MAX, CHAMBER_HEATER, CHAMBER_FAN,
# CHAMBER_SENSOR (full Klipper object name), HAS_Z_TILT, HAS_FAN0_EN, HAS_FAN2,
# FAN0_SCALE, FAN2_SCALE
detect_printer() {
    # Travel limits reach past the bed on the K2 (X -12..262, Y up to 296.5 for the
    # CFS cutter / wiper), so moves use the [bed_mesh] area: it is always on the bed
    X_TRAVEL_MAX=$(to_int "$(cfg_option stepper_x position_max)" 262)
    local mesh_min mesh_max
    mesh_min=$(cfg_option bed_mesh mesh_min | tr -d ' ')
    mesh_max=$(cfg_option bed_mesh mesh_max | tr -d ' ')
    MESH_X_MIN=$(to_int "${mesh_min%%,*}" 5)
    MESH_Y_MIN=$(to_int "${mesh_min##*,}" 5)
    MESH_X_MAX=$(to_int "${mesh_max%%,*}" $((X_TRAVEL_MAX - 10)))
    MESH_Y_MAX=$(to_int "${mesh_max##*,}" $((X_TRAVEL_MAX - 10)))

    # Status prefers a dedicated chamber sensor; a temperature_fan reports its own sensor too
    CHAMBER_HEATER=$(cfg_chamber_object heater_generic)
    CHAMBER_FAN=$(cfg_chamber_object temperature_fan)
    CHAMBER_SENSOR=$(cfg_chamber_object temperature_sensor)
    if [ -n "$CHAMBER_HEATER" ]; then
        CHAMBER_SENSOR="heater_generic $CHAMBER_HEATER"
    elif [ -n "$CHAMBER_SENSOR" ]; then
        CHAMBER_SENSOR="temperature_sensor $CHAMBER_SENSOR"
    elif [ -n "$CHAMBER_FAN" ]; then
        CHAMBER_SENSOR="temperature_fan $CHAMBER_FAN"
    fi

    HAS_Z_TILT=0;  cfg_has_section "z_tilt" && HAS_Z_TILT=1
    # On the K2 base fan0_en is a static_digital_output (always on), not settable
    HAS_FAN0_EN=0; cfg_has_section "output_pin fan0_en" && HAS_FAN0_EN=1
    HAS_FAN2=0;    cfg_has_section "output_pin fan2" && HAS_FAN2=1
    # Stock fans use "scale: 255", so SET_PIN expects 0-255 instead of 0-1
    FAN0_SCALE=$(to_int "$(cfg_option "output_pin fan0" scale)" 1)
    FAN2_SCALE=$(to_int "$(cfg_option "output_pin fan2" scale)" 1)

    if [ "$X_TRAVEL_MAX" -ge 330 ]; then
        PRINTER_MODEL="K2 Plus"
    elif [ "$X_TRAVEL_MAX" -ge 285 ]; then
        PRINTER_MODEL="K2 Pro"
    else
        PRINTER_MODEL="K2"
    fi
}

printer_summary() {
    local heater="no chamber heater"
    [ -n "$CHAMBER_HEATER" ] && heater="chamber heater"
    echo "$PRINTER_MODEL ($heater, bed mesh ${MESH_X_MIN},${MESH_Y_MIN} to ${MESH_X_MAX},${MESH_Y_MAX})"
}

# Append chamber macros matching the detected hardware to file $1.
# Without a chamber heater (K2 base) only status/cooling macros are written.
write_chamber_macros() {
    local out="$1"
    [ -z "$CHAMBER_SENSOR" ] && [ -z "$CHAMBER_FAN" ] && return 0

    echo "" >> "$out"
    echo "# ── Chamber ──────────────────────────────────────────────────────────────────" >> "$out"

    if [ -n "$CHAMBER_HEATER" ]; then
        cat >> "$out" << EOF

[gcode_macro CHAMBER_HEAT]
description: Set chamber heater target. Usage: CHAMBER_HEAT TARGET=45 WAIT=1
gcode:
  {% set target = params.TARGET|default(0)|float %}
  {% set wait   = params.WAIT|default(0)|int %}
  SET_HEATER_TEMPERATURE HEATER=${CHAMBER_HEATER} TARGET={target}
  {% if wait == 1 and target > 0 %}
    {action_respond_info("Waiting for chamber to reach %.0f C..." % target)}
    TEMPERATURE_WAIT SENSOR="heater_generic ${CHAMBER_HEATER}" MINIMUM={target - 3}
    {action_respond_info("Chamber reached target: %.0f C" % target)}
  {% endif %}
EOF
    fi

    if [ -n "$CHAMBER_HEATER" ] || [ -n "$CHAMBER_FAN" ]; then
        {
            echo ""
            echo "[gcode_macro CHAMBER_COOL]"
            echo "description: Turn off chamber heating and run the chamber fan"
            echo "gcode:"
            [ -n "$CHAMBER_HEATER" ] && echo "  SET_HEATER_TEMPERATURE HEATER=${CHAMBER_HEATER} TARGET=0"
            [ -n "$CHAMBER_FAN" ] && echo "  SET_TEMPERATURE_FAN_TARGET TEMPERATURE_FAN=${CHAMBER_FAN} TARGET=20"
            echo '  {action_respond_info("Chamber cooling started.")}'
        } >> "$out"
    fi

    if [ -n "$CHAMBER_SENSOR" ]; then
        cat >> "$out" << EOF

[gcode_macro CHAMBER_STATUS]
description: Print current chamber temperature (and target, if heated)
gcode:
  {% set c = printer["${CHAMBER_SENSOR}"] %}
  {% if c.target is defined %}
    {action_respond_info("Chamber: %.1f C  /  target: %.1f C" % (c.temperature, c.target))}
  {% else %}
    {action_respond_info("Chamber: %.1f C" % c.temperature)}
  {% endif %}
EOF
    fi
}

# Space-separated list of the chamber macros write_chamber_macros produces
chamber_macro_names() {
    local names=""
    [ -n "$CHAMBER_HEATER" ] && names="CHAMBER_HEAT"
    { [ -n "$CHAMBER_HEATER" ] || [ -n "$CHAMBER_FAN" ]; } && names="$names CHAMBER_COOL"
    [ -n "$CHAMBER_SENSOR" ] && names="$names CHAMBER_STATUS"
    echo "${names# }"
}

# Find this printer's stock Klipper config dir in /rom (F008_... on the K2 Plus).
# The firmware image may carry configs for several K2 models, so match on bed size
# and give up (print nothing) unless exactly one directory matches.
stock_config_dir() {
    local ours dir match="" n=0
    ours=$(cfg_option stepper_x position_max)
    [ -z "$ours" ] && return 0
    for dir in /rom/usr/share/klipper/config/*/; do
        [ -f "${dir}motor_control.cfg" ] && [ -f "${dir}printer.cfg" ] || continue
        [ "$(cfg_option stepper_x position_max "${dir}printer.cfg")" = "$ours" ] || continue
        match="${dir%/}"
        n=$((n + 1))
    done
    [ "$n" -eq 1 ] && echo "$match"
}

# ── moonraker.conf management ─────────────────────────────────────────────────

MOONRAKER_CONF=$CONFIG_DIR/moonraker.conf
MOONRAKER_RC=/etc/rc.d/S56moonraker
MOONRAKER_RC_BAK=/mnt/UDISK/helper-script/.S56moonraker.orig
MOONRAKER_STOCK_CONF=/usr/share/moonraker/moonraker.conf

# Patch S56moonraker to use our config wrapper instead of the stock one
patch_moonraker_startup() {
    if grep -q "CONF=/mnt/UDISK" "$MOONRAKER_RC" 2>/dev/null; then
        log_info "Moonraker startup already patched."
        return 0
    fi

    # Back up original
    if [ ! -f "${MOONRAKER_RC}.orig" ]; then
        cp "$MOONRAKER_RC" "${MOONRAKER_RC}.orig"
        log_success "Backed up original S56moonraker to ${MOONRAKER_RC}.orig"
    fi

    # Replace the CONF= line
    sed -i "s|CONF=/usr/share/moonraker/moonraker.conf|CONF=/mnt/UDISK/printer_data/config/moonraker.conf|g" "$MOONRAKER_RC"
    log_success "Patched S56moonraker to use /mnt/UDISK/printer_data/config/moonraker.conf"
}

# Restore the original CONF= line
unpatch_moonraker_startup() {
    if [ -f "${MOONRAKER_RC}.orig" ]; then
        cp "${MOONRAKER_RC}.orig" "$MOONRAKER_RC"
        log_success "Restored original S56moonraker startup."
        rm -f "${MOONRAKER_RC}.orig"
    else
        # Restore manually if backup is missing
        sed -i "s|CONF=/mnt/UDISK/printer_data/config/moonraker.conf|CONF=/usr/share/moonraker/moonraker.conf|g" "$MOONRAKER_RC"
        log_success "Restored S56moonraker CONF to stock path."
    fi
}

# Add a section to our moonraker.conf (idempotent)
add_moonraker_section() {
    local section_name="$1"
    local section_content="$2"

    if grep -q "^\[${section_name}" "$MOONRAKER_CONF" 2>/dev/null; then
        log_info "[$section_name] already present in moonraker.conf"
        return 0
    fi

    echo "" >> "$MOONRAKER_CONF"
    echo "$section_content" >> "$MOONRAKER_CONF"
    log_success "Added [$section_name] to moonraker.conf"
}

# Remove a section from our moonraker.conf
remove_moonraker_section() {
    local section_name="$1"
    if [ ! -f "$MOONRAKER_CONF" ]; then return 0; fi

    # Remove from [section_name] to the next blank line + section start
    python3 - "$MOONRAKER_CONF" "$section_name" << 'PYEOF'
import sys, re
path, section = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
# Remove the section block
pattern = r'\n\[' + re.escape(section) + r'\][^\[]*'
content = re.sub(pattern, '', content)
with open(path, 'w') as f:
    f.write(content)
PYEOF
    log_success "Removed [$section_name] from moonraker.conf"
}

# ── nginx management ──────────────────────────────────────────────────────────

NGINX_CONF=/etc/nginx/nginx.conf
NGINX_CONF_BAK=/mnt/UDISK/helper-script/.nginx.conf.bak

backup_nginx_conf() {
    if [ ! -f "$NGINX_CONF_BAK" ]; then
        cp "$NGINX_CONF" "$NGINX_CONF_BAK"
        log_success "Backed up nginx.conf to $NGINX_CONF_BAK"
    fi
}

restore_nginx_conf() {
    if [ -f "$NGINX_CONF_BAK" ]; then
        cp "$NGINX_CONF_BAK" "$NGINX_CONF"
        log_success "Restored nginx.conf from backup."
        rm -f "$NGINX_CONF_BAK"
        restart_nginx
    else
        log_warn "No nginx.conf backup found."
    fi
}

# ── Stock config patch (fix underscore prefix bug) ────────────────────────────

patch_stock_configs() {
    # Ensure /usr/bin/wget exists. Moonraker's shell_command subprocess
    # PATH does not include /opt/bin (where wget actually lives on this
    # firmware), causing "FileNotFoundError: wget" for every timelapse
    # frame capture (TIMELAPSE_TAKE_FRAME -> [timelapse] component ->
    # wget against the go2rtc frame.jpeg endpoint). /usr/bin is on every
    # process's default PATH, so a symlink there fixes it without
    # touching Moonraker's service config.
    if [ -x /opt/bin/wget ] && [ ! -e /usr/bin/wget ]; then
        ln -sf /opt/bin/wget /usr/bin/wget
        log_success "Linked /usr/bin/wget -> /opt/bin/wget (fixes timelapse frame capture)"
    fi

    local box_cfg="$CONFIG_DIR/box.cfg"
    local macro_cfg="$CONFIG_DIR/gcode_macro.cfg"

    log_info "Patching stock config files to fix macro naming..."

    if [ -f "$box_cfg" ]; then
        sed -i 's/\[gcode_macro _BOX_/[gcode_macro BOX_/g' "$box_cfg"
        log_success "Patched box.cfg"
    fi

    if [ -f "$macro_cfg" ]; then
        sed -i \
          -e 's/\[gcode_macro _PRINTER_PARAM\]/[gcode_macro PRINTER_PARAM]/g' \
          -e "s/gcode_macro _PRINTER_PARAM'/gcode_macro PRINTER_PARAM'/g" \
          -e 's/printer\["gcode_macro _PRINTER_PARAM"\]/printer["gcode_macro PRINTER_PARAM"]/g' \
          -e 's/MACRO=_PRINTER_PARAM/MACRO=PRINTER_PARAM/g' \
          -e 's/\[gcode_macro _MAINTENANCE_ITEM_PARAM\]/[gcode_macro MAINTENANCE_ITEM_PARAM]/g' \
          -e 's/\[gcode_macro _IF_NEED_HOME\]/[gcode_macro IF_NEED_HOME]/g' \
          -e 's/\[gcode_macro _LOAD_MATERIAL_CLOSE_FAN2\]/[gcode_macro LOAD_MATERIAL_CLOSE_FAN2]/g' \
          -e 's/\[gcode_macro _LOAD_MATERIAL_RESTORE_FAN2\]/[gcode_macro LOAD_MATERIAL_RESTORE_FAN2]/g' \
          -e 's/\[gcode_macro _LOAD_MATERIAL_HEATING\]/[gcode_macro LOAD_MATERIAL_HEATING]/g' \
          -e 's/\[gcode_macro _LOAD_MATERIAL_MATERIAL_FLUSH\]/[gcode_macro LOAD_MATERIAL_MATERIAL_FLUSH]/g' \
          -e 's/\[gcode_macro _LOAD_MATERIAL_END\]/[gcode_macro LOAD_MATERIAL_END]/g' \
          -e 's/\[gcode_macro _LOAD_MATERIAL\]/[gcode_macro LOAD_MATERIAL]/g' \
          -e 's/\[gcode_macro _QUIT_MATERIAL_HEATING\]/[gcode_macro QUIT_MATERIAL_HEATING]/g' \
          -e 's/\[gcode_macro _QUIT_MATERIAL_CUT_MATERIAL\]/[gcode_macro QUIT_MATERIAL_CUT_MATERIAL]/g' \
          -e 's/\[gcode_macro _QUIT_MATERIAL_RETRUDE_MATERIAL\]/[gcode_macro QUIT_MATERIAL_RETRUDE_MATERIAL]/g' \
          -e 's/\[gcode_macro _QUIT_MATERIAL_END\]/[gcode_macro QUIT_MATERIAL_END]/g' \
          -e 's/\[gcode_macro _QUIT_MATERIAL\]/[gcode_macro QUIT_MATERIAL]/g' \
          -e 's/\[gcode_macro _Qmode\]/[gcode_macro Qmode]/g' \
          -e "s/gcode_macro _Qmode'/gcode_macro Qmode'/g" \
          -e 's/MACRO=_Qmode/MACRO=Qmode/g' \
          -e 's/\[gcode_macro _Qmode_exit\]/[gcode_macro Qmode_exit]/g' \
          -e 's/\[gcode_macro _M205\]/[gcode_macro M205]/g' \
          -e 's/\[gcode_macro _M106\]/[gcode_macro M106]/g' \
          -e 's/\[gcode_macro _M107\]/[gcode_macro M107]/g' \
          -e 's/\[gcode_macro _M900\]/[gcode_macro M900]/g' \
          -e 's/\[gcode_macro _WAIT_TEMP_START\]/[gcode_macro WAIT_TEMP_START]/g' \
          -e 's/\[gcode_macro _WAIT_TEMP_END\]/[gcode_macro WAIT_TEMP_END]/g' \
          -e 's/\[gcode_macro _PRINT_CALIBRATION\]/[gcode_macro PRINT_CALIBRATION]/g' \
          -e 's/\[gcode_macro _FIRST_FLOOR_PAUSE_POSITION\]/[gcode_macro FIRST_FLOOR_PAUSE_POSITION]/g' \
          -e 's/\[gcode_macro _PRINT_TEMP_SET\]/[gcode_macro PRINT_TEMP_SET]/g' \
          -e 's/\[gcode_macro _ZDOWN_SWITCH_SET\]/[gcode_macro ZDOWN_SWITCH_SET]/g' \
          -e 's/\[gcode_macro _PRINT_PREPARED\]/[gcode_macro PRINT_PREPARED]/g' \
          -e 's/\[gcode_macro _PRINT_PREPARE_CLEAR\]/[gcode_macro PRINT_PREPARE_CLEAR]/g' \
          -e 's/\[gcode_macro _END_PRINT_POINT_WITHOUT_LIFTING\]/[gcode_macro END_PRINT_POINT_WITHOUT_LIFTING]/g' \
          -e 's/\[gcode_macro _END_PRINT_Z_SAFE\]/[gcode_macro END_PRINT_Z_SAFE]/g' \
          -e 's/\[gcode_macro _END_PRINT_POINT\]/[gcode_macro END_PRINT_POINT]/g' \
          -e 's/\[gcode_macro _FIRST_FLOOR_PAUSE\]/[gcode_macro FIRST_FLOOR_PAUSE]/g' \
          -e 's/\[gcode_macro _FIRST_FLOOR_RESUME\]/[gcode_macro FIRST_FLOOR_RESUME]/g' \
          -e 's/\[gcode_macro _PAUSE_EXTERNAL\]/[gcode_macro PAUSE_EXTERNAL]/g' \
          -e 's/\[gcode_macro _RESUME_EXTERNAL_PROCESS\]/[gcode_macro RESUME_EXTERNAL_PROCESS]/g' \
          -e 's/\[gcode_macro _RESUME_EXTERNAL\]/[gcode_macro RESUME_EXTERNAL]/g' \
          -e 's/\[gcode_macro _MOTOR_CANCEL_PRINT\]/[gcode_macro MOTOR_CANCEL_PRINT]/g' \
          -e 's/\[gcode_macro _BED_MANUAL_CAL_START\]/[gcode_macro BED_MANUAL_CAL_START]/g' \
          -e 's/\[gcode_macro _BED_MANUAL_CAL_END\]/[gcode_macro BED_MANUAL_CAL_END]/g' \
          -e 's/\[gcode_macro _BED_MESH_CALIBRATE_START_PRINT\]/[gcode_macro BED_MESH_CALIBRATE_START_PRINT]/g' \
          -e 's/\[gcode_macro _CANCEL_CHAMBER_FAN_SWITCH\]/[gcode_macro CANCEL_CHAMBER_FAN_SWITCH]/g' \
          -e 's/\[gcode_macro _INPUTSHAPER\]/[gcode_macro INPUTSHAPER]/g' \
          -e 's/\[gcode_macro _BEDPID\]/[gcode_macro BEDPID]/g' \
          -e 's/\[gcode_macro _NOZZLE_PID\]/[gcode_macro NOZZLE_PID]/g' \
          -e 's/\[gcode_macro _NOZZLE_PID_HIGH\]/[gcode_macro NOZZLE_PID_HIGH]/g' \
          -e 's/\[gcode_macro _TUNOFFINPUTSHAPER\]/[gcode_macro TUNOFFINPUTSHAPER]/g' \
          -e 's/    _PRINT_PREPARE_CLEAR/    PRINT_PREPARE_CLEAR/g' \
          -e 's/  _END_PRINT_Z_SAFE/  END_PRINT_Z_SAFE/g' \
          -e 's/  _QMODE_EXIT/  QMODE_EXIT/g' \
          -e 's/  _PRINT_PREPARE_CLEAR/  PRINT_PREPARE_CLEAR/g' \
          -e 's/  _END_PRINT_POINT/  END_PRINT_POINT/g' \
          -e 's/  _WAIT_TEMP_START/  WAIT_TEMP_START/g' \
          -e 's/M140 S{params\.BED_TEMP}/M140 S{BED_TEMP}/g' \
          -e 's/M104 S{params\.EXTRUDER_TEMP}/M104 S{EXTRUDER_TEMP}/g' \
          -e 's/M190 S{params\.BED_TEMP}/M190 S{BED_TEMP}/g' \
          -e 's/M109 S{params\.EXTRUDER_TEMP}/M109 S{EXTRUDER_TEMP}/g' \
          "$macro_cfg"
        log_success "Patched gcode_macro.cfg"
    fi

    local printer_cfg="$CONFIG_DIR/printer.cfg"
    if [ -f "$printer_cfg" ]; then
        sed -i 's/mesh_min: 5,5/mesh_min: 20,20/' "$printer_cfg"
        log_success "Patched printer.cfg mesh_min"
    fi

    # Restore motor_control.cfg from stock if it has been truncated/modified.
    # A stripped-down motor_control.cfg (missing the PID/protection/LESO
    # tuning block, e.g. x_protection_param_prt_track_max_err) makes the
    # closed-loop X stepper far more sensitive to position-tracking errors,
    # causing key789 stalls during the CFS cut-position move (CR_BOX_CUT).
    # The stock file is taken from this model's directory in /rom (see
    # stock_config_dir), so K2 / K2 Pro / K2 Plus each get their own tuning.
    local motor_cfg="$CONFIG_DIR/motor_control.cfg"
    local stock_dir
    stock_dir=$(stock_config_dir)
    if [ -z "$stock_dir" ]; then
        log_info "Stock config dir for this model not found in /rom, skipping motor_control.cfg check."
        return 0
    fi
    local stock_motor_cfg="$stock_dir/motor_control.cfg"
    if [ -f "$motor_cfg" ] && [ -f "$stock_motor_cfg" ]; then
        if ! diff -q "$stock_motor_cfg" "$motor_cfg" > /dev/null 2>&1; then
            cp "$motor_cfg" "${motor_cfg}.before_patch" 2>/dev/null
            cp "$stock_motor_cfg" "$motor_cfg"
            log_success "Restored motor_control.cfg from stock (was truncated/modified - this caused X-axis tracking errors during CFS cuts)"
        else
            log_info "motor_control.cfg already matches stock."
        fi
    fi
}

# Add-ons that live partly outside /mnt/UDISK: KAMP-K2 (restore_bed_mesh.py in
# Klipper's extras + gcode_macro.cfg patches) and Gcode Shell Command. A firmware
# update can undo them, after which Klipper refuses to start on the unknown
# config sections. Re-apply here.
# $1 = "boot" when called from rc.local: only then is Klipper restarted, never
# from the menu (a print may be running).
ensure_addons() {
    local changed=0
    if is_installed "gcode_shell_command"; then
        sh "$SCRIPT_DIR/scripts/shell_command.sh" ensure
        [ $? -eq 2 ] && changed=1
    fi
    if is_installed "kamp"; then
        sh "$SCRIPT_DIR/scripts/kamp.sh" ensure
        [ $? -eq 2 ] && changed=1
        detect_printer
        if python3 "$SCRIPT_DIR/scripts/kamp_k2_patch.py" install "$CONFIG_DIR" "$PRINTER_MODEL" | grep -q "^CHANGED$"; then
            changed=1
            log_success "Re-applied KAMP-K2 config patches"
        fi
    fi
    if [ "$changed" = 1 ]; then
        if [ "$1" = "boot" ]; then
            restart_klipper force
        else
            log_warn "Add-on files were re-applied - restart Klipper to load them."
        fi
    fi
}


# ── rc.local patch (ensure patch_stock_configs runs on every boot) ────────────

install_rc_local_patch() {
    local rc_local="/etc/rc.local"
    if grep -q "patch_stock_configs" "$rc_local" 2>/dev/null; then
        log_info "rc.local patch already installed."
    else
        sed -i 's|exit 0|# Patch stock Klipper configs\n/bin/sh /mnt/UDISK/helper-script/scripts/system.sh patch_stock_configs boot\n\nexit 0|' "$rc_local"
        log_success "Added patch_stock_configs to rc.local"
    fi

    if grep -q "install_moonraker_include" "$rc_local" 2>/dev/null; then
        log_info "moonraker include rc.local patch already installed."
    else
        sed -i 's|exit 0|# Ensure Moonraker loads UDISK extension config\n/bin/sh /mnt/UDISK/helper-script/scripts/system.sh install_moonraker_include\n\nexit 0|' "$rc_local"
        log_success "Added install_moonraker_include to rc.local"
    fi
}

# ── Moonraker include fix (ensure UDISK moonraker.conf is actually loaded) ────

install_moonraker_include() {
    local real_conf="/usr/share/moonraker/moonraker.conf"
    local udisk_conf="$CONFIG_DIR/moonraker.conf"
    local include_line="[include $udisk_conf]"

    if [ ! -f "$real_conf" ]; then
        log_info "Moonraker base config not found at $real_conf, skipping."
        return 0
    fi

    if [ ! -f "$udisk_conf" ]; then
        log_info "No UDISK moonraker.conf found, skipping include fix."
        return 0
    fi

    # Remove any stale/incorrect include in the UDISK file pointing back at
    # the real config -- this causes a recursive include loop.
    if grep -q "\[include $real_conf\]" "$udisk_conf" 2>/dev/null; then
        sed -i "\|\[include $real_conf\]|d" "$udisk_conf"
        log_info "Removed recursive include from $udisk_conf"
    fi

    if grep -qF "$include_line" "$real_conf" 2>/dev/null; then
        log_info "Moonraker include already installed."
    else
        sed -i "1i\\
$include_line
" "$real_conf"
        log_success "Added include for $udisk_conf to $real_conf"
        log_info "Without this, sections like [timelapse] and [update_manager] in $udisk_conf are silently ignored by Moonraker."
    fi

    # Queue gcode uploads so the UI waits for metadata extraction to finish
    # instead of hammering Moonraker with "Metadata not available" requests
    # and falling back to showing the slicer as "Unknown" in history.
    if grep -q "queue_gcode_uploads: False" "$real_conf" 2>/dev/null; then
        sed -i "s/queue_gcode_uploads: False/queue_gcode_uploads: True/" "$real_conf"
        log_success "Enabled queue_gcode_uploads in $real_conf"
    fi
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "$1" in
    restart_klipper)   restart_klipper ;;
    restart_moonraker) restart_moonraker ;;
    restart_nginx)     restart_nginx ;;
    restart_camera)    restart_camera ;;
    show_installed)    show_installed ;;
    update_entware)    update_entware ;;
    clear_logs_cache)  clear_logs_cache ;;
    system_info)       system_info ;;
    patch_stock_configs) patch_stock_configs; ensure_addons "$2" ;;
    install_rc_local_patch) install_rc_local_patch ;;
    install_moonraker_include) install_moonraker_include ;;
esac
