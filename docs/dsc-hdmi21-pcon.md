# DSC + HDMI 2.1 PCON on DCN201

The BC-250 (Cyan Skillfish / gfx1013, DCN 2.0.1) can output 4K120 at full
4:4:4 chroma through an active DP 1.4 → HDMI 2.1 FRL converter, but the stock
DCN201 driver refuses it: it advertises neither the PCON HDMI 2.1 capability
nor the two DSC engines the silicon actually carries. This feature enables both.

## What the two patches do

`bc250-dcn201-pcon-hdmi21.patch`
: Sets `dc->caps.dp_hdmi21_pcon_support` on DCN201. Without it, link validation
checks a DP→HDMI converter against the converter's TMDS pixel-clock limit
(one DPCD byte × 2.5 MHz, 600 MHz in practice), so 4K120 is reachable only at
4:2:0 8-bit and 4K60 HDR only via 4:2:2. With it, the converter's FRL link
bandwidth (read from DPCD) is the ceiling instead.

`bc250-dcn201-dsc-enable.patch`
: Selects a second `resource_caps` with `num_dsc = 2`, creates the two DSC
objects with `dcn20_dsc_create()`, wires `dcn20_add_dsc_to_stream_resource`,
and propagates `num_dsc` into `dcn201_ip` before `dml_init_instance()` — DML
reads `NumberOfDSC` from there, so without it every DSC mode is rejected with
"Not enough DSC Units" while the objects sit unused.

DCN201 and DCN200 share the same display register base
(`DMU_BASE__INST0_SEG2 == DCN_BASE__INST0_SEG2 == 0x34C0`), so DCN200's
register tables address the real hardware and its DSC code can be reused as-is.

## The switch

Both patches are gated behind one module parameter:

```
amdgpu.bc250_hdmi21=1   # default: PCON + DSC enabled
amdgpu.bc250_hdmi21=0   # stock behaviour, path for path
```

With `=0`, `res_cap_dnc201` (`num_dsc = 0`) is used, the create and destroy
loops run zero times, `.add_dsc_to_stream_resource` stays NULL, and
`dc->config.bc250_hdmi21` is false so `dp_hdmi21_pcon_support` is never set.
Nothing observable changes.

### Recovering from a dark display

Some DP→HDMI 2.1 adapters show black from the moment amdgpu takes over the
display at boot until a hotplug, with this feature off as well and with an
ordinary 4K60 signal. That is a BIOS/GOP → amdgpu handover issue, not these
patches, and a hotplug (unplug/replug the adapter) works around it.

If the screen goes dark after installing this feature, boot with the switch
off — no rebuild needed:

1. Add `amdgpu.bc250_hdmi21=0` to `GRUB_CMDLINE_LINUX_DEFAULT` in
   `/etc/default/grub` (inside the quotes).
2. Run `sudo update-grub` and reboot.

## Bandwidth

The DP 1.4 link between the GPU and the PCON is the limit, not the HDMI 2.1
FRL link on the far side. HBR3 ×4 carries ~25.92 Gbit/s of payload; 4K120 at
4:4:4 needs ~28 Gbit/s. DSC compresses it ~1.7:1 and it fits. 4:2:0 already
fits uncompressed, so DSC only switches on for a stream that does not.

Verified end to end on a BC-250 into an LG G5 through a UGREEN 8K DP→HDMI 2.1
adapter: off = 4K120 YUV420, no DSC, HBR2 ×4; on = 4K120 RGB, DSC 12 bpp
(192/16), HBR2 ×4, FEC, "DP-HDMI FRL PCON supported", BT2020_RGB.

## Toolkit notes

- The two patches are applied as one unit by the Combined Fix. Either
  `--dsc` or `--dsc-pcon` selects the pair.
- Only offered on kernel 7.x.
- Upstream source: [TeleBooth's BC-250 DCN/DSC gist](https://gist.github.com/TeleBooth/d88ef745895d444a401d0e621de9818e),
  carried by [MastaG/linux-cachyos-bc250](https://github.com/MastaG/linux-cachyos-bc250).
  The toolkit versions are adapted to Valve's kernel
  (`7.2.4-valve1-1-neptune-72`).
