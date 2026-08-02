# AMDGPU corrections

Corrects DisplayPort video/audio timing and Cyan Skillfish GPU telemetry
through one patched `amdgpu` module. GPU activity comes from GC status
sampling, GFX clock comes from a direct SMU query (range-validated against
CYAN_SKILLFISH_SCLK_MIN/MAX). On Robin 3.00 BIOS + unlocked 8-core/16-thread
topologies, per-core CPU power/temperature/frequency comes from a direct read
of the SMU's PMSTATUSLOG table (real per-core data for all 8 cores); every
other topology (stock 6-core/12-thread, or 8-core on a different BIOS/SMU
version) falls back to the firmware's published `SmuMetrics_t` six-entry
layout.

## Install

Run from the logged-in user session:

```bash
cd ~/.local/share/bc250-fixes/bc250-steamos/bc250-audio-fix
./patch-driver.sh
sudo reboot
```

`patch-driver.sh` restores the SteamOS build toolchain if an OS update removed it, fetches matching sources and kernel-specific dependencies, builds the module, validates it, and invokes `sudo` for privileged steps. If Valve omitted the exact headers package, it builds the exact kernel source completely to generate the missing symbol inventory. That fallback can take hours and requires about 40 GiB of free temporary space.

## Kernel Support

| SteamOS | Kernel | Patch |
|---|---|---|
| 3.8.x | `linux-neptune-616` | [`bc250-dp-audio-clock-6.16.patch`](bc250-dp-audio-clock-6.16.patch) |
| 3.9.x | `linux-neptune-618` | [`bc250-dp-audio-clock-6.18.patch`](bc250-dp-audio-clock-6.18.patch) |

Both versions also apply the Cyan Skillfish telemetry patches. They preserve
the firmware's published metrics layout, query the GFX clock through the SMU,
and sample GPU activity from GC status.
The build selects the display patch from the running kernel and produces
`amdgpu.ko.zst` for that exact release.

## GPU Metrics Patches

Display/audio and telemetry corrections share the same per-kernel `amdgpu`
override.

### Runtime Patch Set

| Patch | Operation |
|---|---|
| `bc250-cyan-skillfish-gpu-telemetry.patch` | Apply GC activity sampling while retaining `SmuMetrics_t` |
| `bc250-cyan-skillfish-gfxclk.patch` | Apply direct SMU GFX-clock reporting via `PPSMC_MSG_GetGfxFrequency` |
| `bc250-cyan-skillfish-8core-metrics.patch` | Real per-core power/temp/freq on Robin 3.00 8c/16t; `-ENODEV` fallback to `SmuMetrics_t` otherwise |

### Runtime Data

| Export | Source | Representation |
|---|---|---|
| `AMDGPU_PP_SENSOR_GPU_LOAD` | `GRBM_STATUS.GUI_ACTIVE` sampling | `0-100` percent |
| `gpu_metrics_v2_2.average_gfx_activity` | `GRBM_STATUS.GUI_ACTIVE` sampling | `0-10000` centipercent |
| `METRICS_CURR_GFXCLK` | `PPSMC_MSG_GetGfxFrequency` | Point-in-time MHz |
| `gpu_metrics_v2_2.current_gfxclk` | `PPSMC_MSG_GetGfxFrequency` | Point-in-time MHz |
| `gpu_metrics_v2_2.average_gfxclk_frequency` | `PPSMC_MSG_GetGfxFrequency` | Point-in-time MHz |
| CPU core arrays | PMSTATUSLOG (Robin 3.00 8c/16t) or firmware `SmuMetrics_t` fallback | Eight or six per-core entries |

### Activity Sampling

`gpu-telemetry` samples `GRBM_STATUS.GUI_ACTIVE` 32 times at 50-microsecond
intervals. The approximately 1.55-millisecond window supplies both activity
exports. The `average_gfx_activity` member name follows the
`gpu_metrics_v2_2` ABI; its value represents this sampling window.

### GFX Clock Query

`gfxclk` maps `SMU_MSG_GetGfxclkFrequency` to Cyan Skillfish firmware command
`PPSMC_MSG_GetGfxFrequency`. One SMU reply populates `METRICS_CURR_GFXCLK`,
`current_gfxclk`, and `average_gfxclk_frequency`. Query errors propagate to the
metrics caller.

### Core Count

`cyan_skillfish_is_robin3_8core()` detects Robin 3.00 BIOS + a fully unlocked
8-core/16-thread topology by checking the SMU firmware version, the core
presence mask, and `num_present_cpus()`. When all three match, per-core power,
temperature, and frequency come from a live PCIe-register read of the SMU's
PMSTATUSLOG table (8 real per-core rows) instead of the firmware's published
`SmuMetrics_t`, which only carries six. Any other topology (stock 6c/12t, or
8c/16t on a BIOS/SMU version this check doesn't recognize) falls back to the
six-entry `SmuMetrics_t` layout (`-ENODEV`). GPU activity and GFX clock
reporting use topology-independent register and SMU sources.

## Commands

| Command | Action |
|---|---|
| `./patch-driver.sh` | Fetch, build, validate, and install |
| `./patch-driver.sh status` | Report installed per-kernel module overrides |
| `./patch-driver.sh uninstall` | Noninteractively restore stock modules for all installed kernels |
| `./fetch-sources.sh` | Fetch the matching kernel source, symbols, and dependencies |
| `./ensure-build-prereqs.sh` | Restore a missing SteamOS host build toolchain |
| `./prepare-kernel.sh` | Prepare an exact Kbuild tree for external modules |
| `./build.sh` | Build and validate `amdgpu.ko.zst` |
| `./check-module.sh amdgpu.ko.zst` | Validate vermagic and ABI compatibility |
| `sudo ./install.sh` | Install the module and rebuild the initramfs |
| `sudo ./rollback.sh` | Restore the stock module for the running kernel |
| `sudo ./rollback.sh <kernel-release>` | Restore the stock module for a selected kernel |
| `sudo ./rollback.sh --all` | Restore stock modules for every installed kernel override |
| `sudo ./cleanup-other-slot.sh` | Restore the stock module in the alternate SteamOS slot |
| `./clean.sh` | Reset build state and retain downloaded packages |
| `./clean.sh --all` | Remove the kernel tree, dependencies, downloads, and generated builds |
| `./clean.sh --dry-run` | Preview cleanup |

Use a custom kernel-tree path as the final argument:

```bash
./patch-driver.sh /path/to/kernel-tree
./fetch-sources.sh /path/to/kernel-tree
./build.sh /path/to/kernel-tree
```

## Validation

The build and installer verify the source revision, kernel release, kernel configuration, and stock-module ABI before installation.

## Clock Gating

Clock-gating patches are experimental and opt-in.

| Command | Configuration |
|---|---|
| `./patch-driver.sh` | Display clock correction |
| `./patch-driver.sh --cg` | Display clock correction plus GFX MGCG/CGCG |
| `./patch-driver.sh --cg-unvalidated` | Display clock correction plus GFX, MC, SDMA, ATHUB, HDP, and NBIO clock gating |

`--cg-unvalidated` applies register programming across additional GPU blocks and carries black-screen risk. Use `amdgpu.cg_mask=0x5` for GFX-only recovery or `amdgpu.cg_mask=0` for the stock clock-gating mask.

The flags also work with `build.sh`:

```bash
./build.sh --cg
./build.sh --cg-unvalidated
```

## Rollback

Restore the stock module and reboot:

```bash
cd ~/.local/share/bc250-fixes/bc250-steamos/bc250-audio-fix
./patch-driver.sh uninstall
sudo reboot
```

Recovery environments can target the installed kernel directly:

```bash
sudo ./rollback.sh 6.16.12-valve24.2-1-neptune-616-g57ac0765fe0d
```

For an override installed in the alternate A/B slot:

```bash
sudo ./cleanup-other-slot.sh
```

## SteamOS Updates

Rebuild after each kernel update:

```bash
cd ~/.local/share/bc250-fixes/bc250-steamos
git pull
cd bc250-audio-fix
./patch-driver.sh
sudo reboot
```

Source availability follows the Evlav kernel mirror. Run the command again after the target kernel commit appears in the mirror. When the commit exists but Valve's headers package does not, the full-build fallback runs automatically. Set `FULL_BUILD_JOBS` to control parallelism or `FULL_BUILD_MIN_FREE_GB` to adjust the default 40 GiB free-space guard.

The complete fallback remains mandatory for the AMDGPU override. AIC8800 may instead use `prepare-kernel.sh --wifi`, which runs `modules_prepare` without `Module.symvers` only when `CONFIG_MODVERSIONS` is explicitly disabled.

## Files

| File | Purpose |
|---|---|
| `patch-driver.sh` | Complete build and installation workflow |
| `fetch-sources.sh` | Source, symbol, and dependency acquisition |
| `ensure-build-prereqs.sh` | Conditional SteamOS host-toolchain installation |
| `prepare-kernel.sh` | Shared exact Kbuild preparation for Wi-Fi and GPU modules |
| `build.sh` | Patch application, module build, packaging, and validation |
| `check-module.sh` | Vermagic and ABI validation |
| `install.sh` | Module override installation and initramfs generation |
| `rollback.sh` | Stock-module restoration |
| `cleanup-other-slot.sh` | Alternate-slot restoration |
| `clean.sh` | Generated-state cleanup |
| `build-env.sh` | Local build environment |
| `bc250-dp-audio-clock-6.16.patch` | SteamOS 3.8.x display clock patch |
| `bc250-dp-audio-clock-6.18.patch` | SteamOS 3.9.x display clock patch |
| `bc250-cyan-skillfish-gpu-telemetry.patch` | Runtime GPU activity export using the published metrics layout |
| `bc250-cyan-skillfish-gfxclk.patch` | Runtime GFX clock export using a direct SMU query |
| `bc250-cyan-skillfish-8core-metrics.patch` | Real per-core metrics on Robin 3.00 8c/16t, falls back to `SmuMetrics_t` otherwise |
| `bc250-cg-flags.patch` | Experimental GFX clock gating |
| `bc250-cg-flags-unvalidated.patch` | Experimental expanded clock gating |
