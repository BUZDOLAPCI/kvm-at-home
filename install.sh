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
