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
            # Keep the executable bit from the repository (shims, .sh scripts)
            if rel.endswith('.sh') or (info.external_attr >> 16) & 0o111:
                os.chmod(tmp, 0o755)
            os.replace(tmp, dest)
            count += 1
    with open(version_file, 'w') as f:
        f.write(sha + '\n')
    print('UPDATED %s (%d files)' % (sha, count))


check() if mode == 'check' else update()
PYEOF
}

# ── git mode ──────────────────────────────────────────────────────────────────
# With the updatable Moonraker the helper directory is a git checkout, so
# Moonraker's update manager can update it too. Then git is the source of truth
# (both update paths agree), generated files are untracked/ignored.
export PATH=/opt/bin:/opt/sbin:$PATH

is_git_install() {
    [ -d "$SCRIPT_DIR/.git" ] && command -v git > /dev/null
}

git_check() {
    local old new
    cd "$SCRIPT_DIR" || return 1
    if ! git fetch -q origin "$BRANCH" 2> /dev/null; then
        echo "OFFLINE"
        return 0
    fi
    old=$(git rev-parse HEAD)
    new=$(git rev-parse "origin/$BRANCH")
    if [ "$old" = "$new" ]; then
        echo "CURRENT $new"
        return 0
    fi
    echo "UPDATE $old $new"
    git log --format='  - %s' "$old..$new" | cut -c1-104 | tail -10
}

git_update() {
    local sha
    cd "$SCRIPT_DIR" || return 1
    git fetch -q origin "$BRANCH" && git reset -q --hard "origin/$BRANCH" || return 1
    sha=$(git rev-parse HEAD)
    echo "$sha" > "$VERSION_FILE"
    echo "UPDATED $sha (git)"
}

# Turn a zip install into a git checkout in place (Moonraker's update manager
# only updates git repositories). Untracked / ignored files are kept.
convert_to_git() {
    [ -d "$SCRIPT_DIR/.git" ] && return 0
    command -v git > /dev/null || { echo "git not found (install Entware)"; return 1; }
    cd "$SCRIPT_DIR" || return 1
    if git init -q -b "$BRANCH" &&
       git remote add origin "https://github.com/$REPO.git" &&
       git fetch -q origin "$BRANCH" &&
       git reset -q --hard "origin/$BRANCH" &&
       git branch -q -u "origin/$BRANCH"; then
        git rev-parse HEAD > "$VERSION_FILE"
        echo "CONVERTED $(git rev-parse HEAD)"
        return 0
    fi
    rm -rf "$SCRIPT_DIR/.git"
    echo "Converting to a git checkout failed"
    return 1
}

case "$1" in
    check)   if is_git_install; then git_check; else run check; fi ;;
    update)  if is_git_install; then git_update; else run update; fi ;;
    convert) convert_to_git ;;
    *)       echo "Usage: $0 [check|update|convert]" ;;
esac
