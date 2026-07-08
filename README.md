# BC-250 SteamOS Real Toolkit

A toolkit for the AMD BC-250 (Cyan Skillfish / GFX1013) running **real SteamOS** — not a CachyOS port.

> **Warning:** Overclocking and unlocking compute units increase power draw and heat. Make sure your PSU, cabling, and cooling can handle the load before applying high-risk profiles.

## Features

- **CPU & GPU governors** — install/revert `bc250-smu-oc` and `cyan-skillfish-governor-smu`.
- **Performance profiles** — presets from Stock to Extreme, or fully custom CPU/GPU combos.
- **CPU mitigations toggle** — disable/re-enable via GRUB, adapted for SteamOS's bootloader.
- **CU live manager** — unlock up to 40 compute units at runtime using `umr`, with boot persistence.
- **Sensors & fan control** — install the NCT6686D SuperIO driver as read-only sensors (`nct6683`) or full PWM fan control (`nct6687`, built from source).
- **CoolerControl integration** — install the `coolercontrold` daemon (+ optional GUI) from AUR and manage custom fan curves via its web UI.
- **Community fixes** — ACPI CPU C-/P-states, DisplayPort audio/video clock fix, and AIC8800 USB WiFi/BT driver, sourced from [keyboardspecialist/bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos).
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
  [ F]  Sensors & Fan Control      NCT6686D sensors / NCT6687 PWM fan control
  [ K]  CoolerControl              Install/revert CoolerControl fan-curve daemon + GUI
  [ X]  Community Fixes            ACPI power states, DP audio/video, AIC8800 WiFi

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

## Sensors & Fan Control

The BC-250 uses a Nuvoton NCT6686D SuperIO chip for hardware monitoring (temperatures, voltage rails, up to 8 fan headers). It isn't auto-detected, so the driver must be loaded with `force=true`. From the main menu, choose **`F` — Sensors & Fan Control**:

| Option | Driver | Access |
|--------|--------|--------|
| Read-Only Sensors | `nct6683` (in-kernel) | Temperatures, voltages, fan RPM — no PWM control |
| Full PWM Fan Control | `nct6687` (built from [Fred78290/nct6687d](https://github.com/Fred78290/nct6687d)) | Everything above **+ writable PWM fan control** |

The toolkit handles this automatically:

- Detects the exact kernel package in use (e.g. `linux-neptune-616-drm-exec`) and installs its matching `-headers` package — this is the most common point of failure when following the driver's manual build instructions, since SteamOS kernels are custom-built and need an exact headers match.
- Clones and builds `nct6687d` against the running kernel, installs the module, blacklists `nct6683` (the two drivers conflict), and configures both `/etc/modprobe.d/sensors.conf` and `/etc/modules-load.d/99-sensors.conf` for autoload on boot.
- Regardless of which driver is loaded, sensors report as `nct6686-isa-0a20`.

```bash
sensors nct6686-isa-0a20
```

PWM fan control is exposed as standard hwmon files once `nct6687` is loaded:

```bash
cat /sys/class/hwmon/hwmon*/name        # find the nct6686 hwmon dir
echo 1 | sudo tee /sys/class/hwmon/hwmonN/pwm1_enable   # 1 = manual control
echo 128 | sudo tee /sys/class/hwmon/hwmonN/pwm1        # 0-255 duty cycle
```

**Note:** `nct6687` is an out-of-tree module rebuilt against the currently running kernel. A SteamOS kernel update may require reinstalling it from the menu.

## CoolerControl

For a proper fan-curve UI on top of the sensors above, choose **`K` — CoolerControl** from the main menu. It installs [`coolercontrold-bin`](https://aur.archlinux.org/packages/coolercontrold-bin) (the daemon, lightweight prebuilt binary) from AUR, with an optional prompt to also install the [`coolercontrol-bin`](https://aur.archlinux.org/packages/coolercontrol-bin) desktop GUI (pulls in Qt6 WebEngine, larger download), then enables and starts the `coolercontrold` systemd service.

```text
Web UI: https://localhost:11987
```

- Install the **PWM driver first** (`F` → Full PWM Fan Control) so CoolerControl has writable `pwmN` channels to build fan curves against — read-only sensors alone won't let it control fan speed.
- The revert option stops/disables the service and removes both the daemon and GUI packages (bin or source variants).

## Community Fixes

The **`X` — Community Fixes** menu wraps three fixes from [keyboardspecialist/bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos) that complement (not replace) this toolkit's own CPU/GPU governors and CU unlock. The repo is cloned/updated on demand to `~/.local/share/bc250-fixes/bc250-steamos` (deliberately **not** under `/var` — SteamOS's `/var` partition is tiny, ~230 MB, and is frequently already near-full).

| Fix | What it does | Risk |
|-----|--------------|------|
| **ACPI Fix (C/P-states)** | Installs SSDT-CST/SSDT-PST as an early-initrd ACPI override (BC-250's BIOS ships no CPU power tables, so without it cores never idle and cpufreq scaling doesn't exist). Self-heals after SteamOS updates wipe `/boot`. | Low — reversible, GRUB-only change |
| **DisplayPort Audio/Video Clock Fix** | Rebuilds `amdgpu.ko` with a 2-hunk kernel patch fixing a DP reference-clock bug that plays both video and audio at ~82% speed. Runs the upstream repo's own `patch-driver.sh`, which builds against your *exact* running kernel and includes vermagic + ABI guards. | **High** — a bad out-of-tree GPU driver build can leave the machine with no display at boot. Only run this if you're actually seeing the slow-motion DP bug. |
| **AIC8800 WiFi/BT Driver** | Builds and installs the driver for AIC8800D80-based USB WiFi/BT dongles (the ones that enumerate as a fake `1111:1111` mass-storage device). Only relevant if you have one of these dongles. | Low — an isolated USB driver, unrelated to boot/display |

Each fix has a matching **Revert** option in the same menu, and all three are included in **Install All** / **Uninstall All** (the audio fix still asks for confirmation before touching `amdgpu.ko`, since it's the risky one).

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

### 2026-07-08

- Added **Sensors & Fan Control** menu (`F`) for the Nuvoton NCT6686D SuperIO chip:
  - Read-only sensors option (`nct6683`, in-kernel, `modprobe force=true`).
  - Full PWM fan control option (`nct6687`, built from source against the exact running kernel) with automatic kernel-headers package detection (`pacman -Qoq` on the running kernel's module dir), build, install, `nct6683` blacklist, and boot autoload config.
  - Revert option to unload the driver and remove `/etc/modprobe.d/sensors.conf` + `/etc/modules-load.d/99-sensors.conf`.
- Fixed a `set -o pipefail` bug where `lsmod | grep -q` could report a loaded module as "not loaded" due to a SIGPIPE on `lsmod`; module detection now checks `/sys/module/<name>` instead.
- Validated the full PWM install flow on real BC-250 hardware (headers install, module build/install, `pwm1`-`pwm8` writable under `nct6686-isa-0a20`).
- Added **CoolerControl** menu (`K`): installs `coolercontrold-bin` from AUR (with an optional `coolercontrol-bin` desktop GUI prompt), enables/starts the `coolercontrold` service, and includes a matching revert option.
- Updated **Status** screen (`S`) to show the active sensor driver (`nct6687`/`nct6683`/not loaded) and the `coolercontrold` service state.
- Validated CoolerControl install and revert end-to-end on real BC-250 hardware.
- Added **Community Fixes** menu (`X`), sourced from [keyboardspecialist/bc250-steamos](https://github.com/keyboardspecialist/bc250-steamos) (repo cloned on demand to `~/.local/share/bc250-fixes/bc250-steamos`):
  - **ACPI Fix** — implemented directly (SSDT-CST/SSDT-PST early-initrd override, GRUB wiring, boot self-heal + schedutil services) for CPU C-states/P-states.
  - **DisplayPort Audio/Video Clock Fix** — wraps the upstream repo's own `patch-driver.sh`/`rollback.sh` (kernel-specific `amdgpu.ko` rebuild with vermagic/ABI guards) rather than reimplementing it, given the risk of a bad build leaving no display at boot.
  - **AIC8800 WiFi/BT Driver** — wraps the upstream repo's `steamdeck-setup.sh`, symlinked to its expected `/home/deck/tools/bc250/aic8800` path.
  - All three now included in **Install All** / **Uninstall All**, and reported on the **Status** screen.
- Excluded the upstream repo's CU unlock (`bc250-40cu.sh`, `bc250-cu-status.sh`) and CPU/GPU governor/overclock scripts (`bc250-power.sh`'s governor/freq/gpu-volt/cpu-oc commands), since this toolkit already covers that functionality with `bc250-cu-live-manager.sh` and its own governors.
- **Fixed:** the fixes repo clone initially targeted `/var/lib/bc250-fixes`, which filled SteamOS's tiny (~230 MB) `/var` partition and failed the checkout (`Não há espaço disponível no dispositivo`). Moved the clone to `~/.local/share/bc250-fixes` (on the large `/home` partition) and added a pre-clone free-space check (aborts with a clear error below 500 MB free) plus automatic cleanup of a failed/partial clone.
- **Fixed:** the DP Audio/Video Fix always failed with `run as the normal user — sudo is used for the install step only` — `patch-driver.sh` (and the `build.sh`/`fetch-sources.sh` it calls) refuse to run as root, but this toolkit runs entirely as root. Now runs `patch-driver.sh` via `runuser -u <real user>` (it invokes `sudo` itself only for the final `install.sh` step, so a sudo password prompt may appear mid-run).
- **Fixed:** the DP Audio/Video Fix's `fetch-sources.sh` hardcodes the `jupiter-main` repo channel when downloading the matching kernel-headers package, which 404s on a system pinned to a versioned branch (e.g. `jupiter-3.8`) even though the exact package exists one channel over. Added `audio_fix_prefetch_headers()`, which derives the expected headers package name from `uname -r` and pre-stages it from this system's actual repo channels (read from `/etc/pacman.conf`) before `fetch-sources.sh` runs — it skips its own download when the file is already present.
- **Known environment gotcha (not a toolkit bug):** if `build.sh` fails on `scripts/basic/fixdep` or `scripts/kconfig/conf.o` with a missing `sys/types.h` or `linux/limits.h`, this SteamOS install's `glibc`/`linux-api-headers` packages have their `/usr/include/*` dev headers missing on disk despite `pacman` believing they're fully installed (seen via `pacman -Qkk <pkg>` reporting hundreds of "changed"/missing files — likely from a prior debloat/cleanup pass). Fix: `steamos-readonly disable && pacman -Sy --overwrite '*' glibc linux-api-headers && steamos-readonly enable`, then retry. Needs ~20 MB download / ~40 MB more disk on `/` combined.
- **Fixed:** `install.sh`/`rollback.sh` hardcode `mkinitcpio -p linux-neptune-616`, which fails with `Failed to load preset` on non-standard kernel flavors whose preset file has a suffix (e.g. the `-drm-exec` experimental kernel: `linux-neptune-616-drm-exec.preset`) — the module itself installs correctly either way, only the final initramfs rebuild breaks. Added `audio_fix_ensure_mkinitcpio_preset()`, which symlinks the expected preset name to whatever preset actually exists before calling `patch-driver.sh`/`rollback.sh`.
- Validated the full DP Audio/Video Fix build → vermagic/ABI verification → install → initramfs rebuild end-to-end on real BC-250 hardware (custom `drm-exec` kernel flavor).

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
