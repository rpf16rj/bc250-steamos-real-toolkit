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

## Diagnostics — Display Capture Decky Plugin
`extras/bc250-display-capture/` — Decky plugin with **Start collection** /
**Stop and package** buttons. The backend launches the collector via
`systemd-run` (system scope) so it survives the KDE→gamescope session
teardown — the reason an in-terminal capture is impossible mid-test: KDE is
killed and a new session starts. Collects `journalctl -k -b -f`, per-second
DRM connector status/modes/gpu_busy/sclk, and periodic `drm_info`/`modetest`
snapshots into `/home/deck/bc250-display-captures/<timestamp>/`, then packages
a `.tar.gz` on stop. Install with `extras/bc250-display-capture/install.sh`
(copies to `~/homebrew/plugins/` and restarts the plugin loader). The
`dist/index.js` frontend bundle is hand-written — the Deck has no node, so
it follows the same `SP_REACT`/`DFL` global pattern as
`extras/bc250-fsr4-launch-options/` instead of a rollup build.

