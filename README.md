# Creality K2 - Helper Script

A menu-driven helper script for the **Creality K2 series**: K2 / K2 Combo (with CFS), K2 Pro and K2 Plus.
The script reads the hardware from your stock `printer.cfg` (bed size, chamber heater, chamber fan / sensor,
fans, Z-tilt) instead of assuming one model.

Forked from [sw3defy's K2 Plus Helper Script](https://github.com/sw3defy/Creality-Helper-Script-K2-Plus), which is based on the excellent [Guilouz Creality Helper Script](https://github.com/Guilouz/Creality-Helper-Script).

## Wiki & Documentation

**[https://bbraeu.github.io/Creality-Helper-Script-Wiki-K2/](https://bbraeu.github.io/Creality-Helper-Script-Wiki-K2/)**

## Installation

Connect to your K2 via SSH (user `root`, password `creality_2024`), then run:

```sh
python3 -c "import urllib.request; urllib.request.urlretrieve('https://github.com/bbraeu/Creality-Helper-Script-K2/archive/refs/heads/main.zip', '/tmp/helper.zip')"
python3 -c "import shutil; shutil.unpack_archive('/tmp/helper.zip', '/tmp/')"
mkdir -p /mnt/UDISK/helper-script
cp -r /tmp/Creality-Helper-Script-K2-main/* /mnt/UDISK/helper-script/
chmod +x /mnt/UDISK/helper-script/helper.sh
sh /mnt/UDISK/helper-script/helper.sh
```

The menu header shows what was detected, e.g. `Detected: K2 (no chamber heater, bed mesh 20,20 to 255,255)`.

## Updating

The helper updates itself from **GitHub releases** (`vMAJOR.MINOR.PATCH`, no drafts or
pre-releases) - not from every commit. The installed release is stored in
`/mnt/UDISK/helper-script/.version`; on every start `helper.sh` compares it with the
newest release, shows its release notes and offers the update (Enter = yes).
You can also update from the menu (Tools → 34) or non-interactively over SSH:

```sh
sh /mnt/UDISK/helper-script/helper.sh --update
```

Only the script files are replaced. Your installed features, `go2rtc.yaml`, backups
and other generated files are kept. Set `HELPER_SKIP_UPDATE=1` to skip the check
(e.g. without internet). Features whose generated config changed (macros, camera)
pick up the change when you reinstall them from the menu.

With the updatable Moonraker (option 1 -> 2) the helper also appears in Fluidd /
Mainsail *Software Updates* (`channel: stable`, i.e. the same releases).

Releasing a new version: tag the commit `vX.Y.Z` and publish a GitHub release for it;
its release notes are what the update prompt shows.

## Features

| Option | Feature |
|--------|---------|
| 1 | Moonraker: extensions for Creality's Moonraker, or an **updatable upstream Moonraker** (Software Updates in Fluidd/Mainsail) |
| 2 | Fans Control Macros |
| 3 | Useful Macros (PID, bed leveling, warmup, chamber status) |
| 4 | Save Z-Offset Macros |
| 5 | M600 Filament Change Support |
| 6 | KAMP-K2 (Klipper Adaptive Meshing & Purging, K2 port) |
| 7 | Improved Shapers Calibrations |
| 8 | Fluidd (install/update/repair - port 4408). With Creality's Moonraker it installs v1.36.4, the newest version whose config editor works there |
| 9 | Mainsail (install/update/repair - port 4409) |
| 10 | Moonraker Timelapse |
| 11 | Camera Support for Fluidd, Mainsail and Mobileraker (WebRTC + optional MJPEG via go2rtc; live MJPEG needs Entware ffmpeg 5) |
| 12 | HelixScreen (modern touchscreen UI) |
| 13 | Entware Package Manager |
| 14 | OctoEverywhere |
| 15 | Mobileraker Companion |
| 16 | OctoApp Companion |
| 17 | Git Backup |
| 18 | Klipper Gcode Shell Command |
| 19 | Auto Power Off - switch the printer off with a smart plug after the print has cooled down (Kasa with network search, Tasmota, Shelly, Home Assistant) |
| 21-24 | Backup / restore Klipper configuration and Moonraker database |
| 25-34 | Tools: restarts, logs, Entware update, clear logs & cache, system information, update helper script |
| 35 | Stock config fixes: switch the optional fixes for Creality's config files on/off, restore `motor_control.cfg` from stock |

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

## Auto Power Off

Option 19 switches the printer off through a smart plug once a print has finished
and nozzle and bed are below 50 °C (configurable). Starting a print or heating up
cancels it; a cancelled print does not power off.

- **TP-Link Kasa**: the installer can search the network for Kasa plugs (it asks
  first). Classic plugs (HS100, HS110, KP105, KP115, ...) become a Moonraker
  `tplink_smartplug` device, no login needed. Newer models / firmware with the
  encrypted KLAP protocol (KP125M, EP25, ...), which Moonraker cannot switch, are
  switched locally by `scripts/kasa.py` with your TP-Link account; only a hash of
  the password is stored, in `/mnt/UDISK/helper-script/.kasa.json`. Tapo plugs
  answer the same search and work the same way.
- **Tasmota, Shelly, Home Assistant** or an existing Moonraker power device:
  added as `[power printer_plug]` to `moonraker.conf` (needs option 1).

Macros: `ACTIVATE_POWER_OFF` (power off after this print), `DEACTIVATE_POWER_OFF`,
`AUTO_POWER_OFF ENABLE=1|0` (every print; the installer sets the default).
Give the plug a fixed IP address (DHCP reservation in your router).

## Updatable Moonraker

Creality ships an old Moonraker without git, so Fluidd's *Software Updates* cannot work.
Option 1 -> 2 replaces it with the current upstream Moonraker (Entware Python 3.11 in
`/mnt/UDISK`), migrates your database and keeps Creality's Moonraker as a fallback
(Remove menu 20 -> 1 switches back). Its compiled Python packages are prebuilt by
[a GitHub workflow](.github/workflows/moonraker-wheels.yml) and published as
`moonraker-wheels-*` releases, so nothing needs to be compiled on the printer.

## Requirements

- Creality K2 / K2 Combo (also K2 Pro, K2 Plus)
- Root SSH access enabled
- SSH client (e.g. PuTTY on Windows)
- Entware (option 13) for OctoEverywhere, Mobileraker Companion, OctoApp and Git Backup

## Support

If this project saved you some time, you can buy me a coffee:

<a href="https://buymeacoffee.com/braeubernhk"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="40"></a>

## Credits

- [sw3defy](https://github.com/sw3defy/Creality-Helper-Script-K2-Plus) - K2 Plus Helper Script this fork is based on
- [Guilouz](https://github.com/Guilouz) - Original Creality Helper Script for K1 Series
- [grant0013/KAMP-K2](https://github.com/grant0013/KAMP-K2) - KAMP port for the K2 (GPL-3.0)
- [DnG-Crafts](https://github.com/DnG-Crafts/K2-Camera) - K2 camera WebRTC discovery
- [vsevolod-volkov](https://github.com/vsevolod-volkov/K2Plus-entware) - Entware on K2 (wget shim solution)
- [AlexxIT/go2rtc](https://github.com/AlexxIT/go2rtc) - Stream conversion software
- [Arksine](https://github.com/Arksine) - gcode_shell_command.py
- [tinntbg/auto-power-off-klipper](https://github.com/tinntbg/auto-power-off-klipper) - Auto power off macros
- [python-kasa](https://github.com/python-kasa/python-kasa) - Kasa protocol and discovery reference
- [Clon1998/mobileraker_companion](https://github.com/Clon1998/mobileraker_companion) - Mobileraker Companion
- [prestonbrown/HelixScreen](https://github.com/prestonbrown/helixscreen) - Modern touchscreen UI for Klipper
- [Klipper](https://www.klipper3d.org), [Moonraker](https://moonraker.readthedocs.io), [Fluidd](https://docs.fluidd.xyz), [Mainsail](https://docs.mainsail.xyz)
- [KAMP](https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging) - Adaptive meshing
