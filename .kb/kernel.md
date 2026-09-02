<!-- tags: kernel, neptune, valve, version, amdgpu, module-params, vermagic, dkms -->
# SteamOS Kernel (Neptune)

## Current Kernel
- **Version**: 7.2.0-valve1-1-neptune-72 (as of 2026-09-01)
- **Source**: `/usr/src/linux-neptune-72` (headers only, no full source tree)
- **Build headers**: `/usr/lib/modules/$(uname -r)/build`
- **Kernel source for patching**: fetched by `fetch-sources.sh` from Valve's git

## Kernel 7.x vs 6.x
- Kernel 7.x already has HDMI 2.1 FRL/DSC patches upstream (Tomasz Pakuła series)
- VRR and ALLM patches are NOT needed on 7.x (already functional upstream)
- The toolkit's `install_combined_fix` skips VRR/ALLM patches on kernel ≥7
- Audio fix, GFX1013, telemetry, SCLK, TTM patches still needed on 7.x

## Module Parameters (amdgpu)
- `dcfeaturemask=0x402` — enables FRL only (set via modprobe.d, not GRUB)
- `force_ycbcr444=1` — force YCbCr 4:4:4 on PCON (STALE in GRUB, should be removed)
- `force_min_bpc=10` — minimum bpc floor on PCON (STALE in GRUB, should be removed)
- `freesync_pcon_allow_all=1` — allow VRR bypass for any PCON (set via GRUB)
- `hdmi_hpd_debounce_delay_ms=1500` — prevent spurious HPD on TV power cycling
- `cs_legacy_8core_metrics=1` — needed if stock BIOS (no SMU telemetry patch)
- `sched_hw_submission=4` — default
- `lockup_timeout=5000,10000,10000,5000` — default

## Why modprobe.d instead of GRUB for some params
SteamOS's `steamenv_boot` in GRUB filters unknown params from the kernel command
line. `force_ycbcr444` and `force_min_bpc` are custom module params not recognized
by steamenv_boot, so they must be set via `/etc/modprobe.d/amdgpu-ycbcr444.conf`
instead of GRUB_CMDLINE_LINUX_DEFAULT.

## GRUB Config
- **File**: `/etc/default/grub`
- **Regenerate**: `sudo update-grub` or `sudo grub-mkconfig -o /boot/grub/grub.cfg`
- **Boot chain**: EFI → steamcl.efi → GRUB → vmlinuz-linux-neptune-72
- **EFI partition**: `/esp` (nvme0n1p1), `/efi` (nvme0n1p3)
- **SteamOS bootconf**: `/esp/SteamOS/conf/A.conf` and `B.conf` (A/B partition scheme)

## mkinitcpio
- **Preset**: `/etc/mkinitcpio.d/linux-neptune-72.preset` (toolkit symlinks if missing)
- **Rebuild**: `sudo mkinitcpio -P`
- **EDID firmware**: must be in `/lib/firmware/edid/` BEFORE rebuilding initramfs
  so the firmware is included in the initramfs image
- **Read-only fs**: must `steamos-readonly disable` before writing to `/lib/firmware/`
  or `/etc/`, then `steamos-readonly enable` after

## Patches Applied on Top of Kernel 7.2
1. `bc250-dp-audio-clock-7.2.patch` — DP audio/video clock fix
2. `bc250-cyan-skillfish-telemetry-cache-7.2.patch` — telemetry cache for 7.2
3. `bc250-dp-audio-dm-ignore-ss.patch` — disable DP spread spectrum
4. `bc250-dp-hdmi-ycbcr444-deep-color.patch` — CH7218 quirk + YCbCr 4:4:4 + deep color
5. `bc250-vrr-pcon-freesync.patch` — VRR FreeSync fallback (NOT needed on 7.x, but harmless)
6. `bc250-allm-via-dp.patch` — ALLM via AVI content_type (NOT needed on 7.x, but harmless)
7. `bc250-ttm-null-page-guard.patch` — TTM NULL page guard
8. `bc250-sclk-range.patch` — SCLK range 350-2230 MHz
9. `bc250-kfd-flush-tlb-by-runlist.patch` — KFD flush TLB
10. `bc250-tunable-gfxclk-activity-cache.patch` — tunable gfxclk/activity cache
11. `bc250-pcon-frl-hotplug-preserve.patch` — preserve FRL config across hotplug
12. `0001-gfx1013-compute-*` — GFX1013 async compute patches
13. `bc250-cyan-skillfish-gfxclk.patch` — direct GFX clock query from SMU
14. `bc250-cyan-skillfish-gpu-telemetry.patch` — GPU utilization reporting
