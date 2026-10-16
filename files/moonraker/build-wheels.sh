#!/bin/sh
# build-wheels.sh - Prebuild Moonraker's Python wheels for the Creality K2
#
# Runs inside an ARMv7 container (QEMU) with the same Entware toolchain and
# Python 3.11 as the printer (armv7sf-k2.6), so the K2 can install Moonraker
# without compiling: the printer has 488 MB RAM and no swap, and building
# PyYAML / tornado / streaming-form-data there gets killed by the OOM killer.
# Used by .github/workflows/moonraker-wheels.yml.
#
#   build-wheels.sh <output dir> [moonraker git ref]
set -e
OUT=$1
REF=${2:-master}

apt-get update -qq
apt-get install -y -qq --no-install-recommends wget ca-certificates > /dev/null

echo "### Entware (armv7sf-k2.6)"
wget -qO - http://bin.entware.net/armv7sf-k2.6/installer/generic.sh | sh > /dev/null
export PATH=/opt/bin:/opt/sbin:$PATH
opkg update > /dev/null
opkg install python3 python3-pip python3-dev python3-sqlite3 gcc make git git-http > /dev/null
python3 --version

echo "### Moonraker $REF"
git clone -q https://github.com/Arksine/moonraker.git /tmp/moonraker
git -C /tmp/moonraker checkout -q "$REF"
COMMIT=$(git -C /tmp/moonraker rev-parse HEAD)

# Same workarounds as on the printer: Entware's headers lack SSIZE_MAX,
# Cython builds are huge (dbus-fast / zeroconf have pure-Python fallbacks)
export CFLAGS=-DSSIZE_MAX=2147483647 SKIP_CYTHON=1
WHEELS=$OUT/wheels
mkdir -p "$WHEELS"

echo "### Moonraker requirements"
# Pillow comes from Entware's python3-pillow on the printer (system site packages)
grep -v -i '^pillow' /tmp/moonraker/scripts/moonraker-requirements.txt \
    | grep -v '^--find-links' > /tmp/requirements.txt
python3 -m pip wheel -q -w "$WHEELS" -r /tmp/requirements.txt

echo "### lmdb (database migration)"
# pip cannot build it: its setup applies a patch that fails; LMDB_PURE skips it.
# setup.py needs setuptools / wheel (a virtualenv has them, plain Entware not)
python3 -m pip install -q setuptools wheel
mkdir -p /tmp/lmdb && cd /tmp/lmdb
python3 - << 'PYEOF'
import json, tarfile, urllib.request
d = json.load(urllib.request.urlopen('https://pypi.org/pypi/lmdb/1.4.1/json'))
url = [u['url'] for u in d['urls'] if u['packagetype'] == 'sdist'][0]
urllib.request.urlretrieve(url, 'lmdb.tar.gz')
tarfile.open('lmdb.tar.gz').extractall('.')
PYEOF
cd lmdb-1.4.1
LMDB_FORCE_CPYTHON=1 LMDB_PURE=1 python3 setup.py -q bdist_wheel > /dev/null
cp dist/*.whl "$WHEELS/"

cat > "$WHEELS/BUILD_INFO" << EOF
moonraker_commit=$COMMIT
python=$(python3 -c 'import sys; print(sys.version.split()[0])')
platform=$(python3 -c 'import sysconfig; print(sysconfig.get_platform())')
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
cp /tmp/moonraker/scripts/moonraker-requirements.txt "$WHEELS/moonraker-requirements.txt"

ls -la "$WHEELS"
tar czf "$OUT/moonraker-wheels-k2.tar.gz" -C "$OUT" wheels
echo "### done: $COMMIT"
