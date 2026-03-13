# Bug: LG 27GN880 Does Not Switch Input via DDC/CI

## Status: Confirmed Monitor Limitation

## Summary

The LG 27GN880 (UltraGear) monitor ignores all DDC/CI input source switching commands. The Dell C3422WE switches correctly, but the LG stays on its current input regardless of the command sent. This means the KVM switch script (`kvm-switch.sh`) only partially works - it switches the Dell but not the LG.

## Environment

- **Monitor**: LG 27GN880-B (EDID model: "LG ULTRAGEAR", product code: 0x5b80, internal model: "WK95U")
- **Controller**: Mstar (VCP 0xC8 = 0x05)
- **Firmware**: 3.2 (VCP 0xC9)
- **MCCS version**: 2.1
- **I2C bus**: /dev/i2c-1
- **DRM connector**: card1-HDMI-A-1 (this machine connects to LG via HDMI)
- **GPU**: NVIDIA RTX 3080 (GA102)
- **ddcutil versions tested**: 1.4.1, 2.2.1
- **OS**: Ubuntu (Linux 6.17.0-14-generic)

## What Works

- `ddcutil detect` correctly identifies the LG on bus 1
- `ddcutil capabilities --bus 1` correctly lists Feature 0x60 (Input Source) with values: 0x11 (HDMI-1), 0x12 (HDMI-2), 0x0f (DP-1), 0x10 (DP-2)
- `ddcutil getvcp 0x60 --bus 1` correctly reads the current input (e.g., DisplayPort-1 = 0x0f)
- `ddcutil setvcp 0x10 <value> --bus 1` (brightness) works - confirmed writes to VCP features work
- DDC/CI communication is functional for all features **except** input switching

## What Was Tried (All Failed)

### 1. Standard DDC/CI (VCP 0x60)
```bash
ddcutil setvcp 0x60 0x11 --bus 1                    # no effect
ddcutil setvcp 0x60 0x11 --bus 1 --noverify          # no effect
ddcutil setvcp 0x60 0x11 --bus 1 --force             # no effect
ddcutil setvcp 0x60 0x11 --bus 1 --sleep-multiplier 2.0  # no effect
ddcutil setvcp 0x60 0x11 --bus 1 --sleep-multiplier 3.0 --verbose  # no effect
ddcutil setvcp 0x60 17 --bus 1 --noverify            # decimal value, no effect
```
All commands return exit code 0 but the monitor does not switch. No flicker, no OSD change, nothing.

### 2. Save Current Settings (scs) after setvcp
```bash
ddcutil setvcp 0x60 0x11 --bus 1 --noverify && ddcutil scs --bus 1
```
No effect.

### 3. LG Manufacturer-Specific VCP 0xF4 (standard address)
```bash
ddcutil setvcp 0xF4 0x90 --bus 1 --noverify    # HDMI-1 in LG encoding
ddcutil setvcp 0xF4 0x01 --bus 1 --noverify    # small value
```
No effect. VCP 0xF4 reads as `sh=0x00, sl=0x06` and does not change.

### 4. LG Sidechannel (VCP 0xF4 + i2c-source-addr=0x50, ddcutil 2.2.1)
```bash
ddcutil setvcp 0xF4 0x0090 --bus 1 --i2c-source-addr=0x50 --noverify  # HDMI-1
ddcutil setvcp xF4 xD0 --bus 1 --i2c-source-addr=x50 --noverify       # DP-1
ddcutil setvcp 0xF4 0x01 --bus 1 --i2c-source-addr=0x50 --noverify    # small value
```
No effect. The `--i2c-source-addr` option (ddcutil 2.2.1 from PPA) was installed specifically for this, but the 27GN880 does not respond to the sidechannel protocol.

### 5. LG Sidechannel via VCP 0x60 (source-addr=0x50)
```bash
ddcutil setvcp 0x60 0x0090 --bus 1 --i2c-source-addr=0x50 --noverify
```
No effect.

### 6. Raw I2C via i2ctransfer (manual DDC/CI packet with source addr 0x50)
```bash
# DDC/CI Set VCP packet: src=0x50, len=0x84, cmd=0x03, vcp=0xF4, val=0x0090, checksum=0xDD
i2ctransfer -y 1 w7@0x37 0x50 0x84 0x03 0xF4 0x00 0x90 0xDD

# Same with standard source addr 0x51
i2ctransfer -y 1 w7@0x37 0x51 0x84 0x03 0xF4 0x00 0x90 0xDC
```
No effect. Commands succeed without error but monitor does not respond.

### 7. Alternative VCP codes
```bash
ddcutil setvcp 0xD7 0x01 --bus 1 --noverify   # Auxiliary power output
```
No effect.

### 8. CEC (HDMI Consumer Electronics Control)
```bash
cec-client -l   # "Found devices: NONE"
```
RTX 3080 does not expose a CEC adapter on its HDMI output. Dead end.

## I2C Bus Scan

```
i2cdetect -y 1:
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:                         -- -- -- -- -- -- -- --
10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
30: 30 -- -- -- -- -- -- 37 -- -- 3a -- -- -- -- --
40: -- -- -- -- -- -- -- -- -- 49 -- -- -- -- -- --
50: 50 51 -- -- 54 -- -- -- -- 59 -- -- -- -- -- --
60: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
70: -- -- -- -- -- -- -- --
```
Standard DDC/CI devices present: 0x37 (DDC/CI), 0x50 (EDID), 0x51.

## Relevant VCP Feature Values

| VCP Code | Description | Value |
|----------|-------------|-------|
| 0x60 | Input Source | sl=0x0f (DP-1) - reads correctly, writes ignored |
| 0xF4 | Manufacturer Specific | mh=0xff, ml=0xff, sh=0x00, sl=0x06 |
| 0xF5 | Manufacturer Specific | mh=0x00, ml=0xff, sh=0x00, sl=0x01 |
| 0xC8 | Display controller | Mstar (sl=0x05) |
| 0xC9 | Firmware level | 3.2 |
| 0x10 | Brightness | works (read/write confirmed) |

## References

- [ddcutil Wiki: Switching input source on LG monitors](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors)
- [ddcutil Issue #100: LG 29UM69G fails switching input](https://github.com/rockowitz/ddcutil/issues/100)
- [ddcutil Discussion #331: Switching Input on LG Monitors](https://github.com/rockowitz/ddcutil/discussions/331)
- [BetterDisplay Discussion #4246: DDC Input Source Control on LG displays](https://github.com/waydabber/BetterDisplay/discussions/4246)
- [ddcutil PPA](https://launchpad.net/~rockowitz/+archive/ubuntu/ddcutil) (installed 2.2.1 for --i2c-source-addr support)

## Current Config

```ini
# ~/.config/kvm-at-home/config
LG_BUS=1
LG_INPUT=0x0f    # DP-1 (other machine's input)
DELL_BUS=3
DELL_INPUT=0x11  # HDMI (other machine's input)
```

## xrandr Layout

```
HDMI-0: LG 27GN880, 2560x1440@99.95Hz, primary, position +0+0
DP-2:   Dell C3422WE, 3440x1440@59.97Hz, position +2560+0
```

## Investigation Findings

This does **not** appear to be a bug in `kvm-switch.sh` itself.

- The script uses the standard MCCS input switch command (`ddcutil setvcp 0x60 ...`), and the same command path works on the Dell.
- On the LG, DDC/CI transport is clearly working because `detect`, `capabilities`, `getvcp 0x60`, and writable features like brightness (`0x10`) all succeed.
- The LG still ignores **all** tested input-switching paths:
  - standard MCCS `0x60`
  - LG sidechannel `0xF4`
  - source address `0x50`
  - raw `i2ctransfer`
- The current ddcutil wiki says recent LG monitors often no longer switch inputs through standard `setvcp`, and only **some** models respond to the alternative LG sidechannel protocol. As of the wiki revision dated February 11, 2026, `UN880` is listed as only "potentially supported" on that sidechannel, while `27GN880` is not called out as verified support.
- BetterDisplay's public "LG alt" tracking issue likewise lists many newer LG families, but not this model. Recent public reports also show some newer LGs still ignoring the alternate command path even when other DDC features work.

The most likely explanation is therefore:

1. The monitor firmware advertises input capability through VCP `0x60`.
2. It accepts DDC/CI writes in general.
3. It silently ignores source-switch writes on this model/firmware.

In other words, this is best understood as an LG firmware limitation or model-specific lockout, not a bug in the repo's shell logic.

## Repo Impact

`kvm-switch.sh` currently assumes both monitors honor `setvcp 0x60`. That assumption is false for the LG 27GN880-B in this environment, so the script can only reliably switch the Dell.

Retrying, adding `--force`, adding `--sleep-multiplier`, verifying less, or sending the writes serially instead of in parallel is unlikely to fix this. Those variants were already tested directly against the LG and had no effect.

## Practical Options

- Treat the LG as unsupported for software input switching on Linux.
- Keep using DDC/CI for the Dell only.
- Switch the LG manually with the joystick.
- Try the monitor's OSD auto-input behavior instead of explicit DDC switching, if that fits the workflow.
- Use an external HDMI/DP KVM or monitor-side hardware workaround if one-button switching is required.

## Conclusion

This bug should not stay in "open" status as if more shell-script debugging is likely to fix it. The current evidence supports a narrower conclusion:

> LG 27GN880-B on firmware 3.2 accepts DDC/CI communication but does not honor software input-switch commands, including both standard MCCS `0x60` and the known LG sidechannel variants tested here.

Unless new firmware, a new reverse-engineered LG command path, or a hardware workaround appears, there is nothing meaningful left to fix in `kvm-switch.sh` for this monitor specifically.
