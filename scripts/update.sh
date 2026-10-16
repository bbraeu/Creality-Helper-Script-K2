#!/bin/sh
# update.sh - Self-update the helper script from GitHub releases
#
# Updates follow GitHub *releases* with a version tag vMAJOR.MINOR.PATCH
# (no drafts, no pre-releases) - not every commit on main. Other releases of
# the repository (moonraker-wheels-*) are ignored. The installed version is
# stored in $SCRIPT_DIR/.version.
#
#   update.sh check     "UPDATE <installed|unknown> <latest>" plus release
#                       notes, "CURRENT <version>" or "OFFLINE"
#   update.sh update    install the latest release (never downgrades)
#   update.sh version   print the installed version
#   update.sh convert   turn a zip install into a git checkout (Moonraker)
#
# Zip installs: the release archive is unpacked over the installation. Only
# files of the repository are replaced (atomically, so a running helper.sh
# keeps reading its old copy); generated files (go2rtc.yaml, .installed,
# backups, ...) are never touched and nothing is deleted.
# Git installs (updatable Moonraker lists the helper in Software Updates with
# "channel: stable"): same rule as Moonraker - fast-forward main to the newest
# final release tag.
SCRIPT_DIR=/mnt/UDISK/helper-script
VERSION_FILE=$SCRIPT_DIR/.version
REPO=bbraeu/Creality-Helper-Script-K2-Base
BRANCH=main
export PATH=/opt/bin:/opt/sbin:$PATH

# Python part: GitHub API, version sorting, zip install
py() {
    python3 - "$@" << 'PYEOF'
import io, json, os, re, shutil, sys, urllib.request, zipfile

cmd, script_dir, repo, version_file = sys.argv[1:5]
args = sys.argv[5:]
API = 'https://api.github.com/repos/' + repo
VERSION_RE = re.compile(r'v(\d+)\.(\d+)\.(\d+)')
# Generated on the printer - never replaced by repository copies
KEEP = {'go2rtc', 'go2rtc.yaml', 'camera_watchdog.py'}


def key(tag):
    m = VERSION_RE.fullmatch(tag or '')
    return tuple(int(x) for x in m.groups()) if m else None


def get(url, timeout):
    req = urllib.request.Request(url, headers={'User-Agent': 'k2-helper-script',
                                               'Accept': 'application/vnd.github+json'})
    return urllib.request.urlopen(req, timeout=timeout)


def installed():
    try:
        with open(version_file) as f:
            v = f.read().strip()
    except OSError:
        return ''
    return v if key(v) else ''   # older versions stored a commit SHA


def latest_release():
    best = None
    for r in json.load(get(API + '/releases?per_page=50', 15)):
        k = key(r['tag_name'])
        if k and not r['draft'] and not r['prerelease'] and (best is None or k > best[0]):
            best = (k, r)
    return best[1] if best else None


def notes(release):
    """A few lines of the release notes for the update prompt."""
    lines = [l.rstrip() for l in (release.get('body') or '').splitlines()]
    picked = [l for l in lines if l.startswith(('- ', '* ', '## '))][:10]
    if release.get('name'):
        print('  ' + release['name'])
    for l in picked:
        if l.startswith('## '):
            print('  ' + l[3:])
        else:
            print('    - ' + l[2:].strip())


def check():
    try:
        rel = latest_release()
    except Exception:
        print('OFFLINE')
        return
    cur = installed()
    if rel is None:
        print('CURRENT ' + (cur or 'unknown'))
        return
    tag = rel['tag_name']
    if cur and key(cur) >= key(tag):
        print('CURRENT ' + cur)
        return
    print('UPDATE %s %s' % (cur or 'unknown', tag))
    notes(rel)


def update():
    rel = latest_release()
    if rel is None:
        print('No release found')
        sys.exit(1)
    tag = rel['tag_name']
    cur = installed()
    if cur and key(cur) >= key(tag):
        print('CURRENT ' + cur)
        return
    data = get('https://github.com/%s/archive/refs/tags/%s.zip' % (repo, tag), 60).read()
    count = 0
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            rel_path = info.filename.split('/', 1)[1]  # strip "<repo>-<tag>/"
            if not rel_path or rel_path in KEEP or rel_path.startswith('.git'):
                continue
            dest = os.path.join(script_dir, rel_path)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            tmp = dest + '.update'
            with z.open(info) as src, open(tmp, 'wb') as dst:
                shutil.copyfileobj(src, dst)
            # Keep the executable bit from the repository (shims, .sh scripts)
            if rel_path.endswith('.sh') or (info.external_attr >> 16) & 0o111:
                os.chmod(tmp, 0o755)
            os.replace(tmp, dest)
            count += 1
    with open(version_file, 'w') as f:
        f.write(tag + '\n')
    print('UPDATED %s (%d files)' % (tag, count))


def max_tag():
    """Newest version tag from stdin (git tag --merged ...)."""
    tags = [t.strip() for t in sys.stdin if key(t.strip())]
    print(max(tags, key=key) if tags else '')


def release_notes():
    try:
        notes(json.load(get(API + '/releases/tags/' + args[0], 15)))
    except Exception:
        pass


{'check': check, 'update': update, 'max_tag': max_tag,
 'notes': release_notes}[cmd]()
PYEOF
}

pyrun() {
    local cmd="$1"
    shift
    py "$cmd" "$SCRIPT_DIR" "$REPO" "$VERSION_FILE" "$@"
}

# ── git mode ──────────────────────────────────────────────────────────────────

is_git_install() {
    [ -d "$SCRIPT_DIR/.git" ] && command -v git > /dev/null
}

git_latest_tag() {
    git -C "$SCRIPT_DIR" tag --merged "origin/$BRANCH" -l 'v*' | pyrun max_tag
}

git_version() {
    # v2.0.0, or v2.0.0-3-gabcdef12 when ahead of the release
    git -C "$SCRIPT_DIR" describe --tags --match 'v[0-9]*.[0-9]*.[0-9]*' 2> /dev/null || echo unknown
}

git_check() {
    local tag
    git -C "$SCRIPT_DIR" fetch -q --tags origin "$BRANCH" 2> /dev/null || { echo "OFFLINE"; return 0; }
    tag=$(git_latest_tag)
    if [ -z "$tag" ] || git -C "$SCRIPT_DIR" merge-base --is-ancestor "$tag" HEAD; then
        echo "CURRENT $(git_version)"
        return 0
    fi
    echo "UPDATE $(git_version) $tag"
    pyrun notes "$tag"
}

git_update() {
    local tag
    cd "$SCRIPT_DIR" || return 1
    git fetch -q --tags origin "$BRANCH" || return 1
    tag=$(git_latest_tag)
    [ -n "$tag" ] || { echo "No release found"; return 1; }
    if git merge-base --is-ancestor "$tag" HEAD; then
        echo "CURRENT $(git_version)"
        return 0
    fi
    git checkout -q "$BRANCH" 2> /dev/null
    git merge -q --ff-only "$tag" 2> /dev/null || git reset -q --hard "$tag" || return 1
    echo "$tag" > "$VERSION_FILE"
    echo "UPDATED $tag (git)"
}

# Turn a zip install into a git checkout in place (Moonraker's update manager
# only updates git repositories). Untracked / ignored files are kept. The
# checkout is placed on the newest release, like Moonraker's stable channel.
convert_to_git() {
    local tag
    [ -d "$SCRIPT_DIR/.git" ] && return 0
    command -v git > /dev/null || { echo "git not found (install Entware)"; return 1; }
    cd "$SCRIPT_DIR" || return 1
    if git init -q -b "$BRANCH" &&
       git remote add origin "https://github.com/$REPO.git" &&
       git fetch -q --tags origin "$BRANCH" &&
       tag=$(git_latest_tag) &&
       git reset -q --hard "${tag:-origin/$BRANCH}" &&
       git branch -q -u "origin/$BRANCH"; then
        echo "${tag:-unknown}" > "$VERSION_FILE"
        echo "CONVERTED $(git_version)"
        return 0
    fi
    rm -rf "$SCRIPT_DIR/.git"
    echo "Converting to a git checkout failed"
    return 1
}

case "$1" in
    check)   if is_git_install; then git_check; else pyrun check; fi ;;
    update)  if is_git_install; then git_update; else pyrun update; fi ;;
    version)
        if is_git_install; then
            git_version
        else
            # Older versions stored a commit SHA instead of a release tag
            v=$(cat "$VERSION_FILE" 2> /dev/null)
            case "$v" in v[0-9]*.[0-9]*.[0-9]*) echo "$v" ;; *) echo "unknown" ;; esac
        fi ;;
    convert) convert_to_git ;;
    *)       echo "Usage: $0 [check|update|version|convert]" ;;
esac
