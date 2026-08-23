#!/usr/bin/env python3
# Talks to Keychron wireless peripherals over raw hidraw. Written and tested
# against exactly one keyboard (Q3 HE) and one mouse (M6 8K, via its
# Ultra-Link 8K receiver) - see PROTOCOL NOTES below for what was actually
# confirmed live vs read from source. Device *matching* (which hidraw node is
# "the mouse", "the keyboard", "a receiver") is done generically from HID
# usage pages and USB product-string patterns rather than a hardcoded model
# list, on the theory that Keychron's wireless peripherals share the same
# vendor HID protocol and receiver naming convention across the current
# lineup - but this is unverified beyond the two devices above. If something
# here misbehaves on a different model, that's expected; treat it as
# best-effort, not a guarantee.
#
# PROTOCOL NOTES
#  - mouse battery/profile: community reverse-engineering of Keychron's
#    vendor HID protocol (report 0xB3/cmd 0x06 -> 0xB4 response, battery at
#    offset 20, current profile index at offset 2), confirmed live against
#    an Ultra-Link 8K receiver and a directly-wired M6 8K. Profile select is
#    report 0xB5/cmd 0x0E <index> 0x02 -> 0xB6 ack (success = byte[2] == 0),
#    recovered from a live USB capture of the Keychron Launcher web app
#    switching profiles. The number of profile slots isn't exposed by any
#    command found in the capture, so it's live-probed once per device (see
#    detect_mouse_profile_count) and cached.
#  - mouse wired/charging mode: plugging the M6 8K in over USB while it's set
#    to 2.4G exposes it directly on its own PID - its RF radio appears to
#    power down while wired, since the dongle then stops answering entirely.
#    While charging, the battery byte comes back as (100 + real percentage)
#    instead of a plain 0-100 value - confirmed live and stable across
#    repeated reads (155 while charging ~55%, ticking up over time).
#  - keyboard HE profile info/select: read directly from Keychron's own open
#    QMK firmware (keyboards/keychron/common/analog_matrix/analog_matrix.c,
#    AMC_GET_PROFILES_INFO=0x10 / AMC_SELECT_PROFILE=0x11 under command group
#    0xA9), confirmed live via USB capture and a real profile switch/readback
#    on the Q3 HE. Non-HE Keychron keyboards won't have this at all - they'll
#    just get no response, which is handled as "no profile info available".
#  - keyboard battery: the firmware has no HID query for this at all (checked
#    in source, and via a live capture that showed zero related traffic while
#    the vendor's own Launcher app was connected and "doing a whole bunch of
#    stuff"), regardless of connection mode. Only available over Bluetooth,
#    via the standard BlueZ battery service.
#  - keyboard wired-vs-2.4G with cable plugged in: unlike the mouse, plugging
#    a cable in does NOT stop the 2.4G link if the physical mode switch is
#    still set to 2.4G - keystrokes keep flowing over the dongle (confirmed
#    live: 111 boot-keyboard reports on the dongle interface, 0 on the wired
#    one, while a cable was plugged in purely for charging). Worse, the
#    AMC/VIA config channel answers over USB either way, so "does AMC
#    respond" can't be used as a proxy for "is USB the active input path"
#    either (also confirmed live). There's no HID query for which path is
#    actually active, so the only ground truth is which boot-keyboard
#    interface is actually emitting reports - see detect_kb_link, which
#    passively listens for a short window and remembers the last interface
#    it actually saw traffic on.
#  - receiver vs direct-connection classification: Keychron's 2.4G receivers
#    all seem to carry "Link" in their USB product string ("Keychron Link",
#    "Keychron Ultra-Link 8K", ...) while the peripherals themselves are
#    named after the model ("Keychron Q3 HE", "Keychron M6 8K"). Used here to
#    tell receivers apart from directly-wired devices without hardcoding
#    PIDs; unverified beyond the two receivers above.
import fcntl
import json
import os
import re
import select
import struct
import subprocess
import sys
import time

VENDOR_KEYCHRON = 0x3434

VIA_USAGE_PAGE = 0xFF60          # raw HID (AMC / KC_* commands) - keyboard side
MOUSE_STATUS_USAGE_PAGE = 0xFFC1  # vendor status page carrying 0xB3/0xB4/0xB5/0xB6 - mouse side
BOOT_USAGE_PAGE = 0x1             # standard Generic Desktop collection
BOOT_KEYBOARD_USAGE = 0x6
BOOT_MOUSE_USAGE = 0x2

CACHE_DIR = os.path.dirname(os.path.abspath(__file__))
LINK_CACHE_PATH = os.path.join(CACHE_DIR, '.kb_link_cache.json')
LINK_CACHE_MAX_AGE = 120  # seconds - how long a stale "last seen active" guess stays trusted

HIDIOCGRDESCSIZE = 0x80044801
HIDIOCGRDESC = 0x90044802
HIDIOCGRAWINFO = 0x80084803


def _hidiocsfeature(fd, data):
    ln = len(data)
    req = (3 << 30) | (ord('H') << 8) | 0x06 | (ln << 16)
    fcntl.ioctl(fd, req, bytearray(data))


def _rdesc_info(path):
    fd = os.open(path, os.O_RDWR)
    try:
        size_buf = fcntl.ioctl(fd, HIDIOCGRDESCSIZE, struct.pack('i', 0))
        size = struct.unpack('i', size_buf)[0]
        req = bytearray(struct.pack('i', size) + b'\x00' * 4096)
        fcntl.ioctl(fd, HIDIOCGRDESC, req)
        desc = bytes(req[4:4 + size])
        rawinfo = fcntl.ioctl(fd, HIDIOCGRAWINFO, b'\x00' * 8)
        _bustype, vendor, product = struct.unpack('<iHH', rawinfo)
        return desc, vendor, product
    finally:
        os.close(fd)


def _usage_page_and_usage(desc):
    i = 0
    usage_page = None
    usage = None
    while i < len(desc):
        item = desc[i]
        size = item & 0x03
        size = 4 if size == 3 else size
        tag = item & 0xFC
        i += 1
        val = 0
        for b in range(size):
            val |= desc[i + b] << (8 * b)
        i += size
        if tag == 0x04 and usage_page is None:
            usage_page = val
        if tag == 0x08 and usage is None:
            usage = val
        if usage_page is not None and usage is not None:
            break
    return usage_page, usage


def _find_usb_device_dir(interface_dir):
    """Walks up from a hidraw's sysfs interface directory to the parent USB
    device directory (the one with idVendor/product, not the per-interface
    subdirectory)."""
    d = interface_dir
    for _ in range(6):
        if os.path.exists(os.path.join(d, 'idVendor')):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent
    return None


def _usb_product_name(hidraw_name):
    try:
        iface_dir = os.path.realpath(f'/sys/class/hidraw/{hidraw_name}/device')
        dev_dir = _find_usb_device_dir(iface_dir)
        if not dev_dir:
            return ''
        with open(os.path.join(dev_dir, 'product')) as f:
            return f.read().strip()
    except OSError:
        return ''


def enumerate_keychron_nodes():
    """-> list of dict(path, pid, usage_page, usage, product, is_receiver)"""
    nodes = []
    try:
        entries = os.listdir('/dev')
    except OSError:
        return nodes
    for name in entries:
        if not name.startswith('hidraw'):
            continue
        path = f'/dev/{name}'
        try:
            desc, vendor, pid = _rdesc_info(path)
        except OSError:
            continue
        if vendor != VENDOR_KEYCHRON:
            continue
        usage_page, usage = _usage_page_and_usage(desc)
        product = _usb_product_name(name)
        nodes.append({
            'path': path,
            'pid': pid,
            'usage_page': usage_page,
            'usage': usage,
            'product': product,
            'is_receiver': 'link' in product.lower(),
        })
    return nodes


def _group_by_pid(nodes):
    groups = {}
    for n in nodes:
        g = groups.setdefault(n['pid'], {'nodes': [], 'product': n['product'], 'is_receiver': n['is_receiver']})
        g['nodes'].append(n)
    return groups


def _group_has(group, usage_page, usage=None):
    return any(n['usage_page'] == usage_page and (usage is None or n['usage'] == usage) for n in group['nodes'])


def _node_path(group, usage_page, usage=None):
    for n in group['nodes']:
        if n['usage_page'] == usage_page and (usage is None or n['usage'] == usage):
            return n['path']
    return None


def discover_role(nodes, role):
    """Finds every Keychron USB product currently on the bus that looks like
    the given role ('mouse' or 'keyboard'), split into direct (wired) and
    receiver groups. A device is classified purely from which HID usage
    pages it exposes, not its PID, so unrecognized models still get picked
    up automatically as long as they speak the same vendor protocols."""
    direct, receiver = [], []
    for group in _group_by_pid(nodes).values():
        if role == 'mouse':
            is_role = _group_has(group, MOUSE_STATUS_USAGE_PAGE)
        else:
            is_role = _group_has(group, VIA_USAGE_PAGE) and _group_has(group, BOOT_USAGE_PAGE, BOOT_KEYBOARD_USAGE)
        if not is_role:
            continue
        (receiver if group['is_receiver'] else direct).append(group)
    return direct, receiver


def _mouse_drain(fd):
    while True:
        r, _, _ = select.select([fd], [], [], 0.05)
        if not r:
            return
        os.read(fd, 64)


def _mouse_send(fd, report_id, payload, timeout=1.0):
    """Sends a 64-byte FEATURE report and returns every response read back
    within `timeout` (the mouse can emit more than one report per command)."""
    report = bytearray(64)
    report[0] = report_id
    for i, b in enumerate(payload):
        report[1 + i] = b
    _hidiocsfeature(fd, bytes(report))
    responses = []
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], max(0, deadline - time.time()))
        if not r:
            break
        responses.append(os.read(fd, 64))
    return responses


def query_mouse_status(path, timeout=1.0, retries=3):
    """Returns {'battery': 0-100 or None, 'charging': bool, 'profile': 0-based
    index or None}. battery/profile are None if the mouse didn't answer (it's
    frequently asleep, notably right after boot, or its radio is off while
    wired-charging)."""
    fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
    try:
        for _ in range(retries):
            _mouse_drain(fd)
            for data in _mouse_send(fd, 0xB3, [0x06], timeout=timeout):
                if len(data) > 20 and data[0] == 0xB4 and data[1] == 0x06:
                    raw = data[20]
                    charging = raw > 100
                    battery = (raw - 100) if charging else raw
                    if battery > 100:
                        battery = None
                    return {'battery': battery, 'charging': charging, 'profile': data[2]}
        return {'battery': None, 'charging': False, 'profile': None}
    finally:
        os.close(fd)


def select_mouse_profile(path, index):
    fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
    try:
        _mouse_drain(fd)
        for resp in _mouse_send(fd, 0xB5, [0x0E, index, 0x02]):
            if resp[0] == 0xB6 and resp[3] == 0x0E:
                return resp[2] == 0x00
        return False
    finally:
        os.close(fd)


def _mouse_profile_count_cache_path(pid):
    return os.path.join(CACHE_DIR, f'.mouse_profile_count_{pid:04x}.json')


def detect_mouse_profile_count(path, pid, max_slots=8):
    """No command was found that reports how many profile slots a mouse has
    (see PROTOCOL NOTES), so this live-probes indices 0..max_slots-1 once per
    PID and caches the result - selecting an already-active or genuinely
    invalid slot both come back as a distinguishable ack, so this is safe to
    run, but it does cause a brief real profile switch/flicker the first time
    a given mouse is seen. Returns None if the mouse didn't answer at all."""
    cache_path = _mouse_profile_count_cache_path(pid)
    try:
        with open(cache_path) as f:
            return json.load(f)['count']
    except (OSError, ValueError, KeyError):
        pass

    status = query_mouse_status(path)
    if status['profile'] is None:
        return None
    baseline = status['profile']

    valid = []
    for idx in range(max_slots):
        if select_mouse_profile(path, idx):
            valid.append(idx)
    select_mouse_profile(path, baseline)

    count = (max(valid) + 1) if valid else 1
    try:
        with open(cache_path, 'w') as f:
            json.dump({'count': count}, f)
    except OSError:
        pass
    return count


def _kb_raw_hid_query(path, cmd, sub, arg=None, timeout=1.0):
    fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
    try:
        report = bytearray(32)
        report[0] = cmd
        report[1] = sub
        if arg is not None:
            report[2] = arg
        try:
            os.write(fd, bytes(report))
        except OSError:
            return None
        r, _, _ = select.select([fd], [], [], timeout)
        if not r:
            return None
        return os.read(fd, 32)
    finally:
        os.close(fd)


def get_profile_info(path):
    resp = _kb_raw_hid_query(path, 0xA9, 0x10, timeout=0.6)
    if not resp or resp[0] != 0xA9 or resp[1] != 0x10:
        return None
    return {'current': resp[2], 'count': resp[3]}


def select_kb_profile(path, index):
    resp = _kb_raw_hid_query(path, 0xA9, 0x11, arg=index, timeout=1.0)
    if not resp or resp[0] != 0xA9 or resp[1] != 0x11:
        return False
    return resp[2] == 0x00


def bt_devices(state):
    try:
        out = subprocess.run(
            ['bluetoothctl', 'devices', state],
            capture_output=True, text=True, timeout=2,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    devices = []
    for line in out.splitlines():
        parts = line.split(' ', 2)
        if len(parts) == 3:
            devices.append((parts[1], parts[2]))
    return devices


def bt_battery_percent(mac):
    try:
        out = subprocess.run(
            ['upower', '-i', f'/org/freedesktop/UPower/devices/battery_dev_{mac.replace(":", "_")}'],
            capture_output=True, text=True, timeout=2,
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith('percentage:'):
            try:
                return int(line.split(':', 1)[1].strip().rstrip('%'))
            except ValueError:
                return None
    return None


def bt_connected_keychron(role):
    """Best-effort: matches any connected BT device with 'keychron' in its
    name, then guesses mouse-vs-keyboard from Keychron's model-naming
    convention (mice are 'M' + a digit, e.g. M3/M6; everything else in their
    current lineup is a keyboard). Unverified beyond that convention."""
    for mac, name in bt_devices('Connected'):
        if 'keychron' not in name.lower():
            continue
        is_mouse = re.search(r'\bM\d', name) is not None
        if (role == 'mouse') == is_mouse:
            return mac
    return None


def mouse_status_group(nodes):
    """Wired takes priority: when plugged in over USB the mouse's radio
    appears to power down, so the receiver stops answering entirely."""
    direct, receiver = discover_role(nodes, 'mouse')
    if direct:
        return direct[0], 'USB (wired)'
    if receiver:
        return receiver[0], '2.4G dongle'
    return None, None


def mouse_status(nodes):
    group, connection = mouse_status_group(nodes)
    if group is None:
        return {'connected': False, 'connection': None, 'battery': None, 'charging': False, 'profile': None}

    status_path = _node_path(group, MOUSE_STATUS_USAGE_PAGE)
    status = query_mouse_status(status_path)
    profile = None
    if status['profile'] is not None:
        count = detect_mouse_profile_count(status_path, group['nodes'][0]['pid'])
        if count is not None:
            profile = {'current': status['profile'], 'count': count}
    return {
        'connected': True,
        'connection': connection,
        'battery': status['battery'],
        'charging': status['charging'],
        'profile': profile,
    }


def _load_link_cache():
    try:
        with open(LINK_CACHE_PATH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _save_link_cache(link):
    try:
        with open(LINK_CACHE_PATH, 'w') as f:
            json.dump({'link': link, 'ts': time.time()}, f)
    except OSError:
        pass


def detect_kb_link(direct, receiver, window=0.25):
    """Figures out which of wired-USB/2.4G-dongle is actually carrying the
    keyboard's keystrokes right now (see PROTOCOL NOTES for why this can't be
    done with a single query). Returns 'wired', '2.4g', or None (neither
    present at all)."""
    wired_boot = _node_path(direct[0], BOOT_USAGE_PAGE, BOOT_KEYBOARD_USAGE) if direct else None
    dongle_boot = _node_path(receiver[0], BOOT_USAGE_PAGE, BOOT_KEYBOARD_USAGE) if receiver else None

    if wired_boot and not dongle_boot:
        return 'wired'
    if dongle_boot and not wired_boot:
        return '2.4g'
    if not wired_boot and not dongle_boot:
        return None

    # Both enumerated (e.g. cable plugged in purely to charge while still on
    # 2.4G) - passively listen for a moment to see which one is actually
    # live, since presence alone doesn't tell us that.
    fds = {}
    try:
        fds[os.open(wired_boot, os.O_RDONLY | os.O_NONBLOCK)] = 'wired'
        fds[os.open(dongle_boot, os.O_RDONLY | os.O_NONBLOCK)] = '2.4g'
        deadline = time.time() + window
        while time.time() < deadline:
            r, _, _ = select.select(list(fds.keys()), [], [], max(0, deadline - time.time()))
            for fd in r:
                os.read(fd, 64)
                link = fds[fd]
                _save_link_cache(link)
                return link
    finally:
        for fd in fds:
            os.close(fd)

    cached = _load_link_cache()
    if cached and (time.time() - cached['ts']) < LINK_CACHE_MAX_AGE:
        return cached['link']

    return 'wired'


def keyboard_status(nodes):
    direct, receiver = discover_role(nodes, 'keyboard')
    link = detect_kb_link(direct, receiver)

    # The AMC/VIA config channel answers over USB regardless of which link is
    # actually carrying input (confirmed live), so it's tried independently
    # of the connection label below - profile switching can still work over
    # a charging-only cable even while 2.4G carries the keystrokes.
    via_path = _node_path(direct[0], VIA_USAGE_PAGE) if direct else None
    info = get_profile_info(via_path) if via_path else None

    if link == 'wired':
        return {
            'connected': True,
            'connection': 'USB (wired)',
            'battery': None,
            'battery_source': None,
            'profile': info,
        }
    if link == '2.4g':
        return {
            'connected': True,
            'connection': '2.4G dongle',
            'battery': None,
            'battery_source': None,
            'profile': info,
        }

    mac = bt_connected_keychron('keyboard')
    if mac:
        return {
            'connected': True,
            'connection': 'Bluetooth',
            'battery': bt_battery_percent(mac),
            'battery_source': 'bluez' if bt_battery_percent(mac) is not None else None,
            'profile': None,
        }

    return {'connected': False, 'connection': None, 'battery': None, 'battery_source': None, 'profile': None}


def keyboard_raw_hid_node(nodes):
    # Only a direct wired connection answers AMC/VIA commands (confirmed live
    # - a 2.4G receiver never responds, even mid-keystroke), so that's the
    # only path worth trying here.
    direct, _receiver = discover_role(nodes, 'keyboard')
    return _node_path(direct[0], VIA_USAGE_PAGE) if direct else None


def cmd_status():
    nodes = enumerate_keychron_nodes()
    print(json.dumps({
        'mouse': mouse_status(nodes),
        'keyboard': keyboard_status(nodes),
    }))


def cmd_select_kb_profile(index):
    nodes = enumerate_keychron_nodes()
    node = keyboard_raw_hid_node(nodes)
    if node is None:
        print(json.dumps({'ok': False, 'error': 'keyboard not reachable over USB/2.4G'}))
        return
    ok = select_kb_profile(node, index)
    print(json.dumps({'ok': ok}))


def cmd_select_mouse_profile(index):
    nodes = enumerate_keychron_nodes()
    group, _connection = mouse_status_group(nodes)
    if group is None:
        print(json.dumps({'ok': False, 'error': 'mouse not reachable'}))
        return
    node = _node_path(group, MOUSE_STATUS_USAGE_PAGE)
    ok = select_mouse_profile(node, index)
    print(json.dumps({'ok': ok}))


def main():
    usage = 'usage: keychron_ctl.py status|select-kb-profile <index>|select-mouse-profile <index>'
    if len(sys.argv) < 2:
        print(json.dumps({'error': usage}))
        sys.exit(1)

    action = sys.argv[1]
    if action == 'status':
        cmd_status()
    elif action == 'select-kb-profile':
        if len(sys.argv) < 3:
            print(json.dumps({'ok': False, 'error': 'missing profile index'}))
            sys.exit(1)
        cmd_select_kb_profile(int(sys.argv[2]))
    elif action == 'select-mouse-profile':
        if len(sys.argv) < 3:
            print(json.dumps({'ok': False, 'error': 'missing profile index'}))
            sys.exit(1)
        cmd_select_mouse_profile(int(sys.argv[2]))
    else:
        print(json.dumps({'error': f'unknown action {action}'}))
        sys.exit(1)


if __name__ == '__main__':
    main()
