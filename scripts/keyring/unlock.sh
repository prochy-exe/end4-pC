#!/usr/bin/env bash
# Unlocks the login keyring collection of whichever gnome-keyring-daemon is
# currently registered on the session D-Bus (org.freedesktop.secrets) - it
# may have been started by Hyprland's exec-once, by D-Bus's own service
# activation (/usr/share/dbus-1/services/org.freedesktop.secrets.service -
# merely CHECKING the lock state via busctl is enough to trigger this), or
# by a previous run of this script.
#
# Approaches confirmed NOT to work by direct testing against a live daemon:
# - `gnome-keyring-daemon --unlock` alone: always exits 0 regardless of
#   whether the password was even correct, and never actually unlocks the
#   existing daemon's collection - a dead end masquerading as success.
# - killall + fresh `--login` daemon: races D-Bus's own activation of
#   org.freedesktop.secrets - in the gap between the kill and the new daemon
#   claiming the bus name, D-Bus can activate a competing, freshly-locked
#   daemon, and everything afterward may end up talking to that one instead.
#   Reproduced live: a bare `is_unlocked.sh` check alone was enough to spawn
#   a competing daemon during that gap.
# - `--replace` without `--foreground`: silently fails to actually take over
#   the bus name (the old daemon stays the owner) and leaves an orphaned
#   process behind.
#
# `--replace --unlock --foreground` is the one combination that reliably and
# atomically takes over the existing daemon's bus registration (no killall,
# no gap, no orphaned process) while correctly validating the password
# against it. It has to be started detached since, once it takes over, it
# runs forever as the new persistent daemon rather than exiting.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip if already unlocked
if "${SCRIPT_DIR}/is_unlocked.sh"; then
    exit 1
fi

# Prompt for password if not provided
if [[ -z "${UNLOCK_PASSWORD}" ]]; then
    echo -n 'Login password: ' >&2
    read -s UNLOCK_PASSWORD || exit 1
fi

echo -n "${UNLOCK_PASSWORD}" | setsid gnome-keyring-daemon --replace --unlock --components=secrets --foreground >/dev/null 2>&1 &
disown
unset UNLOCK_PASSWORD

# --replace's own exit code isn't a reliable success signal either (see
# above) - give the handshake a moment to complete, then report the real
# outcome via the same lock-state check callers already trust.
sleep 0.5
"${SCRIPT_DIR}/is_unlocked.sh"
