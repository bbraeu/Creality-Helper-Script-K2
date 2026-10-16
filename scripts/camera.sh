#!/bin/sh
# camera.sh - Install K2 camera support for Fluidd, Mainsail and Mobileraker
# Credit: DnG-Crafts (https://github.com/DnG-Crafts/K2-Camera)
#         AlexxIT/go2rtc (https://github.com/AlexxIT/go2rtc)
SCRIPT_DIR=/mnt/UDISK/helper-script
. "$SCRIPT_DIR/scripts/system.sh"
GO2RTC=$SCRIPT_DIR/go2rtc
GO2RTC_YAML=$SCRIPT_DIR/go2rtc.yaml
K2RTC=$SCRIPT_DIR/k2rtc.py
WATCHDOG=$SCRIPT_DIR/camera_watchdog.py

# Print the first ffmpeg with version >= 5 (go2rtc refuses older ones for transcoding)
find_ffmpeg5() {
    local f major
    for f in /opt/bin/ffmpeg /usr/bin/ffmpeg; do
        [ -x "$f" ] || continue
        major=$("$f" -version 2>/dev/null | sed -n '1s/^ffmpeg version n\{0,1\}\([0-9]\{1,\}\).*/\1/p')
        if [ -n "$major" ] && [ "$major" -ge 5 ]; then
            echo "$f"
            return 0
        fi
    done
}

install_camera() {
    echo ""
    echo ""
    echo "======================================================"
    echo "  Camera Support for Fluidd, Mainsail and Mobileraker"
    echo "======================================================"
    echo ""
    echo "  This installs a WebRTC bridge that makes the K2"
    echo "  camera available in both Fluidd and Mainsail dashboards."
    echo ""
    echo "  Credit: DnG-Crafts and AlexxIT/go2rtc"
    echo ""

    echo ""
    echo -e "  ${YELLOW}NOTE: A reboot is required after install for the camera to start.${NC}"
    printf "  Continue? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }

    # Mobileraker shows go2rtc WebRTC only to supporters, and only MJPEG
    # webcams can provide Companion notification snapshots. An extra MJPEG
    # camera covers both. Live MJPEG = H264 -> MJPEG transcode by go2rtc, which
    # needs ffmpeg >= 5 (the K2 ships 4.3: "ffmpeg: unsupported version");
    # Entware has 5.x. Without it, snapshot mode polls frame.jpeg (~1 fps),
    # which works with the stock ffmpeg.
    echo ""
    echo "  Add an MJPEG camera for Mobileraker / OctoEverywhere?"
    echo "  (free Mobileraker version, notification snapshots, remote viewing;"
    echo "   live mode transcodes with ffmpeg - costs CPU only while it is watched)"
    printf "  Add MJPEG camera? [y/n]: "
    read add_mjpeg
    MJPEG_MODE=none
    FFMPEG_BIN=""
    if [ "$add_mjpeg" = "y" ] || [ "$add_mjpeg" = "Y" ]; then
        FFMPEG_BIN=$(find_ffmpeg5)
        if [ -z "$FFMPEG_BIN" ] && [ -x /opt/bin/opkg ]; then
            echo ""
            echo "  Live MJPEG needs ffmpeg 5 or newer; the K2 ships ffmpeg 4."
            printf "  Install ffmpeg 5 from Entware (about 15 MB)? [y/n]: "
            read install_ffmpeg
            if [ "$install_ffmpeg" = "y" ] || [ "$install_ffmpeg" = "Y" ]; then
                opkg_install ffmpeg && FFMPEG_BIN=$(find_ffmpeg5)
            fi
        fi
        if [ -n "$FFMPEG_BIN" ]; then
            MJPEG_MODE=stream
            log_info "MJPEG camera: live stream (ffmpeg: $FFMPEG_BIN)"
        else
            MJPEG_MODE=snapshot
            log_info "MJPEG camera: snapshot mode (about 1 frame per second)."
            [ -x /opt/bin/opkg ] || log_info "For live MJPEG install Entware, then re-run Camera Support."
        fi
    fi

    # Download go2rtc if not present
    if [ ! -f "$GO2RTC" ]; then
        log_info "Downloading go2rtc (ARM)..."
        python3 -c "
import urllib.request
urllib.request.urlretrieve(
    'https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_arm',
    '$GO2RTC'
)
print('Downloaded go2rtc')
"
        chmod +x $GO2RTC
    fi

    # Get printer IP
    PRINTER_IP=$(python3 -c "import subprocess; print(subprocess.check_output(['ip', 'route', 'get', '1']).decode().split('src')[1].strip().split()[0])")

    # k2plus_mjpeg reads k2plus via go2rtc's RTSP server (:8554) on demand.
    # The camera delivers 1280x720@15; lower -r (or add #width=640) if CPU
    # load while printing is too high
    MJPEG_STREAM=""
    [ "$MJPEG_MODE" = stream ] && MJPEG_STREAM='  k2plus_mjpeg:
    - "ffmpeg:k2plus#video=mjpeg#raw=-r 10"'

    # Create go2rtc config
    cat > $GO2RTC_YAML << YAML
api:
  listen: :1984
  origin: '*'

streams:
  k2plus:
    - "webrtc:http://127.0.0.1:8000/call/webrtc_local#format=creality"
$MJPEG_STREAM

webrtc:
  listen: :8555
  candidates:
    - $PRINTER_IP
  ice_servers:
    - urls:
        - stun:stun.l.google.com:19302
YAML

    if [ -n "$FFMPEG_BIN" ]; then
        cat >> $GO2RTC_YAML << YAML

ffmpeg:
  bin: $FFMPEG_BIN
YAML
    fi


    # Create watchdog
    cat > $WATCHDOG << 'PYTHON'
#!/usr/bin/env python3
import urllib.request, json, time

def reconnect():
    try:
        urllib.request.urlopen('http://127.0.0.1:1984/api/streams?src=k2plus', timeout=10)
        print('Stream reconnected', flush=True)
    except Exception as e:
        print('Reconnect error:', e, flush=True)

print('Camera watchdog started', flush=True)
last_bytes = 0
stale_count = 0
while True:
    try:
        r = urllib.request.urlopen('http://127.0.0.1:1984/api/streams', timeout=3)
        data = json.loads(r.read())
        producers = data.get('k2plus', {}).get('producers', [])
        if not producers:
            print('No producers - reconnecting...', flush=True)
            reconnect()
            stale_count = 0
            last_bytes = 0
        else:
            current_bytes = producers[0].get('bytes_recv', 0)
            if current_bytes == last_bytes:
                stale_count += 1
                if stale_count >= 3:
                    print('Stream stale - reconnecting...', flush=True)
                    reconnect()
                    stale_count = 0
                    last_bytes = 0
            else:
                stale_count = 0
                last_bytes = current_bytes
    except Exception as e:
        print('Watchdog error:', e, flush=True)
        reconnect()
    time.sleep(10)
PYTHON

    # Create startup service
    cat > /etc/rc.d/S99camera << 'SHELL'
#!/bin/sh
HELIX=/mnt/UDISK/helper-script
start() {
    echo "Starting K2 camera bridge..."
    sleep 60
    $HELIX/go2rtc -config $HELIX/go2rtc.yaml >> /tmp/go2rtc.log 2>&1 &
    echo "Camera bridge started" >> /tmp/camera_startup.log 2>&1
    sleep 5
    python3 $HELIX/camera_watchdog.py >> /tmp/watchdog.log 2>&1 &
}
stop() {
    killall go2rtc 2>/dev/null
    kill $(ps aux | grep camera_watchdog | grep -v grep | awk '{print $1}') 2>/dev/null
}
case "$1" in
    start) start ;;
    stop)  stop ;;
    restart) stop; sleep 1; start ;;
    *) echo "Usage: $0 {start|stop|restart}" ;;
esac
SHELL
    chmod +x /etc/rc.d/S99camera
    cp /etc/rc.d/S99camera /etc/init.d/S99camera

    # Add to rc.local
    python3 -c "
content = open('/etc/rc.local').read()
if 'S99camera' not in content:
    content = content.replace('exit 0', '# K2 Camera bridge\n/etc/rc.d/S99camera start &\nexit 0')
    open('/etc/rc.local', 'w').write(content)
    print('Added to rc.local')
else:
    print('Already in rc.local')
"

    # Add nginx proxy for go2rtc on port 4408 (Fluidd) and 4409 (Mainsail)
    # Also maps the mjpg-streamer style /webcam/?action=stream|snapshot URLs
    # (Mobileraker / Moonraker defaults) to go2rtc
    K2CAM_STREAM=$([ "$MJPEG_MODE" = stream ] && echo k2plus_mjpeg || echo snapshot) \
        python3 $SCRIPT_DIR/nginx_go2rtc.py

    # Add camera(s) to Moonraker (shared by Fluidd, Mainsail and Mobileraker).
    # Absolute URLs: Mobileraker resolves relative ones against port 80 and
    # maps them through OctoEverywhere only when the host matches its printer IP.
    # Port 4408 (stock Fluidd) always exists; 4409 only when Mainsail is installed.
    MJPEG=$MJPEG_MODE python3 -c "
import urllib.request, json, os
import subprocess; ip = subprocess.check_output(['ip', 'route', 'get', '1']).decode().split('src')[1].strip().split()[0]
for name in ['K2 Camera', 'K2 Camera Mainsail', 'K2 Camera MJPEG']:
    try:
        req = urllib.request.Request('http://127.0.0.1:7125/server/webcams/item?name=' + name.replace(' ', '%20'), method='DELETE')
        urllib.request.urlopen(req)
    except: pass

snapshot = 'http://' + ip + ':4408/go2rtc/api/frame.jpeg?src=k2plus'
camera = {
    'name': 'K2 Camera',
    'location': 'printer',
    'service': 'webrtc-go2rtc',
    'target_fps': 15,
    'stream_url': 'http://' + ip + ':4408/go2rtc/',
    'snapshot_url': snapshot,
    'flip_horizontal': False,
    'flip_vertical': False,
    'rotation': 0
}
cameras = [camera]
mode = os.environ.get('MJPEG')
if mode == 'stream':
    cameras.append({
        'name': 'K2 Camera MJPEG',
        'location': 'printer',
        'service': 'mjpegstreamer',
        'target_fps': 10,
        'target_fps_idle': 2,
        'stream_url': 'http://' + ip + ':4408/go2rtc/api/stream.mjpeg?src=k2plus_mjpeg',
        'snapshot_url': snapshot,
        'flip_horizontal': False,
        'flip_vertical': False,
        'rotation': 0
    })
elif mode == 'snapshot':
    # Clients poll snapshot_url; works with the stock ffmpeg 4
    cameras.append({
        'name': 'K2 Camera MJPEG',
        'location': 'printer',
        'service': 'mjpegstreamer-adaptive',
        'target_fps': 2,
        'target_fps_idle': 1,
        'stream_url': snapshot,
        'snapshot_url': snapshot,
        'flip_horizontal': False,
        'flip_vertical': False,
        'rotation': 0
    })
for cam in cameras:
    req = urllib.request.Request(
        'http://127.0.0.1:7125/server/webcams/item',
        data=json.dumps(cam).encode(), method='POST',
        headers={'Content-Type': 'application/json'}
    )
    urllib.request.urlopen(req)
    print('Camera added to Moonraker: ' + cam['name'])
"

    # Fluidd: enable the WebRTC camera (Creality's Moonraker has no "enabled" flag)
    python3 "$SCRIPT_DIR/scripts/fluidd_camera.py" install

    # Update Mainsail index.html with enabled cam injection
    python3 -c "
import re
import os
if not os.path.exists('/usr/share/mainsail/index.html'): exit(0)
content = open('/usr/share/mainsail/index.html').read()
content = re.sub(r'<iframe[^>]*go2rtc_keepalive[^>]*>.*?</iframe>', '', content)
content = re.sub(r'<script>.*?enableMainsailCams.*?</script>', '', content, flags=re.DOTALL)
script = '''<script>
function enableMainsailCams() {
  try {
    var s = document.querySelector(\"#app\").__vue__.\$store;
    var cams = s.state.gui.webcams.webcams;
    if(cams && cams.length > 0) {
      var changed = false;
      cams.forEach(function(cam, i) {
        if(!cam.enabled && cam.service === 'webrtc-go2rtc') { s.state.gui.webcams.webcams[i].enabled = true; changed = true; }
      });
      if(changed) s.state.gui.webcams.webcams = s.state.gui.webcams.webcams.slice();
    }
  } catch(e) {}
}
setTimeout(enableMainsailCams, 2000);
</script>'''
content = content.replace('</body>', script + '</body>')
open('/usr/share/mainsail/index.html', 'w').write(content)
print('Mainsail index.html updated')
"

    /etc/rc.d/S80nginx restart
    mark_installed "camera_support"
    echo ""
    log_success "Camera support installed for Fluidd, Mainsail and Mobileraker!"
    log_info "The camera will appear in both dashboards after reboot."
    log_info "Mobileraker: add the printer by IP address. 'K2 Camera' (WebRTC) needs a"
    log_info "Mobileraker supporter subscription; 'K2 Camera MJPEG' works for everyone."
    log_info "Note: Camera takes 60-90 seconds to appear after boot."
    echo ""
    echo -e "  ${YELLOW}A reboot is required for the camera service to start!${NC}"
    printf "  Reboot now? [y/n]: "
    read confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] && reboot
}

remove_camera() {
    if ! is_installed "camera_support"; then
        log_info "Camera Support is not installed."
        return 0
    fi
        echo ""
    echo -e "${YELLOW}WARNING: This will remove the K2 camera support.${NC}"
    printf "Are you sure? [y/n]: "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { log_info "Cancelled."; return 0; }

    # Stop services
    /etc/rc.d/S99camera stop 2>/dev/null

    # Remove startup entries
    rm -f /etc/rc.d/S99camera
    rm -f /etc/init.d/S99camera
    python3 -c "
content = open('/etc/rc.local').read()
content = content.replace('# K2 Camera bridge\n/etc/rc.d/S99camera start &\n', '')
open('/etc/rc.local', 'w').write(content)
print('Removed from rc.local')
"

    # Remove nginx config
    python3 $SCRIPT_DIR/nginx_go2rtc.py remove
    /etc/rc.d/S80nginx restart

    # Remove cameras from Moonraker
    python3 -c "
import urllib.request
for name in ['K2 Camera', 'K2 Camera Mainsail', 'K2 Camera MJPEG']:
    try:
        req = urllib.request.Request('http://127.0.0.1:7125/server/webcams/item?name=' + name.replace(' ', '%20'), method='DELETE')
        urllib.request.urlopen(req)
        print('Removed:', name)
    except: pass
"

    # Remove the Fluidd camera script
    python3 "$SCRIPT_DIR/scripts/fluidd_camera.py" remove

    # Restore Mainsail index.html
    python3 -c "
import re
import os
if not os.path.exists('/usr/share/mainsail/index.html'): exit(0)
content = open('/usr/share/mainsail/index.html').read()
content = re.sub(r'<script>.*?enableMainsailCams.*?</script>', '', content, flags=re.DOTALL)
open('/usr/share/mainsail/index.html', 'w').write(content)
print('Mainsail index.html restored')
"

    mark_removed "camera_support"
    log_success "Camera support removed."
}

case "$1" in
    install) install_camera ;;
    remove)  remove_camera ;;
    *)       echo "Usage: $0 [install|remove]" ;;
esac
