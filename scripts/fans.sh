#!/bin/sh
# fans.sh - Install/remove Fans Control Macros for K2

SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"

FANS_CFG=$CONFIG_DIR/fans_control.cfg

install_fans() {

    if is_installed "fans_control_macros"; then
        log_info "Fans Control Macros is already installed."
        echo ""
        printf "  Reinstall? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0
    fi
    echo ""
    log_info "Installing Fans Control Macros..."
    echo ""

    detect_printer
    log_info "Detected: $(printer_summary)"

    # fan0 = part cooling, fan2 = aux. Only reference pins this printer has.
    local fan2_save="" fan2_restore="" fan2_off="" fan0_en=""
    if [ "$HAS_FAN2" = 1 ]; then
        fan2_save="  SET_GCODE_VARIABLE MACRO=SAVE_FANS VARIABLE=fan2_speed VALUE={printer['output_pin fan2'].value}"
        fan2_restore="  SET_FAN2 S={( s.fan2_speed * 255 )|int}"
        fan2_off="  SET_FAN2 S=0"
    fi
    [ "$HAS_FAN0_EN" = 1 ] && fan0_en="  SET_PIN PIN=fan0_en VALUE={% if speed > 0 %}1{% else %}0{% endif %}"

    cat > "$FANS_CFG" << EOF
# Fans Control Macros — $(printer_summary)
# Managed by Creality Helper Script (generated from the detected printer.cfg)
# Part cooling: fan0 | Aux fan: $([ "$HAS_FAN2" = 1 ] && echo fan2 || echo none) | Chamber fan: ${CHAMBER_FAN:-none}
# Chamber heater: ${CHAMBER_HEATER:-none}

# ── Save / Restore fan state ──────────────────────────────────────────────────

[gcode_macro SAVE_FANS]
description: Save current fan speeds
variable_fan0_speed: 0
variable_fan2_speed: 0
gcode:
  SET_GCODE_VARIABLE MACRO=SAVE_FANS VARIABLE=fan0_speed VALUE={printer['output_pin fan0'].value}
${fan2_save}

[gcode_macro RESTORE_FANS]
description: Restore previously saved fan speeds
gcode:
  {% set s = printer['gcode_macro SAVE_FANS'] %}
  SET_FAN0 S={( s.fan0_speed * 255 )|int}
${fan2_restore}

# ── Part cooling fan (fan0) ───────────────────────────────────────────────────

[gcode_macro SET_FAN0]
description: Set part cooling fan speed. S=0-255
gcode:
  {% set speed = params.S|default(0)|int %}
  {% set pwm = (speed / 255.0 * ${FAN0_SCALE})|round(4) %}
${fan0_en}
  SET_PIN PIN=fan0 VALUE={pwm}
EOF

    if [ "$HAS_FAN2" = 1 ]; then
        cat >> "$FANS_CFG" << EOF

# ── Aux fan (fan2) ────────────────────────────────────────────────────────────

[gcode_macro SET_FAN2]
description: Set aux fan speed. S=0-255
gcode:
  {% set speed = params.S|default(0)|int %}
  {% set pwm = (speed / 255.0 * ${FAN2_SCALE})|round(4) %}
  SET_PIN PIN=fan2 VALUE={pwm}
EOF
    fi

    cat >> "$FANS_CFG" << EOF

# ── Turn off all output fans ──────────────────────────────────────────────────

[gcode_macro FANS_OFF]
description: Turn off all output fans (does not affect hotend_fan auto-control)
gcode:
  SET_FAN0 S=0
${fan2_off}
EOF

    write_chamber_macros "$FANS_CFG"

    add_include_to_printer_cfg "fans_control.cfg"
    restart_klipper force

    mark_installed "fans_control_macros"
    echo ""
    log_success "Fans Control Macros installed!"
    echo ""
    local fan_macros="SET_FAN0, FANS_OFF, SAVE_FANS, RESTORE_FANS"
    [ "$HAS_FAN2" = 1 ] && fan_macros="SET_FAN0, SET_FAN2, FANS_OFF, SAVE_FANS, RESTORE_FANS"
    log_info "Available macros: $fan_macros"
    [ -n "$(chamber_macro_names)" ] && log_info "Chamber macros:   $(chamber_macro_names)"
    echo ""
}

remove_fans() {
    if ! is_installed "fans_control_macros"; then
        log_info "Fans Control Macros is not installed."
        return 0
    fi

    echo -e "${YELLOW}WARNING: This will remove Fans Control Macros.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    echo ""
    log_info "Removing Fans Control Macros..."
    remove_include_from_printer_cfg "fans_control.cfg"
    rm -f "$FANS_CFG"
    restart_klipper force
    mark_removed "fans_control_macros"
    log_success "Fans Control Macros removed."
    echo ""
}

case "$1" in
    install) install_fans ;;
    remove)  remove_fans ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
