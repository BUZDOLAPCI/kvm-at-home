# KVM-at-Home: Software KVM Switch Design

## Problem

Two computers share two monitors (Dell C3422WE and LG 27GN880). Switching between machines requires manually changing input sources on both monitors via their OSD menus. The goal is to switch both monitors simultaneously with a single keyboard shortcut (Ctrl+Alt+P).

## Physical Setup

| Monitor        | Computer 1 Input | Computer 2 Input |
|----------------|------------------|------------------|
| LG 27GN880     | HDMI 1           | DP               |
| Dell C3422WE   | DP               | HDMI             |

- The Dell C3422WE has built-in USB KVM — it routes keyboard/mouse to whichever computer is currently displayed. No separate peripheral switching is needed.
- Both machines run Ubuntu with GNOME.
- Both machines will run identical copies of this solution, each configured to switch "away from itself."

## Approach: DDC/CI via ddcutil

Monitors support DDC/CI (Display Data Channel Command Interface), a protocol that allows software to change monitor settings over the existing display cable. The Linux tool `ddcutil` sends these commands.

The VCP (Virtual Control Panel) feature code `0x60` controls input source selection. Each input has a numeric code (e.g., HDMI-1 might be `0x11`, DisplayPort-1 might be `0x0f`). The exact codes are monitor-specific and discovered during installation.

## Components

### 1. kvm-switch.sh — The Switch Script

Triggered by Ctrl+Alt+P. Reads the config file and sends `ddcutil setvcp 0x60` to both monitors in parallel.

**Behavior:**
- Reads `~/.config/kvm-at-home/config` for bus numbers and target input codes
- Fires both ddcutil commands in parallel (backgrounded with `&`) for near-simultaneous switching
- Always sends the same "switch to other machine" command — no state tracking needed
- Idempotent: pressing twice on the same machine just re-sends the same command harmlessly

**Config file format** (`~/.config/kvm-at-home/config`):
```ini
# LG 27GN880
LG_BUS=<bus_number>
LG_INPUT=<hex_input_code>

# Dell C3422WE
DELL_BUS=<bus_number>
DELL_INPUT=<hex_input_code>
```

The input codes point to the **other machine's** input on each monitor. So on Computer 1, `LG_INPUT` is the code for DP (Computer 2's input), and on Computer 2, `LG_INPUT` is the code for HDMI 1 (Computer 1's input).

### 2. install.sh — Setup and Discovery Script

Run once per machine during initial setup.

**Step 1: Install prerequisites**
- Install `ddcutil` via apt
- Load `i2c-dev` kernel module (`modprobe i2c-dev`)
- Persist the module in `/etc/modules-load.d/i2c-dev.conf`
- Add current user to `i2c` group for permission to access `/dev/i2c-*`

**Step 2: Detect monitors**
- Run `ddcutil detect` to list connected monitors with model names and I2C bus numbers
- Match model names ("DELL C3422WE" and similar for LG) to identify which bus corresponds to which monitor

**Step 3: Read current input source**
- Run `ddcutil getvcp 0x60 --bus <N>` on each monitor
- Since the install runs on the machine currently displayed, this reveals "this machine's" input code

**Step 4: User selects other machine's input**
- Run `ddcutil capabilities --bus <N>` to list all available input sources per monitor
- Present the list interactively, asking the user to select which input the other machine is connected to
- Example prompt:
  ```
  Detected: DELL C3422WE (bus 5)
    Current input: DP-1 (0x0f)  <- this machine
    Available: DP-1 (0x0f), HDMI-1 (0x11), HDMI-2 (0x12)
    Which input is the other machine? [0x11]:
  ```

**Step 5: Write config**
- Write discovered bus numbers and selected target input codes to `~/.config/kvm-at-home/config`

**Step 6: Register GNOME keybinding**
- Use `gsettings` to create a custom keybinding:
  - Path: `/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/kvm-switch/`
  - Name: "KVM Switch"
  - Binding: `<Ctrl><Alt>p`
  - Command: absolute path to `kvm-switch.sh`

**Why discovery isn't fully automatic:** Monitors often expose input ports that have nothing connected to them. There's no reliable way to detect which specific port the other machine is plugged into without asking the user.

## Prerequisites and Permissions

| Requirement     | How                                              |
|-----------------|--------------------------------------------------|
| ddcutil         | `sudo apt install ddcutil`                       |
| i2c-dev module  | `sudo modprobe i2c-dev` + persist in modules-load.d |
| i2c group       | `sudo usermod -aG i2c $USER` (requires re-login) |

## File Layout

```
kvm-at-home/
  kvm-switch.sh     # The switch script (Ctrl+Alt+P runs this)
  install.sh        # One-time setup: installs deps, discovers monitors, writes config
  README.md         # Usage instructions
```

Runtime config lives at `~/.config/kvm-at-home/config` (per-user, per-machine).

## Edge Cases

- **Monitor off/sleeping:** ddcutil commands may fail or be ignored. This is expected — the monitor will show the correct input when it wakes.
- **ddcutil speed:** Each command takes ~1-3 seconds. Running both in parallel keeps total switch time to ~1-3s rather than ~2-6s sequential.
- **Double press:** Idempotent — just re-sends the same input switch command.
- **Post-install re-login:** Required after adding user to `i2c` group. The install script should warn about this.
