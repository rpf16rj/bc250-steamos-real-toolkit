<!-- tags: build, patch-driver, fetch-sources, build-sh, install-sh, rollback, mesa, radv, mesh, prebuilt, recovery, grub -->
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
- **Snapshots the pre-install kernel+initramfs** to `/boot/bc250-backup/`
  (`vmlinuz-<preset>` + `initramfs-<preset>.img`) BEFORE installing — this is
  the stock-drivers boot target for the GRUB recovery entry. Only snapshots
  while no override is installed; if an override exists but no backup does
  (upgrade from an older toolkit), it rebuilds a stock initramfs once just
  to snapshot it.
- Installs the patched amdgpu.ko to `/lib/modules/$(uname -r)/...`
- Runs `depmod -a`
- Rebuilds initramfs (`mkinitcpio -P`)

### rollback.sh
- Restores the stock amdgpu.ko from backup
- Runs `depmod -a`
- Rebuilds initramfs

### patch-driver.sh
- Orchestrates: fetch-sources.sh → build.sh → install.sh
- **Prebuilt fast path:** before building, tries to download
  `amdgpu-<uname -r>.ko.zst` (+ `.sha256` + `.flags` manifest) from the
  rolling `prebuilt` GitHub release. Installs only on an EXACT kernel
  release + flag-signature match (SHA256 verified; install.sh re-checks
  vermagic/ABI). Any mismatch → normal source build. `--no-prebuilt`
  forces a local build. `BC250_NO_PREBUILT=1` does the same via
  environment — works through `sudo BC250_NO_PREBUILT=1 ./start.sh`
  (propagated through `runuser` via `patch_env`) and also skips the Mesa
  prebuilt in `gfx1013_try_mesa_prebuilt`.
- Accepts flags: `--audio`, `--gfx1013`, `--vrr`, `--allm`, `--no-audio-clock`, `--no-ss`, `--no-telemetry`, `--no-ttm`, `--no-sclk`, `--no-kfd`, `--no-frl-hp`, `--no-ycbcr444`, `--mastag-mesh`, `--native-mesh`, `--vcn`, `--no-prebuilt`
- `--vcn` is diagnostic-only: the investigation concluded 2026-09-23 that
  the VCN register file is electrically dead (first read wedges the
  fabric). The staged `bc250_vcn_ungate` param stays inert at `=0` — see
  `.kb/vcn.md` → "Verdict" before ever using level 3
- All `--no-*` flags skip individual patches and reverse leftovers from previous builds

### package-prebuilt.sh (maintainer)
- Packages `amdgpu.ko.zst` → `prebuilt/amdgpu-<rel>.ko.zst` + `.sha256` +
  `.flags` manifest (flag signature normalized like `kernel_flags_sig`)
- `--upload` pushes the 3 assets to release tag `prebuilt` via `gh`
  (creates the release on first use); uses `~/.local/bin/gh` fallback

### Mesa prebuilt (bc250-gfx1013-fix)
- `package-mesa-prebuilt.sh --upload --mastag-mesh|--native-mesh` —
  tars `/opt/bc250-gfx1013/<VERSION>` into
  `mesa-<mesaver>-bc250.<ver>-<mesh>.tar.zst` + sha256 + flags
  manifest, uploads to the same `prebuilt` release
- `install-mesa-prebuilt.sh <tarball>` — extracts to `/`, sets
  `VK_DRIVER_FILES` (falls back to stock 32-bit ICD when the tarball has
  no lib32)
- `gfx1013_try_mesa_prebuilt` in start.sh runs it before the source build:
  mesa/mesh must match the manifest exactly; glibc is a MINIMUM
  (`user_glibc >= manifest_glibc` via sort -V — glibc is forward-compat,
  so it stays out of the asset name so any client can find the file).
  Mesa is built `-Dllvm=disabled` so there is no libLLVM coupling; glibc
  is the only ABI guard needed. A Mesa that fails checks is never
  installed — a broken RADV would take down Game Mode (gamescope needs
  Vulkan), so strictness here is load-bearing, not just caution.
- SIGPIPE gotcha: `ldd --version | head` under `set -o pipefail` exits 141 —
  capture full ldd output first, then grep. Same for `tar -tf | grep -q` on
  the Mesa tarball (grep exits early, tar dies on SIGPIPE) — list once into
  a variable and use bash `[[ "$var" == *pat* ]]` instead.
- Flag-signature gotcha (2026-09-20): `--no-ss` is a no-op on kernels >= 7.2
  (the DP spread-spectrum patch is upstream and build.sh force-skips it), but
  the Combined Fix still appends it because the checklist item doesn't exist
  there — the sig became `audio gfx1013 dsc no-ss` vs the published
  `audio gfx1013 dsc` manifest and the prebuilt never matched. Both
  `kernel_flags_sig` and `package-prebuilt.sh` now drop `no-ss` on >=7.2,
  and patch-driver.sh writes `prebuilt/amdgpu-<rel>.flags` after every build
  so packaging never guesses flags.
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
