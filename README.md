# KVM-at-Home

Switch both monitors between two computers with a single keyboard shortcut (`Ctrl+Alt+P`).

- Linux uses DDC/CI commands via `ddcutil`.
- Windows uses native DDC/CI calls through PowerShell and `dxva2.dll`.

## Setup

| Monitor        | Computer 1 | Computer 2 |
|----------------|------------|------------|
| LG 27GN880     | HDMI 1     | DP         |
| Dell C3422WE   | DP         | HDMI       |

The Dell C3422WE routes keyboard/mouse to whichever machine is displayed via its built-in USB KVM.

## Linux Install

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

## Windows Install

Run from PowerShell on the Windows boot:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
```

The Windows installer will:
1. Enumerate DDC/CI physical monitors exposed by Windows
2. Ask whether this is Computer 1 or Computer 2
3. Ask which indexes are the Dell C3422WE and LG 27GN880
4. Write config to `%APPDATA%\kvm-at-home\config.json`
5. Register `Ctrl+Alt+P` using a Start Menu shortcut

For **Computer 2 booted into Windows**, accept the default `Computer 2` choice. The defaults target Computer 1:

| Monitor      | Target input | Default setting |
|--------------|--------------|-----------------|
| Dell C3422WE | DP           | `0x0f`          |
| LG 27GN880   | HDMI 1       | `signal` method |

The LG 27GN880 does not reliably switch inputs through DDC/CI, so the Windows default uses the `signal` LG method. That temporarily disables the LG's Windows display output so the monitor's auto-input behavior can move to the other computer. This requires Auto Input to be enabled in the LG OSD.

## Usage

Press **Ctrl+Alt+P** to switch both monitors to the other machine.

On Windows you can also run:

```powershell
powershell -ExecutionPolicy Bypass -File .\kvm-switch.ps1
```

## Troubleshooting

- **Nothing happens on Ctrl+Alt+P:** Check that DDC/CI is enabled in each monitor's OSD menu.
- **Permission denied:** Log out and back in after install (for `i2c` group membership), or run `newgrp i2c`.
- **Verify monitor communication:** Run `ddcutil detect` to confirm both monitors are visible.
- **Windows hotkey does not fire:** Confirm the `KVM-at-Home` shortcut exists in `%APPDATA%\Microsoft\Windows\Start Menu\Programs`.
- **LG will not move on Windows:** Rerun `install-windows.ps1` and choose `signal` or `ddc-then-signal` for the LG method.
