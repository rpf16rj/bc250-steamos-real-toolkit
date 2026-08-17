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

The BC-250's HDMI audio card supports AC-3 encoding, and SteamOS ships the
necessary profile configuration (`hdmi-ac3.conf`). However, the profile is
never loaded because the BC-250 identifies itself as "AMD BC-250" in DMI
instead of Valve's "OEM F7F" — so the hardware profile that triggers AC-3
support is silently skipped. This script works around that by installing a
udev rule and WirePlumber config that activates the profile directly.

On other distros (CachyOS, Arch, etc.) where `hdmi-ac3.conf` doesn't ship by
default, the script creates it automatically.

## Requirements

- PipeWire + WirePlumber
- `alsa-plugins` (provides the `a52` PCM plugin)
- `ffmpeg` (provides libavcodec, used by the a52 plugin)
- `alsa-card-profile` (provides the profile set framework; the script creates
  `hdmi-ac3.conf` automatically if it's missing)
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
   `ACP_PROFILE_SET=hdmi-ac3.conf` for the HDMI audio card, making the AC-3
   profiles discoverable by PipeWire/WirePlumber.

2. **WirePlumber config** (`~/.config/wireplumber/wireplumber.conf.d/ac3-profile.conf`):
   - Sets `device.profile-set = "hdmi-ac3.conf"` for the HDMI card
   - Sets `session.suspend-timeout-seconds = 3600` (keep sink alive 1h)
   - Sets `api.alsa.start-delay = 1536` (prevent a52 plugin EPIPE on startup)
   - Sets `api.alsa.period-size = 768` and `api.alsa.period-num = 4` (64ms
     buffer for low latency)

3. **ACP profile set** (`/usr/share/alsa-card-profile/mixer/profile-sets/hdmi-ac3.conf`):
   defines the `hdmi-ac3-surround` mapping using
   `device-strings = plug:{SLAVE="a52:%f,'hw:%f,3'"}`, which routes audio
   through the ALSA `a52` plugin to encode 6-channel PCM to AC-3.

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
