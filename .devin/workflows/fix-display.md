---
description: Diagnose and fix display issues (sync, VRR, ALLM, FRL, EDID) on the BC-250 DP→HDMI PCON pipeline
---

## Knowledge Base

Before diagnosing, read the local KB for full context:
- `.kb/hardware.md` — BC-250 hardware, PCON CH7218, Samsung Q80A specs
- `.kb/display.md` — Full display pipeline architecture, FRL, EDID override, VRR, ALLM
- `.kb/kernel.md` — Kernel versions, module params, GRUB vs modprobe.d
- `.kb/troubleshooting.md` — Known issues and diagnostic commands

## Diagnostic Steps

1. Check kernel version and module params:
   ```bash
   uname -r
   cat /proc/cmdline
   cat /sys/module/amdgpu/parameters/dcfeaturemask
   cat /sys/module/amdgpu/parameters/freesync_pcon_allow_all
   ```

2. Check VRR range:
   ```bash
   sudo cat /sys/kernel/debug/dri/0/DP-1/vrr_range
   ```
   If 0-0, EDID override is missing or not applied.

3. Check EDID for HF-VSDB:
   ```bash
   edid-decode /sys/class/drm/card0-DP-1/edid | grep 'HDMI Forum'
   ```
   If no output, EDID override is not active.

4. Check GRUB config for stale params:
   ```bash
   grep 'GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub
   ```
   If `force_ycbcr444=1` or `force_min_bpc=10` present, they should be removed
   (steamenv_boot filters them anyway; use modprobe.d instead).

5. Check modprobe.d:
   ```bash
   cat /etc/modprobe.d/amdgpu-ycbcr444.conf
   ```
   Should contain `options amdgpu dcfeaturemask=0x402`.

6. Check dmesg for PCON/FRL:
   ```bash
   dmesg | grep -iE 'CH7218|PCON|FRL|frl_lt|dongle'
   ```

## Common Fixes

- **Sync instability**: Install EDID override (menu item 12 in start.sh)
- **VRR not working**: EDID override + `freesync_pcon_allow_all=1` in GRUB
- **ALLM not triggering**: EDID override (adds ALLM flag to HF-VSDB)
- **FRL not negotiating**: `dcfeaturemask=0x402` in modprobe.d + patched amdgpu.ko
- **Audio at wrong speed**: Install audio fix (patch-driver.sh --audio)
- **HPD spam**: `hdmi_hpd_debounce_delay_ms=1500` in GRUB
