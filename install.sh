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
