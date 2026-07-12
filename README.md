# BC-250 SteamOS Real Toolkit

> ⚠️ **Disclaimer:** This toolkit changes low-level system settings (bootloader, kernel modules, power and overclock profiles) on unofficial BC-250 hardware. Use it at your own risk — the author and contributors are not responsible for any damage, data loss, or hardware failure. Always make sure your PSU, cabling, and cooling can handle overclocked profiles before applying them, and keep backups when possible.

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
curl -sSL https://raw.githubusercontent.com/rpf16rj/bc250-steamos-real-toolkit/main/bc250-tollkit-steam-os-real.sh -o bc250-tollkit-steam-os-real.sh && chmod +x bc250-tollkit-steam-os-real.sh && sudo ./bc250-tollkit-steam-os-real.sh
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
