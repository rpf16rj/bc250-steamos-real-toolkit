# BC-250 SteamOS Real Toolkit

A SteamOS-focused toolkit for the AMD BC-250 (Cyan Skillfish / GFX1013) board. It installs and manages the CPU and GPU governors, applies performance profiles, and includes the live CU/WGP manager for unlocking up to 40 compute units.

> **Warning:** Overclocking and unlocking compute units increase power draw and heat. Make sure your PSU, cabling, and cooling can handle the load before applying high-risk profiles.

## Contents

- `bc250-tollkit-steam-os-real.sh` — interactive menu for CPU/GPU governor installation and performance profiles.
- `bc250-cu-live-manager.sh` — live CU/WGP manager using `umr` to enable/disable compute pairs at runtime.

## Requirements

- SteamOS (or another Arch-based distro with `steamos-readonly` support)
- AMD BC-250 board (PCI ID `1002:13fe`)
- Root access (`sudo`)
- Internet connection for AUR/git installs
- An AUR helper such as `shelly`, `paru`, or `yay`
- `umr` for the CU live manager (it will be installed if missing)

## Quick Start

1. Clone or copy this repository to your SteamOS machine.
2. Open a terminal in the folder.
3. Run the toolkit:

```bash
sudo ./bc250-tollkit-steam-os-real.sh
```

## Toolkit Menu Options

### 1. Performance Profiles
Apply pre-defined CPU/GPU overclock presets or create a custom mix:

- **Stock** — CPU 3.5 GHz, GPU 1500 MHz
- **Mild** — CPU 3.5 GHz, GPU 1600 MHz
- **Moderate** — CPU 3.5 GHz, GPU 1750 MHz
- **Strong** — CPU 3.5 GHz, GPU 1850 MHz
- **Aggressive** — CPU 3.5 GHz, GPU 2000 MHz
- **Extreme** — higher CPU/GPU clocks, requires explicit `OC` acknowledgement

You can also choose **Custom** to mix CPU and GPU profiles independently, or edit the config files directly with nano.

### 2. Install CPU Governor
Installs `bc250-smu-oc` from the [bc250-collective/bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc) repository and enables the `bc250-smu-oc.service` systemd service.

On SteamOS, the toolkit temporarily disables the read-only filesystem to install `python-pipx` and `stress`, then re-enables it.

### 3. Install GPU Governor
Installs `cyan-skillfish-governor-smu` from the AUR and enables the `cyan-skillfish-governor-smu.service` systemd service.

On SteamOS, the toolkit temporarily disables the read-only filesystem, installs the build dependencies, builds the AUR package, and re-enables read-only mode.

### 4. Revert CPU Governor
Stops and disables `bc250-smu-oc.service`, uninstalls the package via `pipx`, and removes `/etc/bc250-smu-oc.conf`.

### 5. Revert GPU Governor
Stops and disables `cyan-skillfish-governor-smu.service`, and removes the package via your AUR helper.

### S. Status
Shows the current kernel, active performance profile, and the state of the CPU/GPU governor services.

## CU Live Manager

The `bc250-cu-live-manager.sh` script lets you control which Work Group Processors (WGPs) are active. This can re-enable all 40 CUs on the BC-250 after boot.

### Run the interactive menu

```bash
sudo ./bc250-cu-live-manager.sh
```

Useful commands:

| Command | Action |
|---------|--------|
| `status` | Show current CU routing status |
| `enable all` | Enable all 40 CUs |
| `stock-dispatch` | Restore the driver-default 24 CU layout |
| `table` | Interactive TUI to edit WGP routing |
| `install-service` | Install a systemd service that restores a saved table on boot |
| `write-service-table` | Save the current table for the boot service |
| `apply-service` | Apply the saved table now |

### Example: enable 40 CUs and persist across reboots

```bash
sudo ./bc250-cu-live-manager.sh enable all
sudo ./bc250-cu-live-manager.sh write-service-table
sudo ./bc250-cu-live-manager.sh install-service
```

### SteamOS note

The SteamOS-packaged `umr` ships its register database compressed in `/usr/share/umr/database/database.tar.zst` and cannot read BC-250 registers directly. The script automatically extracts this database to `/var/lib/umr/database` and passes `--database-path` to `umr`.

### Kernel patch for true 40 CU enumeration

The live manager can route work to all 40 CUs, but the kernel driver still reports the stock number of CUs unless the `amdgpu` module is patched with `bc250_cc_write_mode=3`. To get the full 40 CU benefit you need to apply the kernel patch from [duggasco/bc250-40cu-unlock](https://github.com/duggasco/bc250-40cu-unlock).

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

## License

These scripts are based on community work for the BC-250. Use at your own risk.
