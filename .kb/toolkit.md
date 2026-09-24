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
extras/                           # Optional add-ons (not in start.sh)
  bc250-fsr4-launch-options/      # Decky plugin: FSR4 launch-option presets
  toolkit-steamos-control/        # Decky plugin: toolkit control panel
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
- **VA-API Video Driver** — simpmix/bc250-encoding-decoding-fix; since v0.5.0 a
  full suite: H.264/HEVC encode + bit-exact H.264/HEVC decode (incl. Main10,
  `VAEntrypointVLD`) + VideoProc scaling, via Vulkan compute + threaded CPU
  wavefront (VCN is fused off — proven at register level 2026-09-23, see
  `.kb/vcn.md`). Downloaded from GitHub `releases/latest` at
  install time; driver+shaders to `/var/lib/bc250` (survives updates), env to
  `/etc/environment.d` + `/etc/profile.d` (`LIBVA_DRIVER_NAME=bc250`). The
  bundled DKMS audio module is intentionally NOT installed — audio is the
  toolkit's own job. Manual: 14/14R.
  **Flatpak caveat:** sandboxed apps don't inherit `/etc/environment.d` and
  some manifests (e.g. Moonlight) explicitly unset `LIBVA_DRIVER_NAME`/
  `LIBVA_DRIVERS_PATH`. Fix per app:
  `flatpak override --user <app-id> --env=LIBVA_DRIVER_NAME=bc250
  --env=LIBVA_DRIVERS_PATH=/var/lib/bc250/dri
  --env=BC250_SHADER_DIR=/var/lib/bc250/shaders
  --filesystem=/var/lib/bc250:ro` — verified working with
  com.moonlight_stream.Moonlight 6.1.0 (VAAPI encode probe OK inside the
  sandbox). Undo: `flatpak override --user --reset <app-id>`.
  **Decode caveat (measured):** bc250 VLD decode ≈30 fps vs FFmpeg software
  ≈510 fps at 1080p60 HEVC — Moonlight-as-client should stay on software
  decoding (VAAPI decode caused ~2 fps + apparent "network drops" = decode
  queue overflow). The driver's real win is host-side encode (~86 fps
  HEVC 1080p measured in-sandbox).

### CPU/GPU
- **CPU Governor** — bc250-smu-oc CPU overclock service. Installed via
  pipx into the persistent `/var/lib/bc250/pipx` venv (`bc250_pipx`
  wrapper sets `PIPX_HOME`/`PIPX_BIN_DIR` — NEVER use bare `pipx` as root:
  it lands on the read-only `/root/.local` and dies every SteamOS update)
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
- **Never commit, push to main, or cut a release unless the user explicitly asks at that moment.
  The user always wants to test first — finish the work, then stop and wait for them.**
- `develop` is where work happens
- `main` only receives merges at release time (GitFlow)
- `.kb/` is local-only (in .gitignore)
