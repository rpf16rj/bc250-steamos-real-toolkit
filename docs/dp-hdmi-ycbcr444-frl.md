# DP-HDMI YCbCr 4:4:4 Deep Color + HDMI 2.1 FRL

This document covers the DP-HDMI PCON deep color and FRL support added to the
BC-250 SteamOS Real Toolkit. It explains what the patches do, how to enable
them, and the bandwidth limitations of the BC-250's DisplayPort 1.4 link.

## Overview

The BC-250 (Van Gogh / DCN201) has DisplayPort 1.4 output. To connect to an
HDMI TV, an active DP-to-HDMI protocol converter (PCON) dongle is required.
The Chrontel CH7218-based adapters (e.g. Ugreen DP-HDMI 2.1) support HDMI 2.1
FRL up to 48 Gbps on the HDMI side.

The toolkit patches enable:

1. **YCbCr 4:4:4 pixel encoding** on PCON outputs (stock driver only allows
   RGB over DP, even when the downstream sink is HDMI).
2. **Deep color (10/12-bit)** using HDMI CTA EDID deep-color flags instead of
   the generic `display_info.bpc`, which doesn't reflect deep color for DP
   connectors.
3. **HDMI 2.1 FRL activation** via `dcfeaturemask=0x402` (DC_FRL_MASK) and a
   CH7218 PCON quirk that restores FRL capability when the dongle reports a
   malformed downstream port topology.
4. **`dp_hdmi21_pcon_support`** on DCN201 — the stock kernel omits this
   capability flag for Van Gogh, preventing FRL capability parsing.

## How to Enable

After installing the Combined Fix via the toolkit, answer **Yes** to the
YCbCr 4:4:4 deep color prompt. This creates:

```
/etc/modprobe.d/amdgpu-ycbcr444.conf
```

with contents:

```
options amdgpu force_ycbcr444=1 force_min_bpc=10 dcfeaturemask=0x402
```

The initramfs is rebuilt automatically. Reboot to apply.

### Module Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `force_ycbcr444` | 0 (off) | Force YCbCr 4:4:4 pixel encoding on DP-HDMI PCON outputs |
| `force_min_bpc` | 0 (auto) | Minimum bits per color (0=auto, 8/10/12=floor). Prevents silent 8-bit fallback. |
| `dcfeaturemask` | 0x2 | DC feature mask. 0x402 adds DC_FRL_MASK (bit 10) for HDMI 2.1 FRL. |

### Requirements

- **DP-HDMI PCON dongle** with Chrontel CH7218 chipset (e.g. Ugreen DP-HDMI 2.1)
- **TV with HDMI deep color support** (DC_Y444 or DC_RGB in EDID)
- **Kernel 7.2+** (FRL framework merged but disabled by default)
- **Combined Fix installed** (patches amdgpu.ko with the 4 source changes)

## Bandwidth Limitations

The BC-250's DisplayPort 1.4 link (HBR3, 4 lanes, 8b/10b encoding) provides
**25.14 Gbps** effective bandwidth between the GPU and the PCON. The HDMI 2.1
FRL link (48 Gbps) is between the PCON and the TV — the GPU must still send
all pixel data over DP 1.4 to the PCON first.

### DP 1.4 Link Budget (GPU → PCON): 25.14 Gbps

| Resolution | Refresh | 8-bit 4:4:4 | 10-bit 4:4:4 | 12-bit 4:4:4 |
|------------|---------|-------------|--------------|--------------|
| 1440p      | 60 Hz   | 5.97 Gbps ✓ | 7.46 Gbps ✓  | 8.95 Gbps ✓  |
| 1440p      | 120 Hz  | 11.94 Gbps ✓| 14.93 Gbps ✓ | 17.92 Gbps ✓ |
| 4K         | 60 Hz   | 14.26 Gbps ✓| 17.82 Gbps ✓ | 21.38 Gbps ✓ |
| 4K         | 90 Hz   | 21.38 Gbps ✓| 26.73 Gbps ✗ | 32.08 Gbps ✗ |
| 4K         | 100 Hz  | 23.76 Gbps ✓| 29.70 Gbps ✗ | 35.64 Gbps ✗ |
| 4K         | 120 Hz  | 28.51 Gbps ✗| 35.64 Gbps ✗ | 42.77 Gbps ✗ |

### What Works

| Mode | Pixel Encoding | Color Depth | Status |
|------|---------------|-------------|--------|
| 1440p@120 | YCbCr 4:4:4 | 12-bit | ✓ Full chroma + deep color |
| 1440p@60 | YCbCr 4:4:4 | 12-bit | ✓ |
| 4K@60 | YCbCr 4:4:4 | 12-bit | ✓ Full chroma + deep color |
| 4K@100 | YCbCr 4:4:4 | 8-bit | ✓ (set `force_min_bpc=0`) |
| 4K@120 | YCbCr 4:2:0 | 10-bit | ✓ (half chroma, needs TV support) |
| 4K@120 | YCbCr 4:4:4 | any | ✗ DP 1.4 bandwidth limit |

### Fallback Behavior

When 4:4:4 validation fails at the requested bit depth, the patched driver
tries in order:

1. **YCbCr 4:4:4** at lower bit depth (12→10→8)
2. **YCbCr 4:2:2** (half horizontal chroma)
3. **YCbCr 4:2:0** (quarter chroma, needs TV support)

With `force_min_bpc=10`, step 1 won't go below 10-bit, so modes that don't
fit at 10-bit 4:4:4 will fall through to 4:2:2 or 4:2:0.

## Patched Files

The patch (`bc250-dp-hdmi-ycbcr444-deep-color.patch`) modifies 4 files in the
AMD display driver:

1. **`amdgpu_dm.c`** — `force_ycbcr444` and `force_min_bpc` module params,
   PCON deep color from EDID flags, YCbCr 4:4:4 fallback before 4:2:2.
2. **`link_validation.c`** — Debug prints in dongle validation and DP link
   bandwidth validation.
3. **`link_dp_capability.c`** — CH7218 PCON quirk (restores FRL caps when
   dongle reports malformed topology), debug prints for DPCD det_caps.
4. **`dcn201_resource.c`** — Adds `dp_hdmi21_pcon_support = true` to DCN201
   (was missing, preventing FRL capability parsing on Van Gogh).

## Troubleshooting

### Check if FRL is active

```bash
sudo dmesg | grep -iE "FRL PCON|frl_bw|CH7218"
```

You should see:
- `DP-HDMI FRL PCON supported`
- `frl_bw=48000000` in dongle_validate lines

If `frl_bw=0`, check:
- `cat /sys/module/amdgpu/parameters/dcfeaturemask` — should be `1026` (0x402)
- `cat /etc/modprobe.d/amdgpu-ycbcr444.conf` — should contain `dcfeaturemask=0x402`

### Check current stream

```bash
sudo dmesg | grep "stream depth" | tail -5
```

- `depth=4` = 12-bit, `depth=3` = 10-bit, `depth=2` = 8-bit
- `encoding=3` = YCbCr 4:4:4, `encoding=2` = RGB, `encoding=1` = 4:2:2

### Flickering in Steam Big Picture

Mode switches between resolutions/refresh rates can cause brief flicker.
This is normal — each modeset revalidates the stream. If flickering is
persistent, the TV may not support the requested mode at the requested bit
depth; check `dmesg` for `VALIDATION FAILED` entries.
