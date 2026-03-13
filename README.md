# KVM-at-Home

Switch both monitors between two computers with a single keyboard shortcut (`Ctrl+Alt+P`), using DDC/CI commands via `ddcutil`.

## Setup

| Monitor        | Computer 1 | Computer 2 |
|----------------|------------|------------|
| LG 27GN880     | HDMI 1     | DP         |
| Dell C3422WE   | DP         | HDMI       |

The Dell C3422WE routes keyboard/mouse to whichever machine is displayed via its built-in USB KVM.

## Install

Run on **each** machine:

```bash
./install.sh
```

The installer will:
1. Install `ddcutil` and load the `i2c-dev` kernel module
2. Add your user to the `i2c` group (may require re-login)
3. Detect your monitors and ask you to identify the other machine's input for each
4. Write config to `~/.config/kvm-at-home/config`
5. Register `Ctrl+Alt+P` as a GNOME keyboard shortcut

## Usage

Press **Ctrl+Alt+P** to switch both monitors to the other machine.

## Troubleshooting

- **Nothing happens on Ctrl+Alt+P:** Check that DDC/CI is enabled in each monitor's OSD menu.
- **Permission denied:** Log out and back in after install (for `i2c` group membership), or run `newgrp i2c`.
- **Verify monitor communication:** Run `ddcutil detect` to confirm both monitors are visible.
