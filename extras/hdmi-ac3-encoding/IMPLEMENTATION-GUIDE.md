# HDMI AC-3 Surround Encoding — Implementation Guide

## How to get 5.1 audio over HDMI when the system only exposes PCM stereo

This document describes the approach used to achieve real-time Dolby Digital
(AC-3) 5.1 surround sound over HDMI on a system whose audio controller only
exposes a 2-channel PCM stereo interface. The guide is written so it can be
replicated on any Linux system with PipeWire + WirePlumber.

---

## The Problem

Many embedded APU systems (notably the ASRock BC-250 with AMD Cyan Skillfish)
have an HDMI audio controller (HDA ATI HDMI / HD-Audio Generic) that only
exposes **2-channel PCM stereo** over the HDMI/DisplayPort link. The hardware
does not support multichannel LPCM (linear PCM) output.

When connected to an AV receiver or soundbar capable of 5.1, the receiver
expects a **bitstream** (AC-3 / Dolby Digital, E-AC-3 / DD+, or DTS) — not
multichannel PCM. Since the GPU can only push 2 channels of PCM, the system is
limited to stereo.

On some systems (e.g. SteamOS on Valve's own hardware), the OS ships a
hardware-specific profile that enables AC-3 encoding, but it is only loaded when
the DMI board name matches a known string. Third-party boards with different DMI
identifiers never trigger this profile, leaving the user stuck on stereo.

## The Solution

**Real-time AC-3 encoding via the ALSA `a52` plugin.**

The ALSA `a52` plugin (`libasound_module_pcm_a52.so`, part of `alsa-plugins`)
uses `libavcodec` (from FFmpeg) to encode 6-channel PCM into an AC-3 bitstream
in real-time. The compressed bitstream is then sent over the HDMI link as a
standard 2-channel PCM signal. The receiver detects the AC-3 bitstream
(synchronization frames in the data) and decodes it back to 5.1 channels.

```
┌──────────┐     6-ch PCM      ┌──────────┐     AC-3 bitstream     ┌──────────┐
│  Audio   │ ───────────────▶  │  a52     │ ────────────────────▶  │  HDMI    │
│  Source  │   (6 channels)    │  plugin  │   (2-ch PCM carrier)   │  output  │
│ (games,  │                   │ (FFmpeg  │                         │ (hw:%f,3)│
│  browser)│                   │  libav)  │                         └────┬─────┘
└──────────┘                   └──────────┘                              │
                                                                         │ HDMI/DP cable
                                                                         ▼
                                                                ┌──────────────┐
                                                                │  Receiver    │
                                                                │  detects     │
                                                                │  AC-3 stream │
                                                                │  → 5.1 out   │
                                                                └──────────────┘
```

**Key characteristics:**
- Zero added latency (encoding is real-time, ~1-2% CPU overhead)
- Works with any audio source (games, browsers, media players)
- Stereo content is automatically upmixed to 5.1 by PipeWire's channel mixer
- The receiver displays "Dolby Digital" / "DD" when audio is playing

## Prerequisites

| Component | Package (Arch/SteamOS) | Package (Debian/Ubuntu) | Purpose |
|---|---|---|---|
| ALSA a52 plugin | `alsa-plugins` | `libasound2-plugins` | AC-3 encoding via `libasound_module_pcm_a52.so` |
| FFmpeg / libavcodec | `ffmpeg` | `ffmpeg` | Provides the AC-3 encoder used by the a52 plugin |
| ALSA card profiles | `alsa-card-profile` | (may need manual creation) | Provides the `hdmi-ac3.conf` profile set |
| PipeWire | `pipewire` | `pipewire` | Audio server |
| WirePlumber | `wireplumber` | `wireplumber` | Session manager for PipeWire |

Verify the a52 plugin is installed:
```bash
ls /usr/lib/alsa-lib/libasound_module_pcm_a52.so
ldconfig -p | grep libavcodec
```

## Implementation Steps

### Step 1: Create the `hdmi-ac3.conf` profile set

If your system does not already ship `/usr/share/alsa-card-profile/mixer/profile-sets/hdmi-ac3.conf`,
create it. This file defines the ALSA card profile that maps a 6-channel PCM
sink to the a52 encoder, which outputs to the HDMI hardware device.

The critical line is the `device-strings` — it tells ALSA to route audio through
the a52 plugin into the HDMI PCM device:

```ini
; hdmi-ac3.conf — AC-3 (Dolby Digital) encoding profile set
; The a52 plugin encodes 6-channel PCM to AC-3 in real-time using libavcodec.

.include default.conf

[Mapping hdmi-ac3-surround]
description = Digital Surround 5.1 (HDMI/AC3)
device-strings = plug:{SLAVE="a52:%f,'hw:%f,3'"}
paths-output = hdmi-output-0
channel-map = front-left,front-right,rear-left,rear-right,front-center,lfe
priority = 1
direction = output

[Profile output:hdmi-ac3-surround]
description = Digital Surround 5.1 (HDMI/AC3) Output
output-mappings = hdmi-ac3-surround
priority = 100
skip-probe = no
```

**How `device-strings` works:**

- `plug:` — ALSA plug layer (format conversion)
- `a52:%f` — the a52 plugin, `%f` expands to the card index
- `'hw:%f,3'` — the raw HDMI PCM device (card `%f`, device `3` is typically the
  first HDMI audio output; adjust the device number for your hardware)
- The single quotes inside the double quotes are required by the ALSA config
  parser to nest the slave device specification

For multiple HDMI outputs, create additional `[Mapping]` sections with different
device numbers (7, 8, 9, etc. for HDMI 2, 3, 4) and corresponding `[Profile]`
sections.

### Step 2: Install a udev rule to select the profile set

The ALSA card profile subsystem reads the `ACP_PROFILE_SET` environment variable
to decide which profile set to load for a given sound card. Set it via udev so it
persists across reboots:

```bash
# /etc/udev/rules.d/91-ac3-audio.rules
SUBSYSTEM=="sound", KERNEL=="card0", ENV{ACP_PROFILE_SET}="hdmi-ac3.conf"
```

Reload udev:
```bash
udevadm control --reload-rules
udevadm trigger /sys/class/sound/card0
```

**Note:** Replace `card0` with your actual HDMI audio card number if different.
Use `aplay -l` to identify which card has the HDMI outputs.

### Step 3: Configure WirePlumber to load the AC-3 profile

WirePlumber needs to know which audio device should use the AC-3 profile set.
Create a config fragment in the user's WirePlumber config directory:

```bash
mkdir -p ~/.config/wireplumber/wireplumber.conf.d/
```

Create `~/.config/wireplumber/wireplumber.conf.d/ac3-profile.conf`:

```lua
monitor.alsa.rules = [
  {
    matches = [
      {
        -- Match your HDMI audio device. Adjust device.nick to match your
        -- hardware (check: pactl list cards | grep -A5 "alsa.card_name")
        device.name = "~alsa_card.pci-.*"
        device.nick = "~HD-Audio Generic"
      }
    ]
    actions = {
      update-props = {
        device.description = "HDMI / DisplayPort"
        -- Disable the pro-audio profile to avoid conflicts
        api.acp.disable-pro-audio = true
        -- Load the AC-3 profile set
        device.profile-set = "hdmi-ac3.conf"
        device.routes.default-sink-volume = 1.0
      }
    }
  }
  {
    matches = [
      {
        -- Match HDMI sink nodes
        node.name = "~alsa_output.pci-.*hdmi.*"
      }
    ]
    actions = {
      update-props = {
        -- Keep the sink alive for 1 hour after the last sound.
        -- Without this, the receiver falls back to PCM between tracks
        -- or during dialogue pauses, causing audible pops/clicks.
        session.suspend-timeout-seconds = 3600
      }
    }
  }
  {
    matches = [
      {
        -- Match the a52-encoded sink specifically
        node.name = "~alsa_output.pci-.*hdmi.*"
        alsa.name = "~a52.*"
      }
    ]
    actions = {
      update-props = {
        -- Collect one full AC-3 frame (1536 samples) before starting
        -- playback. Without this, the a52 plugin raises EPIPE on
        -- startup because it hasn't accumulated enough samples to
        -- emit a complete AC-3 frame.
        api.alsa.start-delay = 1536
      }
    }
  }
]
```

**Why these three rules matter:**

1. **Profile selection** — Without `device.profile-set = "hdmi-ac3.conf"`,
   WirePlumber loads the default profile set, which only has stereo mappings.
   The `api.acp.disable-pro-audio = true` prevents the pro-audio profile from
   taking priority (it would expose raw channels without the a52 encoder).

2. **Suspend timeout** — When the sink suspends (no audio for N seconds),
   PipeWire closes the ALSA device. The receiver then loses the AC-3 bitstream
   and switches back to PCM stereo. When audio resumes, there's a pop/click as
   the receiver re-detects AC-3. A 1-hour timeout keeps the sink alive through
   normal gaps (track changes, dialogue pauses, menu navigation).

3. **Start delay** — AC-3 encodes audio in fixed-size frames of 1536 samples
   (32 ms at 48 kHz). If playback starts before a full frame is accumulated,
   the a52 plugin fails with `EPIPE` (broken pipe). The start-delay tells ALSA
   to buffer exactly one frame's worth of samples before beginning playback.

### Step 4: Restart WirePlumber and select the profile

```bash
# Restart WirePlumber (user service)
systemctl --user restart wireplumber

# Wait for it to probe the card with the new profile set
sleep 3

# Find your HDMI audio card
card_name=$(pactl list cards | grep "Name:" | awk '{print $2}' | head -1)

# Select the AC-3 surround profile
pactl set-card-profile "$card_name" output:hdmi-ac3-surround

# Find the AC-3 sink and set it as default
ac3_sink=$(pactl list sinks short | grep "hdmi-ac3-surround" | awk '{print $2}' | head -1)
pactl set-default-sink "$ac3_sink"
```

### Step 5: Verify

```bash
# Check the active profile
pactl list cards | grep "Active Profile"
# Should show: output:hdmi-ac3-surround

# Check the default sink
pactl get-default-sink
# Should contain: hdmi-ac3-surround

# Test 5.1 speaker output (each channel in sequence)
speaker-test -D "$ac3_sink" -c 6 -t sine -l 1 -p 1
```

Your receiver should display "Dolby Digital" or "DD" during playback.

## How It Works — Technical Detail

### The ALSA a52 plugin

The `a52` plugin is a PCM plugin that sits between the application and the
hardware. It presents a 6-channel PCM virtual device to the application. When
the application writes 6-channel PCM samples, the plugin:

1. Collects 1536 samples per channel (one AC-3 frame at 48 kHz)
2. Encodes the 6-channel block to an AC-3 frame using `libavcodec`'s AC-3
   encoder
3. Writes the compressed AC-3 frame to the underlying hardware device as a
   2-channel PCM stream

The HDMI link carries this as a standard S/PDIF-style bitstream inside the
HDMI audio packets. The receiver's AC-3 decoder recognizes the sync pattern
(`0x0B77`) and decodes the frame back to 5.1 channels.

### Why this works when multichannel PCM doesn't

HDMI audio supports two modes:
- **LPCM** (Linear PCM) — up to 8 channels, but requires the GPU's audio
  controller to support the channel count. Many embedded GPUs only support
  2-channel LPCM.
- **Compressed bitstream** (AC-3, DTS, E-AC-3, etc.) — sent as a 2-channel PCM
  stream where the PCM data is actually compressed audio. The receiver decodes
  it. This only requires 2-channel PCM support from the GPU.

The a52 plugin exploits the second mode: it compresses 5.1 audio into a
2-channel PCM carrier, which any HDMI audio controller can output.

### Sample rate and format

AC-3 encoding requires a fixed sample rate of 48 kHz. The `plug:` layer in the
device string handles resampling if the application requests a different rate.
The a52 plugin handles the 16-bit signed PCM format internally.

### Channel mapping

The `channel-map` in the profile set defines the order of channels in the
6-channel PCM stream that the a52 plugin receives:

```
front-left, front-right, rear-left, rear-right, front-center, lfe
```

This matches the standard ALSA surround 5.1 channel order. The a52 encoder
internally maps these to the AC-3 channel order (L, C, R, Ls, Rs, LFE).

## Troubleshooting

### No AC-3 sink appears after profile selection

- Verify `/usr/lib/alsa-lib/libasound_module_pcm_a52.so` exists
- Verify `ldconfig -p | grep libavcodec` finds the FFmpeg library
- Check WirePlumber logs: `journalctl --user -u wireplumber -b`
- Verify the udev rule triggered: `udevadm info /sys/class/sound/card0 | grep ACP_PROFILE_SET`

### Receiver shows PCM / no Dolby Digital

- Ensure the AC-3 sink is the default: `pactl get-default-sink`
- Check the suspend timeout is set (otherwise the sink closes between sounds)
- Some TVs/receivers need "Audio Format" set to "Auto" or "Bitstream" in their
  settings
- eARC must be enabled on the TV if the receiver is connected through the TV

### Audio pops/clicks between tracks

- Increase `session.suspend-timeout-seconds` (or set to 0 to disable suspend
  entirely)
- The receiver is losing and re-acquiring the AC-3 stream; a longer timeout
  prevents the sink from closing

### EPIPE error on playback start

- The `api.alsa.start-delay = 1536` setting is missing or incorrect
- This must be set on the a52 sink node specifically (the third WirePlumber
  rule with `alsa.name = "~a52.*"`)

### Wrong HDMI device

- Check `aplay -l` to find available PCM devices
- The device number in `device-strings` (`hw:%f,3`) must match your HDMI output
- Device 3 is typically the first HDMI output on AMD HDA controllers; device 7,
  8, 9, etc. are additional HDMI/DP outputs

## Reverting

To restore stereo PCM:

1. Remove the udev rule: `rm /etc/udev/rules.d/91-ac3-audio.rules`
2. Remove the WirePlumber config: `rm ~/.config/wireplumber/wireplumber.conf.d/ac3-profile.conf`
3. Reload udev: `udevadm control --reload-rules && udevadm trigger /sys/class/sound/card0`
4. Restart WirePlumber: `systemctl --user restart wireplumber`
5. Select stereo profile: `pactl set-card-profile <card> output:hdmi-stereo`
6. Set stereo sink as default: `pactl set-default-sink <stereo_sink>`

## Platform-Specific Notes

### SteamOS (BC-250)

SteamOS ships `hdmi-ac3.conf` and has a hardware profile (`valve-fremont`) that
loads it automatically — but only when the DMI board name matches `OEM F7F`.
The BC-250's DMI identifies as `AMD BC-250`, so the profile is never loaded.
The udev rule + WirePlumber config in this guide bypass that DMI check.

The BC-250 also requires a kernel patch (`bc250-audio.patch`) that disables DP
spread spectrum for Cyan Skillfish (`ignore_dpref_ss`), without which HDMI audio
is garbled or silent. This is a hardware-specific prerequisite unrelated to the
AC-3 encoding approach.

### Arch Linux / CachyOS

Install `alsa-plugins`, `ffmpeg`, and `alsa-card-profile` from the official
repositories. The `hdmi-ac3.conf` file may not exist — create it as described
in Step 1. No DMI-specific workarounds are needed.

### Debian / Ubuntu

Install `libasound2-plugins` (provides the a52 plugin) and `ffmpeg`. The
`alsa-card-profile` package may not be available — if not, create the
`hdmi-ac3.conf` file manually in `/usr/share/alsa-card-profile/mixer/profile-sets/`
or in a custom path referenced by your WirePlumber config.

### Non-PipeWire systems (PulseAudio)

The same approach works with PulseAudio instead of PipeWire/WirePlumber, but the
configuration method differs:

1. Create the `hdmi-ac3.conf` profile set (same as Step 1)
2. Set the profile via `pactl set-card-profile` (PulseAudio loads profile sets
   from the same `/usr/share/alsa-card-profile/mixer/profile-sets/` directory)
3. No WirePlumber config is needed — PulseAudio's module-alsa-card reads the
   `ACP_PROFILE_SET` udev property directly
4. The suspend timeout can be set in `/etc/pulse/daemon.conf` via
   `exit-idle-time = -1` (never exit)

### Non-Linux systems

The AC-3-over-PCM approach is not Linux-specific. On Windows, equivalent
functionality is provided by:
- **Dolby Digital Live** — real-time AC-3 encoding built into some audio
  drivers (notably Realtek and Creative)
- **AC3Filter** — a DirectShow filter that can encode to AC-3 in real-time
- The fundamental concept is identical: encode 5.1 PCM to AC-3, send the
  bitstream as 2-channel PCM over HDMI/SPDIF

On macOS, tools like **Audio Hijack** with the AC-3 encoder can achieve similar
results, though macOS's HDMI audio handling is more restrictive.

## Summary

| Step | What | Why |
|---|---|---|
| 1 | Create `hdmi-ac3.conf` profile set | Defines the a52-encoded 5.1 sink mapping |
| 2 | Install udev rule (`ACP_PROFILE_SET`) | Tells ALSA which profile set to load for the HDMI card |
| 3 | Configure WirePlumber | Matches the device, sets profile, prevents suspend, fixes EPIPE |
| 4 | Restart WirePlumber + select profile | Activates the AC-3 sink |
| 5 | Verify | Confirm receiver sees Dolby Digital |

The entire solution requires no custom kernel code, no binary blobs, and no
proprietary software — just standard ALSA plugins, FFmpeg's AC-3 encoder, and
correct configuration of the audio profile subsystem.
