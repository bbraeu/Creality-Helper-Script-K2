#!/bin/sh
# kamp.sh - Install/remove Klipper Adaptive Meshing & Purging for K2
#
# Uses KAMP-K2 (https://github.com/grant0013/KAMP-K2, GPL-3.0), a K2 port of
# kyleisah/Klipper-Adaptive-Meshing-Purging. Plain upstream KAMP does not work
# on the K2: Creality's prtouch_v3 replaces BED_MESH_CALIBRATE with a handler
# that ignores MESH_MIN/MESH_MAX (always a full mesh, or a crash on the K2 Plus),
# and the master-server daemon runs its own full mesh before every print.
# KAMP-K2 restores Klipper's upstream handler (restore_bed_mesh.py), defers the
# master-server mesh, and runs the adaptive mesh inside START_PRINT.
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"
KAMP_DIR=$CONFIG_DIR/KAMP
KAMP_K2_REF=v1.1.0
KAMP_K2_URL=https://github.com/grant0013/KAMP-K2/archive/refs/tags/$KAMP_K2_REF.zip
KLIPPER_EXTRAS=/usr/share/klipper/klippy/extras
KAMP_FILES_DIR=$SCRIPT_DIR/files/kamp
PATCHER=$SCRIPT_DIR/scripts/kamp_k2_patch.py

install_kamp() {

    if is_installed "kamp"; then
        log_info "Kamp is already installed."
        echo ""
        printf "  Reinstall / update? [y/n]: "
        read confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0
    fi
    echo ""
    log_info "Installing Klipper Adaptive Meshing & Purging (KAMP-K2 $KAMP_K2_REF)..."
    echo ""

    if [ ! -d "$KLIPPER_EXTRAS" ]; then
        log_error "$KLIPPER_EXTRAS not found - unsupported firmware."
        return 1
    fi

    if ! is_installed "moonraker_extensions"; then
        log_warn "Moonraker Extensions not installed. Installing now (required for KAMP)..."
        sh "$SCRIPT_DIR/scripts/moonraker.sh" install
    fi

    detect_printer
    log_info "Detected: $(printer_summary)"

    # Back up the files this install modifies
    local backup_dir="$CONFIG_DIR/backups/kamp_k2_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp "$CONFIG_DIR/printer.cfg" "$backup_dir/" 2>/dev/null
    cp "$CONFIG_DIR/gcode_macro.cfg" "$backup_dir/" 2>/dev/null
    [ -d "$KAMP_DIR" ] && cp -r "$KAMP_DIR" "$backup_dir/" 2>/dev/null
    log_success "Backed up printer.cfg, gcode_macro.cfg and KAMP/ to $backup_dir"

    log_info "Downloading KAMP-K2..."
    if ! python3 - "$KAMP_K2_URL" "$KAMP_DIR" "$KAMP_FILES_DIR" << 'PYEOF'
import os, shutil, sys, urllib.request, zipfile
url, kamp_dir, files_dir = sys.argv[1:4]
urllib.request.urlretrieve(url, '/tmp/kamp_k2.zip')
shutil.rmtree('/tmp/kamp_k2_extract', ignore_errors=True)
with zipfile.ZipFile('/tmp/kamp_k2.zip') as z:
    z.extractall('/tmp/kamp_k2_extract')
src = os.path.join('/tmp/kamp_k2_extract', os.listdir('/tmp/kamp_k2_extract')[0])
os.makedirs(kamp_dir, exist_ok=True)
os.makedirs(files_dir, exist_ok=True)
# Smart_Park / Voron_Purge are not used: Creality's BOX_GO_TO_EXTRUDE_POS already parks
for name in ('KAMP_Settings.cfg', 'Adaptive_Meshing.cfg', 'Line_Purge.cfg'):
    shutil.copy(os.path.join(src, 'Configuration', name), kamp_dir)
    print('Copied: ' + name)
shutil.copy(os.path.join(src, 'extras', 'restore_bed_mesh.py'), files_dir)
shutil.rmtree('/tmp/kamp_k2_extract', ignore_errors=True)
os.remove('/tmp/kamp_k2.zip')
PYEOF
    then
        log_error "Download failed. Nothing was changed in printer.cfg."
        return 1
    fi

    # Includes resolve relative to KAMP_Settings.cfg, so ./KAMP/... would be KAMP/KAMP/...
    sed -i \
        -e 's|^#*\[include \./KAMP/Adaptive_Meshing\.cfg\]|[include Adaptive_Meshing.cfg]|' \
        -e 's|^#*\[include \./KAMP/Line_Purge\.cfg\]|[include Line_Purge.cfg]|' \
        "$KAMP_DIR/KAMP_Settings.cfg"
    # Unique rename target: some firmware already registers _BED_MESH_CALIBRATE
    sed -i \
        -e 's/rename_existing: _BED_MESH_CALIBRATE$/rename_existing: _BMC_KAMP_INNER/' \
        -e 's/^\( *\)_BED_MESH_CALIBRATE mesh_min=/\1_BMC_KAMP_INNER mesh_min=/' \
        "$KAMP_DIR/Adaptive_Meshing.cfg"

    install_restore_bed_mesh

    # Older helper versions added the KAMP include after the other includes;
    # the patcher places it (with [restore_bed_mesh]) itself
    python3 "$PATCHER" install "$CONFIG_DIR" "$PRINTER_MODEL"

    if grep -qs "^\[gcode_macro G92\]" $(cfg_loaded_files | grep -v "/KAMP/"); then
        log_warn "Another [gcode_macro G92] exists outside KAMP/. KAMP's Line_Purge.cfg defines one too -"
        log_warn "remove the other one if Klipper reports a duplicate rename_existing."
    fi

    # Ensure object processing is enabled in moonraker.conf
    if [ -f "$CONFIG_DIR/moonraker.conf" ]; then
        if ! grep -q "enable_object_processing: True" "$CONFIG_DIR/moonraker.conf"; then
            echo "" >> "$CONFIG_DIR/moonraker.conf"
            echo "[file_manager]" >> "$CONFIG_DIR/moonraker.conf"
            echo "enable_object_processing: True" >> "$CONFIG_DIR/moonraker.conf"
            restart_moonraker force
        fi
    fi

    restart_klipper force
    mark_installed "kamp"
    echo ""
    if tail -n 300 "$LOGS_DIR/klippy.log" 2>/dev/null | grep -q "bed_mesh_override: re-registered"; then
        log_success "KAMP installed - bed mesh override active."
    else
        log_success "KAMP installed!"
        log_info "Check klippy.log for 'bed_mesh_override: re-registered' once Klipper is ready."
    fi
    echo ""
    log_info "Slicer setup (OrcaSlicer):"
    echo "  1. Print Settings > Others > Output options: enable 'Label objects'"
    echo "  2. Machine start G-code (each command on its own line):"
    echo ""
    echo "     START_PRINT EXTRUDER_TEMP=[nozzle_temperature_initial_layer] BED_TEMP=[bed_temperature_initial_layer_single]"
    echo "     T[initial_no_support_extruder]"
    echo "     LINE_PURGE"
    echo "     M204 S2000"
    echo "     M83"
    echo ""
    echo "  LINE_PURGE must come after T<n> (the CFS loads filament on T<n>)."
    echo "  Add MESH=0 to the START_PRINT line to skip the mesh for a print."
    echo "  Creality Print still triggers its own full mesh - OrcaSlicer is recommended."
    echo ""
}

# Copy restore_bed_mesh.py into Klipper. A firmware update replaces
# /usr/share/klipper, so system.sh calls this again on boot.
install_restore_bed_mesh() {
    if [ ! -f "$KAMP_FILES_DIR/restore_bed_mesh.py" ]; then
        log_error "$KAMP_FILES_DIR/restore_bed_mesh.py missing - reinstall KAMP."
        return 1
    fi
    if ! cmp -s "$KAMP_FILES_DIR/restore_bed_mesh.py" "$KLIPPER_EXTRAS/restore_bed_mesh.py"; then
        cp "$KAMP_FILES_DIR/restore_bed_mesh.py" "$KLIPPER_EXTRAS/restore_bed_mesh.py"
        chmod 644 "$KLIPPER_EXTRAS/restore_bed_mesh.py"
        log_success "Installed $KLIPPER_EXTRAS/restore_bed_mesh.py"
        return 2
    fi
    return 0
}

remove_kamp() {
    if ! is_installed "kamp"; then
        log_info "Kamp is not installed."
        return 0
    fi

    echo -e "${YELLOW}WARNING: This will remove KAMP and restore gcode_macro.cfg from before the install.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }
    echo ""
    log_info "Removing KAMP..."
    python3 "$PATCHER" remove "$CONFIG_DIR"
    # Older helper versions added the include with add_include_to_printer_cfg
    remove_include_from_printer_cfg "KAMP/KAMP_Settings.cfg"
    rm -f "$KLIPPER_EXTRAS/restore_bed_mesh.py"
    rm -rf "$KAMP_DIR" "$KAMP_FILES_DIR"
    restart_klipper force
    mark_removed "kamp"
    log_success "KAMP removed."
    echo ""
}

case "$1" in
    install) install_kamp ;;
    remove)  remove_kamp ;;
    ensure)  install_restore_bed_mesh ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
