# BC-250 SteamOS Real Toolkit

> ⚠️ **Disclaimer:** This toolkit changes low-level system settings (bootloader, kernel modules, power and overclock profiles) on unofficial BC-250 hardware. Use it at your own risk — the author and contributors are not responsible for any damage, data loss, or hardware failure. Always make sure your PSU, cabling, and cooling can handle overclocked profiles before applying them, and keep backups when possible.

> ⚠️ **SteamOS updates:** an OS update can replace the kernel, modules, headers, boot configuration, or installed services. After **every SteamOS update**, check the toolkit status and be prepared to reinstall the affected components. This is especially important when the **Beta channel** is enabled. If an operation fails, the toolkit saves a diagnostic log in your home directory and copies it to the Desktop when available. The Desktop shortcut keeps the terminal open after the script exits so the error remains visible.

> 🔄 **Already installed and just want to update?** After downloading a newer [release](https://github.com/rpf16rj/bc250-steamos-real-toolkit/releases/latest) of the toolkit, you don't need to uninstall anything first — just run **Install All** again from the main menu. It re-applies and upgrades every component in place (fixes, drivers, services, profiles), skipping what's already up to date.

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
- HDMI AC-3 Surround Encoding — Dolby Digital 5.1 over HDMI/DP via eARC, previously impossible on SteamOS with the BC-250; works with any active DP-to-HDMI adapter
- Community-sourced fixes: ACPI power states, DisplayPort audio/video clock fix, AIC8800 WiFi/BT driver, GFX1013 compute queue fix (async compute, patched kernel + Mesa/RADV with mesh shader and FSR4 V3 support)
- One-click install, automatic desktop shortcut, and versioned releases with a changelog — everything is fully revertible

## Compatible System

- Real SteamOS (tested on 3.8.21 beta)
- AMD BC-250 board
- Root access and an internet connection

## Quick Start

1. Download the zip from the [**latest release**](https://github.com/rpf16rj/bc250-steamos-real-toolkit/releases/latest) on your SteamOS machine (Desktop Mode).
2. Extract it, open a terminal in the extracted folder (Desktop Mode → Konsole), and run:

```bash
sudo ./start.sh
```

That's it — the script asks for `sudo` if needed, creates a desktop shortcut on first run, and guides you through everything else from its menu.

To update later, download the newest release zip, extract it over the old folder (or to a fresh one), and run `start.sh` again — see the banner above about `Install All`.

## Thanks

This toolkit builds on top of great work from the BC-250 community. Huge thanks to:

- [keyboardspecialist](https://github.com/keyboardspecialist) — [bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos) (ACPI fix, DisplayPort audio/video fix, AIC8800 WiFi/BT driver, HDMI-CEC control)
- [DryhoppedIPA](https://github.com/DryhoppedIPA) — [bc250-gfx1013-fix](https://github.com/DryhoppedIPA/bc250-gfx1013-fix) (GFX1013 compute queue kernel + Mesa/RADV patches)
- [MastaG](https://github.com/MastaG) — [linux-cachyos-bc250](https://github.com/MastaG/linux-cachyos-bc250) (updated Mesa/RADV patches: mesh/task shaders, compute queue, GFX10.3 promotion)
- [lonewolf0622](https://github.com/lonewolf0622) — [BC250-Native-Mesh-Shaders-](https://github.com/lonewolf0622/BC250-Native-Mesh-Shaders-) (native MESH-only shader patch without GFX10.3 spoofing)
- [dmorazasanchez](https://github.com/dmorazasanchez) — [bc250-fsr4](https://github.com/dmorazasanchez/bc250-fsr4) (FSR4 V3 deferred SDot hybrid optimization)
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

See [CHANGELOG.md](./CHANGELOG.md) for the full version history (or [CHANGELOG.pt-br.md](./CHANGELOG.pt-br.md) for Portuguese).

## License

These scripts are based on community work for the BC-250. Use at your own risk.

## Community

Questions, issues, or just want to chat about the BC-250? Join us on [Discord](https://discord.com/channels/1315924807128449065/).

## Support

If this toolkit saved you some time, consider buying me a coffee: [buymeacoffee.com/rpf16rj](https://buymeacoffee.com/rpf16rj) ☕
