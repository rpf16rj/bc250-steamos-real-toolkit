<!-- tags: hardware, apu, gpu, soc, cyan-skillfish, rdna2, zen2, pcon, ch7218, memory -->
# BC-250 Hardware

## APU
- **SoC**: AMD A4A505 (Cyan Skillfish), custom APU for BC-250
- **Architecture**: Zen 2 + RDNA 2 (GFX10), Van Gogh family
- **DCN**: DCN201 (Display Core Next 2.0.1)
- **Physical cores**: 8 cores / 16 threads (stock BIOS may expose only 6c/12t)
- **GPU**: 12 CUs (WGP6), up to 16 CUs unlockable via bc250-cu-live-manager
- **Max GPU clock**: 2230 MHz (SCLK range patch: 350-2230 MHz)
- **VRAM**: Unified memory (UMA), configurable split (stock 256MB, toolkit default 512MB)

## Display Pipeline
- **Output**: DisplayPort only (no native HDMI)
- **DP→HDMI PCON**: CH7218 chip on Ugreen adapter, supports HDMI 2.1 FRL
- **PCON FRL bandwidth**: 48 Gbps (4 lanes × 12 Gbps)
- **PCON max bpc**: 12
- **PCON capabilities**: FRL, SCDC, scrambling for ≤340 MHz, YCbCr 4:4:4/4:2:2/4:2:0 passthrough
- **DC capability**: `dp_hdmi21_pcon_support=true` set in dcn201_resource.c

## PCON CH7218 Quirk
The CH7218 PCON has a DPCD firmware bug where it reports `PORT_PRESENT=0` or
`DOWN_STREAM_DETAILED_DP` instead of HDMI converter type. The kernel patch
in `bc250-dp-hdmi-ycbcr444-deep-color.patch` detects the CH7218 by branch_dev_id
(0x2B02F0) and branch_dev_name ("CH7218") and restores the correct dongle caps
(FRL 48G, max bpc 12, YCbCr passthrough, extendedCapValid=true).

## HDMI 2.1 EDID Problem
The CH7218 PCON does NOT pass the HF-VSDB (HDMI Forum Vendor Specific Data Block)
in the EDID it presents to the GPU. Without HF-VSDB:
- Kernel thinks TV is HDMI 2.0 (max TMDS 300 MHz)
- VRR not detected (vrr_range = 0-0)
- ALLM not detected (edid_caps->allm = false)
- Sync instability for modes >300 MHz (kernel tries TMDS first instead of FRL)

Solution: EDID override binary (`edid/samsung-q80a-hdmi21.bin`) adds HF-VSDB with:
- Max FRL: 48 Gbps (4 lanes × 12 Gbps)
- VRR: 48-120 Hz
- ALLM: yes
- Max TMDS: 600 MHz
- Deep Color 4:2:0: 10-bit and 12-bit

## TV: Samsung Q80A
- HDMI 2.1 ports: 3 and 4
- VRR: 48-120 Hz (FreeSync Premium)
- ALLM: yes
- FRL: 48 Gbps
- Native resolution: 3840x2160 (4K)
- Used connector: DP-1 (via PCON adapter to HDMI 2.1 port)
