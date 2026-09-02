<!-- tags: build, patch-driver, fetch-sources, build-sh, install-sh, rollback, mesa, radv, mesh -->
# Build System

## Overview
The toolkit patches the amdgpu kernel module in-place (DKMS-style) without
building the full kernel. It fetches the matching Valve kernel source tree,
applies patches, builds only the amdgpu.ko module, and installs it.

## Scripts (in external/bc250-steamos/bc250-audio-fix/)

### fetch-sources.sh
- Clones the Valve kernel source tree matching the running kernel version
- Uses `FULLSHA` env var if provided (resolved by `audio_fix_resolve_fullsha`)
- Creates a `.git` directory for version tracking
- Output: `valve-kernel/` directory with full kernel source

### build.sh
- Applies selected patches to the kernel source
- Builds only `drivers/gpu/drm/amd/amdgpu/amdgpu.ko`
- Uses `make -j$(nproc) M=drivers/gpu/drm/amd/amdgpu modules`
- Verifies vermagic/ABI matches the running kernel exactly
- Refuses to install if vermagic doesn't match (safety guard)

### install.sh
- Backs up the stock amdgpu.ko
- Installs the patched amdgpu.ko to `/lib/modules/$(uname -r)/...`
- Runs `depmod -a`
- Rebuilds initramfs (`mkinitcpio -P`)

### rollback.sh
- Restores the stock amdgpu.ko from backup
- Runs `depmod -a`
- Rebuilds initramfs

### patch-driver.sh
- Orchestrates: fetch-sources.sh → build.sh → install.sh
- Accepts flags: `--audio`, `--gfx1013`, `--vrr`, `--allm`, `--no-audio-clock`, `--no-ss`, `--no-telemetry`, `--no-ttm`, `--no-sclk`, `--no-kfd`, `--no-frl-hp`, `--no-ycbcr444`, `--mastag-mesh`, `--native-mesh`
- All `--no-*` flags skip individual patches and reverse leftovers from previous builds
- `--no-audio-clock`, `--no-telemetry`, `--no-ss` only apply within `--audio`
- `--no-ttm`, `--no-sclk`, `--no-kfd`, `--no-frl-hp`, `--no-ycbcr444` apply to always-on patches
- Must run as regular user (calls sudo internally for install step)
- The toolkit wraps this in `runuser -u "$REAL_USER"`

## Mesa Build (in external/bc250-steamos/bc250-gfx1013-fix/)

### build-mesa.sh
- Builds patched Mesa/RADV with GFX1013 spoof + mesh/task shader support
- Two modes:
  - MastaG (default): GFX10.3 spoof + mesh/task via RADV_GFX103=1
  - Native: Native MESH only on GFX10, no GFX10.3 spoof
- Output: `/opt/bc250-gfx1013/`
- Build deps: meson, ninja, dev headers (auto-installed by `gfx1013_ensure_mesa_build_deps`)

## Kernel Version Resolution
- `audio_fix_resolve_fullsha()` resolves the short kernel commit to a full SHA
- Uses `/usr/lib/modules/$(uname -r)/build/` headers to find the commit
- Passes `FULLSHA` to `fetch-sources.sh` for exact source tree matching

## mkinitcpio Preset
- `audio_fix_ensure_mkinitcpio_preset()` ensures `/etc/mkinitcpio.d/linux-neptune-72.preset` exists
- If the exact preset is missing, symlinks to the closest `linux-neptune-6*.preset`
- Required because install.sh/rollback.sh hardcode `mkinitcpio -p linux-neptune-616`
