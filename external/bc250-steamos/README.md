# bc250-steamos

Management tools for SteamOS 3.8.x and 3.9.x.

## Install

```bash
mkdir -p ~/.local/share/bc250-fixes
git clone https://github.com/keyboardspecialist/bc250-steamos.git \
  ~/.local/share/bc250-fixes/bc250-steamos
cd ~/.local/share/bc250-fixes/bc250-steamos
```

## Tools

| Tool | Purpose |
|---|---|
| [`bc250-40cu.sh`](#compute-units) | Runtime 40 CU configuration and boot persistence |
| [`bc250-cu-status.sh`](#compute-units) | CU dispatch status |
| [`bc250-power.sh`](#power-management) | CPU power states, GPU governor, clock and voltage tuning, CPU overclocking |
| [`bc250-cec.sh`](#cec) | TV, receiver, input, and power control over HDMI-CEC |
| [`bc250-update-persistence.sh`](#steamos-updates) | Atomic-update allowlist and tuning recovery |
| [`decky-plugin/`](#big-picture-plugin) | Quick Access interface for daily controls |
| [`bc250-audio-fix/`](#display-clock) | DisplayPort video and audio clock correction |
| [`aic8800/`](#wifi-and-bluetooth) | AIC8800D80 USB WiFi and Bluetooth driver |

`bc250-40cu.sh`, `bc250-power.sh`, and `bc250-cec.sh` open an interactive menu when launched in a terminal. Each also provides a command interface through `<script> help`.

## Compute Units

Open the setup menu:

```bash
sudo ./bc250-40cu.sh
```

| Command | Action |
|---|---|
| `sudo ./bc250-40cu.sh check` | Show board, debugfs, UMR, and service state |
| `sudo ./bc250-40cu.sh prep` | Build and install UMR |
| `sudo ./bc250-40cu.sh manager` | Open the live CU manager |
| `sudo ./bc250-40cu.sh persist` | Install the boot-persistent manager |
| `sudo ./bc250-40cu.sh verify` | Verify registers and service state |
| `sudo ./bc250-40cu.sh revert` | Restore the 24 CU dispatch state at the next boot |

Review the harvest map in the live manager before selecting a dispatch layout. Prefer selective routing for scattered harvest patterns.

CU status:

```bash
sudo ./bc250-cu-status.sh
sudo ./bc250-cu-status.sh -q
```

## Power Management

Open the setup and tuning menu:

```bash
sudo ./bc250-power.sh
```

### Setup

| Command | Action |
|---|---|
| `sudo ./bc250-power.sh acpi` | Install CPU C-states and 800-3200 MHz P-states |
| `sudo ./bc250-power.sh governor` | Install and start the adaptive GPU governor |
| `sudo ./bc250-power.sh enable` | Enable the GPU governor and CPU frequency policy at boot |
| `sudo ./bc250-power.sh all` | Install the ACPI tables and GPU governor |
| `sudo ./bc250-power.sh status` | Show clocks, power states, temperatures, and services |

Reboot after installing the ACPI tables.

### GPU Tuning

```bash
sudo ./bc250-power.sh freq status
sudo ./bc250-power.sh freq 1800
sudo ./bc250-power.sh freq 0 2000
sudo ./bc250-power.sh freq auto

sudo ./bc250-power.sh gpu-volt show
sudo ./bc250-power.sh gpu-volt offset -25
sudo ./bc250-power.sh gpu-volt set 2000 985
sudo ./bc250-power.sh gpu-volt reset

sudo ./bc250-power.sh load-target eager
sudo ./bc250-power.sh load-target set 70 55
sudo ./bc250-power.sh load-target reset

sudo ./bc250-power.sh ramp set 500
sudo ./bc250-power.sh ramp reset
```

Frequency, voltage, load-target, and ramp settings persist across boots. GPU voltage points use a 700-1050 mV range.

### CPU Tuning

```bash
sudo ./bc250-power.sh cpu-oc detect 4000 1275
sudo ./bc250-power.sh cpu-oc enable
sudo ./bc250-power.sh cpu-oc status
sudo ./bc250-power.sh cpu-oc apply
sudo ./bc250-power.sh cpu-oc off
```

`cpu-oc detect` stress-tests each frequency step. Keep the VID limit at or below 1325 mV.

## CEC

Run CEC commands from the logged-in user session:

```bash
./bc250-cec.sh
./bc250-cec.sh setup
```

CEC requires a DP-to-HDMI adapter with CEC tunneling over AUX. Compatible designs include Club3D CAC-1080/CAC-1085 and Parade PS176/PS186 adapters.

| Command | Action |
|---|---|
| `./bc250-cec.sh status` | Show adapter, daemon, bus, TV, and service state |
| `./bc250-cec.sh scan` | Show the HDMI device tree and active source |
| `./bc250-cec.sh tv-on` | Wake the TV and select this input |
| `./bc250-cec.sh tv-off` | Put the TV in standby |
| `./bc250-cec.sh amp-on` | Wake the receiver and enable system audio |
| `./bc250-cec.sh amp-off` | Put the receiver in standby |
| `./bc250-cec.sh vol-up` | Raise receiver volume |
| `./bc250-cec.sh vol-down` | Lower receiver volume |
| `./bc250-cec.sh mute` | Toggle receiver mute |
| `./bc250-cec.sh active` | Show the active source |
| `./bc250-cec.sh handoff` | Select another CEC source |
| `./bc250-cec.sh release` | Release active-source ownership |
| `./bc250-cec.sh repair` | Re-register CEC after a link interruption |

Use `./bc250-cec.sh help` for boot, suspend, poweroff, receiver-follow, and behavior-toggle commands.

## Big Picture Plugin

[`decky-plugin/`](decky-plugin/) provides a Decky Loader Quick Access interface with vertical sections for CU status, power health, GPU tuning, saved CPU tuning, and CEC controls.

The plugin uses the toolkit checkout at `~/.local/share/bc250-fixes/bc250-steamos`. Build instructions are in [`decky-plugin/README.md`](decky-plugin/README.md).

## AMDGPU Driver

Build and install the matching `amdgpu` module:

```bash
cd bc250-audio-fix
./patch-driver.sh
```

The patch restores the DisplayPort pixel and audio reference clock. Builds are matched to the running kernel and checked for vermagic and ABI compatibility before installation.

Rollback:

```bash
sudo ./rollback.sh
```

See [`bc250-audio-fix/README.md`](bc250-audio-fix/README.md) for kernel support, build controls, and clock-gating options.

## AIC8800 Class WiFi and Bluetooth Driver

Install the AIC8800D80 USB modules and firmware configuration:

```bash
sudo bash aic8800/steamdeck-setup.sh
```

The installer snapshots driver source and firmware into root-owned storage. The
boot helper rebuilds from that trusted snapshot for a new kernel, then validates
and stages the exact module files it loads.

## SteamOS Updates

| Component | Update action |
|---|---|
| Compute-unit manager | Run `sudo ./bc250-40cu.sh verify` after an update |
| Power management | The keep list retains tuning and the ACPI service restores its boot files |
| CEC | Home configuration and allowlisted system integration carry forward |
| Display clock module | Run `bc250-audio-fix/patch-driver.sh` after each kernel update |
| AIC8800 modules | The root-owned boot helper rebuilds for a new kernel; rerun setup only if it reports a missing source snapshot or build failure |

Current installers preserve their configuration across atomic updates.

Privileged executables, firmware, and state live at `/var/lib/bc250-control`.
On SteamOS this is a bind mount backed by
`/home/.steamos/offload/var/lib/bc250-control`, following Valve's offload
layout. The backing path and all of its ancestors are root-owned, so the Deck
user cannot replace code later executed by a root service. The mount unit and
its enablement symlink are included in a dedicated atomic-update drop-in and
in every component drop-in.

```bash
sudo bash ./bc250-storage.sh status
sudo bash ./bc250-storage.sh repair
```

`repair` is idempotent and recreates the backing directory, mount unit,
enablement symlink, and atomic-update drop-in if an update removed integration
files. The backing data survives normal atomic updates because `/home` is the
shared partition; reinstalling or reimaging the device is outside that guarantee.

### Persistence Commands

Run `./bc250-update-persistence.sh` to open the interactive menu with current protection status for each component.

| Example | Action |
|---|---|
| `sudo ./bc250-update-persistence.sh install compute` | Protect compute-unit configuration |
| `sudo ./bc250-update-persistence.sh install power` | Protect power and tuning configuration |
| `sudo ./bc250-update-persistence.sh install cec` | Protect CEC system integration |
| `sudo ./bc250-update-persistence.sh install aic` | Protect AIC8800 system integration |
| `sudo ./bc250-update-persistence.sh install all` | Protect every component |
| `./bc250-update-persistence.sh status` | Show protection and recovery status |

### Recover an Earlier Installation

SteamOS stores edits from the previous image under `/etc/previous` and archives them in `/var/lib/steamos-atomupd/etc_backup`.

```bash
cd ~/.local/share/bc250-fixes/bc250-steamos
git pull
```

| Example | Action |
|---|---|
| `sudo ./bc250-update-persistence.sh recover compute` | Recover CU routing configuration |
| `sudo ./bc250-update-persistence.sh recover power` | Recover GPU and CPU tuning configuration |
| `sudo ./bc250-update-persistence.sh recover all` | Recover compute and power configuration |
| `sudo ./bc250-update-persistence.sh recover all --force` | Replace current configuration from the newest snapshot |

Run the normal component setup commands afterward to regenerate services for the current image.

## References

| Project | Resources | Used by |
|---|---|---|
| BC-250 40 CU Unlock | [Repository](https://github.com/duggasco/bc250-40cu-unlock) | Original Arch implementation for `bc250-40cu.sh` |
| BC-250 CU Live Manager | [Repository](https://github.com/WinnieLV/bc250-cu-live-manager) · [Script](https://github.com/WinnieLV/bc250-cu-live-manager/blob/main/bc250-cu-live-manager.sh) | `bc250-40cu.sh` |
| UMR | [Repository](https://gitlab.freedesktop.org/tomstdenis/umr) | `bc250-40cu.sh`, `bc250-cu-status.sh` |
| BC-250 ACPI Fix | [Repository](https://github.com/bc250-collective/bc250-acpi-fix) · [SSDT-CST](https://github.com/bc250-collective/bc250-acpi-fix/blob/main/SSDT-CST.aml) · [SSDT-PST](https://github.com/bc250-collective/bc250-acpi-fix/blob/main/SSDT-PST.aml) | `bc250-power.sh` |
| Cyan Skillfish Governor | [Repository](https://github.com/filippor/cyan-skillfish-governor/tree/smu) · [Performance-mode script](https://github.com/filippor/cyan-skillfish-governor/blob/smu/scripts/cyan-skillfish-performance-mode) | `bc250-power.sh` |
| BC-250 SMU OC | [Repository](https://github.com/bc250-collective/bc250_smu_oc) | `bc250-power.sh` |
| Valve kernel mirror | [Repository](https://github.com/Evlav/linux-integration) | `bc250-audio-fix/fetch-sources.sh` |
| SteamOS package mirror | [Package index](https://steamdeck-packages.steamos.cloud/archlinux-mirror/) | Audio-driver and AIC8800 build scripts |
| SteamOS atomic-update keep list | [Defaults](https://github.com/evlaV/steamos-customizations/blob/master/atomic-update/rauc/atomic-update-keep.conf.in) · [Drop-in example](https://github.com/evlaV/steamos-customizations/blob/master/atomic-update/rauc/example-additional-keep-list.conf.in) | `bc250-update-persistence.sh` |
| AIC8800 | [Repository](https://github.com/radxa-pkg/aic8800) | `aic8800/steamdeck-setup.sh` |
