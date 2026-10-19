# Changelog

## [Unreleased]

### Changed
- **Repository renamed to `Creality-Helper-Script-K2`** (wiki:
  `Creality-Helper-Script-Wiki-K2`) - the helper is for the whole K2 series, not
  only the base model. Old GitHub links redirect; git installs switch their
  `origin` to the new URL on the next update check, so Moonraker's Software
  Updates keep recognising the helper.
- **Stock config fixes are opt-in.** The helper no longer edits `box.cfg`,
  `gcode_macro.cfg` and `printer.cfg` on every start and boot without asking
  (macro underscore renames, `params.BED_TEMP` defaults, `mesh_min 20,20`). On
  the first start it explains the fixes and asks (default: no); the answer is
  kept in `.stock_config_fixes` and can be changed in Tools -> 35. When enabled,
  a file is only written if a fix actually changes it, and the original is saved
  as `<file>.helper-<date>.bak` first.
- **`motor_control.cfg` is never replaced automatically** any more. The helper
  only warns when it differs from this model's stock file; Tools -> 35 shows the
  differences and restores it after confirmation (with a backup).

### Fixed
- **Fluidd config editor with Creality's Moonraker.** Fluidd 1.37+ cannot edit
  config files against the stock Moonraker; Install menu 8 now installs Fluidd
  v1.36.4 there and the latest Fluidd only with the updatable Moonraker.
- The Moonraker `[update_manager]` warning now points to the updatable
  Moonraker (Install menu 1 -> 2), which is what makes Software Updates work.

## [2.0.0] - 2026-10-16 - Updatable Moonraker, release-based updates

### Added
- **Updates follow GitHub releases** (`vX.Y.Z`, no drafts / pre-releases),
  not every commit: the self-update installs the newest release archive and
  shows its release notes; `.version` holds the release tag. Git checkouts
  (updatable Moonraker) fast-forward to the newest release tag, and
  Moonraker lists the helper with `channel: stable` - same rule.
- **Helper script in Moonraker's Software Updates.** With the updatable
  Moonraker, `/mnt/UDISK/helper-script` is converted in place into a git
  checkout (generated files are git-ignored) and listed as
  `[update_manager helper-script]`; the helper's own updater then uses git
  too, so both update paths agree.
- **Weekly Moonraker check** (GitHub Actions): fails and opens an issue when
  upstream Moonraker requires a newer Python than the K2's Entware 3.11;
  rebuilds the prebuilt wheels when Moonraker's requirements change.
- **Updatable Moonraker** (Install menu 1 -> 2, `scripts/moonraker_upstream.sh`).
  Creality's Moonraker (Python 3.9, no git) cannot run the update manager;
  this installs current upstream Moonraker in `/mnt/UDISK/moonraker` with an
  Entware Python 3.11 virtualenv, migrates the existing database (lmdb ->
  sqlite, the old one is kept), generates `moonraker_upstream.conf` (includes
  `moonraker.conf`, update_manager entries for Fluidd / Mainsail / Mobileraker)
  and swaps the procd service (Creality's backed up). `supervisorctl` / `sudo`
  shims map service restarts and reboot/shutdown to OpenWrt. Falls back to
  Creality's Moonraker automatically if the new one does not start; Remove
  menu 1 switches back; re-applied at boot after firmware updates.
- **Prebuilt Moonraker wheels**: `.github/workflows/moonraker-wheels.yml`
  builds the compiled dependencies in an ARMv7 container with the K2's Entware
  toolchain and publishes them as a `moonraker-wheels-<commit>` release. The
  installer uses them; on-printer builds (with a temporary swap file) are only
  the fallback - without swap they were killed by the OOM killer.
- **mjpg-streamer style webcam URLs** `/webcam/?action=stream|snapshot` on
  ports 4408 / 4409 (Mobileraker / Moonraker defaults) served by go2rtc.

### Fixed
- **Entware filled the 240 MB system partition** (Python + ffmpeg ~150 MB),
  which breaks writes to `/etc`, nginx and opkg (its package list got
  truncated). Entware now lives in `/mnt/UDISK/opt` (`/opt` is a symlink);
  existing installs are offered a move at helper start, and opkg's status file
  is rebuilt when truncated.

## [1.0.0] - 2026-10-16 - Auto Power Off

### Added
- **Auto Power Off (menu 19).** Switches the printer off with a smart plug after
  a print, once nozzle and bed have cooled down (after
  [tinntbg/auto-power-off-klipper](https://github.com/tinntbg/auto-power-off-klipper)).
  Optionally armed for every print; heating up, a new print or a cancelled print
  stop it. Macros `ACTIVATE_POWER_OFF`, `DEACTIVATE_POWER_OFF`, `AUTO_POWER_OFF`.
- **TP-Link Kasa plugs** with network search (asked first) via the new
  `scripts/kasa.py` (standard library only). Classic plugs become a Moonraker
  `tplink_smartplug` device; newer KLAP plugs (KP125M, EP25, also Tapo), which
  Moonraker cannot switch, are switched locally by `kasa.py` through
  `[gcode_shell_command]` after a login test. Tasmota, Shelly, Home Assistant
  and existing devices use Moonraker's `[power]` component.

### Changed
- Menu entries 19-33 moved to 20-34 (Remove, Backup & Restore, Tools).

## [1.0.0] - 2026-10-16 - Fluidd camera, update_manager error

### Fixed
- **Camera not shown in Fluidd.** Creality's Moonraker does not store the
  webcam `enabled` flag, so Fluidd treats every webcam as disabled; the old
  injected script only enabled the first one (now the MJPEG camera). The new
  `scripts/fluidd_camera.py` enables the WebRTC camera and leaves the MJPEG
  camera (for Mobileraker) off, so ffmpeg does not transcode whenever Fluidd
  is open. Re-applied after a Fluidd update.
- **"Moonraker has failed plugins: update_manager".** Moonraker's update
  manager cannot load on the K2's stock Moonraker (no git install, missing
  `scripts/` folder). Mobileraker Companion no longer adds
  `[update_manager mobileraker]`; existing sections are removed automatically
  at helper start / boot. Menu entry 1 is now just "Moonraker Extensions".

## [1.0.0] - 2026-10-16 - Self-update, camera fixes

### Added
- **Self-update.** `helper.sh` compares the installed commit (`.version`) with
  the latest commit on GitHub at every start, lists the new commits and offers
  the update; also Tools → 33 and `sh helper.sh --update` (non-interactive).
  Files are replaced atomically; generated files (`go2rtc.yaml`,
  `camera_watchdog.py`, `.installed`, backups) are kept.

### Fixed
- **Camera not shown without Mainsail.** Webcam URLs pointed to port 4409,
  which only exists when Mainsail is installed. They now use 4408 (stock
  Fluidd nginx, always present). Re-run Camera Support to fix existing installs.
- **MJPEG camera never streamed:** go2rtc refuses the K2's stock ffmpeg 4.3 for
  transcoding ("ffmpeg: unsupported version"). The installer now looks for
  ffmpeg >= 5, offers to install it from Entware, and otherwise registers the
  MJPEG camera in snapshot mode (`mjpegstreamer-adaptive`, ~1 fps).
- Removed the stale `go2rtc.yaml` / `camera_watchdog.py` from the repository
  (both are generated by Camera Support).

## [1.0.0] - 2026-10-16 - K2 (base) support

### Changed
- **Works on the K2 base model (and K2 Pro / K2 Plus).** `system.sh` now detects
  the hardware from the config Klipper actually loads (printer.cfg and its
  include tree, not SAVE_CONFIG backups): model (X `position_max`), usable bed
  area (`[bed_mesh]` mesh_min/max), chamber heater, chamber sensor, chamber fan,
  `fan0_en` / `fan2` and their PWM `scale`, and `z_tilt`. Checked against
  Creality's published K2 config (F021_CR0CN200400C10). The menu header shows
  the detected printer.
- Fans Control Macros / Useful Macros are generated for the detected hardware:
  no `CHAMBER_HEAT` / `PID_CHAMBER` without a chamber heater (K2 base),
  `CHAMBER_STATUS` uses whichever chamber sensor exists, `SET_FAN2` and
  `Z_TILT_*` only when present. `WARMUP` stays inside the bed mesh area (it
  drove to X/Y 345 before, which is out of range on a 260 mm bed).
- `SET_FAN0` / `SET_FAN2` honour the pins' `scale: 255` (S=255 was 1/255 duty).
  `fan0_en` is a static output on the K2 and is no longer toggled.
- `motor_control.cfg` restore takes the stock file from this model's directory
  in `/rom` (matched by bed size) instead of the hard-coded K2 Plus `F008_*`.
- Shaper macros no longer mention the K2 Plus probe point / 140 N belt target.
- **KAMP is now KAMP-K2** (grant0013/KAMP-K2 v1.1.0). Plain upstream KAMP never
  produced an adaptive mesh on the K2 (prtouch_v3 ignores MESH_MIN/MESH_MAX,
  master-server runs its own full mesh). Installs `restore_bed_mesh.py`, hijacks
  `G29` / `BED_MESH_CALIBRATE_START_PRINT`, adds the mesh to `START_PRINT`
  right after the prepare branch (homed and hot; unknown layouts get a warning
  instead of a guess) (`scripts/kamp_k2_patch.py`, idempotent, UTF-8/CRLF safe). Re-applied on boot after firmware
  updates. Remove restores `gcode_macro.cfg`.
- Camera: optional MJPEG stream (`k2plus_mjpeg`, ffmpeg on demand) registered
  as "K2 Camera MJPEG" for Mobileraker (free version, notification snapshots)
  and remote viewing.
- Menu renumbered (see README).

### Added
- Mobileraker Companion (Entware python3 + virtualenv + procd service).
- OctoEverywhere and OctoApp Companion (upstream installers, which support the K2).
- Git Backup (procd service, token stored outside the config folder).
- Klipper Gcode Shell Command.
- Moonraker database backup / restore.
- Tools: update Entware packages, clear logs & cache, system information.

### Fixed
- nginx `/go2rtc/api/ws` on port 4408 forwarded `?src=k2plus?src=...` when the
  client sent a query string (stream not found). Existing installs are repaired
  when Camera Support is installed again.
- Reinstalling Camera Support no longer injects a duplicate script into Fluidd's
  `index.html`, and removing it now removes that script.

## [Unreleased] - 2026-06-17

### Fixed
- **CFS load/unload failures** — Root cause identified and fixed: stock Creality
  firmware ships box.cfg and gcode_macro.cfg with all macros prefixed with
  an underscore (e.g. _BOX_QUIT_MATERIAL, _WAIT_TEMP_START). In Klipper,
  a leading underscore makes a macro private/hidden, meaning it cannot be called
  by the CFS system, the UI, or other macros. The helper script now automatically
  patches these files on startup via patch_stock_configs() in system.sh.

### Errors resolved
- key865 - retrude error, failed to exit connections
- key789 - position tracking error on X/Y axes
- key22 - no trigger on Y after full movement
- key274 - unknown g-code state: helix_cfs_load
- Unknown command: WAIT_TEMP_START
- Unknown command: END_PRINT_POINT
- Unknown command: PRINT_PREPARE_CLEAR
- Unknown command: CANCEL_CHAMBER_FAN_SWITCH



### Also fixed (2026-06-17)
- **printer.cfg mesh_min edge artifact** — Stock Creality firmware sets
  `mesh_min: 5,5` which causes the adaptive bed mesh algorithm to probe
  too close to the bed edge, producing false spike readings at the front-left
  corner. The helper script now automatically patches this to `mesh_min: 20,20`
  on startup via `patch_stock_configs()` in `system.sh`.
- **Duplicate patch_stock_configs function** — Removed a duplicate function
  that was accidentally added to `system.sh`.

- **useful_macros.sh conflicting macros** — Removed START_PRINT, END_PRINT,
  PAUSE, RESUME, CANCEL_PRINT from useful_macros.sh. These are already defined
  in stock gcode_macro.cfg with full CFS integration (BOX_START_PRINT,
  BOX_END, BOX_END_PRINT etc). Overwriting them broke CFS filament loading
  and unloading. useful_macros.sh now only installs genuinely new macros:
  PID_HOTEND, PID_BED, PID_CHAMBER, BED_LEVELING, Z_TILT_CALIBRATE,
  WARMUP, CHAMBER_HEAT, CHAMBER_COOL, CHAMBER_STATUS.


### Also fixed (2026-06-18)
- **patch_stock_configs not running on boot** — The stock config patches
  were only applied when helper.sh was run manually from the menu. This
  meant reboots would revert the fixes. Added install_rc_local_patch()
  which adds patch_stock_configs to /etc/rc.local so fixes are applied
  automatically on every boot.


### Also fixed (2026-06-22)
- **Moonraker silently ignoring UDISK extension config** — The stock
  moonraker init script only loads /usr/share/moonraker/moonraker.conf.
  The UDISK config at printer_data/config/moonraker.conf (where
  [timelapse] and the HelixScreen update_manager settings live) was
  never actually read. Added install_moonraker_include() which wires
  up the proper [include] directive and avoids a recursive-include
  loop. This was the root cause of prints getting stuck at 99% /
  showing as "Cancelled" in history -- TIMELAPSE_RENDER would throw
  an unregistered-remote-method error mid-END_PRINT and the gcode
  stream would abort before the file finished reading.
- **Missing END_PRINT underscore fixes** — _PRINT_PREPARE_CLEAR,
  _END_PRINT_Z_SAFE, _QMODE_EXIT, _END_PRINT_POINT, and
  _WAIT_TEMP_START were still called with underscores from inside
  other macros, even though their definitions were already patched.
  These are now fixed too.


### Also fixed (2026-06-22)
- **queue_gcode_uploads race condition** — Stock moonraker.conf has
  this set to False, causing Mainsail/Fluidd to poll for gcode
  metadata before background extraction finishes on larger files.
  This produced hundreds of "Metadata not available" errors per
  upload and made history permanently show "Unknown" as the slicer.
  install_moonraker_include() now also flips this to True.
- Fixed install_moonraker_include() returning early when the include
  line was already present, which skipped any fixes added after it.


### Also fixed (2026-06-22)
- **helper.sh failed on first run for everyone** — SCRIPTS_DIR was
  already set to .../helper-script/scripts, but the line sourcing
  system.sh appended another /scripts/ segment, producing a path
  that doesn't exist (scripts/scripts/system.sh). This crashed
  helper.sh immediately for any brand new install, before reaching
  the menu at all. Reported by a user attempting first setup.

### Known issues being investigated
- useful_macros.sh installs START_PRINT, END_PRINT, PAUSE, RESUME,
  CANCEL_PRINT macros that conflict with and override the stock Creality
  versions which have full CFS integration. This will be fixed in a future
  update to only install macros that do not exist in stock.
