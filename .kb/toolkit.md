<!-- tags: project, overview, structure, components, git, repo -->
# BC-250 SteamOS Real Toolkit

## Overview
Open-source toolkit to unlock the full potential of the BC-250 (ASRock A4A505)
mini PC running SteamOS. Provides TUI-based installation of kernel patches,
GPU/CPU tuning, display fixes, and more.

## Repository
- **GitHub**: `rpf16rj/bc250-steamos-real-toolkit`
- **Branches**: `develop` (ongoing work), `main` (releases only)
- **Version**: tracked in `VERSION` file at repo root
- **Changelog**: `CHANGELOG.md` (EN), `CHANGELOG.pt-br.md` (PT)

## Project Structure
```
start.sh                          # Main TUI entry point
VERSION                           # Current version (e.g. 1.1.0)
CHANGELOG.md                      # English changelog
CHANGELOG.pt-br.md                # Portuguese changelog
edid/                             # EDID override binaries
  samsung-q80a-hdmi21.bin         # HF-VSDB override for Samsung Q80A
external/
  bc250-steamos/                  # Vendored fix repos
    bc250-audio-fix/              # Kernel patches + build system
      *.patch                     # All kernel patches
      patch-driver.sh             # Main build orchestrator
      build.sh                    # Module builder
      fetch-sources.sh            # Kernel source fetcher
      install.sh                  # Module installer
      rollback.sh                 # Module rollback
    bc250-gfx1013-fix/            # Mesa/RADV build
      build-mesa.sh               # Patched Mesa builder
    aic8800/                      # WiFi/BT driver
    aic8800-legacy-mcu1/          # Legacy WiFi/BT driver
  nct6687d/                       # Sensor PWM driver
  bc250-core-unlock/              # CPU core unlock
  bc250_memcfg/                   # Memory config tool
  bc250_smu_oc/                   # SMU overclock tool
.kb/                              # Local knowledge base (not committed)
.devin/workflows/                 # Cascade skills/workflows
  toolkit.md                      # General toolkit skill
  fix-display.md                  # Display diagnostics skill
  release.md                      # Release workflow
```

## Components (installable via start.sh)

### Display/Audio
- **Audio Fix** — DP audio/video clock fix + GPU metrics + telemetry + tunable cache
  - Optional sub-components (via prompt): DP audio clock, DP spread spectrum disable
- **GFX1013 Compute Fix** — async compute + Mesa/RADV + mesh/task shaders + FSR4
- **Combined Fix** — single kernel build with selectable: audio + gfx1013 + vrr + allm
- **EDID Override** — HF-VSDB for HDMI 2.1 PCON (FRL 48G, VRR 48-120, ALLM)
- **AC-3 Surround** — HDMI/DP Dolby Digital 5.1 via eARC

### CPU/GPU
- **CPU Governor** — bc250-smu-oc CPU overclock service
- **GPU Governor** — cyan-skillfish GPU governor service
- **CPU Core Unlock** — 6c/12t → 8c/16t (experimental, needs reboot)
- **CU Live Manager** — WGP/CU live manager for GPU compute units
- **Disable CPU Mitigations** — mitigations=off for performance

### System
- **ACPI Fix** — CPU C-/P-states
- **RAM/VRAM Split** — UMA_SIZE=512 + ttm.pages_limit dynamic ceiling
- **Swap Configuration** — resize swapfile, set vm.swappiness
- **ZRAM/ZSWAP** — disable ZRAM, enable ZSWAP (lz4, 25% pool)
- **Sensor PWM Driver** — NCT6687D for fan control
- **CoolerControl** — GUI fan control app
- **AIC8800 WiFi/BT** — USB WiFi/BT dongle drivers
- **DS5 Bridge** — DualSense bridge for Steam Input
- **DS5 Chord VDF** — DualSense chord macros via VDF

## Key Files
- `start.sh` — main script (~6300 lines), all functions and menus
- `/etc/default/grub` — GRUB config (kernel cmdline)
- `/etc/modprobe.d/amdgpu-ycbcr444.conf` — FRL enable (dcfeaturemask=0x402)
- `/lib/firmware/edid/samsung-q80a-hdmi21.bin` — EDID override
- `/opt/bc250-gfx1013/` — patched Mesa installation

## State Tracking
- `persist_state_add` / `persist_state_remove` — track installed components
- `INSTALL_ALL_PROGRESS` — resume interrupted Install All
- `/usr/lib/modules/*/updates/.bc250-audio-fix` — module install marker
- `/usr/lib/modules/*/updates/.bc250-metrics-fix` — metrics-aware build marker

## Important Constants
- `SCRIPT_DIR` — repo root
- `GRUB_DEFAULT` — `/etc/default/grub`
- `FIXES_REPO_DIR` — `external/bc250-steamos`
- `SWAPFILE_PATH` — swapfile location
- `SWAPFILE_STOCK_SIZE_MB` — default swap size
- `RAM_SPLIT_STOCK_UMA_MB` — default UMA size (256MB)
- `RAM_SPLIT_DEFAULT_TTM_PAGES` — default ttm.pages_limit

## Git Policy
- **Never commit to develop or main without explicit user permission**
- `develop` is where work happens
- `main` only receives merges at release time (GitFlow)
- `.kb/` is local-only (in .gitignore)
