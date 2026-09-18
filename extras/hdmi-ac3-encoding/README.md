# HDMI AC-3 Surround Encoding (Dolby Digital 5.1)

A standalone script that enables real-time Dolby Digital (AC-3) 5.1 encoding
over HDMI/DisplayPort via eARC on Linux systems running PipeWire + WirePlumber.

## What it does

All audio — games, browsers, media players — is encoded to Dolby Digital 5.1
in real-time by the native ALSA `a52` plugin and sent as an AC-3 bitstream over
HDMI. The TV passes AC-3 bitstreams through eARC without downmixing, so your
receiver gets true 5.1 surround sound instead of PCM stereo.

- Zero added latency (native ALSA plugin, no external pipeline)
- ~1-2% CPU overhead (libavcodec a52 encoder)
- Stereo content is automatically upmixed to 5.1 by PipeWire's channel mixer
- Sink stays active for 1 hour after last sound (prevents receiver PCM fallback)
- 64ms audio buffer (tuned for low latency in gamescope)

## Why this is needed (SteamOS / BC-250)

The BC-250's HDMI audio card supports AC-3 encoding, and SteamOS ships a
profile configuration for it (`hdmi-ac3.conf`). However, the profile is
never loaded because the BC-250 identifies itself as "AMD BC-250" in DMI
instead of Valve's "OEM F7F" — so the hardware profile that triggers AC-3
support is silently skipped. This script works around that by installing its
own tuned profile set plus a udev rule and WirePlumber config that activate
the profile directly.

The bundled `bc250-hdmi-ac3.conf` profile set improves on the stock
`hdmi-ac3.conf` in exactly one way: it encodes at **640 kbps** (the AC-3
maximum — the stock profile leaves BITRATE unset, so the a52 plugin uses its
448 kbps default, which produces audible quantization harshness). It does this
by passing RATE and BITRATE positionally to the a52 plugin:

```
device-strings = plug:{SLAVE="a52:%f,'hw:%f,3',48000,640"}
```

The transport itself is the proven stock one — the a52 plugin wraps the bare
`hw:` slave and the receiver locks Dolby Digital from the AC3 sync word. No
`hdmi:`/AES wrapper is used: that approach (borrowed from the dual-audio
reference) was never validated on BC-250 hardware and produced a PCM-locked,
silent stream. The stock file is left untouched.

## Requirements

- PipeWire + WirePlumber
- `alsa-plugins` (provides the `a52` PCM plugin)
- `ffmpeg` (provides libavcodec, used by the a52 plugin)
- `alsa-card-profile` (provides the profile set framework; the tuned
  `bc250-hdmi-ac3.conf` is installed by the script)
- An HDMI audio device (e.g. HDA ATI HDMI)
- A display connected via HDMI or an active DisplayPort-to-HDMI adapter
- An AV receiver or soundbar with Dolby Digital support

### Installing dependencies

```bash
# Arch / CachyOS / SteamOS
sudo pacman -S alsa-plugins ffmpeg

# Debian / Ubuntu
sudo apt install libasound2-plugins ffmpeg
```

## Usage

```bash
sudo ./ac3-surround.sh install    # enable AC-3 surround encoding
sudo ./ac3-surround.sh revert     # restore default HDMI stereo
sudo ./ac3-surround.sh status     # check current state
```

After installing, go to your desktop's audio settings and select the AC-3
device as the output:

> **HD-Audio Generic Digital Surround 5.1 (HDMI/AC3)**

Your receiver should now show Dolby Digital when audio plays.

## How it works

1. **Udev rule** (`/etc/udev/rules.d/91-ac3-audio.rules`): sets
   `ACP_PROFILE_SET=bc250-hdmi-ac3.conf` for the HDMI audio card, making the
   AC-3 profiles discoverable by PipeWire/WirePlumber.

2. **WirePlumber config** (`~/.config/wireplumber/wireplumber.conf.d/ac3-profile.conf`):
   - Sets `device.profile-set = "bc250-hdmi-ac3.conf"` for the HDMI card
   - Sets `session.suspend-timeout-seconds = 3600` (keep sink alive 1h)
   - Sets `api.alsa.start-delay = 1536` on the AC-3 sinks (prevents the a52
     plugin from raising EPIPE on playback start). The rule matches
     `node.name = "~alsa_output.*ac3.*"` — matching `alsa.name` would silently
     never fire, since the a52 plugin reports an empty `alsa.name` when it is
     reached through a named PCM.

3. **ACP profile set** (`/usr/share/alsa-card-profile/mixer/profile-sets/bc250-hdmi-ac3.conf`):
   defines the `hdmi-ac3-surround` mapping using the stock transport with the
   bitrate added:
   `device-strings = plug:{SLAVE="a52:%f,'hw:%f,3',48000,640"}` — `plug` →
   `a52` at 640 kbps → bare `hw:` slave. The same `hw:` device indices as the
   stock profile (3, 7, 8 … 16) are used for the extra mappings.

4. **Profile selection**: the script selects `output:hdmi-ac3-surround` and
   sets the resulting sink as the default.

## Porting to other systems

The script is designed to be distro-agnostic. Key considerations when porting:

- The `device.nick = "HDA ATI HDMI"` match in the WirePlumber config may need
  to be adjusted for different GPU vendors (e.g. NVIDIA, Intel).
- The `hw:%f,3` device index in the profile set corresponds to the HDMI PCM
  device number. Check `aplay -l` to find the correct index for your card.
- On systems without `alsa-card-profile`, the profile set is created by the
  script. The `.include default.conf` line may need adjustment if the default
  profile set has a different name or location.
- The udev rule targets `KERNEL=="card0"`. If your HDMI audio is on a different
  card number, adjust accordingly.

## License

Use at your own risk. Based on community work for the BC-250 and SteamOS.
