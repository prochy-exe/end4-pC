#!/usr/bin/env python3
# Thin JSON wrapper around the `tailscale` CLI - unlike the Keychron scripts
# next door, this is all official/documented: `tailscale status --json` and
# `tailscale debug prefs` for reads, `tailscale set`/`up`/`down` for writes.
# Requires the invoking user to be a Tailscale "operator" (`tailscale set
# --operator=$USER`, or already the case if tailscaled was started as that
# user) so these commands work without sudo - if they're not, every action
# here will just fail with a permission error surfaced in 'error'.
import json
import math
import re
import subprocess
import sys

TAILSCALE = 'tailscale'

# Tailscale's standard hosted DERP relay regions (login.tailscale.com/derpmap/
# default) with approximate city-center coordinates - used to estimate which
# DERP region is geographically nearest to a given Mullvad exit node, so its
# *measured* latency (from `tailscale netcheck`, real RTT from this specific
# client) can stand in for "how fast is this general area for me", since
# there's no cheap way to actually ping 500+ idle peers individually (the
# first ping to a peer with no active session commonly times out - confirmed
# live, a cold `tailscale ping` took the full 5s and failed).
DERP_COORDS = {
    'nyc': (40.7128, -74.0060), 'sfo': (37.7749, -122.4194), 'sin': (1.3521, 103.8198),
    'fra': (50.1109, 8.6821), 'syd': (-33.8688, 151.2093), 'tok': (35.6762, 139.6503),
    'lhr': (51.5074, -0.1278), 'waw': (52.2297, 21.0122), 'par': (48.8566, 2.3522),
    'sao': (-23.5505, -46.6333), 'hkg': (22.3193, 114.1694), 'dbi': (25.2048, 55.2708),
    'blr': (12.9716, 77.5946), 'mad': (40.4168, -3.7038), 'sea': (47.6062, -122.3321),
    'ord': (41.8781, -87.6298), 'iad': (38.9519, -77.4480), 'nue': (49.4521, 11.0767),
    'tor': (43.6532, -79.3832), 'hel': (60.1699, 24.9384), 'jnb': (-26.2041, 28.0473),
    'ams': (52.3676, 4.9041), 'mia': (25.7617, -80.1918), 'den': (39.7392, -104.9903),
    'dfw': (32.7767, -96.7970), 'lax': (34.0522, -118.2437), 'hnl': (21.3069, -157.8583),
    'nai': (-1.2921, 36.8219),
}


def run(args, timeout=5):
    try:
        return subprocess.run(
            [TAILSCALE, *args],
            capture_output=True, text=True, timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(args, 1, '', str(e))


def haversine_km(lat1, lon1, lat2, lon2):
    r = 6371
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def get_derp_latencies():
    """-> {region_code: latency_ms}, omitting regions netcheck couldn't
    measure this run (unreachable/skipped)."""
    proc = run(['netcheck'], timeout=10)
    if proc.returncode != 0:
        return {}
    latencies = {}
    for m in re.finditer(r'-\s+(\w+):\s*([\d.]+)ms', proc.stdout):
        latencies[m.group(1)] = float(m.group(2))
    return latencies


def estimate_latency_ms(lat, lon, derp_latencies):
    """Nearest DERP region (by great-circle distance) that netcheck actually
    measured a latency for - None if no coordinates or no measurements at all."""
    if lat is None or lon is None or not derp_latencies:
        return None
    best = None
    for code, ms in derp_latencies.items():
        coords = DERP_COORDS.get(code)
        if coords is None:
            continue
        dist = haversine_km(lat, lon, coords[0], coords[1])
        if best is None or dist < best[0]:
            best = (dist, ms)
    return best[1] if best else None


def get_status():
    proc = run(['status', '--json'])
    if proc.returncode != 0:
        return None
    try:
        return json.loads(proc.stdout)
    except ValueError:
        return None


def get_prefs():
    proc = run(['debug', 'prefs'])
    if proc.returncode != 0:
        return {}
    try:
        return json.loads(proc.stdout)
    except ValueError:
        return {}


def strip_dns_suffix(name, magic_suffix):
    name = (name or '').rstrip('.')
    if magic_suffix and name.endswith('.' + magic_suffix):
        name = name[:-(len(magic_suffix) + 1)]
    return name


def cmd_status():
    status = get_status()
    if status is None:
        print(json.dumps({
            'installed': True, 'connected': False, 'backend_state': 'Unknown',
            'error': 'tailscaled not reachable (is it running?)',
        }))
        return

    prefs = get_prefs()
    backend_state = status.get('BackendState', 'Unknown')
    self_node = status.get('Self', {})
    magic_suffix = (status.get('CurrentTailnet') or {}).get('MagicDNSSuffix', '')

    exit_node = None
    for peer in status.get('Peer', {}).values():
        if peer.get('ExitNode'):
            location = peer.get('Location') or {}
            is_mullvad = bool(location)
            raw_dns = (peer.get('DNSName') or '').rstrip('.')
            exit_node = {
                'value': strip_dns_suffix(peer.get('DNSName'), magic_suffix),
                'hostname': strip_dns_suffix(peer.get('DNSName'), magic_suffix),
                'id': mullvad_short_id(raw_dns.split('.', 1)[0]) if is_mullvad else '',
                'country': location.get('Country', ''),
                'country_code': location.get('CountryCode', ''),
                'city': location.get('City', ''),
                'is_mullvad': is_mullvad,
            }
            break

    peers = list(status.get('Peer', {}).values())
    online = sum(1 for p in peers if p.get('Online'))

    advertise_routes = prefs.get('AdvertiseRoutes') or []
    advertise_exit_node = '0.0.0.0/0' in advertise_routes and '::/0' in advertise_routes

    print(json.dumps({
        'installed': True,
        'connected': backend_state == 'Running',
        'backend_state': backend_state,
        'needs_login': backend_state == 'NeedsLogin',
        'auth_url': status.get('AuthURL') or None,
        'self': {
            'hostname': self_node.get('HostName', ''),
            'dns_name': strip_dns_suffix(self_node.get('DNSName'), magic_suffix),
            'ips': self_node.get('TailscaleIPs', []),
        },
        'tailnet': (status.get('CurrentTailnet') or {}).get('Name', ''),
        'exit_node': exit_node,
        'peers': {'online': online, 'total': len(peers)},
        'prefs': {
            'accept_routes': bool(prefs.get('RouteAll', False)),
            'accept_dns': bool(prefs.get('CorpDNS', True)),
            'shields_up': bool(prefs.get('ShieldsUp', False)),
            'ssh': bool(prefs.get('RunSSH', False)),
            'exit_node_allow_lan_access': bool(prefs.get('ExitNodeAllowLANAccess', False)),
            'advertise_exit_node': advertise_exit_node,
        },
        'error': None,
    }))


def mullvad_short_id(first_label):
    # Mullvad hostnames look like "<countrycode>-<citycode>-wg-<number>",
    # e.g. "jp-tyo-wg-001" - the "wg-NNN" tail is the only part that tells
    # otherwise-identical "Tokyo, Japan" entries apart.
    m = re.search(r'(wg-\d+)$', first_label)
    return m.group(1) if m else first_label


def get_suggested_exit_node():
    # `tailscale exit-node suggest` picks the best exit node for *this*
    # client based on measured DERP latency, not a static server-side
    # ranking - unlike the "fastest for anyone" Priority field Mullvad
    # attaches to each node's Location, this is actually about your link to
    # it. Prints e.g. "Suggested exit node: foo.tailnet.ts.net.\nTo accept...".
    proc = run(['exit-node', 'suggest'], timeout=5)
    if proc.returncode != 0:
        return None
    m = re.search(r'Suggested exit node:\s*(\S+)', proc.stdout)
    return m.group(1).rstrip('.') if m else None


def cmd_exit_nodes():
    status = get_status()
    if status is None:
        print(json.dumps({'nodes': [], 'recommended': [], 'suggested': None, 'error': 'tailscaled not reachable'}))
        return

    magic_suffix = (status.get('CurrentTailnet') or {}).get('MagicDNSSuffix', '')
    suggested = get_suggested_exit_node()
    derp_latencies = get_derp_latencies()

    nodes = []
    for peer in status.get('Peer', {}).values():
        if not peer.get('ExitNodeOption'):
            continue
        location = peer.get('Location') or {}
        is_mullvad = bool(location)
        raw_dns = (peer.get('DNSName') or '').rstrip('.')
        dns_name = strip_dns_suffix(peer.get('DNSName'), magic_suffix)
        first_label = raw_dns.split('.', 1)[0]
        nodes.append({
            'value': dns_name,
            'hostname': dns_name,
            'id': mullvad_short_id(first_label) if is_mullvad else '',
            'country': location.get('Country', ''),
            'city': location.get('City', ''),
            '_priority': location.get('Priority', -1),
            '_est_latency': estimate_latency_ms(location.get('Latitude'), location.get('Longitude'), derp_latencies),
            'online': bool(peer.get('Online')),
            'active': bool(peer.get('Active')) and bool(peer.get('ExitNode')),
            'is_mullvad': is_mullvad,
            'suggested': suggested is not None and raw_dns == suggested,
        })

    # Tailscale's own UI (`tailscale exit-node list`'s default grouped view)
    # picks the highest-Priority node as "the" recommended one per city, so
    # the same signal is used here to mark a "best in this city" node - this
    # is Mullvad/Tailscale's static per-server recommendation, NOT a live
    # latency measurement to this specific client (that's what `suggested`
    # is, but exit-node suggest isn't scoped to Mullvad-only, so it can - and
    # often will - point at a plain tailnet peer instead).
    best_priority_by_city = {}
    for n in nodes:
        if not n['is_mullvad']:
            continue
        key = (n['country'], n['city'])
        if n['_priority'] > best_priority_by_city.get(key, -1):
            best_priority_by_city[key] = n['_priority']
    for n in nodes:
        n['city_recommended'] = n['is_mullvad'] and n['_priority'] == best_priority_by_city.get((n['country'], n['city']), -1)

    # Top 10: the fastest-*estimated* distinct Mullvad cities (see
    # estimate_latency_ms - nearest-DERP-region latency, not a direct ping to
    # the node itself), represented by that city's city_recommended node.
    best_latency_by_city = {}
    for n in nodes:
        if not n['is_mullvad'] or n['_est_latency'] is None:
            continue
        key = (n['country'], n['city'])
        if key not in best_latency_by_city or n['_est_latency'] < best_latency_by_city[key]:
            best_latency_by_city[key] = n['_est_latency']

    RECOMMENDED_TOTAL = 5

    # Your own tailnet's exit-capable peers always lead the list (usually
    # just one or two devices, and it's your own infrastructure - no reason
    # to bury it under Mullvad cities), then Mullvad fills whatever's left.
    recommended = [n for n in nodes if not n['is_mullvad']]
    slots_left = max(0, RECOMMENDED_TOTAL - len(recommended))
    ranked_cities = sorted(best_latency_by_city.items(), key=lambda kv: kv[1])[:slots_left]
    for (country, city), est_latency in ranked_cities:
        rep = next((n for n in nodes if n['is_mullvad'] and n['country'] == country
                    and n['city'] == city and n['city_recommended']), None)
        if rep:
            recommended.append({**rep, 'estimated_latency_ms': round(est_latency)})

    for n in nodes:
        n['estimated_latency_ms'] = round(n['_est_latency']) if n['_est_latency'] is not None else None
        n.pop('_priority', None)
        n.pop('_est_latency', None)
    # The own-tailnet entries in `recommended` are the SAME dict objects as
    # in `nodes` (not copies, unlike the Mullvad ones built via {**rep, ...}
    # above), so the keys above are already gone for those - pop, not del,
    # or this throws on the second pass over a shared object.
    for n in recommended:
        n.pop('_priority', None)
        n.pop('_est_latency', None)

    # Own-tailnet exit-capable nodes first (no Location), then Mullvad nodes
    # grouped/sorted by country then city then id, so same-city entries stay
    # adjacent instead of shuffling on every refresh.
    nodes.sort(key=lambda n: (n['is_mullvad'], n['country'], n['city'], n['id']))
    print(json.dumps({'nodes': nodes, 'recommended': recommended, 'suggested': suggested, 'error': None}))


def cmd_up():
    # Doesn't wait for interactive login to complete - if one is needed,
    # `tailscale up` prints an AuthURL and blocks, so this is fired with a
    # short timeout and left running; the next status poll picks up
    # AuthURL/BackendState from `tailscale status --json` regardless of
    # whether this particular invocation is still alive.
    proc = run(['up'], timeout=3)
    print(json.dumps({'ok': True, 'note': proc.stdout.strip() or proc.stderr.strip()}))


def cmd_down():
    proc = run(['down'])
    print(json.dumps({'ok': proc.returncode == 0, 'error': proc.stderr.strip() or None}))


def cmd_set_pref(flag, value):
    proc = run(['set', f'--{flag}={value}'])
    print(json.dumps({'ok': proc.returncode == 0, 'error': proc.stderr.strip() or None}))


def cmd_set_exit_node(value):
    proc = run(['set', f'--exit-node={value}'])
    print(json.dumps({'ok': proc.returncode == 0, 'error': proc.stderr.strip() or None}))


def main():
    if len(sys.argv) < 2:
        print(json.dumps({'error': 'missing action'}))
        sys.exit(1)

    action = sys.argv[1]
    args = sys.argv[2:]

    if action == 'status':
        cmd_status()
    elif action == 'exit-nodes':
        cmd_exit_nodes()
    elif action == 'up':
        cmd_up()
    elif action == 'down':
        cmd_down()
    elif action == 'set-pref' and len(args) == 2:
        cmd_set_pref(args[0], args[1])
    elif action == 'set-exit-node' and len(args) == 1:
        cmd_set_exit_node(args[0])
    else:
        print(json.dumps({'error': f'unknown action {action!r} / bad args'}))
        sys.exit(1)


if __name__ == '__main__':
    main()
