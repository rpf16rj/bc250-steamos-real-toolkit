# Changelog

All notable changes to the BC-250 SteamOS Real Toolkit are documented here.
Versions follow [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`)
starting at `v1.0.0`. Changes before that are kept below as dated history from
before the toolkit adopted numbered releases.

🇧🇷 Prefere português? Leia o [CHANGELOG.pt-br.md](./CHANGELOG.pt-br.md).

## v1.5.0 — 2026-08-21

- **New:** DS5 Bridge PS Button fix — patched `hid-playstation.ko`
  that exposes `BTN_MODE` for the DS5-Linux-Bridge, enabling Steam/Gamescope
  chord combos (PS+Cross=QAM, PS+Triangle=Steam overlay) with a custom
  Steam chord VDF config.
- **New:** Mesa/RADV patches updated from MastaG's latest (Aug 2026) —
  compute queue fix, mesh/task shaders, taskmesh queries, and opt-in
  `RADV_GFX103=1` GFX10.3 promotion all refreshed.
- **New:** FSR4 V3 deferred SDot hybrid (from dmorazasanchez/bc250-fsr4)
  replaces the old V2 selective sdot — adds `iadd(0,SDot)` fusion, MAD24
  chains, and a dense SDot pre-pass for better INT8 throughput.
- **New:** Native mesh shader option (from lonewolf0622) — MESH-only
  shaders on GFX10 without GFX10.3 spoofing. Selectable at install time
  alongside the existing MastaG mesh/task approach.
- **New:** VRR EDID patch for FreeSync over DP→HDMI PCON — zeros HDMI
  VTEM to prevent flickering, adds AMD VSDB v1 for FreeSync SPD.
- **Fixed:** EDID detection on sysfs — `[[ -s ]]` reports size 0 for
  sysfs files; switched to `wc -c` so the VRR EDID patch works.

## v1.4.0 — 2026-08-19

- **New:** SMU SCLK range widened to 350–2230 MHz (from MastaG's kernel
  patch set), allowing userspace governors to drive the full clock range.
- **New:** FSR4 dp4a reassociation optimization now uses a selective
  approach — avoids catastrophic register spilling in pathological
  shaders while keeping the performance win on most kernels.
- **New:** HDMI AC-3 encoding implementation guide for other operating
  systems (documents the ALSA a52 plugin + PipeWire approach).
- **Fixed:** Xbox adapter (xone-dkms) install now detects and installs
  the correct kernel headers package before building the DKMS module.
- **Removed:** GFX clock gating (`--cg`/`--cg-unvalidated`) flags and
  patches removed from the combined fix — the feature was experimental
  and unvalidated on BC-250 hardware.

## v1.3.1 — 2026-08-17

- **Fixed:** AC-3 Surround install/revert now works correctly when the
  toolkit is run via `sudo`. PipeWire and WirePlumber commands are
  executed in a separate user-session script (`ac3-user-setup.sh`) as
  the real user, fixing card detection failures and hangs that occurred
  when `pactl`/`systemctl --user` were called as root.
- **Fixed:** WirePlumber config corrected to use `api.acp.disable-pro-audio`
  instead of `api.alsa.use-acp`, matching Valve's working valve-fremont
  hardware profile. The previous setting prevented the `hdmi-ac3.conf`
  profile set from loading, leaving only generic `on`/`off` profiles.
- **New:** AC-3 Surround status now shown in "Verify My Setup" (option V)
  with a dedicated Audio section showing whether AC-3 is installed and
  whether the profile is currently active.
- **Changed:** Toolkit logs (trace, run, error, diagnostic) now saved in
  `<toolkit-dir>/logs/` instead of `~/.bc250-toolkit/logs/`. Error logs
  are still copied to the Desktop on failure.

## v1.3.0 — 2026-08-17

- **New:** HDMI AC-3 Surround Encoding — enables real-time Dolby Digital
  5.1 encoding over HDMI/DisplayPort via eARC. Previously impossible on
  SteamOS with the BC-250 because the hardware profile that loads the
  AC-3 audio profiles was never triggered (the BC-250's DMI identifies
  as "AMD BC-250" instead of Valve's "OEM F7F"). This installs a udev
  rule and WirePlumber config that activates the built-in `hdmi-ac3.conf`
  profile set, giving a 5.1 sink that encodes all audio to AC-3 via the
  native ALSA `a52` plugin. Works with any active DisplayPort-to-HDMI
  adapter (not brand-specific). Zero added latency, ~1-2% CPU overhead.
  Stereo content is automatically upmixed to 5.1. The sink stays active
  for 1 hour after the last sound to prevent the receiver from falling
  back to PCM. After installing, select "HD-Audio Generic Digital Surround
  5.1 (HDMI/AC3)" in the KDE audio device settings (Desktop Mode) to
  activate Dolby Digital output. Available as menu option 13/13R.

## v1.2.2 — 2026-08-16

- **Fixed:** Mesa build failure on some SteamOS systems — missing build
  dependencies (`zstd`, `glslang`, `python-yaml`) are now installed
  automatically, and the `--needed` flag was removed so pacman
  force-reinstalls packages whose `.pc` files and headers were stripped
  from the SteamOS image.
- **Fixed:** Post-install verification now checks that critical pkgconfig
  files are actually present before attempting the Mesa build.

## v1.2.1 — 2026-08-16

- **Fixed:** Audio stuttering under high load — GRBM polling reduced from
  32 to 16 samples and cache window increased from 25ms to 100ms, cutting
  CPU overhead 8x (from ~6.2% to ~0.78%).
- **Fixed:** Patch application failure on SteamOS 3.8.16 — added `--fuzz=3`
  to all patch commands for greater tolerance of line number offsets.
- **Fixed:** AUR package installation failure in Portuguese locales —
  validity-check errors are now detected as retryable network errors,
  with automatic cache cleanup before retry.
- **Fixed:** Corrected MastaG repository URL in credits.

## v1.2.0 — 2026-08-15

- **New:** Combined Audio + GFX1013 install option — builds both fixes in a
  single kernel module, saving time and avoiding duplicate reboots.
- **New:** Updated GPU telemetry with 100ms cache and 16-sample GRBM polling
  for responsive frequency and activity reporting without audio stuttering
  under high load. Includes full telemetry mode (opt-in via `pp_dpm_socclk`)
  and 8-core hybrid metrics support.
  Based on [MastaG's BC-250 telemetry patch](https://github.com/MastaG/linux-cachyos-bc250).
- **New:** Defensive TTM NULL-page guard — prevents kernel panic on partial
  GPU memory allocation cleanup. Always applied, no configuration needed.
  Based on [MastaG's amdgpu TTM patch](https://github.com/MastaG/linux-cachyos-bc250).
- **New:** Optional KFD runlist flush workaround for ROCm/compute users
  (opt-in via `amdgpu.bc250_flush_by_runlist=1`).
  Based on [MastaG's KFD flush patch](https://github.com/MastaG/linux-cachyos-bc250).
- **Improved:** +20-25% GPU compute performance in async compute workloads
  (e.g. Cyberpunk 2077) thanks to the GFX1013 compute queue fix.
- **Improved:** FSR 4 shader performance — the INT8 dot-product optimization
  (`imul24_relaxed`) is included in Mesa 26.2.0-rc3, giving ~42% fewer
  instructions and ~61% less latency in FSR 4 shaders. Just enable FSR 4 in
  your games — the driver is already optimized.
  Based on [dmorazasanchez/bc250-fsr4](https://github.com/dmorazasanchez/bc250-fsr4).
- **Fixed:** Mesa build compatibility across all glibc versions — the ETIME
  check now detects whether `_GNU_SOURCE` is needed and patches Mesa
  accordingly, preventing build failures on both older and newer glibc.
- **Fixed:** Patch application failure when upgrading from a previous version
  — the kernel header file is now properly reset before applying new patches.

### Credits

This release integrates patches from the BC-250 community:
- **MastaG** ([@MastaG](https://github.com/MastaG)) — GPU telemetry,
  TTM NULL-page guard, and KFD runlist flush patches.
- **dmorazasanchez** ([@dmorazasanchez](https://github.com/dmorazasanchez)) —
  FSR 4 INT8 dot-product optimization research for BC-250.
- **keyboardspecialist** ([@keyboardspecialist](https://github.com/keyboardspecialist)) —
  original BC-250 SteamOS fixes (ACPI, DP audio, WiFi).

## v1.1.5 — 2026-08-14

- **Fixed:** Mesa build still failed with `Could not get define 'ETIME'` on
  glibc 2.43 even after the v1.1.4 fix. The root cause: `cc.has_define()`
  calls `cc.get_define()` internally, so it throws the same error. The build
  script now patches the `get_define` prefix in `meson.build` to include
  `#define _GNU_SOURCE` — glibc 2.43 hides `ETIME` behind `_GNU_SOURCE`, and
  Meson's `get_define` only uses the prefix string (not the project's
  `pre_args`). This makes `get_define` find `ETIME=62` directly, avoiding
  both the error and any redefinition conflict.

## v1.1.4 — 2026-08-13

- **Fixed:** Mesa build still failed with `Could not get define 'ETIME'` on
  systems with GCC 15.x + glibc 2.43 (e.g. SteamOS 3.8.16). The root cause is
  that Meson 1.8.2's `cc.get_define()` errors out instead of returning an
  empty string when a define is missing, breaking Mesa's own ETIME fallback.
  The build script now patches Mesa's `meson.build` to use `cc.has_define()`
  (which returns a boolean) instead, so the fallback works as intended.

## v1.1.3 — 2026-08-12

- **Fixed:** Mesa build still failed with `Could not get define 'ETIME'` even
  with the v1.1.2 fix, because `-Dc_args` doesn't affect Meson's compiler
  checks. The fallback define is now exported via `CFLAGS` instead, which
  Meson's `cc.get_define()` actually respects.

## v1.1.2 — 2026-08-11

- **Fixed:** Mesa build step of the GFX1013 fix could fail during `meson setup`
  with `Could not get define 'ETIME'` on some glibc/GCC combinations (notably
  GCC 15.x). The build script now detects the missing define and injects a
  fallback (`-DETIME=ETIMEDOUT`) so configuration completes successfully.

## v1.1.1 — 2026-08-11

- **Fixed:** the GFX1013 fix (and the plain audio fix, which shares the same
  build step) could fail to install on some systems with a compiler error
  deep in an unrelated kernel build tool, unblocking the affected step in
  the build.

## v1.1.0 — 2026-08-09

- **New:** GFX1013 Compute Fix (menu option 11) — improves GPU compute
  performance and fixes games that wouldn't launch or ran incorrectly on the
  BC-250's GPU.
- Added a status line for the new fix on the main menu.
- The fix can be installed and reverted at any time from the menu.

## v1.0.5 — 2026-08-03

- **Fixed:** v1.0.4's full revert of `build.sh` to the 2026-08-01 state
  dropped the pristine-tree-reset step ahead of the patch stack, exactly as
  warned about at the time. This reintroduced the "tree has drifted" bug it
  had fixed: `fetch-sources.sh` reuses the vendored kernel tree across runs
  once it's at the right commit, so a file left in a state from a previous
  patch attempt could fail to either apply or reverse cleanly against the
  current patch text, aborting the build entirely. Hit in practice:
  `apply Cyan Skillfish GPU telemetry patch` failed with exactly that error
  on a real build attempt after the v1.0.4 revert. Manually reset the
  affected tree (`cyan_skillfish_ppt.c`) back to pristine to unblock the
  in-progress install, and reintroduced the reset step in `build.sh` —
  scoped only to the files the current two-patch stack touches
  (`cyan_skillfish_ppt.c`, `dcn201_clk_mgr.c`, `clk_mgr.c`), with no
  8-core-metrics patch application alongside it.

## v1.0.4 — 2026-08-03

- **Reverted:** `external/bc250-steamos/bc250-audio-fix/` (build system and
  patch set for the DisplayPort audio/video + GPU metrics fix) is reverted
  back to its exact 2026-08-01 state (commit `1e3b9f0`, the day the
  `bc250-detect` menu option was added), on top of v1.0.2's already-reverted
  `gfxclk.patch`. `bc250-cyan-skillfish-8core-metrics.patch` — added
  2026-08-02, entirely new that day — is removed; `build.sh` no longer
  applies it nor resets the vendored tree to a pristine checkout before the
  patch stack (also added 2026-08-02). `README.md` reverted to match. The
  net effect: only the DP audio/video clock patch, GC-activity telemetry,
  and the plain direct-SMU-query `gfxclk` patch remain, matching the last
  known state before the Robin 3.00 8-core metrics work and its follow-up
  regressions/fixes (v1.0.0 through v1.0.3) began. Verified the resulting
  two-patch stack applies cleanly against a fresh pristine checkout.

## v1.0.3 — 2026-08-02

- **Fixed:** `install_audio_fix()`'s `audio_fix_resolve_fullsha()` helper ran
  `git ls-remote https://github.com/Evlav/linux-integration.git` with no
  timeout to pre-resolve the running kernel's full 40-char commit SHA. On at
  least one occasion this call sent its HTTP/2 `git-upload-pack` request and
  then never received a response (confirmed reproducible: a plain HTTPS GET
  to the same URL returned instantly, but `git ls-remote` itself hung past
  30s), freezing the whole "Install All" resume flow indefinitely right
  after "Running patch-driver.sh...". The caller already tolerated a failed
  lookup gracefully (`|| true`, falling back to letting `fetch-sources.sh`
  resolve the commit itself via the GitHub REST API), but that fallback
  never got a chance to run because the blocking call itself never returned.
  Wrapped it in `timeout 15`.

## v1.0.2 — 2026-08-02

- **Reverted:** `bc250-cyan-skillfish-gfxclk.patch`'s range-validation
  wrapper (added in v1.0.0, partially patched in v1.0.1) is fully reverted
  back to the plain, unconditional direct SMU `GetGfxclkFrequency` query —
  the version confirmed working before v1.0.0. Field testing of v1.0.1
  showed GPU activity% recovering (as expected — that fix removed the
  whole-struct abort) but GFX clock MHz still stuck at 0 and GPU
  temperature still frozen: the fallback value used on a rejected/invalid
  clock reading, `metrics.Current.GfxclkFrequency` from the firmware's
  `SmuMetrics_t` table, is itself always stale/zero on this hardware — that
  unreliability is exactly why the direct SMU message query was introduced
  in the first place, so falling back to it was not a usable fix. Root
  cause of the temperature freeze together with the MHz-stuck-at-0 report
  needs further field investigation with this reverted baseline before any
  further attempt at gfxclk range validation.

## v1.0.1 — 2026-08-02

- **Fixed:** `bc250-cyan-skillfish-gfxclk.patch` (introduced in v1.0.0) made
  `cyan_skillfish_get_gpu_metrics()` return early — discarding the *entire*
  `gpu_metrics` readout (GPU temperature, GPU activity %, and all per-core
  CPU metrics, not just the clock) — whenever its own range-validated direct
  SMU GFX-clock query came back outside `CYAN_SKILLFISH_SCLK_MIN`/`MAX` or
  otherwise failed. In practice this made GPU load/temperature reporting go
  stale or show 0% at idle and only "catch up" once load pushed the clock
  back into range, which in turn kept the managed fan curve from ramping up
  in time and could let the board overheat under sustained load. The clock
  query failure now only falls back to the raw (unvalidated)
  `metrics.Current.GfxclkFrequency` for that one field; every other sensor
  in `gpu_metrics` keeps updating on every poll regardless.

## v1.0.0 — 2026-08-02

First numbered release. Adopts semantic versioning and GitHub Releases
(downloadable zip) instead of date-stamped versions and a `curl | bash`
one-liner.

- **Changed:** Distribution moved from a `curl`-piped `start.sh` one-liner /
  self-updating git clone to versioned GitHub Releases. Download the latest
  release zip, extract it, and run `start.sh` — see the Quick Start section
  in the README.
- **Removed:** Auto-update-on-every-launch (`git fetch origin main` +
  `reset --hard` at the top of `start.sh`). It silently discarded any local
  uncommitted changes on launch, which could wipe in-progress work. Updating
  the toolkit now means downloading the latest release zip. The standalone
  bootstrap (fetching the full repo when `start.sh` is run with no vendored
  `external/` assets present) is unaffected.
- **Added:** `bc250-cyan-skillfish-8core-metrics.patch` to
  `external/bc250-steamos/bc250-audio-fix`, vendored from
  [keyboardspecialist/bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos)'s
  newer combined patch set. On Robin 3.00 BIOS + a fully unlocked
  8-core/16-thread topology (`CPU Core Unlock`), reads real per-core
  power/temperature/frequency for all 8 cores from the SMU's `PMSTATUSLOG`
  table via direct PCIe register access, instead of the firmware's stock
  `SmuMetrics_t` layout, which only ever carries 6 core entries — the
  previous audio-fix patch set silently duplicated/truncated per-core data
  on unlocked 8-core systems. Falls back to the stock 6-core `SmuMetrics_t`
  reporting (`-ENODEV`) on any other topology, so it's safe on unmodified
  6c/12t systems too. Note: the upstream patch file as published was
  truncated (missing closing braces) — hand-completed and verified to apply
  cleanly and produce syntactically valid C against this toolkit's vendored
  kernel tree before vendoring.
- **Changed:** `bc250-cyan-skillfish-gfxclk.patch` updated to upstream's
  newer version, which wraps the direct SMU GFX-clock query in range
  validation (discards readings outside `CYAN_SKILLFISH_SCLK_MIN`/`MAX`
  instead of propagating garbage values to `gpu_metrics`/hwmon).
- **Fixed:** `build.sh` reused a stale, already-patched kernel source tree
  across separate runs (`fetch-sources.sh` skips re-checkout once the tree
  is already at the running kernel's commit, by design, for speed). If a
  vendored patch's *content* changed between runs — as with the
  `gfxclk.patch` update above — the leftover file from a previous build
  could end up in a state that neither applied nor reversed cleanly against
  the new patch text, aborting with "tree has drifted". `build.sh` now
  resets the exact files its patch stack touches
  (`cyan_skillfish_ppt.c`, `dcn201_clk_mgr.c`, `clk_mgr.c`) to their
  pristine git-checked-out state before applying patches, on every run.

## Pre-1.0 history (dated releases)

### 2026-08-01

- **Added:** `RAM/VRAM Split` in `Install Manual` (`10`/`10R`) and `Install All`/`Revert All`. Vendors [fanoush/bc250_memcfg](https://github.com/fanoush/bc250_memcfg) (compiled locally at install time) to drop `UMA_SIZE` from the stock permanent 8192MB (8GB/8GB) split down to the documented 512MB minimum in the BC-250's battery-backed CMOS, freeing almost all 16GB of RAM at idle, and raises the kernel's dynamic VRAM ceiling via `ttm.pages_limit` in GRUB (~12GB) so 8GB+ VRAM games don't crash on the lower split. No modded BIOS needed; status now reports the live `UMA_SIZE`. Fixed two follow-up bugs: the build step now force-reinstalls `glibc`/`base-devel` when `gcc` can't actually compile a plain C program (headers can go missing/stripped on the SteamOS overlay even with `gcc` present), and the post-write CMOS readback comparison now strips `bc250memcfg`'s zero-padded output (`0512`) before comparing.
- **Added:** Optional auto-reboot for `CPU Core Unlock`. After a cold power-off, AGESA only re-reads the rewritten core presence mask on the *following* boot (not the one where the boot service re-applies it), so bringing the extra 2 cores back always costs one more reboot. Install now asks whether to trigger that mandatory second reboot automatically, storing the choice in `/etc/bc250-core-unlock.conf`; the boot service only ever auto-reboots right after a fresh mask write with cores still inactive, never on an already-unlocked boot, so a genuine enumeration failure can't turn into a reboot loop.
- **Added:** `Run bc250-detect` (`D`) in the Performance Profile Menu, to manually re-tune the CPU undervolt with custom frequency/voltage/temperature targets — useful after toggling `CPU Core Unlock`, since 6c/12t vs 8c/16t changes the CPU's power/thermal profile enough that a previously-tuned `scale` may no longer be optimal.
- **Fixed:** Status for `CPU Core Unlock` used to hardcode "6c/12t, SteamOS default" whenever the boot-time service wasn't installed, even though reverting only removes that service — the core presence mask itself (and therefore the live 8c/16t state) persists until an actual cold power-off. Status now checks the live core count in that case too.

### 2026-07-30

- **Added:** `CPU Core Unlock` in `Install Manual` (`9`/`9R`) and `Install All`/`Revert All`. Vendors [rw-r-r-0644/bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock), which writes the BC-250's core presence mask via an SMU mailbox message to enable its 2 disabled CPU cores (6c/12t → 8c/16t). No SteamOS-specific adaptation was needed — the upstream script only touches PCI config space and the existing GPU governor service. Since the write is volatile across a cold power-off, install adds a boot-time systemd service (`bc250-core-unlock.service`) that re-applies it on every start; status now reports the current core/thread count. ⚠ Experimental — see `external/bc250-core-unlock/README.md` for caveats (possible silicon binning, GPU clock reporting bug).
- **Changed:** `Install ACPI Fix` now fetches [mendesrr/bc250-acpi-fix-updated-8c](https://github.com/mendesrr/bc250-acpi-fix-updated-8c)'s SSDT-CST/SSDT-PST tables instead of bc250-collective's, since the community reported the original 6c-only tables misbehave once the extra 2 cores are unlocked. Existing installs auto-upgrade the next time the ACPI fix runs. `CPU Core Unlock` now installs/updates this ACPI fix transparently in the same run, with no extra confirmation, so both fixes are always applied together.
- **Changed:** Re-vendored `external/bc250-steamos/bc250-audio-fix` from upstream [keyboardspecialist/bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos), which now also patches `cyan_skillfish_ppt.c` to query GFX clock directly from the SMU and add GPU utilization reporting (`bc250-cyan-skillfish-gfxclk.patch`, `bc250-cyan-skillfish-gpu-telemetry.patch`) — the community-reported fix for GPU clock/load metrics becoming inaccurate once the 2 extra cores are unlocked. `Install DP Audio/Video Fix` (Install Manual `7`) applies it together with the existing DisplayPort clock correction; not chained automatically into `CPU Core Unlock` since it rebuilds a kernel module, but `Install All` already runs it before the core unlock step. Also vendored the upstream `fetch-steamos-package.sh` helper (multi-channel SteamOS package discovery) and fixed a false-failure in this toolkit's own SIGPIPE workaround now that upstream fixed that bug independently.
- **Added:** `RAM/VRAM Split` in `Install Manual` (`10`/`10R`) and `Install All`/`Revert All`. Vendors [fanoush/bc250_memcfg](https://github.com/fanoush/bc250_memcfg) (compiled locally from source at install time) to write `UMA_SIZE=512` to the BC-250's battery-backed CMOS — the stock BIOS reserves a fixed 8192MB (8GB/8GB split) permanently for VRAM, and 512MB is the documented minimum floor, freeing nearly all 16GB of RAM at idle. Also raises the kernel's dynamic VRAM ceiling via `ttm.pages_limit` in GRUB (~12GB), since the default ceiling with a 512MB floor can be too low for games wanting 8GB+ VRAM. No modded BIOS needed; status now reports the live `UMA_SIZE`. Revert restores the stock 8192MB split and removes the GRUB override.
- **Fixed:** `nano` lost arrow-key navigation when editing the CPU/GPU config (Performance menu `F`/`E`) — the toolkit's `exec > >(tee ...) 2>&1` run-log redirection left `nano`'s stdout as a pipe instead of a real TTY, breaking ncurses keypad/cursor addressing. Both editors now talk to `/dev/tty` directly.

### 2026-07-26

- **Fixed:** One-click standalone bootstrap now repairs ownership of `~/.bc250-toolkit` before cloning as the desktop user, preventing `could not create work tree dir: Permission denied` after earlier root-owned runs.
- **Fixed:** Git self-updates run as the desktop user and repair checkout ownership first, preventing `dubious ownership`, `.git/FETCH_HEAD: Permission denied`, and IDE save prompts caused by root-owned repository files.
- **Fixed:** ZSWAP runtime enablement now persists across reboot through a systemd-tmpfiles rule on SteamOS kernels that ignore `zswap.enabled=1`; status also distinguishes configured-but-inactive ZSWAP.

### 2026-07-23

- **Added:** `Extras` option `Z` installs the prebuilt Toolkit SteamOS Control Decky plugin. It installs Decky Loader stable automatically when needed, copies the bundled plugin artifact, and restarts the loader without Node.js, pnpm, or a local build.
- **Added:** Pump Fan automatic, manual, and managed four-point curve controls for the BC-250 NCT sensor/PWM channel, plus optional LED bar effect controls when `steamos-led.service` is present.
- **Added:** SteamOS update persistence for the Toolkit SteamOS Control fan configuration and managed-fan service.
- **Improved:** The Decky interface separates Cooler and LED bar views, preserves unsaved slider changes during status polling, and disables Pump Fan controls when the required sensor/PWM channel is unavailable.

### 2026-07-20

- **Added:** `start.sh` now self-updates on every launch. When run from a git clone it fetches `origin/main` and hard-resets to the latest commit, re-executing if anything changed. When run as a standalone script it bootstraps the full repository into `~/.bc250-toolkit/bc250-steamos-real-toolkit` as before.
- **Removed:** The manual `Update Script` (`U`) menu option and `run_update_script()` function are no longer needed because updates happen automatically at startup.

  *(Both of these were reverted in v1.0.0 above — auto-update on launch turned out to be destructive to in-progress local changes.)*

### 2026-07-19

- **Added:** `start.sh` now self-bootstraps when downloaded standalone (e.g. the one-liner `curl` install). If the vendored `external/` assets are missing, it fetches the full toolkit repository into `${REAL_HOME}/.bc250-toolkit/bc250-steamos-real-toolkit` via `git` (with a `curl`+`tar` fallback) and re-executes from there.
- **Fixed:** `cpu_governor_setup()` now recreates the `bc250-smu-oc.service` from an existing `/etc/bc250-smu-oc.conf` when the vendored `bc250_smu_oc` repository is not present, preventing the `Unit bc250-smu-oc.service does not exist` failure.

### 2026-07-18

- **Changed:** AIC8800D80 USB WiFi/BT Driver moved from "Install All" / "Install Manual" to the `Extras` menu and now uses `A` (install) and `R` (revert). The driver no longer uses the vendor `steamdeck-setup.sh`; it builds and installs the AIC8800 modules, firmware, udev rule and usb_modeswitch data directly, WiFi-only.
- **Changed:** Community fixes repositories (`bc250_smu_oc`, `nct6687d`) and the main fixes repo are now vendored/cloned into `$SCRIPT_DIR/external/` instead of `~/.local/share/`, keeping assets local and cached. `.gitignore` now excludes generated kernel build artifacts inside `external/`.
- **Changed:** `Extras` menu option letters reordered alphabetically (`A`, `F`, `H`, `K`, `P`, `R`, `X`, `0`).
- **Added:** SteamOS update persistence. Toolkit tracks installed components in `${REAL_HOME}/.bc250-toolkit/installed-components`; enabling persistence in `Extras` (`P`) installs `bc250-toolkit-persist.service` and an `atomic-update` keep list. After a SteamOS update the toolkit re-installs lost components and restores saved configs.
- **Added:** Config snapshots for CPU/GPU overclock (`/etc/bc250-smu-oc.conf`, `/etc/cyan-skillfish-governor-smu/config.toml`) and CoolerControl (`/etc/coolercontrol`) that are restored automatically after re-apply.
- **Improved:** Runtime command visibility with concise `[context] starting...` / `[context] completed.` progress messages in `run_with_retry()` and `steamos_writable()` without cluttering output.
- **Improved:** Diagnostic error logs now include a full `set -x` trace and recent captured output.
- **Improved:** Network/download failures now prompt to `[R]etry` or `[A]bort`; prompts are skipped in unattended re-apply (`AUTO=1`) mode.
- **Improved:** `Install All` tracks completed steps and offers to resume from the last unfinished step on the next run.
- **Fixed:** Persistence install no longer starts `bc250-toolkit-persist.service` immediately (`enable` only), preventing a recursive re-apply hang.
- **Fixed:** AIC8800 WiFi/BT install failed with `Update persistence helper missing: /home/deck/tools/bc250/bc250-update-persistence.sh`. The toolkit now links the helper from the fixes repository into the expected location before running `steamdeck-setup.sh`.
- **Changed:** AIC8800 WiFi/BT Driver install and revert options in `Extras` are now grouped into a dedicated submenu.
- **Changed:** SteamOS Update Persistence enable and view options on the main menu are now grouped into a submenu (`E` / `V`).
- **Fixed:** Persistence list now auto-detects and records already-installed toolkit components so nothing is lost when enabling persistence after the fact.

### 2026-07-17

- **Fixed:** ZSWAP status menu showed "ZRAM off / ZSWAP on" even when `/sys/module/zswap/parameters/enabled` was `N` after reboot. The toolkit now enables ZSWAP at runtime immediately and only reports it ON when the runtime parameter is `Y`.
- **Changed:** Default swapfile size raised to 32G and default swappiness to 120 for both manual "Configure Swap" and the "Install All" flow.
- **Changed:** Main menu option 1 now reads "Install all necessary optimizations" in its description.
- **Improved:** Selecting `0` to exit now waits for Enter before closing, keeping the Konsole window visible.

### 2026-07-15

- **Fixed:** DisplayPort Audio/Video Clock Fix failing when the SteamOS kernel release contains only a short commit SHA. The toolkit now resolves the full commit through `git ls-remote` and passes it as `FULLSHA` to the community driver patch script, avoiding the GitHub API HTTP 422 error.
- **Fixed:** DisplayPort Audio/Video Clock Fix stopping during dependency extraction because the upstream `tar | sed | awk` pipeline exited early under `pipefail`. The toolkit now patches that compatibility issue before running the build.
- **Added:** A SteamOS update warning is shown on every launch and documented in both READMEs. Users are instructed to check toolkit status after every update and be prepared to reinstall components, especially on the Beta channel.
- **Improved:** Desktop-launched sessions now use `konsole --hold`, unhandled errors generate diagnostic logs, and error logs are copied to the Desktop when available.
- **Improved:** `sudo` is authenticated once at startup and its timestamp is refreshed during the session, so nested installers should not repeatedly ask for the password.

### 2026-07-14

- **Renamed** main script from `bc250-tollkit-steam-os-real.sh` (typo) to `start.sh`. Updated `TOOLKIT_RAW_URL` (self-updater) and install commands in both READMEs accordingly.
- **Fixed:** `[ERR] failed to read cyan_skillfish.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK with umr` reported by users. `select_asic()` now tries to auto-detect the correct ASIC selector via `umr -lb` before giving up, covering boards where the default `cyan_skillfish.gfx1013` selector doesn't match.
- **Fixed:** `bc250-detect: command not found` when user already had CPU governor installed and chose not to reinstall (answered `n`). The script went straight to `cpu_governor_setup()` without adding the pipx bin dir to `PATH`. Fixed by always prepending `/root/.local/bin` and `/home/deck/.local/bin` at the top of `cpu_governor_setup()`.

### 2026-07-12

- **Fixed:** Menu 2 → option 9 (CU Unlock Live) was closing the entire toolkit when the user pressed `q` to quit the CU manager. Root cause: `bc250-cu-live-manager.sh` calls `exit 0` on quit, which propagated to the parent script. Fixed by running the sub-script in a subshell: `( bash "$CU_LIVE_MANAGER" )`.

### 2026-07-11 (2)

- **`game-save-sync`** has been extracted into its own standalone repository: [nonsteam-save-sync](https://github.com/rpf16rj/nonsteam-save-sync). It is no longer part of this toolkit. See that repo for installation and usage instructions.

### 2026-07-11

- Added an Xbox Wireless Adapter driver installer to **Extras**: installs `dkms`, `xone-dkms`, and `xone-dongle-firmware` via the AUR helper, blacklists conflicting drivers (`xpad`, `mt76x2u`), and loads `xone` automatically.
- Fixed the Community Fixes repo update aborting when a previous build left local artifacts (e.g. `amdgpu.ko.zst`) in the checkout.

### 2026-07-09

- Simplified and reorganized the whole menu: **Install All**, **Install Manual**, **Performance Profiles**, **Revert/Uninstall All**, and **Extras** (sensors, CoolerControl, HDMI-CEC), plus quick access to **Verify My Setup**, **Changelog**, **Update Script**, and **Help**.
- Added a built-in updater, a desktop shortcut created automatically on first run, and CPU mitigations + CU Unlock Live are now part of the one-click install/uninstall flow.
- Added Swap/ZRAM→ZSWAP tuning and HDMI-CEC / TV control.
- Fixed a bug that prevented the GPU governor's remote-control interface from working correctly.

### 2026-07-08

- Added sensor & fan monitoring for the BC-250's onboard chip, with optional full PWM fan control.
- Added CoolerControl integration for custom fan curves.
- Added the Community Fixes menu (ACPI power states, DisplayPort audio/video fix, AIC8800 WiFi/BT driver).
- Various installation reliability fixes validated on real hardware.

### 2026-07-06

- First public release: one-click Install All / Uninstall All, CU Unlock Live, performance profiles, automatic error logging, and automatic pacman keyring repair.
