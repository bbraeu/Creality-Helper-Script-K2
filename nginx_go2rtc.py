import shutil
import subprocess

NGINX_CONF = '/etc/nginx/nginx.conf'
content = original = open(NGINX_CONF).read()

# go2rtc block - identical for port 4408 (Fluidd) and 4409 (Mainsail).
# api/ws is pinned to the k2plus stream so WebRTC clients (Fluidd, Mainsail,
# Mobileraker) need no src parameter. "&$args" matters: with a fixed query in
# proxy_pass, nginx would append the client's query with a second "?", which
# go2rtc then fails to parse (stream not found). proxy_buffering off keeps
# MJPEG streams (stream.mjpeg) flowing instead of being buffered.
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

if 'go2rtc' in content:
    # Repair configs written by older versions of this script
    content = content.replace('proxy_pass http://127.0.0.1:1984/api/ws?src=k2plus;',
                              'proxy_pass http://127.0.0.1:1984/api/ws?src=k2plus&$args;')
    content = content.replace('''            proxy_pass http://127.0.0.1:1984/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade''', '''            proxy_pass http://127.0.0.1:1984/;
            proxy_http_version 1.1;
            proxy_buffering off;
            proxy_set_header Upgrade''')
    if content == original:
        print('Nginx already configured')
        exit(0)
else:
    # 4408 (Fluidd) has a multi-line /webcam/ block, 4409 (Mainsail) a single-line one
    old_4408 = '        location /webcam/ {\n            proxy_pass http://mjpgstreamer1/;\n        }'
    content = content.replace(old_4408, GO2RTC_BLOCK + old_4408, 1)
    old_4409 = '        location /webcam/  { proxy_pass http://mjpgstreamer1/; }'
    content = content.replace(old_4409, GO2RTC_BLOCK + old_4409, 1)

# Write and test
open(NGINX_CONF, 'w').write(content)
result = subprocess.run(['nginx', '-t'], capture_output=True, text=True)
if result.returncode == 0:
    print('Nginx updated for Fluidd and Mainsail')
else:
    print('ERROR:', result.stderr)
    open(NGINX_CONF, 'w').write(original)
    print('Restored previous nginx.conf!')
