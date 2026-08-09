# BC-250 GFX1013 compute queue fix

Patches to make the ASRock BC-250's GPU actually use its compute queues.

## Results

Cyberpunk 2077 benchmark, 1440p Medium, native (no upscaling, no frame gen), with the
40-CU unlock active, 3 runs each:

| CPU config | without the fix | with the fix | delta |
|---|---:|---:|---:|
| 6 cores | 46.4 | 58.0 | +25.0% |
| 8 cores | 47.8 | 57.7 | +20.8% |

Vulkan CTS: the full `dEQP-VK.synchronization2.*` group (81,617 tests) shows **zero regressions**
against stock, and the 7,384 compute-queue cases that stock can't even run all pass. This is one
CTS group, not a full conformance run.

## The problem

The BC-250's GPU has dedicated compute queues (ACE), the hardware behind *async compute*: games
split a frame into graphics work (rendering) and compute work (lighting, particles,
post-processing, upscaling), and a separate queue lets the compute half overlap the graphics
half, using shader cores that would otherwise sit idle.

Linux hard-disables these queues. The compute queue has been "known to be
broken," and it is: enable it on a stock BC250 & frames corrupt.

The actual defect: the chip powers on into a state where ACE dispatches using
threadgroup-dimension mode with `PARTIAL_TG_EN` mis-execute. RADV's internal copy shaders use
exactly that encoding, so every driver-side copy on a compute queue drops the same rows of the
same images, bit-identical, every run. The corruption comes from the driver's own internal
copies, not from application shaders.

Separately: stock kernels break the compute-queue lifecycle on this chip (repeated queue
teardown ends in wedges and allocator failures), and RADV misdetects it as RDNA2 when it's
RDNA1-class. Three independent problems; the queue stayed off.

## The fix

Two halves that work together:

- **Kernel** (3 patches): repairs the compute-queue lifecycle so the ACE works.
- **Mesa/RADV** (3 patches): turns the compute queue on and fixes the dispatch corruption,
  plus correct GFX10.1 detection. Mesh/task shader patches ship disabled (see below).

The corruption fix is one line. RADV has carried a workaround for this exact dispatch class
since the GCN3 era (Iceland and Tonga, 2015): switch async compute dispatches to
thread-dimension mode. GFX1013 needs the same workaround; it was never added to the list:

```c
info->has_async_compute_threadgroup_bug = info->family == CHIP_ICELAND ||
                                          info->family == CHIP_TONGA ||
                                          info->family == CHIP_GFX1013;
```

The remaining patches are a kernel whose compute queues survive use and a driver that exposes them.

The Mesa side is a series you can trim. `patches/mesa/series`:

| patch | what | optional? |
|---|---|---|
| 0001 | compute queue fix (identity + exposure + dispatch workaround) | required |
| 0002 | native mesh + task shaders, Vulkan 1.4 | **disabled** - can hang the GPU |
| 0003 | mesh/task pipeline-statistics queries | **disabled** (needs 0002) |

## Quick Start

### Option 1: install.sh (Fedora 43)

Everything is built from source on your box, no binary blobs.

```bash
sudo ./install.sh deps       # build dependencies (dnf)
./install.sh build           # kernel module + Mesa, from the patches
sudo ./install.sh install
sudo reboot
```

First patched boot is one-shot; your stock entry stays the default until you activate:

```bash
sudo ./install.sh activate
```

The patched module lives in its own initramfs with its own boot entry, and the patched Mesa
lives under `/opt/bc250-gfx1013/`, selected only on the patched boot. Your stock kernel module
and initramfs are never touched.

### Option 2: Apply the patches manually (any distro)

Kernel first. Never run the Mesa half on an unpatched kernel; it will hang.

```bash
# In your kernel source tree (matching the running kernel):
for p in /path/to/repo/patches/kernel/v33/*.patch; do patch -p1 < "$p"; done
make -C /lib/modules/$(uname -r)/build M=$PWD/drivers/gpu/drm/amd/amdgpu -j$(nproc) modules
sudo install -D drivers/gpu/drm/amd/amdgpu/amdgpu.ko \
    /lib/modules/$(uname -r)/updates/amdgpu.ko
sudo depmod -a
# Regenerate your initramfs: dracut -f | update-initramfs -u | mkinitcpio -P
sudo reboot
```

Then Mesa, applied to a pristine `mesa-26.2.0-rc3` tree per `patches/mesa/series`:

```bash
tar xf mesa-26.2.0-rc3.tar.xz && cd mesa-26.2.0-rc3
for p in $(grep -v '^#' /path/to/repo/patches/mesa/series); do
    patch -p1 < /path/to/repo/patches/mesa/"$p"
done
meson setup build -Dvulkan-drivers=amd -Dgallium-drivers= -Dglx=disabled -Dllvm=disabled \
    -Dbuildtype=release -Dprefix=/opt/bc250-gfx1013
ninja -C build && sudo ninja -C build install
```

Point applications at it with
`VK_DRIVER_FILES=/opt/bc250-gfx1013/share/vulkan/icd.d/radeon_icd.x86_64.json`
(system-wide via `/etc/environment`, or per app). The Vulkan loader does not deduplicate ICDs;
without the pin, apps may silently take the stock driver.

### Option 3: Arch / CachyOS

Same as Option 2, with two substitutions (untested; reports welcome):

- Kernel source: grab the tarball matching your base version from kernel.org
  (`linux-$(uname -r | cut -d- -f1)`), or put the patches into your kernel PKGBUILD's patch
  set if you build your own (CachyOS custom kernels). Arch-family kernels rarely patch amdgpu,
  so the patches should apply to the mainline tarball.
- Initramfs: `mkinitcpio -P` instead of dracut.

Everything else is identical: build against `/lib/modules/$(uname -r)/build`, install to
`updates/`, depmod, regenerate, reboot, then the Mesa half.

### Bazzite

Not yet. The module has to be baked into a custom image, and running the Mesa half alone on a
stock kernel is the hang combination. A proper image-based path is coming in the next few days;
until then, wait.

## Verification

```bash
./install.sh status
vulkaninfo --summary                       # driverInfo: Mesa 26.2.0-rc3 (the /opt build)
vulkaninfo | grep -c 'QUEUE_COMPUTE_BIT'   # dedicated compute family present
```

Corruption check: any sustained compute workload alongside rendering (a game with async
compute) should show no missing geometry, banding, or black frames.

## 40 CU

The BC-250 ships with 24 of its 40 CUs enabled. The unlock is
[duggasco/bc250-40cu-unlock](https://github.com/duggasco/bc250-40cu-unlock) (his patch is
vendored here as `patches/kernel/40cu-bc250-unlock.patch`); the benchmark numbers above were
taken with it. Chips vary and it runs hotter, so it's a flag:

```bash
./install.sh build --40cu
sudo ./install.sh install --40cu
```

Don't also run his installer; it targets the stock module, which this setup never boots.

## Reverting

```bash
sudo ./install.sh boot-stock && sudo reboot
sudo ./install.sh uninstall
```

Manual installs: remove `/lib/modules/$(uname -r)/updates/amdgpu.ko`, `depmod -a`, regenerate
the initramfs, delete `/opt/bc250-gfx1013`, and drop the `VK_DRIVER_FILES` pin.

## Fine print

Built and tested on Fedora 43, kernel `7.1.5-101.fc43.x86_64`. The kernel module
is ABI-pinned; rebuild + reinstall after a kernel update. 

The patches themselves aren't Fedora-specific; `install.sh` is (dnf, BLS boot entries, dracut,
grub2-editenv). On another distro, apply `patches/` yourself and handle your own initramfs and
bootloader bits. Reports welcome. 

Don't install the Mesa half without the kernel half, it will hang.

Suspend doesn't work on this hardware, patched or not. I suggest disabling it.

## Bugs / results

Open an issue. Include your distro + kernel, 24 or 40 CU, what you ran, and
`./install.sh status`.

## Thanks

Thanks to `duggasco`, `vogar345`, `lonewolf0622`, `akandr`, `anrp`, `ahorek`.

Kernel patches GPL-2.0 (amdgpu-derived), everything else MIT.
