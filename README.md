# BC-250 SteamOS Real Toolkit

> ⚠️ **Disclaimer:** This toolkit changes low-level system settings (bootloader, kernel modules, power and overclock profiles) on unofficial BC-250 hardware. Use it at your own risk — the author and contributors are not responsible for any damage, data loss, or hardware failure. Always make sure your PSU, cabling, and cooling can handle overclocked profiles before applying them, and keep backups when possible.

> ⚠️ **SteamOS updates:** an OS update can replace the kernel, modules, headers, boot configuration, or installed services. After **every SteamOS update**, check the toolkit status and be prepared to reinstall the affected components. This is especially important when the **Beta channel** is enabled. If an operation fails, the toolkit saves a diagnostic log in your home directory and copies it to the Desktop when available. The Desktop shortcut keeps the terminal open after the script exits so the error remains visible.

🇧🇷 Prefere português? Leia o [README.pt-br.md](./README.pt-br.md).

## What is this?

A friendly, menu-driven toolkit for the AMD BC-250 (Cyan Skillfish / GFX1013) board running **real SteamOS** — not a CachyOS port. It wraps CPU/GPU tuning, compute-unit unlocking, sensors/fan control, and a handful of community-made fixes into a single interactive script, so you don't have to touch the bootloader or build anything by hand.

## Main Features

- CPU & GPU performance governors, with ready-made profiles (Stock → Extreme) or fully custom combos
- Compute Unit (CU) unlock — run up to 40 CUs at runtime, with boot persistence
- CPU mitigations toggle (disable/re-enable)
- Sensor & fan monitoring, with optional full PWM fan control
- CoolerControl integration for custom fan curves via a web UI
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
- [redbeard1083](https://github.com/redbeard1083) — [bc250-toolkit](https://github.com/redbeard1083/bc250-toolkit) (swap / ZRAM→ZSWAP setup)
- [bc250-collective](https://github.com/bc250-collective) — [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc) (CPU governor)
- [filippor](https://github.com/filippor) — [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) (GPU governor)
- The [CoolerControl](https://gitlab.com/coolercontrol/coolercontrol) project

Without their work, none of this would be possible. 🙏

## Changelog

### 2026-07-19

- **Changed:** Community fixes repository is now cloned into `$SCRIPT_DIR/external/` (inside the toolkit tree) instead of `~/.local/share/`, keeping scripts/assets local and cached.
- **Changed:** AIC8800 WiFi/BT install no longer uses the vendor `steamdeck-setup.sh` (which pulled in `bc250-storage.sh` and `bc250-update-persistence.sh`); it now builds and installs the AIC8800 modules, firmware, udev rule and usb_modeswitch data directly, WiFi-only.
- **Changed:** `bc250_smu_oc` and `nct6687d` are now vendored under `$SCRIPT_DIR/external/`. `start.sh` no longer performs `git clone` at runtime for these repositories; it uses the local vendored copies.
- **Changed:** `.gitignore` now excludes generated kernel build artifacts inside the vendored `external/` directories (e.g., `steamos-headers`, `*.o`, `*.ko`, `*-drmexec*/`).

### 2026-07-18

- **Improved:** Diagnostic error logs now include a full `set -x` command trace (saved to a hidden fd) and the last lines of the captured script output, so failures show exactly which command failed and the surrounding verbose output.
- **Improved:** Network/download failures (slow SteamOS mirrors, git/clone timeouts, etc.) now prompt to `[R]etry` or `[A]bort` instead of immediately failing the whole script.
- **Improved:** `Install All` tracks completed steps and offers to resume from the last unfinished step on the next run.
- **Fixed:** AIC8800 WiFi/BT install failed with `Update persistence helper missing: /home/deck/tools/bc250/bc250-update-persistence.sh`. The toolkit now links the helper from the fixes repository into the expected location before running `steamdeck-setup.sh`.

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
