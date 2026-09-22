<!-- tags: display, dp, hdmi, pcon, frl, edid, vrr, freesync, allm, ch7218, samsung-q80a -->
# Display Pipeline: DP→HDMI PCON, FRL, EDID, VRR, ALLM

## Architecture
```
GPU (DCN201) → DisplayPort → CH7218 PCON → HDMI 2.1 → Samsung Q80A (HDMI port 3/4)
```

The BC-250 has no native HDMI output. Display goes through DisplayPort to a
CH7218 PCON (Protocol Converter) dongle, which converts DP to HDMI 2.1 with FRL.

## DSC + HDMI 2.1 PCON (current, v1.9.3)
Two patches on DCN201, gated by one kernel parameter `amdgpu.bc250_hdmi21`
(on by default; `=0` restores stock behaviour, path-for-path):
- `bc250-dcn201-pcon-hdmi21.patch` — sets `dc->caps.dp_hdmi21_pcon_support`.
  Without it, link validation checks the PCON against its TMDS pixel-clock limit
  (600 MHz), so 4K120 only fits at 4:2:0 and 4K60 HDR only via 4:2:2.
- `bc250-dcn201-dsc-enable.patch` — selects a second `resource_caps` with
  `num_dsc = 2`, creates the DSC objects via `dcn20_dsc_create()`, wires
  `dcn20_add_dsc_to_stream_resource`, and sets `dcn201_ip.num_dsc` before
  `dml_init_instance()` (DML reads NumberOfDSC from there).
- `bc250-dsc-debugfs-bpp-sticky.patch` — stores the `dsc_bits_per_pixel`
  debugfs write unconditionally instead of dropping it when no stream is
  active on the connector, so the override knob is reliable for DSC
  experiments (display off / mid-transition).

Both are the upstream TeleBooth versions (carried by MastaG), adapted to Valve's
kernel 7.2.4-valve1-1-neptune-72. Applied as one unit by the Combined Fix; the
DSC patch depends on the `dc->config.bc250_hdmi21` field the PCON patch adds.
They supersede the removed YCbCr 4:4:4 / FRL workaround patches. See
`docs/dsc-hdmi21-pcon.md`.

**Verified on the BC-250 (2026-09-15):** after Combined Fix + reboot,
`cat /sys/module/amdgpu/parameters/bc250_hdmi21` = 1 (no GRUB entry needed —
the default is compiled in) and `dmesg` shows `DP-HDMI FRL PCON supported`.
`dsc_clock` does not appear in dmesg at desktop/login (4K60/4:2:0 fits
uncompressed); it only engages for a mode that needs it (4K120 4:4:4) and is
read from debugfs, not dmesg.

Recovery: if the display stays dark after installing, boot with
`amdgpu.bc250_hdmi21=0` (GRUB `GRUB_CMDLINE_LINUX_DEFAULT` + `update-grub`).
Some DP→HDMI adapters show black from boot until a hotplug even with the feature
off — that's a BIOS/GOP→amdgpu handover issue, not these patches.

### gamescope 4K120 PCON failure — root cause: output bpc vs FRL budget (solved 2026-09-20)

Captures show DSC engaging correctly on the failing path: real CTA
3840x2160@120 timing (1188 MHz), `dsc_clock_en=1`, `dsc_bits_per_pixel=192`
(12 bpp — the CTA preset for VIC 117/118), slices 960x108, link-status Good.
VRR and HDR on/off do not change the outcome. The DP link (GPU→PCON) trains
identically in both paths (4 lanes HBR2 during the DSC stream).

**The discriminator is output color depth (`bpc`), not DSC bpp:** every
failing capture shows connector `bpc`/`max_bpc` = 16; every working capture
shows 10. Booting straight into gamescope leaves the driver default
`max_requested_bpc = 16`; KDE's kwin persists `max_bpc = 10` on the
connector, and gamescope inherits the property across the session switch.
An earlier "14 bpp fixed it" result was masked by the session switch.

Mechanism: the CH7218 decodes the DSC-compressed DP stream and re-encodes
uncompressed FRL to the TV (EDID: Max FRL 6/8/10 Gbps × 4 lanes = FRL5,
40 Gbps). Uncompressed 4K120 RGB needs ~35.6 Gbps at 10 bpc (fits),
~42.8 at 12, ~57 at 16 (both exceed FRL5 → no signal/artifacts). DC
validation only checks the DP link budget — compressed DSC fits HBR2
regardless of bpc — so 16 bpc "validates" and kills the TV side.

**Fix (verified 2026-09-20):** `bc250-pcon-frl-bpc-cap.patch` clamps
`requested_bpc` in `create_validate_stream_for_sink()` for
`DISPLAY_DONGLE_DP_HDMI_CONVERTER` links to the highest even bpc fitting
`display_info.hdmi.max_frl_rate_per_lane × max_lanes`, gated by
`dc->config.bc250_hdmi21`. 4K120 → 10 bpc; 4K60 keeps 16 bpc (fits);
non-PCON paths untouched. Verified on hardware: cold boot straight into
gamescope now produces clean 4K120 with no user intervention.

Debugfs knobs on the connector (`/sys/kernel/debug/dri/*/DP-1/`):
`dsc_clock_en` (1=force on/2=off/0=auto), `dsc_bits_per_pixel` (x16,
sticky via the sticky-bpp patch), `dsc_slice_*`, `dsc_disable_passthrough`
(PCON decodes DSC → uncompressed FRL to TV), `link_settings`.

## CH7218 firmware quirk (opt-in, 2026-09-22)
Some CH7218 firmware misreports the downstream port (clears
DP_DOWNSTREAMPORT_PRESENT or reports DP) → driver classifies the adapter
DISPLAY_DONGLE_NONE → no FRL negotiation → 4K90/4K120 black while 4K60
works. Also observed: a *correctly-reporting* unit loses DSC_SUPPORT after
a TV standby cycle (falls back to 4:2:2 10-bit). Ported from
MastaG/linux-cachyos-bc250 `0012-ch7218-pcon-quirk.patch` (author
@dejan_994), applied inside `--dsc` after the PCON patch it depends on.
**Enable with `amdgpu.bc250_ch7218_quirk=1`** on the cmdline — off by
default because nothing in DPCD tells a broken unit from a healthy one.
Check detection: `dmesg | grep "CH7218 quirk"` and
`cat /sys/kernel/debug/dri/*/DP-1/dsc_clock_en`.

## FRL (Fixed Rate Link)
- FRL is HDMI 2.1's high-bandwidth transport, replacing TMDS for high-res modes
- CH7218 supports FRL up to 48 Gbps (4 lanes × 12 Gbps)
- FRL enables: 1440p@120 10-bit, 4K@60 10-bit, and other high-bandwidth modes
- TMDS max: 300 MHz (600 MHz with HDMI 2.0 scrambling, but still limited)
- FRL is enabled in the kernel via `dcfeaturemask=0x402` (modprobe.d)
- The kernel auto-negotiates FRL vs TMDS per mode based on bandwidth requirements

## EDID Override
The CH7218 PCON does NOT pass the HF-VSDB in the EDID it presents to the GPU.
This causes the kernel to think the TV is HDMI 2.0 only.

### EDID Override Binary
- **File**: `edid/samsung-q80a-hdmi21.bin` (256 bytes, 2 blocks)
- **Block 0**: Base EDID (unchanged from TV's original)
- **Block 1**: CTA-861 extension with HF-VSDB added
- **HF-VSDB contents**:
  - OUI: D8:5D:C4 (HDMI Forum)
  - Version: 1
  - Max TMDS: 600 MHz
  - SCDC Present: yes
  - Scrambling for ≤340 MHz: yes
  - Max FRL: 48 Gbps (4L × 12G)
  - Deep Color 4:2:0: 10-bit, 12-bit
  - ALLM: yes
  - FVA (Fast VActive): yes
  - VRR min: 48 Hz, VRR max: 120 Hz

### Installation
1. Copy binary to `/lib/firmware/edid/samsung-q80a-hdmi21.bin`
2. Add `drm.edid_firmware=DP-1:edid/samsung-q80a-hdmi21.bin` to GRUB
3. Rebuild initramfs (`mkinitcpio -P`) so firmware is included
4. Reboot

### Verification
```bash
edid-decode /sys/class/drm/card0-DP-1/edid | grep 'HDMI Forum'
cat /sys/kernel/debug/dri/0/DP-1/vrr_range
```

## VRR (Variable Refresh Rate)
- Samsung Q80A supports VRR 48-120 Hz (FreeSync Premium)
- Kernel 7.x has native VRR support for HDMI 2.1 via VTEM infoframes
- VRR requires `amdgpu.freesync_pcon_allow_all=1` in GRUB for PCON bypass
- Without EDID override, VRR is not detected (vrr_range = 0-0)
- The `bc250-vrr-pcon-freesync.patch` adds AMD VSDB parsing for FreeSync fallback
  (not needed on 7.x but harmless)

## ALLM (Auto Low Latency Mode)
- ALLM signals to the TV that the current content is a game → TV switches to Game Mode
- Kernel 7.x has native ALLM support
- The `bc250-allm-via-dp.patch` sends AVI infoframe with content_type=GAME
  via DP SDP to the PCON, which generates HF-VSIF autonomously in Source Control Mode
- PCON must be in Source Control Mode (set via DPCD write in the patch)
- Without EDID override, `edid_caps->allm` is false → ALLM not triggered

## YCbCr 4:4:4 and Deep Color
- The `bc250-dp-hdmi-ycbcr444-deep-color.patch` adds:
  - CH7218 PCON quirk (restores dongle caps when DPCD reports wrong type)
  - Force YCbCr 4:4:4 pixel encoding when FRL is negotiated
  - Deep color (10/12-bit) from EDID dc_modes for PCON outputs
  - `force_min_bpc` module param to floor bpc at a minimum value
  - YCbCr 4:4:4 fallback when RGB validation fails
- These params are set via modprobe.d, NOT GRUB (steamenv_boot filters them)

## Sync Instability Issue
Symptoms: display loses sync (black screen/flicker) when switching modes,
especially for non-1440p120 modes in gamescope.

Root cause: Without HF-VSDB in EDID, kernel doesn't know the TV supports HDMI 2.1.
For modes >300 MHz pixel clock, kernel tries TMDS first (which fails at >300 MHz
without scrambling), then may or may not fall back to FRL correctly.

Fix: EDID override makes the kernel aware of HDMI 2.1 capabilities from the start,
so FRL is negotiated properly for all high-bandwidth modes.


