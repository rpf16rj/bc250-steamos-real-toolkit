# BC-250 SteamOS Real Toolkit

> ⚠️ **Disclaimer:** This toolkit changes low-level system settings (bootloader, kernel modules, power and overclock profiles) on unofficial BC-250 hardware. Use it at your own risk — the author and contributors are not responsible for any damage, data loss, or hardware failure. Always make sure your PSU, cabling, and cooling can handle overclocked profiles before applying them, and keep backups when possible.

> ⚠️ **SteamOS updates:** an OS update can replace the kernel, modules, headers, boot configuration, or installed services. After **every SteamOS update**, check the toolkit status and be prepared to reinstall the affected components. This is especially important when the **Beta channel** is enabled. If an operation fails, the toolkit saves a diagnostic log in your home directory and copies it to the Desktop when available. The Desktop shortcut keeps the terminal open after the script exits so the error remains visible.

> 🔄 **Already installed and just want to update?** After pulling a newer version of the toolkit, you don't need to uninstall anything first — just run **Install All** again from the main menu. It re-applies and upgrades every component in place (fixes, drivers, services, profiles), skipping what's already up to date.

> ⚡ **Power draw with 8 CPU cores / 40 CUs active:** Running all 8 CPU cores (CPU Core Unlock) together with all 40 GPU compute units draws noticeably more power from the PSU than the stock 6c/12t + 32 CU configuration. If you experience random crashes, reboots, or shutdowns under load with this combination, your power supply may be undersized for it — try an undervolt profile before assuming a hardware fault. The **Mild (undervolt)** performance profile (CPU 3.5 GHz / GPU 1600 MHz, undervolted) has been tested stable on an HP server PSU rated at 460 W.

🇧🇷 Prefere português? Leia o [README.pt-br.md](./README.pt-br.md).

## What is this?

A friendly, menu-driven toolkit for the AMD BC-250 (Cyan Skillfish / GFX1013) board running **real SteamOS** — not a CachyOS port. It wraps CPU/GPU tuning, compute-unit unlocking, sensors/fan control, and a handful of community-made fixes into a single interactive script, so you don't have to touch the bootloader or build anything by hand.

## Main Features

- CPU & GPU performance governors, with ready-made profiles (Stock → Extreme) or fully custom combos
- Compute Unit (CU) unlock — run up to 40 CUs at runtime, with boot persistence
- CPU Core Unlock — ⚠ experimental 6c/12t → 8c/16t via an SMU mailbox write, with a boot-time re-apply service
- RAM/VRAM Split — UMA_SIZE=512MB dynamic split + raised ttm.pages_limit ceiling, frees nearly all 16GB of RAM at idle
- CPU mitigations toggle (disable/re-enable)
- Sensor & fan monitoring, with optional full PWM fan control
- CoolerControl integration for custom fan curves via a web UI
- Prebuilt Toolkit SteamOS Control Decky plugin with Pump Fan automatic/manual/managed controls, four-point profiles, and optional LED bar controls
- HDMI-CEC / TV & receiver control
- Community-sourced fixes: ACPI power states, DisplayPort audio/video clock fix, AIC8800 WiFi/BT driver
- One-click install, automatic desktop shortcut, and a built-in updater — everything is fully revertible

## Compatible System

- Real SteamOS (tested on 3.8.21 beta)
- AMD BC-250 board
- Root access and an internet connection

## Quick Start

Open a terminal on your SteamOS machine (Desktop Mode → Konsole) and run:

```bash
curl -sSL https://raw.githubusercontent.com/rpf16rj/bc250-steamos-real-toolkit/main/start.sh -o start.sh && chmod +x start.sh && sudo ./start.sh
```

That's it — the script asks for `sudo` if needed, creates a desktop shortcut on first run, and guides you through everything else from its menu.

## Thanks

This toolkit builds on top of great work from the BC-250 community. Huge thanks to:

- [keyboardspecialist](https://github.com/keyboardspecialist) — [bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos) (ACPI fix, DisplayPort audio/video fix, AIC8800 WiFi/BT driver, HDMI-CEC control)
- [Fred78290](https://github.com/Fred78290) — [nct6687d](https://github.com/Fred78290/nct6687d) (PWM fan control driver)
- [duggasco](https://github.com/duggasco) — [bc250-40cu-unlock](https://github.com/duggasco/bc250-40cu-unlock) (kernel patch for the 40 CU unlock)
- [rw-r-r-0644](https://github.com/rw-r-r-0644) — [bc250-core-unlock](https://github.com/rw-r-r-0644/bc250-core-unlock) (CPU core unlock, 6c/12t → 8c/16t)
- [mendesrr](https://github.com/mendesrr) — [bc250-acpi-fix-updated-8c](https://github.com/mendesrr/bc250-acpi-fix-updated-8c) (ACPI C-/P-state tables, 6c and 8c compatible)
- [fanoush](https://github.com/fanoush) — [bc250_memcfg](https://github.com/fanoush/bc250_memcfg) (RAM/VRAM split CMOS tool)
- [redbeard1083](https://github.com/redbeard1083) — [bc250-toolkit](https://github.com/redbeard1083/bc250-toolkit) (swap / ZRAM→ZSWAP setup)
- [bc250-collective](https://github.com/bc250-collective) — [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc) (CPU governor)
- [filippor](https://github.com/filippor) — [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) (GPU governor)
- The [CoolerControl](https://gitlab.com/coolercontrol/coolercontrol) project

Without their work, none of this would be possible. 🙏

## Changelog

### 2026-08-02

- **Removed:** Auto-update-on-every-launch (`git fetch origin main` + `reset --hard` at the top of `start.sh`). It silently discarded any local uncommitted changes on launch, which could wipe in-progress work. Updating the toolkit now requires a manual `git pull` in the repo directory. The standalone bootstrap (cloning the repo when `start.sh` is run standalone via `curl`, with no `.git` present) is unaffected.
- **Added:** `bc250-cyan-skillfish-8core-metrics.patch` to `external/bc250-steamos/bc250-audio-fix`, vendored from [keyboardspecialist/bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos)'s newer combined patch set. On Robin 3.00 BIOS + a fully unlocked 8-core/16-thread topology (`CPU Core Unlock`), reads real per-core power/temperature/frequency for all 8 cores from the SMU's `PMSTATUSLOG` table via direct PCIe register access, instead of the firmware's stock `SmuMetrics_t` layout, which only ever carries 6 core entries — the previous audio-fix patch set silently duplicated/truncated per-core data on unlocked 8-core systems. Falls back to the stock 6-core `SmuMetrics_t` reporting (`-ENODEV`) on any other topology, so it's safe on unmodified 6c/12t systems too. Note: the upstream patch file as published was truncated (missing closing braces) — hand-completed and verified to apply cleanly and produce syntactically valid C against this toolkit's vendored kernel tree before vendoring.
- **Changed:** `bc250-cyan-skillfish-gfxclk.patch` updated to upstream's newer version, which wraps the direct SMU GFX-clock query in range validation (discards readings outside `CYAN_SKILLFISH_SCLK_MIN`/`MAX` instead of propagating garbage values to `gpu_metrics`/hwmon).

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

## License

These scripts are based on community work for the BC-250. Use at your own risk.

## Community

Questions, issues, or just want to chat about the BC-250? Join us on [Discord](https://discord.com/channels/1315924807128449065/).

## Support

If this toolkit saved you some time, consider buying me a coffee: [buymeacoffee.com/rpf16rj](https://buymeacoffee.com/rpf16rj) ☕
