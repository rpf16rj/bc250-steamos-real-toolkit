<!-- tags: troubleshooting, display, sync, black-screen, audio, crash, boot, diagnostics -->
# Troubleshooting

## Display Issues

### Sync instability / black screen on mode switch
- **Symptom**: Display loses sync when switching resolutions/refresh rates in gamescope
- **Root cause**: PCON EDID lacks HF-VSDB → kernel doesn't know TV is HDMI 2.1 → tries TMDS for >300 MHz modes
- **Fix**: Install EDID override (`edid/samsung-q80a-hdmi21.bin`) via `drm.edid_firmware=DP-1:edid/samsung-q80a-hdmi21.bin`
- **Verify**: `edid-decode /sys/class/drm/card0-DP-1/edid | grep 'HDMI Forum'`

### VRR not working (vrr_range = 0-0)
- **Cause 1**: EDID override not installed → kernel can't detect VRR capabilities
- **Cause 2**: `amdgpu.freesync_pcon_allow_all=1` not in GRUB
- **Cause 3**: TV not on HDMI 2.1 port (Samsung Q80A: ports 3 or 4)
- **Fix**: Install EDID override + ensure freesync_pcon_allow_all=1 in GRUB
- **Verify**: `cat /sys/kernel/debug/dri/0/DP-1/vrr_range` (should show 48-120)

### ALLM not triggering
- **Cause**: `edid_caps->allm` is false because EDID lacks HF-VSDB
- **Fix**: Install EDID override (adds ALLM flag to HF-VSDB)
- **Note**: On kernel 7.x, ALLM is handled natively. On 6.x, needs bc250-allm-via-dp.patch

### DP audio at wrong speed (pitched down ~82%)
- **Cause**: Missing DP audio clock fix
- **Fix**: Install audio fix (patch-driver.sh --audio)
- **Verify**: Play audio via DP/HDMI and check pitch/speed

### FRL not negotiating (stuck on TMDS)
- **Cause 1**: `dcfeaturemask=0x402` not set (check: `cat /sys/module/amdgpu/parameters/dcfeaturemask`)
- **Cause 2**: CH7218 PCON quirk not applied (kernel module not patched)
- **Cause 3**: EDID override not installed (kernel doesn't know TV supports FRL)
- **Fix**: Install modprobe.d config + audio fix + EDID override

### HPD (Hot Plug Detect) spam when TV power cycles
- **Cause**: TV power on/off generates spurious HPD events
- **Fix**: `amdgpu.hdmi_hpd_debounce_delay_ms=1500` in GRUB

## GPU Issues

### GPU temperature reads 0
- **Cause**: Stock BIOS (no SMU telemetry patch) with kernel 7.x telemetry patch
- **Fix**: Add `amdgpu.cs_legacy_8core_metrics=1` to GRUB

### GPU clock stuck at low value
- **Cause**: SCLK range too restrictive
- **Fix**: SCLK range patch (350-2230 MHz) included in audio fix

### Async compute not working
- **Cause**: GFX1013 not spoofed / Mesa not patched
- **Fix**: Install combined fix with GFX1013 component + patched Mesa

## Kernel Module Issues

### amdgpu.ko vermagic mismatch
- **Cause**: Built module doesn't match running kernel ABI
- **Fix**: The build system refuses to install mismatched modules (safety guard)
- **Ensure**: Correct kernel headers installed, correct kernel source fetched

### mkinitcpio preset missing
- **Cause**: SteamOS may not have the expected preset file
- **Fix**: `audio_fix_ensure_mkinitcpio_preset()` symlinks to closest match

## GRUB Issues

### Stale force_ycbcr444=1 / force_min_bpc=10 in GRUB
- **Cause**: Previous toolkit versions added these to GRUB, but steamenv_boot filters them
- **Effect**: Params are NOT applied (ignored by steamenv_boot), but clutter GRUB config
- **Fix**: `grub_cleanup_stale_params()` removes them; use modprobe.d instead

### GRUB config not updating
- **Cause**: Read-only filesystem
- **Fix**: `steamos-readonly disable` before `update-grub`, then `steamos-readonly enable`

## Diagnostic Commands

```bash
# Kernel version
uname -r

# Current kernel cmdline
cat /proc/cmdline

# amdgpu module params
cat /sys/module/amdgpu/parameters/dcfeaturemask
cat /sys/module/amdgpu/parameters/force_ycbcr444
cat /sys/module/amdgpu/parameters/force_min_bpc
cat /sys/module/amdgpu/parameters/freesync_pcon_allow_all

# VRR range
sudo cat /sys/kernel/debug/dri/0/DP-1/vrr_range

# EDID
edid-decode /sys/class/drm/card0-DP-1/edid

# GRUB config
grep 'GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub

# Check modprobe.d
cat /etc/modprobe.d/amdgpu-ycbcr444.conf

# Check EDID override installed
ls -la /lib/firmware/edid/

# dmesg for PCON/FRL
dmesg | grep -iE 'CH7218|PCON|FRL|frl_lt|dongle'
```
