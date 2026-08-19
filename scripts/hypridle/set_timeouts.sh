#!/usr/bin/env bash
# Writes the idle->lock and idle->suspend listener timeouts into
# hypridle.conf and restarts hypridle so they take effect (hypridle has no
# config live-reload/signal, so a restart is the only way).
#
# Usage: set_timeouts.sh <lock_timeout_sec> <sleep_after_lock_sec>
#   lock_timeout_sec:     idle seconds before the lock screen activates
#   sleep_after_lock_sec: additional idle seconds after that before suspend
set -euo pipefail

LOCK_TIMEOUT="$1"
SLEEP_AFTER_LOCK="$2"
SUSPEND_TIMEOUT=$((LOCK_TIMEOUT + SLEEP_AFTER_LOCK))
CONF="$HOME/.config/hypr/hypridle.conf"

[[ -f "$CONF" ]] || exit 0

python3 - "$CONF" "$LOCK_TIMEOUT" "$SUSPEND_TIMEOUT" <<'PY'
import re
import sys

path, lock_timeout, suspend_timeout = sys.argv[1], sys.argv[2], sys.argv[3]

with open(path) as f:
    content = f.read()

def set_timeout(block, seconds):
    # Also refreshes the trailing "# Nmins" comment, which would otherwise
    # go stale (still show the old value) since it's not touched by editing
    # just the number.
    minutes = int(seconds) / 60
    minutes_str = f"{minutes:g}"
    return re.sub(
        r"timeout\s*=\s*\d+(\s*#.*)?",
        f"timeout = {seconds} # {minutes_str}min",
        block,
        count=1,
    )

def rewrite_listener(match):
    block = match.group(0)
    # Identify the listener by its on-timeout command rather than position,
    # so this stays correct if blocks get reordered.
    if "on-timeout" in block and "loginctl lock-session" in block:
        return set_timeout(block, lock_timeout)
    if "$suspend_cmd" in block:
        return set_timeout(block, suspend_timeout)
    return block

# general { } is a different keyword, so this only ever touches listener
# blocks (including the one whose on-timeout also happens to say
# "loginctl lock-session", not general's before_sleep_cmd of the same text).
content = re.sub(r"listener\s*\{[^}]*\}", rewrite_listener, content, flags=re.S)

with open(path, "w") as f:
    f.write(content)
PY

pkill -x hypridle 2>/dev/null || true
sleep 0.2
setsid -f hypridle >/dev/null 2>&1 &
disown
