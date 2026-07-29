# KVM-at-Home

Switch a Dell U5226KW between two computers with `Ctrl+Alt+P`. Linux uses
`ddcutil`; Windows uses native DDC/CI calls through PowerShell and `dxva2.dll`.
Both implementations read the active source and toggle between HDMI 1 and
HDMI 2.

## Connections

| Monitor input | USB upstream | Computer |
| --- | --- | --- |
| HDMI 1 (`0x11`) | USB-C 2 | Computer 1 |
| HDMI 2 (`0x12`) | USB-C 3 | Computer 2 |

In the monitor OSD:

- Assign HDMI 1 to USB-C 2.
- Assign HDMI 2 to USB-C 3.
- Set Ethernet Switch Mode to `Tie to KVM`.
- Turn PIP/PBP off.
- Keep DDC/CI enabled.

## Linux Install

Run on each Linux GNOME computer:

```bash
./install.sh
```

The installer:

1. Ensures `ddcutil` and the I2C device interface are available.
2. Verifies that `DELL U5226KW` is reachable through DDC/CI.
3. Installs the command as `~/.local/bin/kvm-at-home`.
4. Writes `~/.config/kvm-at-home/config`.
5. Registers `Ctrl+Alt+P` as a GNOME shortcut.

If the installer adds the user to the `i2c` group, log out and back in before
using the shortcut.

## Windows Install

Run from PowerShell on each Windows computer:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
```

The installer:

1. Enumerates physical monitors exposed through Windows DDC/CI.
2. Selects the U5226KW automatically or asks for its monitor index.
3. Verifies that the current source is HDMI 1 or HDMI 2.
4. Writes `%APPDATA%\kvm-at-home\config.json`.
5. Registers `Ctrl+Alt+P` through a Start Menu shortcut.

## Behavior

Both commands read VCP `0x60` before switching:

- HDMI 1 switches to HDMI 2.
- HDMI 2 switches to HDMI 1.
- Any other source or DDC failure stops without guessing.

Use the monitor OSD to recover if the other computer has not been configured
yet.

## Verify

On Linux, read the current source without switching:

```bash
ddcutil getvcp 0x60 --model 'DELL U5226KW' --terse
```

Run the Linux mock-based tests:

```bash
./tests/kvm-switch-test.sh
```

On Windows, rerun `install-windows.ps1` to verify monitor discovery and the
current source without switching. The generated shortcut invokes
`kvm-switch.ps1`.

Install and verify the utility on both computers before testing the shortcut in
both directions.
