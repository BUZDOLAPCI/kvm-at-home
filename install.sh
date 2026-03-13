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
    # Reset bus between display blocks
    if [[ "$line" =~ ^Display\ [0-9]+ ]] || [[ -z "$line" ]]; then
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

if [[ -z "$DELL_BUS" ]]; then
    echo "ERROR: Could not identify Dell C3422WE in ddcutil output." >&2
    echo "Detected monitors shown above. Please provide the Dell bus number manually." >&2
    read -rp "Dell I2C bus number (or press Enter to abort): " DELL_BUS
    if [[ -z "$DELL_BUS" ]]; then
        exit 1
    fi
fi

if [[ -z "$LG_BUS" ]]; then
    echo "ERROR: Could not identify LG 27GN880 in ddcutil output." >&2
    echo "Detected monitors shown above. Please provide the LG bus number manually." >&2
    read -rp "LG I2C bus number (or press Enter to abort): " LG_BUS
    if [[ -z "$LG_BUS" ]]; then
        exit 1
    fi
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

# Show capabilities for each monitor
echo "--- Dell C3422WE available inputs ---"
{ ddcutil capabilities --bus "$DELL_BUS" 2>/dev/null || true; } | awk '/Feature: 60/{flag=1; print; next} /Feature:/{flag=0} flag {print}' || echo "(Could not parse capabilities — you may need to enter the code manually)"
echo ""
read -rp "Enter the hex input code for the OTHER machine on the Dell (e.g., 0x11): " DELL_TARGET

# Ensure 0x prefix
if [[ -n "$DELL_TARGET" && ! "$DELL_TARGET" =~ ^0x ]]; then DELL_TARGET="0x$DELL_TARGET"; fi

echo ""
echo "--- LG 27GN880 available inputs ---"
{ ddcutil capabilities --bus "$LG_BUS" 2>/dev/null || true; } | awk '/Feature: 60/{flag=1; print; next} /Feature:/{flag=0} flag {print}' || echo "(Could not parse capabilities — you may need to enter the code manually)"
echo ""
read -rp "Enter the hex input code for the OTHER machine on the LG (e.g., 0x0f): " LG_TARGET

# Ensure 0x prefix
if [[ -n "$LG_TARGET" && ! "$LG_TARGET" =~ ^0x ]]; then LG_TARGET="0x$LG_TARGET"; fi

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
