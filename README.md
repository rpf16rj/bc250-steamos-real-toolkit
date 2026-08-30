# BC-250 SteamOS Real Toolkit

> ⚠️ **Disclaimer:** This toolkit changes low-level system settings (bootloader, kernel modules, power and overclock profiles) on unofficial BC-250 hardware. Use it at your own risk — the author and contributors are not responsible for any damage, data loss, or hardware failure. Always make sure your PSU, cabling, and cooling can handle overclocked profiles before applying them, and keep backups when possible.

> ⚠️ **SteamOS updates:** an OS update can replace the kernel, modules, headers, boot configuration, or installed services. After **every SteamOS update**, check the toolkit status and be prepared to reinstall the affected components. This is especially important when the **Beta channel** is enabled. If an operation fails, the toolkit saves a diagnostic log in your home directory and copies it to the Desktop when available. The Desktop shortcut keeps the terminal open after the script exits so the error remains visible.

> 🔄 **Already installed and just want to update?** After downloading a newer [release](https://github.com/rpf16rj/bc250-steamos-real-toolkit/releases/latest) of the toolkit, you don't need to uninstall anything first — just run **Install All** again from the main menu. It re-applies and upgrades every component in place (fixes, drivers, services, profiles), skipping what's already up to date.

> ⚡ **Power draw with 8 CPU cores / 40 CUs active:** Running all 8 CPU cores (CPU Core Unlock) together with all 40 GPU compute units draws noticeably more power from the PSU than the stock 6c/12t + 32 CU configuration. If you experience random crashes, reboots, or shutdowns under load with this combination, your power supply may be undersized for it — try an undervolt profile before assuming a hardware fault. The **Mild (undervolt)** performance profile (CPU 3.5 GHz / GPU 1600 MHz, undervolted) has been tested stable on an HP server PSU rated at 460 W.

🇧🇷 Prefere português? Leia o [README.pt-br.md](./README.pt-br.md).

---

## What is this?

A friendly, menu-driven toolkit for the AMD BC-250 (Cyan Skillfish / GFX1013) board running **real SteamOS** — not a CachyOS port. It wraps CPU/GPU tuning, compute-unit unlocking, sensors/fan control, display and audio fixes, and community patches into a single interactive script, so you don't have to touch the bootloader or build anything by hand.

---

## Features

### Performance & Tuning

- **CPU & GPU performance governors** — ready-made profiles (Stock → Extreme) or fully custom combinations
- **Compute Unit (CU) unlock** — run up to 40 CUs at runtime, with boot persistence
- **CPU Core Unlock** — ⚠ experimental 6c/12t → 8c/16t via an SMU mailbox write, with a boot-time re-apply service
- **RAM/VRAM Split** — UMA_SIZE=512MB dynamic split + raised ttm.pages_limit ceiling, frees nearly all 16GB of RAM at idle
- **CPU mitigations toggle** — disable/re-enable Spectre/Meltdown mitigations for performance
- **Swap & ZSWAP** — configurable swapfile + lz4-compressed ZSWAP replacing ZRAM

### Display & Audio

- **DP-HDMI YCbCr 4:4:4 Deep Color + HDMI 2.1 FRL** — forces YCbCr 4:4:4 with 10/12-bit deep color on DP-to-HDMI PCON dongles (e.g. Ugreen CH7218). Enables HDMI 2.1 FRL at 48 Gbps for **1440p@120 12-bit** and **4K@60 12-bit**. See [docs/dp-hdmi-ycbcr444-frl.md](./docs/dp-hdmi-ycbcr444-frl.md) for bandwidth tables.
- **DisplayPort audio/video clock fix** — corrects DP audio/video timing and disables DP spread spectrum
- **HDMI AC-3 Surround Encoding** — Dolby Digital 5.1 over HDMI/DP via eARC, zero-latency native a52 encoding
- **HDMI-CEC / TV control** — control your TV or receiver via HDMI-CEC
- **HPD debounce** — prevents spurious hot-plug detect events when TV power-cycles

### Drivers & Fixes

- **GFX1013 compute queue fix** — async compute + patched Mesa/RADV with mesh/task shader and FSR4 V3 support
- **ACPI power states fix** — proper CPU C-/P-state tables (6c and 8c compatible)
- **AIC8800 WiFi/BT driver** — for AIC8800D80 USB WiFi/BT dongles
- **BE200 Wi-Fi 7 firmware** — for Intel BE200/BE201 PCIe cards missing ucode
- **DS5 Bridge PS Button fix** — DualSense chord combos via patched hid-playstation.ko
- **DS5 Chord Config** — QAM-enabled chord configuration VDF patch

### Monitoring & Control

- **Sensor & fan monitoring** — with optional full PWM fan control
- **CoolerControl integration** — custom fan curves via a web UI
- **Prebuilt Decky plugin** — Toolkit SteamOS Control with Pump Fan controls, four-point profiles, and optional LED bar controls
- **CU/WGP Live Manager** — runtime CU/WGP enable/disable without rebooting

### Quality of Life

- **One-click install** — automatic desktop shortcut, versioned releases with changelog
- **Everything is fully revertible** — revert individual components or all at once
- **SteamOS update persistence** — tracks installed components and re-applies after system updates

## Compatible System

- Real SteamOS (tested on 3.8.21 beta and 3.10 with kernel 7.2)
- AMD BC-250 board
- Root access and an internet connection

> **Updating to SteamOS 3.10 / kernel 7.2:** enable Developer Mode (Settings → System → Developer Mode), then enable Advanced Update Channels and switch the update channel to **Main**. After the update, run Install All again to reapply the toolkit patches for the new kernel.

## Quick Start

1. Download the zip from the [**latest release**](https://github.com/rpf16rj/bc250-steamos-real-toolkit/releases/latest) on your SteamOS machine (Desktop Mode).
2. Extract it, open a terminal in the extracted folder (Desktop Mode → Konsole), and run:

```bash
sudo ./start.sh
```

That's it — the script asks for `sudo` if needed, creates a desktop shortcut on first run, and guides you through everything else from its menu.

To update later, download the newest release zip, extract it over the old folder (or to a fresh one), and run `start.sh` again — see the banner above about `Install All`.

---

## Troubleshooting

### After a SteamOS update, something broke

SteamOS updates can replace the kernel, modules, and boot configuration. Run **Install All** from the toolkit menu to reapply all patches. If the kernel version changed, the Combined Fix will rebuild `amdgpu.ko` for the new kernel automatically.

### No display after reboot (Combined Fix)

The toolkit includes vermagic and ABI guards that refuse to install a mismatched module. If the build fails, the stock `amdgpu.ko` remains untouched and your display should work. If you still get no display:

1. Boot into Desktop Mode (or connect via SSH)
2. Run `sudo ./start.sh` → Revert Combined Fix
3. Reboot

### GPU temperature reads as 0

On kernel 7.x with 8 cores unlocked and a stock BIOS (no SMU telemetry patch), add `amdgpu.cs_legacy_8core_metrics=1` to GRUB. The toolkit prompts for this during installation.

### DP-HDMI adapter: no deep color / color banding

1. Ensure the Combined Fix is installed (the patch is always-on in every build)
2. Ensure `/etc/modprobe.d/amdgpu-ycbcr444.conf` exists with `force_ycbcr444=1 force_min_bpc=10 dcfeaturemask=0x402`
3. Reboot and check: `sudo dmesg | grep -iE "FRL PCON|frl_bw|CH7218"`
4. You should see `frl_bw=48000000` — if `frl_bw=0`, the FRL feature mask or PCON quirk isn't active
5. See [docs/dp-hdmi-ycbcr444-frl.md](./docs/dp-hdmi-ycbcr444-frl.md) for full bandwidth tables

### DP-HDMI: can't get 4K@120 with 4:4:4

This is a hardware limitation. The BC-250's DisplayPort 1.4 link provides 25.14 Gbps (HBR3, 4 lanes). 4K@120 10-bit 4:4:4 requires ~35.6 Gbps — exceeding DP 1.4 capacity. Use 4K@60 12-bit 4:4:4, 1440p@120 12-bit 4:4:4, or 4K@120 with YCbCr 4:2:0 instead.

### Random crashes or reboots under load

If running 8 cores + 40 CUs, your PSU may be undersized. Try the **Mild (undervolt)** profile first. If crashes persist, revert to 6c/12t + 32 CUs and test stability.

### Build fails after SteamOS update

Run `sudo ./ensure-build-prereqs.sh` to restore stripped headers and build dependencies. The toolkit does this automatically during Install All, but manual runs can help diagnose issues.

---

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
- [kungaa](https://github.com/kungaa) — [DS5-Linux-Bridge](https://github.com/kungaa/DS5-Linux-Bridge/) (DS5 Bridge PS Button fix inspiration)
- The [CoolerControl](https://gitlab.com/coolercontrol/coolercontrol) project

Without their work, none of this would be possible. 🙏

---

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for the full version history (or [CHANGELOG.pt-br.md](./CHANGELOG.pt-br.md) for Portuguese).

---

## License

These scripts are based on community work for the BC-250. Use at your own risk.

---

## Community

Questions, issues, or just want to chat about the BC-250? Join us on [Discord](https://discord.com/channels/1315924807128449065/).

---

## Support the Project

If this toolkit saved you time, helped you get the most out of your BC-250, or just made your life easier, consider supporting its continued development:

### ☕ Buy Me a Coffee

[**buymeacoffee.com/rpf16rj**](https://buymeacoffee.com/rpf16rj)

Your support helps cover:

- **Hardware costs** — adapters, dongles, and test equipment for ongoing development
- **Time invested** — reverse-engineering PCON quirks, debugging kernel patches, testing across configurations
- **Infrastructure** — CI/CD, release hosting, and documentation

Every contribution — big or small — directly funds the next feature, fix, or compatibility update. Thank you! 🙏

### Other Ways to Help

- ⭐ **Star the repo** — helps others discover the toolkit
- 🐛 **Report bugs** — open an issue with diagnostic logs and system details
- 💬 **Share your setup** — let the community know what works (and what doesn't)
- 🔀 **Contribute** — PRs are welcome for new fixes, drivers, or improvements
