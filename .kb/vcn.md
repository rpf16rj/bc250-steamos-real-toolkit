<!-- tags: vcn, uvd, psp, gpcom, harvest, experimental, ungate, bc250 -->
# VCN 2.0.3 on BC-250 — Investigation Status

**Status: experimental, NOT working. Hidden from the toolkit menu.**

The BC-250 (Cyan Skillfish 2, PCI 0x13FE) ships with the VCN 2.0.3 block
harvested/gated. This file records what was tried and what remains.

Full raw research log: `~/vcn-research/REPORT.md` (outside this repo).

## Path A — PSP GPCOM probing: CLOSED (conclusive)

The GPCOM ring transport works, but every command needed to create the
missing VCN slot is rejected by the CSF TEE:

| Command | Result | Meaning |
|---|---|---|
| `LOAD_IP_FW` type 13 (VCN) | `0xffff0008` ITEM_NOT_FOUND | VCN slot absent — feature-enable never ran |
| VCN RAM types 49/50 | `0xffff0006` BAD_PARAMETERS | handler exists, dies on slot/config |
| `SETUP_TMR` (0x05) | `0xffff0007` BAD_STATE | TEE already initialized, no re-setup |
| `LOAD_TOC` / `PROG_REG` / `AUTOLOAD_RLC` | NOT_IMPLEMENTED | absent |
| `LOAD_TA` / `LOAD_ASD` (navi10 AND CSF-signed BIOS blobs) | `0x00000034` | categorical rejection — no session, no INVOKE_CMD |
| `BOOT_CFG` (0x22) | NOT_SUPPORTED | recognized, blocked |
| `SAVE_RESTORE` (0x08) | BAD_PARAMETERS | exists but needs a valid payload |

Static RE of the TEE module: `fn_121ee` (the feature-enable walk that
would populate the VCN table at `0xe97b40`) only runs at boot and no
GPCOM command re-triggers it. Conclusion: without an exploit or a BIOS
modification, the PSP path cannot ungate VCN.

## Path B — Kernel-side ungate: built, boot-wedged once, now runtime-gated

`external/bc250-steamos/bc250-audio-fix/bc250-vcn-ungate.patch` removes
the three driver gates, **only when the module parameter is set**:

- `amdgpu_discovery.c`: `case IP_VERSION(2,0,3)` registers
  `vcn_v2_0_ip_block`; harvest quirk clears `vcn.harvest_config` and sets
  `inst_mask` for CSF2; `harvest_ip` skips setting `VCN/JPEG_MASK`
- `amdgpu_ucode.c`: `IP_VERSION(2,0,3)` → `"navi10_vcn"`
- `amdgpu_drv.c` + `amdgpu.h`: `amdgpu_bc250_vcn_ungate` module param,
  **default 0** — the patched kernel boots normally; ungate is opt-in
  per boot via `amdgpu.bc250_vcn_ungate=N` on the kernel cmdline.
- `amdgpu_psp.c`: `psp_load_non_psp_fw()` **skips the VCN ucode at every
  level** — the CSF2 TEE has no VCN slot (LOAD_IP_FW type 13 →
  ITEM_NOT_FOUND via GPCOM, and the KM ring may wedge). The VCPU boots
  the staged image via the driver-programmed LMI path in
  `vcn_v2_0_start()` instead.
- `dev_warn` breadcrumbs (`BC-250: ...`) mark every stage: discovery
  registration, early_init, sw_init, each PSP ucode submission,
  hw_init mode, first MMIO. On a fabric wedge the last breadcrumb in
  `journalctl -k -b -1` is the killer.

### Test procedure (GRUB menu entries, 4-level bisect)

| Level | Effect |
|---|---|
| 0 | off (default) — stock |
| 1 | **reg-only** — IP block registered by discovery, then `early_init`/`sw_init` return immediately: no ucode request, no PSP submission, no rings, zero MMIO |
| 2 | **probe** — + `early_init` (navi10_vcn request/parse) and `sw_init` (irq, BOs, fw staging), still **zero VCN MMIO** and VCN never submitted to the PSP |
| 3 | **full** — complete bring-up incl. MMIO via `vcn_v2_0_start` |

```bash
cd external/bc250-steamos-real-toolkit/external/bc250-steamos/bc250-audio-fix
BC250_NO_PREBUILT=1 ./patch-driver.sh --audio --gfx1013 --dsc --no-ss --vcn
sudo update-grub   # ⚠️ required — patch-driver.sh does NOT regenerate GRUB
# GRUB menu then offers "VCN reg-only" (=1), "VCN probe" (=2),
# "VCN ungate FULL" (=3)
```

Test in order 1 → 2 → 3. The first level that wedges localizes the killer:

- =1 wedges → the harvest/discovery change alone is toxic (other blocks'
  init paths consulting harvest state) — NOT VCN MMIO.
- =2 wedges, =1 boots → death is in ucode request/irq/BO/sw_init — the
  PSP is already ruled out (VCN is never submitted to it).
- =3 wedges, =2 boots → MMIO reachability is the wall → fuse/power-rail
  clamp → Path B dead.

On a wedge: power cycle, boot the default entry, and read
`journalctl -k -b -1 | grep -iE 'bc-250|vcn|uvd|amdgpu'` — the last
`BC-250:` breadcrumb before the cutoff is the failing stage (the kernel
dies mid-probe, ~3 s in, before amdgpu's normal output).

If =3 boots: `detected ip block <vcn_v2_0_0>` + ring test pass = VCN
alive → verify `vainfo` lists real HEVC decode.

### Boot attempts so far (2026-09-23)

- **Old single-level build, `=1` (which meant full bring-up)**: kernel
  lived ~3 s, journal captured zero amdgpu lines → fabric-level stall
  during amdgpu probe (~3 s in, matching the udev-triggered modprobe;
  amdgpu is NOT in the initramfs — `kms` hook but empty `MODULES=`).
- **Two-level build, `=1` (probe, all MMIO guards active) and `=2`
  (full)**: wedged identically (~2–3 s, zero amdgpu output). Root cause
  found: `psp_load_non_psp_fw` was still submitting the VCN ucode to the
  PSP (`LOAD_IP_FW` type 13 — the slot the TEE provably lacks). Fixed by
  skipping VCN ucode in the PSP loop at every level.
- **Three-level build — bisection CONCLUDED**:
  - `=1` reg-only: **boots clean** — discovery registration is harmless
  - `=2` probe: **boots clean** — `Found VCN firmware Version ENC: 1.24
    DEC: 8` (navi10_vcn parses fine), sw_init/irq/BOs fine, PSP submits
    all other ucodes fine, VCN ucode cleanly skipped
  - `=3` full: **wedges** — journal loses the tail at ~3 s, so the exact
    register isn't captured yet. The delta vs level 2 is exclusively
    the MMIO bring-up inside `vcn_v2_0_hw_init` → ring test →
    `set_pg_state(UNGATE)` → `vcn_v2_0_start`.
- Current patch adds per-stage `BC250_VCN_STEP` breadcrumbs
  (`dev_warn` + 200 ms settle so journald flushes before the next MMIO)
  inside `hw_init`, `disable_static_power_gating`, `disable_clock_gating`
  and every phase of `vcn_v2_0_start` — next `=3` boot names the exact
  killing register. Also forces `mc_resume` to the direct BO path
  (`tmr_mc_addr` is never populated without the PSP).
- `CONFIG_PSTORE_CONSOLE` is not built and `CONFIG_NETCONSOLE=m` loads
  too late to catch a 3-second wedge — breadcrumbs + level bisection is
  the capture strategy.

**Interpretation so far**: registration, firmware parse and software
init all succeed — the wedge lives strictly inside the MMIO bring-up.
Two live hypotheses for `=3`: (a) the fuse/power-rail is cut and the
first `mmUVD_PGFSM_CONFIG` write stalls the fabric (Path B dead), or
(b) the block is present but needs a power-up sequence the CSF SMU
doesn't provide (`amdgpu_dpm_enable_vcn` → `set_powergating_by_smu`
targets a VCN feature the SMU doesn't implement — could itself hang the
mailbox, or leave the rail off so the PGFSM write wedges). The step
markers distinguish: death at "dpm_enable_vcn" → SMU mailbox; death at
"PGFSM: config write" → register file dead.

## Verdict — Path B is dead at the register level (2026-09-23)

The EFI-var breadcrumb (`BC250VcnStep`) captured the kill shot on the
instrumented FULL boot: last completed stage was
`"PGFSM: config done, poll status"` — i.e. the `mmUVD_PGFSM_CONFIG` write
completed (posted writes need no live responder) and the very first
**read** of `mmUVD_PGFSM_STATUS` hung the fabric, stalling the CPU mid-
transaction (no NMI, no panic, no pstore, display dies instantly).

Conclusion: the VCN 2.0.3 block is present but electrically dead —
power rail off and/or register interface fused, with no reachable
power-up path (CSF SMU has no VCN feature, `ppfeaturemask` bit19 clear,
`amdgpu_dpm_enable_vcn` is a no-op). Hardware video decode on the BC-250
VCN is not achievable. The viable client-decode path remains software:
measured ~232 fps on 4K60 Main10 via Zen2 CPU FFmpeg.

The staged patch (`bc250_vcn_ungate` param, levels 1/2/3) stays in the
tree as a diagnostic tool — inert at the default `=0`.

## Incidents / lessons

- **Unconditional ungate did not boot** (first patch version added the IP
  block always → kernel never reached userspace; recovery needed). That
  is why the param exists and why the option is hidden from the menu.
- **Patch context collision**: `bc250-dcn201-pcon-hdmi21.patch` (DSC) is
  applied as uncommitted working-tree changes, so `git diff` of the tree
  mixes `amdgpu_bc250_hdmi21` hunks into any new patch touching
  `amdgpu_drv.c`/`amdgpu.h`. All VCN hunks are anchored on pristine lines
  ≥3 context lines away from the PCON insertion points (`sg_display`),
  making the patch order-independent. When regenerating, temporarily
  remove the hdmi21 lines or the diff will swallow them.
- **Never hand-revert hunks**: reverting only some files leaves the tree
  partially patched; the build then fails or miscompiles. `build.sh` now
  `die`s if the real `patch -R` fails and detects a partial VCN
  application via a `bc250_vcn_ungate` marker grep.
- **Stale `.orig` bases poison regenerated patches**: `patch` leaves
  `*.orig` files capturing the pre-patch state *of that run* — which may
  predate other patches in the stack. Diffing a tree file against a stale
  `.orig` silently swallows other patches' hunks (the VCN patch briefly
  carried a duplicate `bc250_pcon_force_dsc` param block → build failed
  with redefinition errors). Correct base for `amdgpu.h`/`amdgpu_drv.c`
  = parked-git pristine + the rest of the stack applied in build order
  (`git apply -p1`/`patch` per-file into a scratch dir).
- **Display dies with the fabric; nothing in-band survives a FULL wedge**
  (2026-09-23): with `fbcon=` stripped, verbose console rendered until the
  wedge, then the screen went black instantly — the DCN/display pipe is on
  the same dying fabric. `/sys/fs/pstore` stayed empty: the CPU likely
  stalls mid-MMIO-transaction so NMI/hardlockup/panic never run. Fix:
  `BC250_VCN_STEP` now also calls `bc250_vcn_persist_step()`, which writes
  the stage name to EFI var `BC250VcnStep` (guid
  b250cafe-f00d-4b1c-8a3d-001122334455) via `efivar_set_variable` —
  NVRAM writes that already completed survive a total CPU stall. After a
  wedge, boot normally and read
  `strings /sys/firmware/efi/efivars/BC250VcnStep-*`; the killer is the
  stage after the persisted one. Requires `MODULE_IMPORT_NS("EFIVAR")`.
- **journald loses the tail on a fabric wedge** (2026-09-23, FULL boot):
  the kernel dies mid-probe and journald's kmsg backlog never reaches
  `/var/log/journal` — boot -1 showed zero `BC-250:` lines despite the
  instrumented module being installed. Fix: the FULL GRUB entry now boots
  verbose (`quiet`/`splash`/`loglevel=N` stripped via `EARGS`, plus
  `loglevel=7 plymouth.enable=0`) so each `dev_warn` breadcrumb renders on
  screen synchronously — the `msleep(200)` per step guarantees the line is
  painted before the next MMIO. On wedge the framebuffer freezes showing
  the killing step; photograph it.

## Deep-dive 2026-09 — decode viability for client use

### SMU/power path analysis (new, source-verified)

- `ppfeaturemask = 0xfff7bfff` → **bit 19 (`FEATURE_VCN_PG_BIT`,
  `smu11_driver_if_navi10.h:92`) is CLEAR**: the Cyan Skillfish SMU does
  not manage VCN power-gating at all.
- `cyan_skillfish_ppt.c` only allows `FCLK_DPM/SOC_DPM/GFX_DPM` — no VCN
  feature bits exist in its table.
- Consequence for `vcn_v2_0_start()`: `amdgpu_dpm_enable_vcn()` is a
  no-op (feature not enabled), and `AMD_PG_SUPPORT_VCN_DPG` is unset →
  the init goes **straight to direct MMIO**
  (`vcn_v2_0_disable_static_power_gating` → `mmUVD_PGFSM_CONFIG` write +
  `SOC15_WAIT_ON_RREG` on `mmUVD_PGFSM_STATUS`, then
  `mmUVD_VCPU_CNTL`/`mmUVD_SOFT_RESET`).
- So the ungate test isolates exactly one question: **does the VCN
  register file respond to MMIO?** If the block is merely driver-skipped
  → registers answer, firmware boots, ring test passes. If the fuse cut
  the power rail → MMIO write stalls the fabric → boot wedge (the same
  failure the first unconditional patch hit). No intermediate outcome.

### Client-decode alternatives investigated — verdicts

- **bc250 VAAPI VLD (simpmix driver)**: ~26 fps HEVC 1080p on Zen2.
  Root cause: wavefront parallelisation requires WPP
  `entry_point_offsets` in the bitstream; NVENC/Sunshine and the bc250
  encoder itself do not emit them → every frame decodes fully serially
  (~47 ms single-core per frame; `BC250_HEVC_THREAD` 1→16 changes
  nothing). perf: `predict_inter_8` ≈25%, `predict_intra_8` ≈14%,
  `gpu_compute_download_nv12`+`copy_from_wc_avx2` ≈9.5% (VRAM readback).
  FFmpeg frame threads (16× `av:hevc:df*`) run but total ≈1.05 cores —
  inter-frame ref deps serialize. Architectural dead-end vs FFmpeg's
  asm decoder.
- **Software decode ceiling (this hardware, measured)**: HEVC 1080p60
  559 fps, H.264 1080p60 917 fps, HEVC 4K60 304 fps, HEVC 4K60 Main10
  232 fps → software already IS a viable quality client path, even for
  4K/HDR streams.
- **Vulkan Video (VK_KHR_video_queue)**: dead — patched RADV exposes
  video image-layout enums but NO video queue family (queues:
  graphics/compute/sparse only). RADV video is implemented on the VCN
  engine; no VCN → no Vulkan Video.
- **libavcodec-backed VLD in the driver**: hard — VA VLD hands parsed
  parameter buffers, not Annex-B; feeding libavcodec needs SPS/PPS
  re-serialisation or private decoder APIs. Days of work, and zero gain
  for Moonlight (it already uses libavcodec in software mode). Only
  helps VAAPI-only apps (mpv --hwdec=vaapi, some players).
- **GPU-hybrid decode** (CPU CABAC + compute recon): no existing code;
  weeks/months, uncertain latency benefit.

### Bottom line for client decode

1. Software mode in Moonlight is the correct path today — delivers
   4K60 Main10 with ~4x headroom.
2. The ONLY route to real hw decode/encode is the `bc250_vcn_ungate`
   boot test (Path B). Precedent is encouraging: the BC-250's
   "harvested" CPU cores and GPU CUs work when ungated — the VCN may be
   the same class of soft-harvest (discovery lists VCN 2.0.3; PS5 die
   has the silicon).
3. If Path B wedges → Path A is closed, BIOS patch (below) is the last
   option; the custom VLD is not worth optimising for client use.

## Remaining option if the ungate test fails

BIOS patch: the feature-enable site `0x9970f4` in the PSP/ABL image is
verified (`cbz r4` → nop forces the enable path). Requires SPI flash
(dump + verify + write), real brick risk without a CH341A backup. Not
pursued yet.
