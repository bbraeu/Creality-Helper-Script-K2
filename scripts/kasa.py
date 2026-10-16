#!/usr/bin/env python3
"""kasa.py - Minimal TP-Link Kasa (and Tapo) smart plug client for the K2 (Auto Power Off)

Classic Kasa plugs (HS100, HS110, KP105, ...) speak the legacy protocol on port
9999, which Moonraker's [power] type tplink_smartplug handles. Newer Kasa models
and firmware (KP125M, EP25, ...) and all Tapo plugs only speak TP-Link's
encrypted KLAP protocol, which Moonraker cannot switch; this client does it.
The K2's stock Python has no crypto module, so only the standard library plus a
small built-in AES-128 is used. Protocol after python-kasa
(https://github.com/python-kasa/python-kasa).

    kasa.py discover [seconds]   list Kasa/Tapo devices on the network (tab
                                 separated: ip, model, name/type, mac, protocol)
    kasa.py probe <ip>           print the plug's protocol: legacy, KLAP or none
    kasa.py setup <ip>           (KLAP) ask for the TP-Link account, test the plug
                                 and save the connection
    kasa.py status | on | off    (KLAP) switch the saved plug ("off" syncs disks first)

The TP-Link password is not stored, only the KLAP auth hashes derived from it
(in $SCRIPT_DIR/.kasa.json, readable by root only).
"""
import base64
import binascii
import getpass
import hashlib
import http.client
import json
import os
import re
import socket
import struct
import subprocess
import sys
import time
import uuid

CONF = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.kasa.json')
TIMEOUT = 8

# ── AES-128 (CBC, PKCS#7) ────────────────────────────────────────────────────


def _rotl8(x, s):
    return ((x << s) | (x >> (8 - s))) & 0xFF


def _gmul(a, b):
    p = 0
    while b:
        if b & 1:
            p ^= a
        a = ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else a << 1
        b >>= 1
    return p


def _make_tables():
    sbox = [0] * 256
    p = q = 1
    while True:
        # p *= 3, q /= 3 in GF(2^8): q walks the inverses of p
        p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)
        q ^= q << 1
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        if q & 0x80:
            q ^= 0x09
        sbox[p] = q ^ _rotl8(q, 1) ^ _rotl8(q, 2) ^ _rotl8(q, 3) ^ _rotl8(q, 4) ^ 0x63
        if p == 1:
            break
    sbox[0] = 0x63
    inv = [0] * 256
    for i, v in enumerate(sbox):
        inv[v] = i
    mul = {n: [_gmul(i, n) for i in range(256)] for n in (2, 3, 9, 11, 13, 14)}
    return sbox, inv, mul


SBOX, INV_SBOX, MUL = _make_tables()


class AES128:
    def __init__(self, key):
        w = [list(key[i:i + 4]) for i in range(0, 16, 4)]
        rcon = 1
        for i in range(4, 44):
            t = list(w[i - 1])
            if i % 4 == 0:
                t = [SBOX[b] for b in t[1:] + t[:1]]
                t[0] ^= rcon
                rcon = _gmul(rcon, 2)
            w.append([a ^ b for a, b in zip(w[i - 4], t)])
        self.rk = [sum(w[r * 4:r * 4 + 4], []) for r in range(11)]

    def encrypt_block(self, block):
        s = [a ^ b for a, b in zip(block, self.rk[0])]
        m2, m3 = MUL[2], MUL[3]
        for r in range(1, 11):
            s = [SBOX[b] for b in s]
            s = [s[(i + 4 * (i % 4)) % 16] for i in range(16)]  # ShiftRows
            if r != 10:
                t = []
                for c in range(0, 16, 4):
                    a0, a1, a2, a3 = s[c:c + 4]
                    t += [m2[a0] ^ m3[a1] ^ a2 ^ a3, a0 ^ m2[a1] ^ m3[a2] ^ a3,
                          a0 ^ a1 ^ m2[a2] ^ m3[a3], m3[a0] ^ a1 ^ a2 ^ m2[a3]]
                s = t
            s = [a ^ b for a, b in zip(s, self.rk[r])]
        return bytes(s)

    def decrypt_block(self, block):
        s = [a ^ b for a, b in zip(block, self.rk[10])]
        m9, m11, m13, m14 = MUL[9], MUL[11], MUL[13], MUL[14]
        for r in range(9, -1, -1):
            s = [s[(i - 4 * (i % 4)) % 16] for i in range(16)]  # InvShiftRows
            s = [INV_SBOX[b] for b in s]
            s = [a ^ b for a, b in zip(s, self.rk[r])]
            if r != 0:
                t = []
                for c in range(0, 16, 4):
                    a0, a1, a2, a3 = s[c:c + 4]
                    t += [m14[a0] ^ m11[a1] ^ m13[a2] ^ m9[a3], m9[a0] ^ m14[a1] ^ m11[a2] ^ m13[a3],
                          m13[a0] ^ m9[a1] ^ m14[a2] ^ m11[a3], m11[a0] ^ m13[a1] ^ m9[a2] ^ m14[a3]]
                s = t
        return bytes(s)


def cbc_encrypt(key, iv, data):
    aes = AES128(key)
    n = 16 - len(data) % 16
    data += bytes([n]) * n
    out, prev = b'', iv
    for i in range(0, len(data), 16):
        prev = aes.encrypt_block(bytes(a ^ b for a, b in zip(data[i:i + 16], prev)))
        out += prev
    return out


def cbc_decrypt(key, iv, data):
    aes = AES128(key)
    out, prev = b'', iv
    for i in range(0, len(data), 16):
        block = data[i:i + 16]
        out += bytes(a ^ b for a, b in zip(aes.decrypt_block(block), prev))
        prev = block
    n = out[-1] if out else 0
    if not 1 <= n <= 16:
        raise PlugError('bad padding in device response')
    return out[:-n]


# ── KLAP transport ────────────────────────────────────────────────────────────


class PlugError(Exception):
    pass


class AuthError(PlugError):
    pass


def sha256(b):
    return hashlib.sha256(b).digest()


def auth_hashes(username, password):
    """KLAP v2 (Tapo) and v1 (newer Kasa) auth hashes"""
    u, p = username.encode(), password.encode()
    v2 = sha256(hashlib.sha1(u).digest() + hashlib.sha1(p).digest())
    v1 = hashlib.md5(hashlib.md5(u).digest() + hashlib.md5(p).digest()).digest()
    return v2, v1


class Klap:
    def __init__(self, host, auth_v2, auth_v1):
        self.host = host
        self.auth = {2: auth_v2, 1: auth_v1}
        self.cookie = None

    def _post(self, path, body):
        conn = http.client.HTTPConnection(self.host, timeout=TIMEOUT)
        headers = {'Content-Type': 'application/octet-stream'}
        if self.cookie:
            headers['Cookie'] = self.cookie
        try:
            conn.request('POST', path, body, headers)
            resp = conn.getresponse()
            return resp.status, resp.getheader('Set-Cookie'), resp.read()
        except (OSError, http.client.HTTPException) as e:
            raise PlugError('cannot reach %s: %s' % (self.host, e))
        finally:
            conn.close()

    def handshake(self):
        local = os.urandom(16)
        status, cookie, data = self._post('/app/handshake1', local)
        if status != 200 or len(data) != 48:
            raise PlugError('%s is not a KLAP device (handshake1: HTTP %s, %d bytes)'
                            % (self.host, status, len(data)))
        if cookie:
            # Only the session id - the device rejects its own TIMEOUT cookie
            self.cookie = cookie.split(';')[0]
        remote, server_hash = data[:16], data[16:]
        for version in (2, 1):
            auth = self.auth[version]
            if version == 2:
                h1, h2 = sha256(local + remote + auth), sha256(remote + local + auth)
            else:
                h1, h2 = sha256(local + auth), sha256(remote + auth)
            if h1 == server_hash:
                break
        else:
            raise AuthError('the plug rejected the TP-Link account (e-mail and password are case-sensitive)')
        status, _, _ = self._post('/app/handshake2', h2)
        if status != 200:
            raise PlugError('handshake2 failed: HTTP %s' % status)
        self.version = version
        seed = local + remote + auth
        self.key = sha256(b'lsk' + seed)[:16]
        ivseq = sha256(b'iv' + seed)
        self.iv = ivseq[:12]
        self.seq = struct.unpack('>i', ivseq[-4:])[0]
        self.sig = sha256(b'ldk' + seed)[:28]

    def request(self, obj):
        if not hasattr(self, 'key'):
            self.handshake()
        self.seq = (self.seq + 1 + 2 ** 31) % 2 ** 32 - 2 ** 31
        seq = struct.pack('>i', self.seq)
        iv = self.iv + seq
        cipher = cbc_encrypt(self.key, iv, json.dumps(obj).encode())
        body = sha256(self.sig + seq + cipher) + cipher
        status, _, data = self._post('/app/request?seq=%d' % self.seq, body)
        if status != 200:
            raise PlugError('request failed: HTTP %s' % status)
        return json.loads(cbc_decrypt(self.key, iv, data[32:]).decode())


# ── Plug commands (SMART protocol for Tapo / KLAP v2, IOT for Kasa / KLAP v1) ─


class Plug:
    def __init__(self, host, auth_v2, auth_v1):
        self.klap = Klap(host, auth_v2, auth_v1)
        self.terminal = base64.b64encode(hashlib.md5(uuid.uuid4().bytes).digest()).decode()

    def _smart(self, method, params=None):
        req = {'method': method, 'request_time_milis': int(time.time() * 1000),
               'terminal_uuid': self.terminal}
        if params is not None:
            req['params'] = params
        resp = self.klap.request(req)
        if resp.get('error_code', 0) != 0:
            raise PlugError('%s failed: error_code %s' % (method, resp.get('error_code')))
        return resp.get('result', {})

    def _version(self):
        if not hasattr(self.klap, 'version'):
            self.klap.handshake()
        return self.klap.version

    def info(self):
        """(name, model, is_on)"""
        if self._version() == 2:
            r = self._smart('get_device_info')
            try:
                name = base64.b64decode(r.get('nickname', '')).decode()
            except (ValueError, UnicodeDecodeError):
                name = r.get('nickname', '')
            return name, r.get('model', '?'), bool(r.get('device_on'))
        r = self.klap.request({'system': {'get_sysinfo': {}}})['system']['get_sysinfo']
        return r.get('alias', ''), r.get('model', '?'), r.get('relay_state') == 1

    def set_power(self, on):
        if self._version() == 2:
            self._smart('set_device_info', {'device_on': bool(on)})
        else:
            r = self.klap.request({'system': {'set_relay_state': {'state': int(bool(on))}}})
            if r.get('system', {}).get('set_relay_state', {}).get('err_code', 0) != 0:
                raise PlugError('set_relay_state failed: %s' % r)


# ── Discovery (UDP 9999 legacy, 20002/20004 TP-Link TDP probe) ────────────────────────────

# Any RSA public key: the device encrypts its (unused here) encrypt_info with it
DISCOVERY_RSA_KEY = """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu6hn6GRcbsKAY38XVUtE
gdaU/YHlEkDPObcK9MDjTUjGJGW9M5J2UacCCIyQp7fck6X6EeXmvYFsltBdfGW/
1w9mnhrBxC0KQBXkopUr7Z+3ASEJCazmGh5MxpEgw21mIvw3JjQ1QKtl6FMyxb4x
18hbdGlTpCcDytsEPMtXhCeuswVZS79CcjvcYMIEPVMbwLfdtwnHpCg4NuJTfyyG
YMYF5niAUNUPOInYfWprYngATJ1ELA9epw32Fyu7erVwv9z9sMpBSAn2/UiBlyym
0X8lPe1y47aLFNCS72/ASndILhHdpqj+EzXH3f3l7/3e9s1vCW2oS60ASFPX4UCL
xwIDAQAB
-----END PUBLIC KEY-----
"""


def discovery_query():
    payload = json.dumps({'params': {'rsa_key': DISCOVERY_RSA_KEY}}).encode()
    serial = struct.unpack('>I', os.urandom(4))[0]
    query = bytearray(struct.pack('>BBHHBBII', 2, 0, 1, len(payload), 17, 0, serial, 0x5A6B7C8D) + payload)
    query[12:16] = struct.pack('>I', binascii.crc32(bytes(query)) & 0xFFFFFFFF)
    return bytes(query)


def broadcast_addresses():
    addrs = {'255.255.255.255'}
    try:
        out = subprocess.run(['ip', '-o', '-4', 'addr', 'show'], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, timeout=5).stdout.decode()
        addrs.update(re.findall(r'brd (\d+\.\d+\.\d+\.\d+)', out))
    except (OSError, subprocess.SubprocessError):
        pass
    return sorted(addrs)


def xor_encrypt(data):
    """Legacy Kasa protocol (port 9999): XOR autokey cipher"""
    key, out = 171, bytearray()
    for b in data:
        key ^= b
        out.append(key)
    return bytes(out)


def xor_decrypt(data):
    key, out = 171, bytearray()
    for b in data:
        out.append(key ^ b)
        key = b
    return bytes(out)


SYSINFO = json.dumps({'system': {'get_sysinfo': {}}}, separators=(',', ':')).encode()


def _legacy_entry(ip, sysinfo):
    return (ip, sysinfo.get('model', '?'), sysinfo.get('alias') or sysinfo.get('mic_type', '?'),
            sysinfo.get('mac') or sysinfo.get('mic_mac', '?'), 'legacy')


def discover(seconds=4.0):
    """Kasa (and Tapo) devices: legacy ones answer on 9999, KLAP ones on 20002/20004"""
    legacy_query, query, addrs = xor_encrypt(SYSINFO), discovery_query(), broadcast_addresses()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind(('', 0))
    sock.settimeout(0.3)
    found, end, next_send = {}, time.time() + seconds, 0
    while time.time() < end:
        # Repeat the probe: UDP broadcasts get lost on busy Wi-Fi
        if time.time() >= next_send:
            for addr in addrs:
                for port, data in ((9999, legacy_query), (20002, query), (20004, query)):
                    try:
                        sock.sendto(data, (addr, port))
                    except OSError:
                        pass
            next_send = time.time() + 1.0
        try:
            data, (ip, port) = sock.recvfrom(4096)
        except OSError:
            continue  # timeout, or an ICMP "port unreachable" from a host without the service
        try:
            if port == 9999:
                found[ip] = _legacy_entry(ip, json.loads(xor_decrypt(data).decode())['system']['get_sysinfo'])
                continue
            r = json.loads(data[16:].decode())['result']
        except (ValueError, KeyError, TypeError, UnicodeDecodeError):
            continue
        if found.get(ip, ('',) * 5)[4] == 'legacy':
            continue  # answers both: the legacy protocol needs no login
        schm = r.get('mgt_encrypt_schm') or {}
        found[ip] = (r.get('ip', ip), r.get('device_model', '?'), r.get('device_type', '?'),
                     r.get('mac', '?'), schm.get('encrypt_type', '?'))
    sock.close()
    return list(found.values())


def probe(host):
    """Protocol of the plug at host: 'legacy', 'KLAP' or 'none'"""
    try:
        with socket.create_connection((host, 9999), timeout=3) as s:
            s.sendall(struct.pack('>I', len(SYSINFO)) + xor_encrypt(SYSINFO))
            data = b''
            while len(data) < 4 or len(data) < 4 + struct.unpack('>I', data[:4])[0]:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
        json.loads(xor_decrypt(data[4:]).decode())['system']['get_sysinfo']
        return 'legacy'
    except (OSError, ValueError, KeyError, TypeError, UnicodeDecodeError, struct.error):
        pass
    try:
        status, _, data = Klap(host, b'', b'')._post('/app/handshake1', os.urandom(16))
        if status == 200 and len(data) == 48:
            return 'KLAP'
    except PlugError:
        pass
    return 'none'


# ── CLI ───────────────────────────────────────────────────────────────────────


def load_conf():
    try:
        with open(CONF) as f:
            c = json.load(f)
        return Plug(c['host'], bytes.fromhex(c['auth_v2']), bytes.fromhex(c['auth_v1']))
    except (OSError, ValueError, KeyError):
        raise PlugError('no KLAP plug configured - run the Auto Power Off installer (%s missing)' % CONF)


def setup(host):
    print('  Enter the TP-Link account (Kasa / Tapo app) the plug is registered to.')
    username = input('  E-mail: ').strip()
    password = getpass.getpass('  Password: ')
    v2, v1 = auth_hashes(username, password)
    plug = Plug(host, v2, v1)
    name, model, on = plug.info()
    old = os.umask(0o077)
    try:
        with open(CONF, 'w') as f:
            json.dump({'host': host, 'auth_v2': v2.hex(), 'auth_v1': v1.hex()}, f)
    finally:
        os.umask(old)
    os.chmod(CONF, 0o600)
    print('  Connected to "%s" (%s), currently %s.' % (name or 'no name', model, 'on' if on else 'off'))


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ''
    try:
        if cmd == 'discover':
            for dev in discover(float(argv[2]) if len(argv) > 2 else 4.0):
                print('\t'.join(dev))
        elif cmd == 'probe' and len(argv) > 2:
            print(probe(argv[2]))
        elif cmd == 'setup' and len(argv) > 2:
            setup(argv[2])
        elif cmd == 'status':
            name, model, on = load_conf().info()
            print('%s (%s): %s' % (name, model, 'on' if on else 'off'))
        elif cmd in ('on', 'off'):
            plug = load_conf()
            if cmd == 'off':
                os.sync()
            plug.set_power(cmd == 'on')
            print('Plug switched %s' % cmd)
        else:
            print(__doc__.strip())
            return 1
    except AuthError as e:
        print('ERROR: %s' % e, file=sys.stderr)
        return 2
    except PlugError as e:
        print('ERROR: %s' % e, file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
