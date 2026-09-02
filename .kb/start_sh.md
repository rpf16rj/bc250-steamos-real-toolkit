<!-- tags: start-sh, tui, menu, functions, pick-items, whiptail, grub, install, revert, persist -->
# start.sh Architecture

## Overview
`start.sh` is the main entry point — a TUI (text user interface) script that
provides menus for installing, configuring, and reverting all toolkit components.

## Key Variables
- `SCRIPT_DIR` — root of the toolkit repo (line 32)
- `GRUB_DEFAULT` — `/etc/default/grub` (line 1186)
- `FIXES_REPO_DIR` — path to `external/bc250-steamos` (vendored fixes)
- `YCBCR444_MODPROBE_FILE` — `/etc/modprobe.d/amdgpu-ycbcr444.conf`
- `EDID_OVERRIDE_DIR` — `/lib/firmware/edid`
- `EDID_OVERRIDE_BIN` — `samsung-q80a-hdmi21.bin`
- `EDID_OVERRIDE_SRC` — `$SCRIPT_DIR/edid/$EDID_OVERRIDE_BIN`
- `EDID_GRUB_PARAM` — `drm.edid_firmware=DP-1:edid/samsung-q80a-hdmi21.bin`

## Key Functions

### SteamOS Helpers
- `steamos_writable()` — disable read-only, run command, re-enable read-only
- `is_steamos()` — detect if running on SteamOS
- `run_with_retry()` — retry a command with sudo

### GRUB Helpers
- `audio_fix_pcon_grub_installed()` — check if freesync_pcon_allow_all=1 in GRUB
- `audio_fix_ensure_pcon_grub_param()` — add freesync_pcon_allow_all=1 to GRUB
- `audio_fix_hpd_debounce_grub_installed()` — check if hdmi_hpd_debounce in GRUB
- `audio_fix_ensure_hpd_debounce_grub_param()` — add hdmi_hpd_debounce to GRUB
- `grub_cleanup_stale_params()` — remove force_ycbcr444=1 and force_min_bpc=10 from GRUB

### EDID Override
- `edid_override_installed()` — check if EDID binary + GRUB param present
- `edid_override_install()` — copy binary, add GRUB param, rebuild initramfs
- `edid_override_remove()` — remove binary, remove GRUB param, rebuild initramfs

### YCbCr 4:4:4 / FRL
- `ycbcr444_modprobe_installed()` — check if modprobe.d config present
- `ycbcr444_ensure_modprobe()` — create modprobe.d with dcfeaturemask=0x402
- `ycbcr444_remove_modprobe()` — remove modprobe.d config

### Legacy EDID Cleanup
- `audio_fix_cleanup_legacy_edid()` — removes old EDID binaries and GRUB params
  (preserves the HDMI 2.1 override binary)

### Install Functions
- `install_audio_fix()` — full audio fix install (patch-driver.sh)
- `install_combined_fix()` — selectable components (audio + gfx1013 + vrr + allm)
- `run_revert_audio_fix()` — rollback audio fix
- `run_revert_gfx1013_fix()` — rollback combined fix

### Menu Functions
- `run_install_all()` — sequential install of all components (14 steps)
- `run_revert_all()` — sequential revert of all components
- `run_install_manual()` — manual menu with individual install/revert items

## Menu Structure (Manual Install)
1. CPU Governor / 1R Revert
2. GPU Governor / 2R Revert
3. Disable CPU Mitigations / 3R Re-enable
4. Configure Swap / 4R Revert
5. Disable ZRAM & Enable ZSWAP / 5R Revert
6. ACPI Fix / 6R Revert
7. CU Unlock Live
8. CPU Core Unlock / 8R Revert
9. RAM/VRAM Split / 9R Revert
10. Combined Audio+GFX1013 / 10R Revert
11. AC-3 Surround Encoding / 11R Revert
12. EDID Override (HDMI 2.1) / 12R Revert

## Install All Flow (14 steps)
1. Configure Swap
2. Enable ZSWAP/Disable ZRAM
3. Disable CPU Mitigations
4. ACPI Fix
5. RAM/VRAM Split
6. Sensor PWM Driver
7. CoolerControl
8. Core Unlock
9. Validate Core Unlock
10. CPU Governor
11. GPU Governor
12. CU Live Manager
13. Combined Fix (includes EDID override prompt)
14. AC-3 Surround

## Post-Install Prompts (in install_audio_fix and install_combined_fix)
After kernel module installation, the script prompts for:
1. `amdgpu.freesync_pcon_allow_all=1` in GRUB (VRR over PCON)
2. `amdgpu.hdmi_hpd_debounce_delay_ms=1500` in GRUB (HPD debounce)
3. GRUB stale param cleanup (force_ycbcr444, force_min_bpc)
4. EDID override for HDMI 2.1 PCON
5. `dcfeaturemask=0x402` via modprobe.d (FRL enable)
