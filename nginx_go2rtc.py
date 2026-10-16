"""nginx_go2rtc.py - Route camera URLs on ports 4408 (Fluidd) / 4409 (Mainsail) to go2rtc

    python3 nginx_go2rtc.py [install|remove]

install (default):
  /go2rtc/          go2rtc API (WebRTC signalling, frame.jpeg, stream.mjpeg)
  /go2rtc/api/ws    pinned to the k2plus stream, so WebRTC clients need no src
  /webcam/          mjpg-streamer style URLs - the defaults of Mobileraker,
                    Moonraker and most apps: /webcam/?action=stream (MJPEG)
                    and /webcam/?action=snapshot (JPEG)
remove: restores the stock /webcam/ -> mjpgstreamer1 block and drops /go2rtc/.

The stream behind /webcam/?action=stream comes from K2CAM_STREAM (default
k2plus_mjpeg). Without a live MJPEG stream (snapshot mode) the camera installer
sets K2CAM_STREAM=snapshot, and stream requests then also get a single JPEG.
"""
import os
import re
import subprocess
import sys

NGINX_CONF = '/etc/nginx/nginx.conf'
MODE = sys.argv[1] if len(sys.argv) > 1 else 'install'
STREAM = os.environ.get('K2CAM_STREAM', 'k2plus_mjpeg')

content = original = open(NGINX_CONF).read()

# "&$args": with a fixed query in proxy_pass nginx would append the client's
# query with a second "?", which go2rtc fails to parse (stream not found).
# proxy_buffering off keeps MJPEG streams flowing instead of being buffered.
GO2RTC_BLOCK = '''        location /go2rtc/ {
            proxy_pass http://127.0.0.1:1984/;
            proxy_http_version 1.1;
            proxy_buffering off;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $http_host;
            proxy_read_timeout 3600;
            proxy_send_timeout 3600;
        }
        location /go2rtc/api/ws {
            proxy_pass http://127.0.0.1:1984/api/ws?src=k2plus&$args;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $http_host;
            proxy_read_timeout 3600;
            proxy_send_timeout 3600;
        }
'''

if STREAM == 'snapshot':
    stream_target = '/api/frame.jpeg?src=k2plus'
else:
    stream_target = '/api/stream.mjpeg?src=' + STREAM

WEBCAM_BLOCK = '''        location /webcam/ {
            # K2 helper: mjpg-streamer style URLs served by go2rtc
            set $k2cam %s;
            if ($arg_action = "snapshot") {
                set $k2cam /api/frame.jpeg?src=k2plus;
            }
            proxy_pass http://127.0.0.1:1984$k2cam;
            proxy_http_version 1.1;
            proxy_buffering off;
            proxy_read_timeout 3600;
        } # end K2 helper webcam
''' % stream_target

STOCK_WEBCAM = '''        location /webcam/ {
            proxy_pass http://mjpgstreamer1/;
        }
'''

# Stock /webcam/ blocks: multi-line on 4408 (Fluidd), single-line on 4409 (Mainsail)
STOCK_WEBCAM_RE = re.compile(
    r'^[ \t]*location /webcam/ +\{\s*proxy_pass http://mjpgstreamer1/;\s*\}[ \t]*\n', re.M)
OURS_WEBCAM_RE = re.compile(
    r'^[ \t]*location /webcam/ \{\n[ \t]*# K2 helper:.*?\} # end K2 helper webcam[ \t]*\n', re.M | re.S)
GO2RTC_RE = re.compile(
    r'^[ \t]*location /go2rtc/(api/ws)? \{.*?^[ \t]*\}[ \t]*\n', re.M | re.S)

if MODE == 'remove':
    content = GO2RTC_RE.sub('', content)
    content = OURS_WEBCAM_RE.sub(lambda m: STOCK_WEBCAM, content)
else:
    if 'location /go2rtc/' in content:
        # Repair blocks written by older versions of this script
        content = content.replace('proxy_pass http://127.0.0.1:1984/api/ws?src=k2plus;',
                                  'proxy_pass http://127.0.0.1:1984/api/ws?src=k2plus&$args;')
        content = content.replace('''            proxy_pass http://127.0.0.1:1984/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade''', '''            proxy_pass http://127.0.0.1:1984/;
            proxy_http_version 1.1;
            proxy_buffering off;
            proxy_set_header Upgrade''')
    else:
        # Insert the go2rtc locations before each stock /webcam/ block
        content = STOCK_WEBCAM_RE.sub(lambda m: GO2RTC_BLOCK + m.group(0), content)
    # /webcam/ -> go2rtc (stock blocks, or ours with a possibly changed stream)
    content = STOCK_WEBCAM_RE.sub(lambda m: WEBCAM_BLOCK, content)
    content = OURS_WEBCAM_RE.sub(lambda m: WEBCAM_BLOCK, content)

if content == original:
    print('Nginx already configured')
    sys.exit(0)

# Write and test
open(NGINX_CONF, 'w').write(content)
result = subprocess.run(['nginx', '-t'], capture_output=True, text=True)
if result.returncode == 0:
    print('Nginx %s for Fluidd and Mainsail' % ('restored' if MODE == 'remove' else 'updated'))
else:
    print('ERROR:', result.stderr)
    open(NGINX_CONF, 'w').write(original)
    print('Restored previous nginx.conf!')
    sys.exit(1)
