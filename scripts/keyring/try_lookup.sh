#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# secret-tool lookup triggers gnome-keyring's own interactive unlock popup
# (via the Secret Service Prompt mechanism) whenever the collection is
# locked - checking first avoids ever spawning that popup as a side effect
# of some service eagerly fetching keyring data at shell startup, before
# the user has had a chance to unlock via our own lock screen flow.
if ! "${SCRIPT_DIR}/is_unlocked.sh"; then
    echo 'locked'
    exit 2
fi

data=$(secret-tool lookup 'application' 'illogical-impulse')
if [[ -z "$data" ]]; then
    echo 'not found'
    exit 1
fi
echo "$data"
