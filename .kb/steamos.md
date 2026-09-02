<!-- tags: steamos, readonly, grub, efi, boot, mkinitcpio, atomic-update, persistence -->
# SteamOS Specifics

## Read-Only Filesystem
- SteamOS mounts the root filesystem read-only by default
- `steamos-readonly disable` — make filesystem writable (needs sudo)
- `steamos-readonly enable` — re-enable read-only
- Always re-enable after modifications
- The toolkit's `steamos_writable()` function handles this automatically

## A/B Partition Scheme
- SteamOS uses A/B partitions for atomic updates
- `/esp/SteamOS/conf/A.conf` and `B.conf` track boot state
- `steamos-bootconf` tool manages boot configuration
- The active partition is writable; the other is the update target

## Boot Chain
```
EFI (nvme0n1p1) → steamcl.efi → GRUB → vmlinuz-linux-neptune-72
```
- `steamcl.efi` is Valve's custom EFI boot manager
- GRUB config: `/etc/default/grub` → `/boot/grub/grub.cfg`
- `steamenv_boot` in GRUB filters unknown kernel params from cmdline
- This is why `force_ycbcr444` and `force_min_bpc` must use modprobe.d, not GRUB

## EFI Partitions
- `/esp` (nvme0n1p1) — EFI System Partition (bootloader, steamcl.efi)
- `/efi` (nvme0n1p3) — EFI partition (mounted by systemd automount)

## Kernel Command Line
- Check: `cat /proc/cmdline`
- GRUB default: `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`
- After editing GRUB: `sudo update-grub` or `sudo grub-mkconfig -o /boot/grub/grub.cfg`
- Note: `/proc/cmdline` may differ from GRUB config if steamcl.efi modifies it

## Module Parameters
Two ways to set amdgpu module params:
1. **GRUB** (`GRUB_CMDLINE_LINUX_DEFAULT`) — for params recognized by steamenv_boot
   - `amdgpu.freesync_pcon_allow_all=1`
   - `amdgpu.hdmi_hpd_debounce_delay_ms=1500`
   - `amdgpu.cs_legacy_8core_metrics=1`
   - `mitigations=off`
2. **modprobe.d** (`/etc/modprobe.d/*.conf`) — for custom/unknown params
   - `options amdgpu dcfeaturemask=0x402`
   - `options amdgpu force_ycbcr444=1` (legacy, should NOT be used)
   - `options amdgpu force_min_bpc=10` (legacy, should NOT be used)

## initramfs
- Must rebuild after: kernel module changes, EDID firmware changes, modprobe.d changes
- Command: `sudo mkinitcpio -P`
- EDID firmware must be in `/lib/firmware/edid/` BEFORE rebuilding
- Preset: `/etc/mkinitcpio.d/linux-neptune-72.preset`

## Package Management
- SteamOS uses pacman (Arch-based)
- `pacman -S <package>` — install (needs steamos-readonly disable)
- `pacman -Q` — query installed packages
- AUR helpers (yay/paru) may not be available
- Some packages require manual build (e.g., CoolerControl, AIC8800 drivers)
