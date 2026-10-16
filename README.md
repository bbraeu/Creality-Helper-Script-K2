# Creality K2 - Helper Script

A menu-driven helper script for the **Creality K2** (base model, 260 × 260 mm) and **K2 Combo (with CFS)**.
It also works on the K2 Pro and K2 Plus: the script reads the hardware from your stock `printer.cfg`
(bed size, chamber heater, chamber fan / sensor, fans, Z-tilt) instead of assuming one model.

Forked from [sw3defy's K2 Plus Helper Script](https://github.com/sw3defy/Creality-Helper-Script-K2-Plus), which is based on the excellent [Guilouz Creality Helper Script](https://github.com/Guilouz/Creality-Helper-Script).

## Wiki & Documentation

**[https://bbraeu.github.io/Creality-Helper-Script-Wiki-K2-Base/](https://bbraeu.github.io/Creality-Helper-Script-Wiki-K2-Base/)**

## Installation

Connect to your K2 via SSH (user `root`, password `creality_2024`), then run:

```sh
python3 -c "import urllib.request; urllib.request.urlretrieve('https://github.com/bbraeu/Creality-Helper-Script-K2-Base/archive/refs/heads/main.zip', '/tmp/helper.zip')"
python3 -c "import shutil; shutil.unpack_archive('/tmp/helper.zip', '/tmp/')"
mkdir -p /mnt/UDISK/helper-script
cp -r /tmp/Creality-Helper-Script-K2-Base-main/* /mnt/UDISK/helper-script/
chmod +x /mnt/UDISK/helper-script/helper.sh
sh /mnt/UDISK/helper-script/helper.sh
```

The menu header shows what was detected, e.g. `Detected: K2 (no chamber heater, bed mesh 20,20 to 255,255)`.

## Features

| Option | Feature |
|--------|---------|
| 1 | Moonraker Extensions & Update Manager |
| 2 | Fans Control Macros |
| 3 | Useful Macros (PID, bed leveling, warmup, chamber status) |
| 4 | Save Z-Offset Macros |
| 5 | M600 Filament Change Support |
| 6 | KAMP-K2 (Klipper Adaptive Meshing & Purging, K2 port) |
| 7 | Improved Shapers Calibrations |
| 8 | Fluidd (install/update/repair - port 4408) |
| 9 | Mainsail (install/update/repair - port 4409) |
| 10 | Moonraker Timelapse |
| 11 | Camera Support for Fluidd, Mainsail and Mobileraker (WebRTC + optional MJPEG via go2rtc) |
| 12 | HelixScreen (modern touchscreen UI) |
| 13 | Entware Package Manager |
| 14 | OctoEverywhere |
| 15 | Mobileraker Companion |
| 16 | OctoApp Companion |
| 17 | Git Backup |
| 18 | Klipper Gcode Shell Command |
| 20-23 | Backup / restore Klipper configuration and Moonraker database |
| 24-32 | Tools: restarts, logs, Entware update, clear logs & cache, system information |

## K2 (base) differences

| | K2 | K2 Pro | K2 Plus |
|---|---|---|---|
| Build volume | 260 × 260 × 260 mm | 300 × 300 × 300 mm | 350 × 350 × 350 mm |
| Chamber heater | **no** | yes | yes |

On a K2 without a chamber heater, `CHAMBER_HEAT` and `PID_CHAMBER` are not installed;
`CHAMBER_STATUS` / `CHAMBER_COOL` are only installed for the chamber sensor / fan your
`printer.cfg` actually defines. `WARMUP` moves stay inside the `[bed_mesh]` area (the K2's travel
limits reach past the bed), and fan macros respect the pins' `scale: 255`.

Detection was checked against Creality's published K2 config
([CrealityOfficial/K2_Series_Klipper](https://github.com/CrealityOfficial/K2_Series_Klipper), `F021_CR0CN200400C10`).

## KAMP on the K2

Plain upstream KAMP does not work on the K2: Creality's `prtouch_v3` replaces
`BED_MESH_CALIBRATE` with a handler that ignores the adaptive mesh bounds, and the
`master-server` daemon runs its own full mesh before every print. Option 6 installs
[KAMP-K2](https://github.com/grant0013/KAMP-K2), which restores Klipper's mesh handler,
defers the master-server mesh and runs the adaptive mesh inside `START_PRINT`.
Put `LINE_PURGE` in your slicer start G-code after `T[initial_no_support_extruder]`
(see the wiki for the full OrcaSlicer start G-code).

## Requirements

- Creality K2 / K2 Combo (also K2 Pro, K2 Plus)
- Root SSH access enabled
- SSH client (e.g. PuTTY on Windows)
- Entware (option 13) for OctoEverywhere, Mobileraker Companion, OctoApp and Git Backup

## Credits

- [sw3defy](https://github.com/sw3defy/Creality-Helper-Script-K2-Plus) - K2 Plus Helper Script this fork is based on
- [Guilouz](https://github.com/Guilouz) - Original Creality Helper Script for K1 Series
- [grant0013/KAMP-K2](https://github.com/grant0013/KAMP-K2) - KAMP port for the K2 (GPL-3.0)
- [DnG-Crafts](https://github.com/DnG-Crafts/K2-Camera) - K2 camera WebRTC discovery
- [vsevolod-volkov](https://github.com/vsevolod-volkov/K2Plus-entware) - Entware on K2 (wget shim solution)
- [AlexxIT/go2rtc](https://github.com/AlexxIT/go2rtc) - Stream conversion software
- [Arksine](https://github.com/Arksine) - gcode_shell_command.py
- [Clon1998/mobileraker_companion](https://github.com/Clon1998/mobileraker_companion) - Mobileraker Companion
- [prestonbrown/HelixScreen](https://github.com/prestonbrown/helixscreen) - Modern touchscreen UI for Klipper
- [Klipper](https://www.klipper3d.org), [Moonraker](https://moonraker.readthedocs.io), [Fluidd](https://docs.fluidd.xyz), [Mainsail](https://docs.mainsail.xyz)
- [KAMP](https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging) - Adaptive meshing
