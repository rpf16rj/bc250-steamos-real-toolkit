# DisplayPort clock correction

Corrects DisplayPort video and audio playback timing through a patched `amdgpu` module.

## Install

Run from the logged-in user session:

```bash
cd ~/.local/share/bc250-fixes/bc250-steamos/bc250-audio-fix
./patch-driver.sh
sudo reboot
```

`patch-driver.sh` fetches matching sources and build dependencies, builds the module, validates it, and invokes `sudo` for installation.

## Kernel Support

| SteamOS | Kernel | Patch |
|---|---|---|
| 3.8.x | `linux-neptune-616` | [`bc250-dp-audio-clock-6.16.patch`](bc250-dp-audio-clock-6.16.patch) |
| 3.9.x | `linux-neptune-618` | [`bc250-dp-audio-clock-6.18.patch`](bc250-dp-audio-clock-6.18.patch) |

The build selects the patch from the running kernel and produces `amdgpu.ko.zst` for that exact release.

## Commands

| Command | Action |
|---|---|
| `./patch-driver.sh` | Fetch, build, validate, and install |
| `./fetch-sources.sh` | Fetch the matching kernel source, symbols, and dependencies |
| `./build.sh` | Build and validate `amdgpu.ko.zst` |
| `./check-module.sh amdgpu.ko.zst` | Validate vermagic and ABI compatibility |
| `sudo ./install.sh` | Install the module and rebuild the initramfs |
| `sudo ./rollback.sh` | Restore the stock module for the running kernel |
| `sudo ./rollback.sh <kernel-release>` | Restore the stock module for a selected kernel |
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
sudo ./rollback.sh
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

Source availability follows the Evlav kernel mirror. Run the command again after the target kernel commit appears in the mirror.

## Files

| File | Purpose |
|---|---|
| `patch-driver.sh` | Complete build and installation workflow |
| `fetch-sources.sh` | Source, symbol, and dependency acquisition |
| `build.sh` | Patch application, module build, packaging, and validation |
| `check-module.sh` | Vermagic and ABI validation |
| `install.sh` | Module override installation and initramfs generation |
| `rollback.sh` | Stock-module restoration |
| `cleanup-other-slot.sh` | Alternate-slot restoration |
| `clean.sh` | Generated-state cleanup |
| `build-env.sh` | Local build environment |
| `bc250-dp-audio-clock-6.16.patch` | SteamOS 3.8.x display clock patch |
| `bc250-dp-audio-clock-6.18.patch` | SteamOS 3.9.x display clock patch |
| `bc250-cg-flags.patch` | Experimental GFX clock gating |
| `bc250-cg-flags-unvalidated.patch` | Experimental expanded clock gating |
