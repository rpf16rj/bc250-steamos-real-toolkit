<!-- tags: patches, audio-clock, spread-spectrum, telemetry, ttm, sclk, kfd, gfx1013, vrr, allm, frl, ycbcr444, build-flags -->
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

### bc250-cyan-skillfish-gpu-telemetry.patch
- **Purpose**: GPU utilization reporting — needed for correct GPU clock/load readings
- **Always needed**: Yes (with audio fix, especially with CPU Core Unlock)

### GFX1013 patches (0001-gfx1013-compute-*)
- **Purpose**: Enable async compute on GFX10 (GFX1013 spoof for mesh/task shaders)
- **Optional**: User selects in combined fix
- **Mesa**: Requires patched Mesa/RADV build (build-mesa.sh)

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

In `start.sh`, both `install_audio_fix` and `install_combined_fix` use
`pick_items` (whiptail --checklist) to show all patches in a single
navigable list with arrow keys + space to toggle. All items are
pre-selected by default.
