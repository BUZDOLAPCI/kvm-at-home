#!/usr/bin/env bash
set -euo pipefail

readonly MONITOR_MODEL="DELL U5226KW"
readonly INPUT_A="0x11"
readonly INPUT_B="0x12"
readonly INPUT_A_LABEL="HDMI 1"
readonly INPUT_B_LABEL="HDMI 2"
readonly SHORTCUT="<Ctrl><Alt>p"
readonly KEYBINDING_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kvm-switch/"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="${HOME}/.local/bin/kvm-at-home"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kvm-at-home"
CONFIG_FILE="${CONFIG_DIR}/config"

printf '%s\n' "=== U5226KW KVM Installer ==="

if ! command -v ddcutil >/dev/null 2>&1; then
    printf '%s\n' "Installing ddcutil..."
    sudo apt-get install -y ddcutil
fi

if ! compgen -G '/dev/i2c-*' >/dev/null; then
    printf '%s\n' "Loading i2c-dev..."
    sudo modprobe i2c-dev
fi

if [[ ! -f /etc/modules-load.d/i2c-dev.conf ]]; then
    printf 'i2c-dev\n' | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
fi

if ! id -nG "$USER" | tr ' ' '\n' | grep -qx i2c; then
    sudo usermod -aG i2c "$USER"
    printf '%s\n' "Added $USER to the i2c group. Log out and back in before using the shortcut."
fi

command -v gsettings >/dev/null 2>&1 || {
    printf '%s\n' "ERROR: gsettings is required for GNOME shortcut registration." >&2
    exit 1
}

if ! ddcutil detect --brief | grep -Fq "$MONITOR_MODEL"; then
    printf 'ERROR: %s was not detected by ddcutil.\n' "$MONITOR_MODEL" >&2
    exit 1
fi

if ! current_source="$(ddcutil getvcp 0x60 --model "$MONITOR_MODEL" --terse)"; then
    printf 'ERROR: Cannot read the current input source for %s.\n' "$MONITOR_MODEL" >&2
    exit 1
fi

install -Dm755 "$SCRIPT_DIR/kvm-switch.sh" "$INSTALL_PATH"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

config_tmp="$(mktemp)"
trap 'rm -f "$config_tmp"' EXIT
cat > "$config_tmp" <<EOF
# Dell U5226KW input pair
monitor_model=$MONITOR_MODEL
input_a=$INPUT_A
input_b=$INPUT_B
EOF
install -m600 "$config_tmp" "$CONFIG_FILE"

gsettings set \
    org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$KEYBINDING_PATH" \
    name "U5226KW KVM Switch"
gsettings set \
    org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$KEYBINDING_PATH" \
    command "$INSTALL_PATH"
gsettings set \
    org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$KEYBINDING_PATH" \
    binding "$SHORTCUT"

existing="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"
updated="$(
    python3 - "$existing" "$KEYBINDING_PATH" <<'PY'
import ast
import sys

raw, target = sys.argv[1:]
if raw.startswith("@as "):
    raw = raw[4:]
paths = ast.literal_eval(raw)
if target not in paths:
    paths.append(target)
print(repr(paths))
PY
)"
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated"

printf '\nInstalled command: %s\n' "$INSTALL_PATH"
printf 'Config: %s\n' "$CONFIG_FILE"
printf 'Shortcut: Ctrl+Alt+P\n'
printf 'Current source: %s\n' "$current_source"
printf 'Configured pair: %s (%s) <-> %s (%s)\n' \
    "$INPUT_A_LABEL" "$INPUT_A" "$INPUT_B_LABEL" "$INPUT_B"
printf '\nConfigure the monitor OSD before switching:\n'
printf '  HDMI 1 -> USB-C 2\n'
printf '  HDMI 2 -> USB-C 3\n'
printf '  Ethernet Switch Mode -> Tie to KVM\n'
printf '  PIP/PBP -> Off\n'
