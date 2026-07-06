# BC-250 SteamOS Real Toolkit

A toolkit for the AMD BC-250 (Cyan Skillfish / GFX1013) running **real SteamOS** — not a CachyOS port.

> **Warning:** Overclocking and unlocking compute units increase power draw and heat. Make sure your PSU, cabling, and cooling can handle the load before applying high-risk profiles.

## Features

- **CPU & GPU governors** — install/revert `bc250-smu-oc` and `cyan-skillfish-governor-smu`.
- **Performance profiles** — presets from Stock to Extreme, or fully custom CPU/GPU combos.
- **CPU mitigations toggle** — disable/re-enable via GRUB, adapted for SteamOS's bootloader.
- **CU live manager** — unlock up to 40 compute units at runtime using `umr`, with boot persistence.
- **Built for SteamOS's read-only filesystem** — handles `steamos-readonly`, `umr` database extraction, and read-only-safe service install paths automatically.

## Benefits

- Real perf gains: Forza Horizon 6 went from ~55 fps to ~80 fps with governors + 40 CUs enabled.
- No manual bootloader/database fiddling — the scripts handle SteamOS quirks for you.
- Fully revertible: every install has a matching revert option.

## Requirements

- Real SteamOS (tested on 3.8.21 beta)
- AMD BC-250 board (PCI ID `1002:13fe`)
- Root access (`sudo`)
- Internet connection
- An AUR helper such as `shelly`, `paru`, or `yay`

## Quick Start

### One-click install & run

Open a terminal on your SteamOS machine (Desktop Mode → Konsole) and run:

```bash
curl -sSL https://raw.githubusercontent.com/rpf16rj/bc250-steamos-real-toolkit/main/bc250-tollkit-steam-os-real.sh -o bc250-tollkit-steam-os-real.sh && chmod +x bc250-tollkit-steam-os-real.sh && sudo ./bc250-tollkit-steam-os-real.sh
```

This downloads the toolkit script, makes it executable, and launches the interactive menu with root privileges (the script re-execs itself with `sudo` if needed).

### CU Live Manager

To also get the CU live manager (unlock 40 CUs), download it the same way:

```bash
curl -sSL https://raw.githubusercontent.com/rpf16rj/bc250-steamos-real-toolkit/main/bc250-cu-live-manager.sh -o bc250-cu-live-manager.sh && chmod +x bc250-cu-live-manager.sh && sudo ./bc250-cu-live-manager.sh
```

### Manual install (clone the repo)

```bash
git clone https://github.com/rpf16rj/bc250-steamos-real-toolkit.git
cd bc250-steamos-real-toolkit
chmod +x bc250-tollkit-steam-os-real.sh bc250-cu-live-manager.sh
sudo ./bc250-tollkit-steam-os-real.sh
```

## Menu Preview

### Main menu — `bc250-tollkit-steam-os-real.sh`

```text
  ╔═════════════════════════════════════════════════════════════════════╗
  ║                                                                     ║
  ║                 BC-250 SteamOS Real Toolkit                         ║
  ║           CPU/GPU Governors & Performance Profiles                  ║
  ║                                                                     ║
  ╚═════════════════════════════════════════════════════════════════════╝

  Quick Start
  ─────────────────────────────────────────────────────────────────────
  [ 1]  Install All                Install CPU + GPU governor in one step
  [ 2]  Uninstall All              Revert CPU + GPU governor in one step

  Governors & Tweaks
  ─────────────────────────────────────────────────────────────────────
  [ 3]  Install CPU Governor       bc250-smu-oc CPU overclock service
  [ 4]  Install GPU Governor       cyan-skillfish GPU governor service
  [ 5]  Disable CPU Mitigations    Add mitigations=off to GRUB
  [ 6]  Performance Profiles       CPU & GPU performance profiles

  Revert
  ─────────────────────────────────────────────────────────────────────
  [ 7]  Re-enable CPU Mitigations  Remove mitigations=off from GRUB
  [ 8]  Revert CPU Governor        Remove bc250-smu-oc service
  [ 9]  Revert GPU Governor        Remove cyan-skillfish-governor-smu

  Tools
  ─────────────────────────────────────────────────────────────────────
  [ C]  CU Unlock Live             Open bc250-cu-live-manager.sh (WGP/CU live manager)

  System
  ─────────────────────────────────────────────────────────────────────
  [ S]  Status                     Current system summary
  [ 0]  Exit                       

  ═════════════════════════════════════════════════════════════════════
  Enter selection: 0

  Goodbye.
```

### CU Dashboard — `bc250-cu-live-manager.sh status`

```text
(deck@steamdeck bc250-steamos-real-toolkit)$ sudo ./bc250-cu-live-manager.sh
[ OK ] using extracted UMR database at /var/lib/umr/database
+------------------------------------------------------------------------------+
| BC-250 CU Dashboard / Live Dispatch                                          |
+------------------------------------------------------------------------------+
  UMR        : /usr/bin/umr
  UMR inst   : 0 (auto)
  ASIC       : cyan_skillfish.gfx1013
  amdgpu     : bc250_cc_write_mode=not exposed, active_cu_number=24
  Service    : enabled
  Boot sync  : current table saved
  Source     : SPI dispatch masks + amdgpu boot CU map
  Legend     : D+ driver+routed, S+ SPI+routed, D! driver+off, -- off

  +---------+------+------+------+------+------+------+------------+--------+
  | Row     | WGP0 | WGP1 | WGP2 | WGP3 | WGP4 | SPI  | CC         | CUs    |
  |         | 0-1  | 2-3  | 4-5  | 6-7  | 8-9  |      |            |        |
  +---------+------+------+------+------+------+------+------------+--------+
  | SE0.SH0 |  D+  |  D+  |  D+  |  S+  |  S+  | 0x1f | 0xffe00000 |  10/10 |
  | SE0.SH1 |  D+  |  D+  |  D+  |  S+  |  S+  | 0x1f | 0xffe00000 |  10/10 |
  | SE1.SH0 |  D+  |  D+  |  D+  |  S+  |  S+  | 0x1f | 0xffe00000 |  10/10 |
  | SE1.SH1 |  D+  |  D+  |  D+  |  S+  |  S+  | 0x1f | 0xffe00000 |  10/10 |
  +---------+------+------+------+------+------+------+------------+--------+

  CUs active & routed  : 40/40

+------------------------------------------------------------------------------+
| Actions                                                                      |
+------------------------------------------------------------------------------+
|  [e] Edit WGP table      [f] Enable all CUs      [t] Enable default CUs      |
|  [i] Install service     [w] Write table         [u] Uninstall service       |
|  [q] Quit                                                                    |
+------------------------------------------------------------------------------+

> Select action: 
```

## CU Live Manager

`bc250-cu-live-manager.sh` unlocks up to 40 compute units at runtime via `umr`, with an interactive dashboard and optional boot-persistence service.

```bash
sudo ./bc250-cu-live-manager.sh
```

Quick reference:

| Command | Action |
|---------|--------|
| `status` | Show current CU routing status |
| `enable all` | Enable all 40 CUs |
| `stock-dispatch` | Restore the driver-default 24 CU layout |
| `install-service` / `write-service-table` | Persist a CU table across reboots |

**Note:** the driver still reports the stock CU count unless you separately apply the kernel patch from [duggasco/bc250-40cu-unlock](https://github.com/duggasco/bc250-40cu-unlock).

## Validation

Check whether the kernel sees 40 CUs:

```bash
dmesg | grep active_cu_number
```

Check the SPI routing register:

```bash
sudo umr --database-path /var/lib/umr/database -r cyan_skillfish.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK
```

Check Vulkan-reported CU count:

```bash
RADV_DEBUG=info vulkaninfo --summary 2>&1 | grep num_cu
```

## Safety

- High-risk GPU profiles (2100 MHz and above) require typing `OC` to confirm.
- Unlocking CUs significantly increases power draw; verify your PSU and cooling.
- Keep the original configs if you need to revert (`/etc/bc250-smu-oc.conf` and `/etc/cyan-skillfish-governor-smu/config.toml`).

## Changelog

### 2026-07-06

- Added **Install All** / **Uninstall All** quick actions to the main menu (installs or reverts CPU + GPU governor in one step).
- Added **CU Unlock Live** entry to the main menu, launching `bc250-cu-live-manager.sh` directly from the wizard.
- Added a **reinstall confirmation** for "Install CPU Governor" / "Install GPU Governor": if already installed, prompts to reinstall (remove + reinstall) or skip straight to a configuration-only setup step.
- Added **automatic pacman keyring repair**: detects keyring-related pacman failures (`chaveiro`/`keyring` errors), runs `pacman-key --init` + `--populate`, and retries the failed command automatically.
- Added **error diagnostic logging**: on install failures, a log with system info, service status, journal, and pacman log is saved to the user's home directory, with instructions to share it with the community or attach it to a GitHub issue.
- Added a new performance preset: **Mild (undervolt)** — GPU 1600 MHz with reduced safe-point voltages (1000MHz@750mV, 1175MHz@788mV, 1500MHz@848mV, 1600MHz@856mV).
- Reordered the Performance Profiles menu so **Performance Profiles** now appears right after **Disable CPU Mitigations**.

## License

These scripts are based on community work for the BC-250. Use at your own risk.
