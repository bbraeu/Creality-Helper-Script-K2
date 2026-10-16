#!/bin/sh
# update.sh - Self-update the helper script from GitHub
#
# The commit SHA of the installed files is stored in $SCRIPT_DIR/.version.
# On start, helper.sh compares it with the latest commit of the branch.
#
#   update.sh check     print "UPDATE <installed|unknown> <latest>" plus the
#                       new commit titles, "CURRENT <sha>" or "OFFLINE"
#   update.sh update    install the latest commit and record its SHA
#
# Only files that exist in the repository are replaced (atomically, so a
# running helper.sh keeps reading its old copy). Files generated on the
# printer (go2rtc.yaml, camera_watchdog.py, .installed, backups, ...) are
# never touched, and nothing is deleted.
SCRIPT_DIR=/mnt/UDISK/helper-script
VERSION_FILE=$SCRIPT_DIR/.version
REPO=bbraeu/Creality-Helper-Script-K2-Base
BRANCH=main

run() {
    python3 - "$1" "$SCRIPT_DIR" "$REPO" "$BRANCH" "$VERSION_FILE" << 'PYEOF'
import io, json, os, shutil, sys, urllib.request, zipfile

mode, script_dir, repo, branch, version_file = sys.argv[1:6]
API = 'https://api.github.com/repos/' + repo
# Generated on the printer - must never be replaced by repository copies
KEEP = {'go2rtc', 'go2rtc.yaml', 'camera_watchdog.py'}


def get(url, timeout):
    req = urllib.request.Request(url, headers={'User-Agent': 'k2-helper-script',
                                               'Accept': 'application/vnd.github+json'})
    return urllib.request.urlopen(req, timeout=timeout)


def installed():
    try:
        with open(version_file) as f:
            return f.read().strip()
    except OSError:
        return ''


def latest():
    return json.load(get(API + '/commits/' + branch, 8))['sha']


def check():
    try:
        new = latest()
    except Exception:
        print('OFFLINE')
        return
    old = installed()
    if old == new:
        print('CURRENT ' + new)
        return
    print('UPDATE %s %s' % (old or 'unknown', new))
    if old:
        try:
            commits = json.load(get('%s/compare/%s...%s' % (API, old, new), 8))['commits']
            for c in commits[-10:]:
                print('  - ' + c['commit']['message'].splitlines()[0][:100])
        except Exception:
            pass


def update():
    sha = latest()
    data = get('https://github.com/%s/archive/%s.zip' % (repo, sha), 60).read()
    count = 0
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            rel = info.filename.split('/', 1)[1]  # strip "<repo>-<sha>/"
            if not rel or rel in KEEP or rel.startswith('.git'):
                continue
            dest = os.path.join(script_dir, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            tmp = dest + '.update'
            with z.open(info) as src, open(tmp, 'wb') as dst:
                shutil.copyfileobj(src, dst)
            if rel.endswith('.sh'):
                os.chmod(tmp, 0o755)
            os.replace(tmp, dest)
            count += 1
    with open(version_file, 'w') as f:
        f.write(sha + '\n')
    print('UPDATED %s (%d files)' % (sha, count))


check() if mode == 'check' else update()
PYEOF
}

case "$1" in
    check)  run check ;;
    update) run update ;;
    *)      echo "Usage: $0 [check|update]" ;;
esac
