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

# Switch Dell via DDC/CI
ddcutil setvcp 0x60 "$DELL_INPUT" --bus "$DELL_BUS" --noverify &

# Switch LG via xrandr signal kill (DDC/CI input switching not supported on 27GN880).
# Disabling the output triggers the monitor's auto-input detection.
# We save the full layout and restore both monitors atomically to prevent GNOME rearranging.
if [[ -n "${LG_OUTPUT:-}" ]]; then
    XRANDR_STATE=$(xrandr)
    parse_output() {
        local name=$1
        local line rest geom mode rate pos primary_flag=""
        line=$(echo "$XRANDR_STATE" | grep "^${name} connected")
        [[ "$line" == *" primary "* ]] && primary_flag="--primary"
        geom=$(echo "$line" | grep -oP '\d+x\d+\+\d+\+\d+')
        mode=${geom%%+*}
        pos=${geom#*+}
        rest=$(echo "$XRANDR_STATE" | grep "^${name} connected" -A1 | tail -1)
        rate=$(echo "$rest" | grep -oP '[\d.]+(?=\*)')
        echo "$mode $rate ${pos/+/x} $primary_flag"
    }
    read -r LG_MODE LG_RATE LG_POS LG_PRIMARY <<< "$(parse_output "$LG_OUTPUT")"
    read -r DELL_MODE DELL_RATE DELL_POS DELL_PRIMARY <<< "$(parse_output "$DELL_OUTPUT")"
    (
        xrandr --output "$LG_OUTPUT" --off
        sleep "${LG_SIGNAL_KILL_DELAY:-10}"
        xrandr --output "$LG_OUTPUT" --mode "$LG_MODE" --rate "$LG_RATE" --pos "$LG_POS" $LG_PRIMARY \
               --output "$DELL_OUTPUT" --mode "$DELL_MODE" --rate "$DELL_RATE" --pos "$DELL_POS" $DELL_PRIMARY
    ) &
else
    ddcutil setvcp 0x60 "$LG_INPUT" --bus "$LG_BUS" --noverify &
fi

wait
