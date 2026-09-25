<!-- tags: troubleshooting, display, sync, black-screen, audio, crash, boot, diagnostics, pipx, governor -->
# Troubleshooting

## Services / Install Issues

### "Kernel incompatible" / build fails on SteamOS 3.8 (kernel 6.18)
- **Symptom**: Combined Fix or any kernel-patch item fails during the build,
  e.g. `error: pathspec 'drivers/gpu/drm/amd/display/dc/link/protocols/link_hdmi_frl.c'
  did not match any file(s)`.
- **Root cause**: the toolkit's kernel patches target Valve's
  `linux-neptune-72` tree (kernel 7.2.x, SteamOS Beta/Preview). Stable 3.8
  ships kernel 6.18 — the patch paths don't exist in that tree.
  `MIN_KERNEL_*` was left at 6.18 when the toolkit moved to 7.2, so the
  version guard silently let 6.18 through (fixed: guard is now 7.2+ and the
  DS5-bridge path was the only unguarded patch-driver caller).
- **Fix**: update to the Beta/Preview channel — README section "Updating
  SteamOS to kernel 7.2" (`#updating-steamos-to-kernel-72`), also printed by
  `require_kernel_version` at block time. Non-kernel components (CPU/GPU
  governor, swap, mitigations) still install on 6.18.


### bc250-smu-oc.service fails 203/EXEC after a SteamOS update
- **Symptom**: `bc250-smu-oc.service` fails at boot with
  `Unable to locate executable '/root/.local/share/pipx/venvs/bc250-smu-oc/bin/python'`
  and toolkit repair reports "Failed to reinstall bc250_smu_oc via pipx".
- **Root cause**: pipx ran as root → venv under `/root/.local/share/pipx`,
  which lives on the read-only A/B rootfs. Every SteamOS update wipes it,
  and repairs used to fail with EROFS because `pipx install` ran before
  any `steamos-readonly disable`. `pipx reinstall` also can't handle
  packages installed from a local path.
- **Fix (v1.9.8+)**: the venv now lives under `/var/lib/bc250/pipx`
  (`PIPX_HOME`, bins in `/var/lib/bc250/bin`) — writable without disabling
  readonly and survives A/B updates. Repair just runs Install → CPU
  Governor once; `bc250-apply --install` rewrites the unit's ExecStart
  with the persistent interpreter automatically.
- **Note**: user-installed pacman packages (python-pipx) are also wiped by
  updates — `cpu_governor_ensure_pipx` now reinstalls pipx first when the
  binary is missing **or broken** (an update can leave `/usr/bin/pipx`
  present but dead, e.g. its site-packages removed by a Python minor bump —
  so the check is `pipx --version`, not just `command -v`).
- **pipx itself as last resort**: if pacman is unavailable, a self-contained
  pipx is built at `/var/lib/bc250/pipx-venv` (update-proof, rebuilt
  automatically when broken). `bc250_pipx` prefers the vendored shim over a
  dead system binary. The old `pip3 install pipx` fallback was removed — it
  could never work on SteamOS (writes to read-only `/usr` outside
  `steamos_writable`).
- **PyPI-free build**: `python-setuptools` is installed alongside pipx so
  `cpu_governor_pipx_install` can use `--system-site-packages` +
  `--pip-args "--no-build-isolation"` — the governor build then needs no
  network at all. Without setuptools it falls back to a normal isolated
  install (PyPI).

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

## Telemetry Issues

### GPU temperature / per-core metrics read 0 after install (8 cores unlocked)
- **Symptom**: after installing the Combined Fix on a modded-BIOS board, GPU
  temperature and most per-core metrics read 0 (or garbage) in amdgpu_top /
  MangoHud.
- **Root cause**: the kernel 7.x telemetry patch defaults to the SMU-patched
  8-core layout (136-byte tables). `amdgpu.cs_legacy_8core_metrics=1` selects the
  older 116-byte layout instead. Only a BIOS **without** the SMU telemetry patch
  needs the legacy layout; on the patched firmware it produces garbage.
- **Which BIOS needs what**:
  | BIOS | `cs_legacy_8core_metrics=1`? |
  |---|---|
  | Stock ASRock `P3.00` (12/09/2021) | yes |
  | Older modded BIOS (unlocks cores, no SMU patch) | yes |
  | Current community BIOS (carries SMU telemetry patch) | no |
- **Fix (test at runtime, no reboot)**: the parameter is writable.
  ```bash
  echo 0 | sudo tee /sys/module/amdgpu/parameters/cs_legacy_8core_metrics
  # then check amdgpu_top / MangoHud
  echo 1 | sudo tee /sys/module/amdgpu/parameters/cs_full_telemetry
  cat /sys/bus/pci/devices/0000:01:00.0/pp_dpm_socclk   # shows layout + per-core
  ```
  If telemetry returns, remove the param from GRUB permanently
  (`audio_fix_remove_cs_legacy_grub_param` does it; manually: sed out
  `amdgpu.cs_legacy_8core_metrics=1` from `/etc/default/grub`, `update-grub`,
  with `steamos-readonly disable/enable` on SteamOS).
- **Detect the BIOS**: `cat /sys/class/dmi/id/bios_version` (`P3.00` = stock).
- **Toolkit behaviour (v1.9.3+)**: reads the BIOS version and only offers the
  param on a stock BIOS; on a modded board it offers to remove it if present.
