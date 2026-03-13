#!/usr/bin/env bash
set -euo pipefail

echo "=== KVM-at-Home Installer ==="
echo ""

# --- Step 1: Install prerequisites ---

if ! command -v ddcutil &>/dev/null; then
    echo "Installing ddcutil..."
    sudo apt install -y ddcutil
else
    echo "ddcutil already installed."
fi

# Load i2c-dev module
if ! lsmod | grep -q i2c_dev; then
    echo "Loading i2c-dev kernel module..."
    sudo modprobe i2c-dev
else
    echo "i2c-dev module already loaded."
fi

# Persist module across reboots
if [[ ! -f /etc/modules-load.d/i2c-dev.conf ]]; then
    echo "Persisting i2c-dev module for boot..."
    echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf > /dev/null
fi

# Add user to i2c group
if ! groups "$USER" | grep -q '\bi2c\b'; then
    echo "Adding $USER to i2c group..."
    sudo usermod -aG i2c "$USER"
    echo ""
    echo "NOTE: You were added to the i2c group."
    echo "You may need to log out and back in for this to take effect."
    echo "Alternatively, run: newgrp i2c"
    echo ""
fi

# Apply udev rules immediately
echo "Triggering udev to apply i2c permissions..."
sudo udevadm trigger

echo ""
echo "Prerequisites installed."

# --- Step 2: Detect monitors ---

echo ""
echo "=== Detecting Monitors ==="
echo ""

DETECT_OUTPUT=$(ddcutil detect 2>/dev/null)

if [[ -z "$DETECT_OUTPUT" ]]; then
    echo "ERROR: ddcutil detected no monitors." >&2
    echo "Make sure:" >&2
    echo "  1. Monitors are connected and powered on" >&2
    echo "  2. You have permission to access /dev/i2c-* (try: newgrp i2c)" >&2
    exit 1
fi

echo "$DETECT_OUTPUT"
echo ""

# Parse bus numbers by matching monitor identifiers
# Dell: match "C3422WE" in Model field
# LG: match by product code since LG often uses generic model names like "LG ULTRAGEAR"
DELL_BUS=""
LG_BUS=""

# ddcutil detect outputs blocks per display separated by blank lines
# Each block contains "I2C bus:" and "Model:" or "Product code:" lines
current_bus=""

while IFS= read -r line; do
    # Reset bus at the start of each display block
    if [[ "$line" =~ ^Display\ [0-9]+ ]]; then
        current_bus=""
    fi
    if [[ "$line" =~ I2C\ bus:.*i2c-([0-9]+) ]]; then
        current_bus="${BASH_REMATCH[1]}"
    fi
    # Dell: match model name
    if [[ -n "$current_bus" && "$line" =~ [Mm]odel:.*C3422WE ]]; then
        DELL_BUS="$current_bus"
    fi
    # LG: match model name or product code (LG often reports generic names like "LG ULTRAGEAR")
    if [[ -n "$current_bus" && ("$line" =~ [Mm]odel:.*27GN880 || "$line" =~ [Pp]roduct\ [Cc]ode:.*5b80) ]]; then
        LG_BUS="$current_bus"
    fi
done <<< "$DETECT_OUTPUT"

# Build list of detected monitors for manual selection
declare -a MON_BUSES=()
declare -a MON_LABELS=()
current_bus=""
current_label=""

while IFS= read -r line; do
    if [[ "$line" =~ ^Display\ ([0-9]+) ]]; then
        current_bus=""
        current_label="Display ${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ I2C\ bus:.*i2c-([0-9]+) ]]; then
        current_bus="${BASH_REMATCH[1]}"
    fi
    if [[ -n "$current_bus" && "$line" =~ [Mm]odel:\ *(.+) ]]; then
        current_label="$current_label — ${BASH_REMATCH[1]}"
        MON_BUSES+=("$current_bus")
        MON_LABELS+=("$current_label")
        current_bus=""
    fi
done <<< "$DETECT_OUTPUT"

pick_monitor_bus() {
    local prompt="$1"
    echo "$prompt" >&2
    for i in "${!MON_LABELS[@]}"; do
        echo "  $((i+1))) ${MON_LABELS[$i]}  (bus ${MON_BUSES[$i]})" >&2
    done
    echo "" >&2
    while true; do
        read -rp "Enter number (or press Enter to abort): " choice </dev/tty
        if [[ -z "$choice" ]]; then
            exit 1
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#MON_BUSES[@]} )); then
            echo "${MON_BUSES[$((choice-1))]}"
            return
        fi
        echo "Invalid choice. Try again." >&2
    done
}

if [[ -z "$DELL_BUS" ]]; then
    echo "Could not auto-detect Dell C3422WE."
    DELL_BUS=$(pick_monitor_bus "Which monitor is the Dell?")
    echo ""
fi

if [[ -z "$LG_BUS" ]]; then
    echo "Could not auto-detect LG 27GN880."
    LG_BUS=$(pick_monitor_bus "Which monitor is the LG?")
    echo ""
fi

echo "Dell C3422WE found on bus: $DELL_BUS"
echo "LG 27GN880 found on bus: $LG_BUS"

# --- Step 3: Read current input sources ---

echo ""
echo "=== Reading Current Input Sources ==="
echo ""

DELL_CURRENT=$(ddcutil getvcp 0x60 --bus "$DELL_BUS" 2>/dev/null) || DELL_CURRENT="(could not read — DDC/CI may be disabled in OSD)"
LG_CURRENT=$(ddcutil getvcp 0x60 --bus "$LG_BUS" 2>/dev/null) || LG_CURRENT="(could not read — DDC/CI may be disabled in OSD)"

echo "Dell current input: $DELL_CURRENT"
echo "LG current input: $LG_CURRENT"

# --- Step 4: User selects other machine's input ---

echo ""
echo "=== Select Other Machine's Inputs ==="
echo ""

# Parse input source options from ddcutil capabilities output
# Returns hex codes in INPUT_CODES array and labels in INPUT_LABELS array
parse_input_sources() {
    local bus="$1"
    INPUT_CODES=()
    INPUT_LABELS=()
    local caps_output in_feature60=0
    caps_output=$(ddcutil capabilities --bus "$bus" 2>/dev/null || true)

    while IFS= read -r line; do
        if [[ "$line" =~ Feature:\ 60 ]]; then
            in_feature60=1
            continue
        fi
        if (( in_feature60 )) && [[ "$line" =~ Feature: ]]; then
            break
        fi
        if (( in_feature60 )) && [[ "$line" =~ ([0-9a-fA-F]{2}):\ *(.+) ]]; then
            INPUT_CODES+=("0x${BASH_REMATCH[1]}")
            INPUT_LABELS+=("${BASH_REMATCH[2]}")
        fi
    done <<< "$caps_output"
}

pick_input_source() {
    local monitor_name="$1" bus="$2"

    parse_input_sources "$bus"

    if [[ ${#INPUT_CODES[@]} -eq 0 ]]; then
        echo "Could not read input options for $monitor_name." >&2
        echo "(DDC/CI may be disabled in the monitor's OSD)" >&2
        read -rp "Enter the hex input code manually (e.g., 0x11): " manual_code </dev/tty
        if [[ -z "$manual_code" ]]; then
            echo "ERROR: No input code provided. Aborting." >&2
            exit 1
        fi
        if [[ ! "$manual_code" =~ ^0x ]]; then manual_code="0x$manual_code"; fi
        echo "$manual_code"
        return
    fi

    echo "--- $monitor_name available inputs ---" >&2
    for i in "${!INPUT_CODES[@]}"; do
        echo "  $((i+1))) ${INPUT_LABELS[$i]}  (${INPUT_CODES[$i]})" >&2
    done
    echo "" >&2
    while true; do
        read -rp "Select the OTHER machine's input for $monitor_name: " choice </dev/tty
        if [[ -z "$choice" ]]; then
            echo "ERROR: No input selected. Aborting." >&2
            exit 1
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#INPUT_CODES[@]} )); then
            echo "${INPUT_CODES[$((choice-1))]}"
            return
        fi
        echo "Invalid choice. Try again." >&2
    done
}

DELL_TARGET=$(pick_input_source "Dell C3422WE" "$DELL_BUS")
echo "Selected: $DELL_TARGET"
echo ""

LG_TARGET=$(pick_input_source "LG 27GN880" "$LG_BUS")
echo "Selected: $LG_TARGET"

# --- Step 5: Write config ---

CONFIG_DIR="${HOME}/.config/kvm-at-home"
CONFIG_FILE="${CONFIG_DIR}/config"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<CONF
# KVM-at-Home configuration
# Generated by install.sh on $(date)
# Input codes point to the OTHER machine's input on each monitor.

# LG 27GN880
LG_BUS=$LG_BUS
LG_INPUT=$LG_TARGET

# Dell C3422WE
DELL_BUS=$DELL_BUS
DELL_INPUT=$DELL_TARGET
CONF

echo ""
echo "Config written to: $CONFIG_FILE"
cat "$CONFIG_FILE"

# --- Step 6: Register GNOME keybinding ---

echo ""
echo "=== Registering GNOME Keybinding ==="
echo ""

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/kvm-switch.sh"
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "ERROR: kvm-switch.sh not found at $SCRIPT_PATH" >&2
    echo "Make sure install.sh and kvm-switch.sh are in the same directory." >&2
    exit 1
fi
KB_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kvm-switch/"

# Set the keybinding properties
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KB_PATH name "KVM Switch"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KB_PATH command "$SCRIPT_PATH"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$KB_PATH binding "<Ctrl><Alt>p"

# Add to the custom-keybindings array (must include existing entries)
EXISTING=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)

if [[ "$EXISTING" == "@as []" || "$EXISTING" == "[]" || -z "$EXISTING" ]]; then
    # Empty array
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$KB_PATH']"
elif [[ "$EXISTING" != *"$KB_PATH"* ]]; then
    # Append to existing array — strip @as type hint and outer brackets, re-wrap
    EXISTING_CLEAN="${EXISTING#@as }"
    EXISTING_INNER="${EXISTING_CLEAN#\[}"
    EXISTING_INNER="${EXISTING_INNER%\]}"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[${EXISTING_INNER}, '$KB_PATH']"
else
    echo "Keybinding already registered."
fi

echo "Keybinding registered: Ctrl+Alt+P -> $SCRIPT_PATH"
echo ""
echo "=== Installation Complete ==="
echo ""
echo "Press Ctrl+Alt+P to switch monitors."
echo ""
echo "If switching doesn't work, check:"
echo "  1. You may need to log out and back in (i2c group)"
echo "  2. Enable DDC/CI in each monitor's OSD settings"
echo "  3. Run 'ddcutil detect' to verify monitor communication"
