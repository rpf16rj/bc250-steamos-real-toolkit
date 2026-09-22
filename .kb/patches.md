<!-- tags: patches, audio-clock, spread-spectrum, telemetry, ttm, sclk, kfd, gfx1013, vrr, allm, frl, ycbcr444, vcn, build-flags -->
# Kernel Patches

All patches live in `external/bc250-steamos/bc250-audio-fix/`.

## Patch Index

### bc250-dp-audio-clock-7.2.patch
- **Purpose**: Fix DP audio/video clock — without this, DP audio plays at ~82% speed (pitched down)
- **Kernel**: 7.2-specific (there are also 6.16 and 6.18 versions)
- **Always needed**: Yes (core audio fix)

### bc250-cyan-skillfish-telemetry-cache-7.2.patch
- **Purpose**: Telemetry and cache improvements for Cyan Skillfish APU on kernel 7.2
- **Kernel**: 7.2-specific
- **Always needed**: Yes (on 7.2)

### bc250-dp-audio-dm-ignore-ss.patch
- **Purpose**: Disable DP spread spectrum at the display manager layer for cleaner audio
- **Always needed**: Yes

### bc250-dp-hdmi-ycbcr444-deep-color.patch
- **Purpose**: CH7218 PCON quirk + YCbCr 4:4:4 + deep color + force_min_bpc + YCbCr fallback
- **Key changes**:
  - `link_dp_capability.c`: CH7218 quirk — restores DISPLAY_DONGLE_DP_HDMI_CONVERTER caps when DPCD reports wrong port type
  - `amdgpu_dm.c`: force_ycbcr444 module param, force_min_bpc module param, PCON bpc from dc_modes, YCbCr 4:4:4 fallback on validation failure
  - `dcn201_resource.c`: `dp_hdmi21_pcon_support=true`
  - `link_validation.c`: debug logging for dongle validation
- **Always needed**: Yes (for PCON to work correctly)

### bc250-vrr-pcon-freesync.patch
- **Purpose**: Parse AMD VSDB from CTA extension directly, FreeSync fallback, LFC-aware range extending
- **Kernel 7.x**: NOT needed (VRR already functional upstream), but harmless
- **Kernel 6.x**: Needed for VRR over PCON
- **Applied when**: User selects VRR in combined fix (kernel <7) or audio fix

### bc250-allm-via-dp.patch
- **Purpose**: ALLM via DP — sends AVI infoframe with content_type=GAME to PCON
- **Key changes**:
  - `amdgpu_dm.c`: set content_type=GAME when allm detected and amdgpu_allm_mode==2
  - `amdgpu_dm_helpers.c`: read allm from EDID even for non-HDMI signals
  - `dc_resource.c`: build AVI infoframe for DP signals too
  - `dcn10_stream_encoder.c`: remap AVI infoframe to DP SDP format (GSP6)
  - `link_dp_capability.c`: set PCON Source Control Mode via DPCD
  - `dcn201_resource.c`: dp_hdmi21_pcon_support=true (same as ycbcr444 patch)
- **Kernel 7.x**: NOT needed (ALLM already functional upstream), but harmless
- **Kernel 6.x**: Needed for ALLM over PCON

### bc250-ttm-null-page-guard.patch
- **Purpose**: TTM NULL-page guard — prevents crashes from NULL page mappings
- **Always needed**: Yes

### bc250-sclk-range.patch
- **Purpose**: Widen SCLK range to 350-2230 MHz (stock is more restrictive)
- **Always needed**: Yes

### bc250-kfd-flush-tlb-by-runlist.patch
- **Purpose**: KFD flush TLB by runlist — fixes compute memory coherency
- **Always needed**: Yes

### bc250-tunable-gfxclk-activity-cache.patch
- **Purpose**: Tunable gfxclk/activity cache — adds cs_gfxclk_cache_ms and cs_activity_cache_ms module params
- **Always needed**: Yes (with audio fix)

### bc250-pcon-frl-hotplug-preserve.patch
- **Purpose**: Preserve FRL configuration across hotplug events
- **Always needed**: Yes (prevents FRL loss when TV power cycles)

### bc250-cyan-skillfish-gfxclk.patch
- **Purpose**: Query GFX clock directly from SMU instead of indirect calculation
- **Always needed**: Yes (with audio fix)

### bc250-psp-ccp.patch
- **Purpose**: Bind the BC-250 secure processor (PCI 1022:143e) — carry of
  Mattia Tadini's 3-patch linux-crypto/LKML series (psp_firmware_is_visible
  NULL deref fix + vdata gating + sp_pci_table entry), ported from MastaG
  `0014-bc250-psp-ccp.patch`
- **Effect**: PSP mailbox/platform access works, fw version readable in
  sysfs. No SEV/TEE/CCP crypto on this firmware (TEE ring never comes up)
- **Always applied** (upstream-bound fix, no flag). Relevant to the VCN
  investigation — PSP was the GPCOM path blocker (.kb/vcn.md)

### bc250-cyan-skillfish-gpu-telemetry.patch
- **Purpose**: GPU utilization reporting — needed for correct GPU clock/load readings
- **Always needed**: Yes (with audio fix, especially with CPU Core Unlock)

### GFX1013 patches (0001-gfx1013-compute-*)
- **Purpose**: Enable async compute on GFX10 (GFX1013 spoof for mesh/task shaders)
- **Optional**: User selects in combined fix
- **Mesa**: Requires patched Mesa/RADV build (build-mesa.sh)

### bc250-vcn-ungate.patch (EXPERIMENTAL — hidden from menu)
- **Purpose**: Ungate VCN 2.0.3 on Cyan Skillfish 2 for a direct MMIO
  bring-up test (navi10_vcn ucode, AMDGPU_FW_LOAD_DIRECT, no PSP)
- **Runtime gate**: `amdgpu.bc250_vcn_ungate=1` cmdline param, default 0 —
  patched kernel boots normally, ungate is opt-in per boot
- **NOT in combined-fix checklist**: unconditional version wedged boot;
  enable only via `patch-driver.sh --vcn` for testing
- **Ordering**: independent of the PCON patch — all hunks anchored on
  pristine lines (never regenerate with `git diff` while PCON hunks are
  uncommitted in the tree)
- **Full notes**: `.kb/vcn.md`

## Patch Application Order
The `patch-driver.sh` script handles patch selection via flags.
ALL patches are now individually excludable with `--no-*` flags:

### Audio sub-patches (require `--audio` base flag)
- `--audio` — enables audio patch group
- `--no-audio-clock` — skip DP audio clock patch
- `--no-telemetry` — skip Cyan Skillfish telemetry+cache patch
- `--no-ss` — skip DP spread spectrum disable patch

### Always-applied patches (now individually excludable)
- `--no-frl-hp` — skip PCON FRL hotplug preserve patch
- `--no-ttm` — skip TTM NULL-page guard patch
- `--no-sclk` — skip SCLK range patch
- `--no-kfd` — skip KFD flush-TLB-by-runlist patch
- `--no-ycbcr444` — skip DP-HDMI YCbCr 4:4:4 deep color patch (kernel 7.x only)

### Separate components
- `--gfx1013` — GFX1013 compute patches + Mesa build
- `--vrr` — VRR PCON FreeSync (skipped on kernel ≥7)
- `--allm` — ALLM via DP (skipped on kernel ≥7)
- `--dsc` / `--dsc-pcon` — DCN201 DSC + PCON HDMI 2.1 pair. Since 2026-09-22
  this block also applies, in order after the PCON patch:
  - `bc250-ch7218-pcon-quirk.patch` (ported from MastaG
    `0012-ch7218-pcon-quirk.patch`, by @dejan_994): opt-in
    `amdgpu.bc250_ch7218_quirk=1` quirk for CH7218 adapters (UGREEN,
    branch OUI 2B:02:F0) that misreport their downstream port or lose
    DSC_SUPPORT after a mode change / TV standby resume. Default off;
    every entry point early-returns without the param.
  - `bc250-pcon-force-dsc.patch` (MastaG `0013-pcon-force-dsc.patch`):
    experimental opt-in `amdgpu.bc250_pcon_force_dsc=1` — treats a
    converter whose DSC capability block reads all zeros as a DSC 1.2a
    decoder with FEC (Cable Matters 102101 / VMM7100 case). Its
    retrieve_link_cap call site anchors on the CH7218 DSC-restore call,
    so it must apply after it.
  - `bc250-cs-relink-after-long-blank.patch` (MastaG
    `0011-cs-relink-after-long-blank.patch`): the CH7218-class converter
    drops its HDMI side after a >few-second blank (KDE<->gamescope
    handover) and DC's cached-caps resume leaves the sink dark. Re-runs
    trigger_hotplug when the stream returns after > cs_relink_ms.
    Tunables: `amdgpu.cs_relink_ms=3000` (0=off),
    `cs_relink_delay_ms=250`, `cs_relink_cooldown_ms=10000`,
    `cs_relink_at_boot=0`, `cs_relink_debug=1`.
- `--vcn` — EXPERIMENTAL VCN 2.0.3 ungate, **hidden from the combined-fix
  menu** (manual flag only). Runtime-gated: all three driver gates open
  only with `amdgpu.bc250_vcn_ungate=1` on the kernel cmdline (default 0,
  boots normally). Unconditional version wedged boot — see `.kb/vcn.md`
  for the full investigation (PSP GPCOM closed, patch pitfalls).

In `start.sh`, both `install_audio_fix` and `install_combined_fix` use
`pick_items` (whiptail --checklist) to show all patches in a single
navigable list with arrow keys + space to toggle. All items are
pre-selected by default.
