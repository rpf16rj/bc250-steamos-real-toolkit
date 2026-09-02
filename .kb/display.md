<!-- tags: display, dp, hdmi, pcon, frl, edid, vrr, freesync, allm, ch7218, samsung-q80a -->
# Display Pipeline: DP→HDMI PCON, FRL, EDID, VRR, ALLM

## Architecture
```
GPU (DCN201) → DisplayPort → CH7218 PCON → HDMI 2.1 → Samsung Q80A (HDMI port 3/4)
```

The BC-250 has no native HDMI output. Display goes through DisplayPort to a
CH7218 PCON (Protocol Converter) dongle, which converts DP to HDMI 2.1 with FRL.

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

## FRL vs VRR Incompatibility (Kernel Limitation)
FRL and VRR are mutually exclusive in the current upstream kernel:
- FRL links don't support VRR yet (upstream patch: "FRL links don't yet support VRR")
- `dcfeaturemask=0x402` enables FRL (bit 0x400) → VRR breaks
- `dcfeaturemask=0x002` disables FRL → VRR works, 4K60 via TMDS+scrambling

### EDID Override: FRL Removed (2026-09-01)
The EDID binary `edid/samsung-q80a-hdmi21.bin` was corrected:
- **Changed**: Max FRL rate from 6 (48 Gbps) to 0 (no FRL) — byte 0xDA, upper nibble
- **Kept**: TMDS 600 MHz, SCDC, scrambling ≤340 MHz, VRR 48-120, ALLM, FVA, deep color 4:2:0 10/12-bit
- **Result**: Kernel uses TMDS with scrambling for 4K60 (fits in 18 Gbps), VRR/HDR/ALLM all work
- **Trade-off**: 4K120 requires FRL and is not available (only 4K60 via TMDS)

### EDID Override Is Recommended
- `drm.edid_firmware` is an official kernel feature (since 2012, commit da0df92)
- Used by Steam Deck users with Samsung TVs + DP-to-HDMI docks (Level1Techs forums)
- Tools: RobertoNegro/edid-generator, ssupt/drmcru
- Arch Linux wiki has official guide for EDID override
