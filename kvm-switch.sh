#!/usr/bin/env bash
set -euo pipefail

CONFIG="${HOME}/.config/kvm-at-home/config"

if [[ ! -f "$CONFIG" ]]; then
    notify-send "KVM Switch" "Config not found. Run install.sh first." 2>/dev/null || true
    echo "ERROR: Config file not found: $CONFIG" >&2
    echo "Run install.sh first." >&2
    exit 1
fi

source "$CONFIG"

# Switch both monitors in parallel
ddcutil setvcp 0x60 "$LG_INPUT" --bus "$LG_BUS" --noverify &
ddcutil setvcp 0x60 "$DELL_INPUT" --bus "$DELL_BUS" --noverify &
wait
