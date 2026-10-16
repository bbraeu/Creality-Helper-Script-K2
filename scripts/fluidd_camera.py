#!/usr/bin/env python3
# fluidd_camera.py - Show the K2 WebRTC camera in Fluidd
#
#   python3 fluidd_camera.py install|remove [index.html]
#
# Creality's Moonraker does not store the webcam "enabled" flag, so Fluidd
# treats every webcam as disabled. This injects a small script into Fluidd's
# index.html that enables the WebRTC camera (webrtc-go2rtc) once Fluidd has
# loaded its webcam list. The MJPEG camera (meant for Mobileraker) stays off,
# otherwise go2rtc would transcode with ffmpeg whenever Fluidd is open.
import re
import sys

INDEX = sys.argv[2] if len(sys.argv) > 2 else '/usr/share/fluidd/index.html'
MARKER = 'k2-helper-camera'

SCRIPT = '''<script id="%s">
(function () {
  var tries = 0;
  var timer = setInterval(function () {
    tries++;
    try {
      var store = document.querySelector('#app').__vue__.$store;
      var cams = store.state.webcams.webcams;
      if (cams && cams.length > 0) {
        cams.forEach(function (cam, i) {
          if (cam.enabled === undefined) {
            store.state.webcams.webcams.splice(i, 1,
              Object.assign({}, cam, { enabled: cam.service === 'webrtc-go2rtc' }));
          }
        });
        clearInterval(timer);
      }
    } catch (e) {}
    if (tries > 30) clearInterval(timer);
  }, 1000);
})();
</script>''' % MARKER


def strip(content):
    # Ours, plus the variants older helper versions injected
    content = re.sub(r'<script id="%s">.*?</script>' % MARKER, '', content, flags=re.S)
    content = re.sub(r'<script>\s*function enableCamera\(\).*?</script>', '', content, flags=re.S)
    content = re.sub(r'<script>\s*var cameraReady.*?</script>', '', content, flags=re.S)
    content = re.sub(r'<iframe[^>]*go2rtc_keepalive[^>]*>.*?</iframe>', '', content, flags=re.S)
    return content


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ''
    if mode not in ('install', 'remove'):
        print('usage: fluidd_camera.py install|remove [index.html]')
        sys.exit(1)
    with open(INDEX, encoding='utf-8') as f:
        content = f.read()
    content = strip(content)
    if mode == 'install':
        content = content.replace('</body>', SCRIPT + '</body>', 1)
    with open(INDEX, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fluidd camera script %s' % ('installed' if mode == 'install' else 'removed'))


main()
