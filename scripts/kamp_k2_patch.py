#!/usr/bin/env python3
# kamp_k2_patch.py - Patch stock K2 configs for KAMP-K2 adaptive meshing
#
# Port of the config patching done by grant0013/KAMP-K2 (install_k2.py, GPL-3.0)
# so it runs on the printer itself. See https://github.com/grant0013/KAMP-K2
#
#   python3 kamp_k2_patch.py install <config_dir> <model>
#   python3 kamp_k2_patch.py remove  <config_dir>
#
# Idempotent: re-running "install" changes nothing once applied. Prints
# "CHANGED" as the last line when any file was modified.
#
# What "install" does:
#   printer.cfg      - ensures [exclude_object], [restore_bed_mesh] and
#                      [include KAMP/KAMP_Settings.cfg]; on the K2 Plus also
#                      sets forced_leveling: false (conflicts with the override)
#   gcode_macro.cfg  - replaces G29 and BED_MESH_CALIBRATE_START_PRINT (fired by
#                      Creality's master-server before every print) with no-ops
#                      that print the [G29_TIME] line master-server waits for,
#                      and inserts the real (adaptive) mesh into START_PRINT

import os
import re
import sys

SAVE_CONFIG_MARKER = "#*# <---------------------- SAVE_CONFIG"
KAMP_INCLUDE = "[include KAMP/KAMP_Settings.cfg]"
FORCED_LEVELING_NOTE = "# patched by helper script for KAMP-K2 (was true)"
MESH_MARKER = "# KAMP-K2: adaptive mesh"

G29_HIJACK = """[gcode_macro G29]
description: Hijacked by KAMP-K2 - defers mesh to START_PRINT (adaptive). Emits fake [G29_TIME] so master-server is satisfied.
gcode:
  {% set bed_temp = params.BED_TEMP|default(0)|float %}
  {% if bed_temp > 0 %}
    M140 S{bed_temp}
  {% endif %}
  {% if "xy" not in printer.toolhead.homed_axes %}
    G28 X Y
  {% endif %}
  BED_MESH_CLEAR
  M118 G29 deferred: real mesh runs in START_PRINT (KAMP adaptive)
  M118 [G29_TIME]Execution time: 0.0 seconds, Time spent at each point: 0.0
"""

BMCSP_HIJACK = """[gcode_macro BED_MESH_CALIBRATE_START_PRINT]
description: Hijacked by KAMP-K2 - defers mesh to START_PRINT (adaptive). Emits fake [G29_TIME] so master-server is satisfied.
gcode:
  BED_MESH_CLEAR
  M118 BED_MESH_CALIBRATE_START_PRINT deferred (KAMP adaptive in START_PRINT)
  M118 [G29_TIME]Execution time: 0.0 seconds, Time spent at each point: 0.0
"""

START_PRINT_MESH_BLOCK = """  """ + MESH_MARKER + """. BED_MESH_CALIBRATE is wrapped by KAMP and
  # reads exclude_object metadata from the loaded gcode to size the probe
  # to just the print area. Pass MESH=0 from the slicer to skip it.
  {% if params.MESH|default(1)|int == 1 %}
    BED_MESH_CLEAR
    BED_MESH_CALIBRATE
  {% else %}
    M118 Mesh skipped (MESH=0 from slicer)
  {% endif %}
"""


# Stock configs contain Chinese UTF-8 comments; surrogateescape round-trips
# any byte unchanged regardless of the printer's locale
def read(path):
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:
        return f.read()


def write(path, content):
    with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
        f.write(content)


def info(msg):
    print("  " + msg)


def macro_block_re(name):
    # Header of an active macro section up to the next section header,
    # SAVE_CONFIG block or end of file. Matches an optional "_" prefix
    # because system.sh only drops it on its next run.
    return re.compile(
        r"^\[gcode_macro\s+_?" + re.escape(name) + r"\s*\].*?(?=^\[|^#\*#|\Z)",
        re.M | re.S)


def hijack_macro(content, name, replacement):
    """Replace macro `name` with `replacement` (active, commented-out or absent)."""
    block = macro_block_re(name)
    m = block.search(content)
    if m and "Hijacked by KAMP-K2" in m.group(0):
        return content, False
    if m:
        return block.sub(lambda m: replacement + "\n", content, count=1), True
    commented = re.compile(r"^#\s*\[gcode_macro\s+_?" + re.escape(name) + r"\s*\]", re.M)
    m = commented.search(content)
    if m:
        # Stock K2 Pro ships "# [gcode_macro G29]": add an active block above it
        return content[:m.start()] + replacement + "\n" + content[m.start():], True
    return content.rstrip("\n") + "\n\n" + replacement, True


def insert_start_print_mesh(content):
    block = macro_block_re("START_PRINT").search(content)
    if not block:
        info("WARNING: [gcode_macro START_PRINT] not found in gcode_macro.cfg - add the mesh manually.")
        return content, False
    body = block.group(0)
    new_body = body

    # Older KAMP installers put LINE_PURGE inside START_PRINT; on CFS printers
    # it then fires before T<n> loads filament. It belongs in the slicer.
    new_body = re.sub(r"^[ \t]*LINE_PURGE[ \t]*(#.*)?\r?\n", "", new_body, flags=re.M)

    already = MESH_MARKER in new_body or re.search(
        r"^\s*BED_MESH_CALIBRATE\s*(#.*)?$", new_body, re.M)
    if not already:
        # Right after the {% endif %} closing the "prepare" branch. With the
        # BED_MESH_CALIBRATE_START_PRINT hijack, prepare stays 0, so START_PRINT
        # always runs the full branch first (heat, G28, NOZZLE_CLEAR, G28 Z):
        # the mesh then runs homed and hot. What follows the endif differs per
        # model (M140 on the K2 Plus, M104 on the K2), so don't anchor on it.
        anchor = re.compile(
            r"(\{% else %\}[ \t]*\r?\n[ \t]*_?PRINT_PREPARE_CLEAR[ \t]*\r?\n[ \t]*\{% endif %\}[ \t]*\r?\n)")
        if not anchor.search(new_body):
            # Guessing a spot could mesh before homing - leave it to the user
            info("WARNING: START_PRINT differs from the known stock layout; mesh NOT added.")
            info("         Add BED_MESH_CLEAR + BED_MESH_CALIBRATE to START_PRINT after homing,")
            info("         or put them in the slicer start G-code after START_PRINT.")
            return content, False
        new_body = anchor.sub(lambda m: m.group(1) + "\n" + START_PRINT_MESH_BLOCK + "\n",
                              new_body, count=1)

    if new_body == body:
        return content, False
    return content[:block.start()] + new_body + content[block.end():], True


def loaded_config_files(config_dir):
    """printer.cfg and its [include] tree - not every *.cfg in the folder
    (SAVE_CONFIG backups like printer-<date>.cfg would fake sections)."""
    import glob
    queue, seen = [os.path.join(config_dir, "printer.cfg")], []
    while queue:
        path = os.path.normpath(queue.pop(0))
        if path in seen or not os.path.isfile(path):
            continue
        seen.append(path)
        for inc in re.findall(r"^\[include\s+([^\]]+)\]", read(path), re.M):
            queue.extend(sorted(glob.glob(os.path.join(os.path.dirname(path), inc.strip()))))
    return seen


def config_has_section(config_dir, section):
    pattern = re.compile(r"^\[" + re.escape(section) + r"\]", re.M)
    return any(pattern.search(read(path)) for path in loaded_config_files(config_dir))


def insert_before_save_config(content, text):
    idx = content.find(SAVE_CONFIG_MARKER)
    if idx == -1:
        return content.rstrip("\n") + "\n\n" + text + "\n"
    return content[:idx] + text + "\n\n" + content[idx:]


def patch_printer_cfg(config_dir, model):
    path = os.path.join(config_dir, "printer.cfg")
    content = original = read(path)

    lines = []
    if not config_has_section(config_dir, "exclude_object"):
        lines.append("[exclude_object]")
    if not re.search(r"^\[restore_bed_mesh\]", content, re.M):
        lines.append("[restore_bed_mesh]")
    if lines:
        info("printer.cfg: adding " + ", ".join(lines))
        # Keep everything right next to the KAMP include if one already exists
        inc = content.find(KAMP_INCLUDE)
        if inc != -1:
            content = content[:inc] + "\n".join(lines) + "\n" + content[inc:]
        else:
            content = insert_before_save_config(content, "\n".join(lines))
    if KAMP_INCLUDE not in content:
        info("printer.cfg: adding " + KAMP_INCLUDE)
        content = insert_before_save_config(content, KAMP_INCLUDE)

    if model == "K2 Plus":
        content, n = re.subn(r"^(\s*)forced_leveling\s*:\s*true\b.*$",
                             r"\1forced_leveling: false  " + FORCED_LEVELING_NOTE,
                             content, flags=re.M | re.I)
        if n:
            info("printer.cfg: forced_leveling set to false (K2 Plus)")

    if content != original:
        write(path, content)
        return True
    return False


def patch_gcode_macro_cfg(config_dir):
    path = os.path.join(config_dir, "gcode_macro.cfg")
    if not os.path.exists(path):
        info("WARNING: gcode_macro.cfg not found, skipping macro hijacks.")
        return False
    content = original = read(path)

    backup = path + ".pre_kamp"
    if not os.path.exists(backup):
        write(backup, original)
        info("Backed up gcode_macro.cfg to gcode_macro.cfg.pre_kamp")

    content, changed = hijack_macro(content, "G29", G29_HIJACK)
    if changed:
        info("gcode_macro.cfg: G29 now defers the mesh to START_PRINT")
    content, changed = hijack_macro(content, "BED_MESH_CALIBRATE_START_PRINT", BMCSP_HIJACK)
    if changed:
        info("gcode_macro.cfg: BED_MESH_CALIBRATE_START_PRINT now defers the mesh to START_PRINT")
    content, changed = insert_start_print_mesh(content)
    if changed:
        info("gcode_macro.cfg: adaptive mesh added to START_PRINT")

    if content != original:
        write(path, content)
        return True
    return False


def install(config_dir, model):
    changed = patch_printer_cfg(config_dir, model)
    changed = patch_gcode_macro_cfg(config_dir) or changed
    if changed:
        print("CHANGED")


def remove(config_dir):
    changed = False
    path = os.path.join(config_dir, "printer.cfg")
    content = original = read(path)
    # Also drop the blank line insert_before_save_config() added after each
    content = re.sub(r"^\[restore_bed_mesh\][ \t]*\n\n?", "", content, flags=re.M)
    content = re.sub(r"^" + re.escape(KAMP_INCLUDE) + r"[ \t]*\n\n?", "", content, flags=re.M)
    content = re.sub(r"^(\s*)forced_leveling: false\s+" + re.escape(FORCED_LEVELING_NOTE),
                     r"\1forced_leveling: true", content, flags=re.M)
    if content != original:
        write(path, content)
        info("printer.cfg: removed KAMP-K2 sections")
        changed = True

    macro = os.path.join(config_dir, "gcode_macro.cfg")
    backup = macro + ".pre_kamp"
    if os.path.exists(backup):
        os.replace(backup, macro)
        info("gcode_macro.cfg: restored from gcode_macro.cfg.pre_kamp")
        changed = True
    else:
        info("WARNING: no gcode_macro.cfg.pre_kamp backup; G29 / START_PRINT changes left in place.")
    if changed:
        print("CHANGED")


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "install":
        install(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 3 and sys.argv[1] == "remove":
        remove(sys.argv[2])
    else:
        print(__doc__ or "usage: kamp_k2_patch.py install <config_dir> <model> | remove <config_dir>")
        sys.exit(1)
