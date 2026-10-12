# BC-250 Dual-Output Audio (MastaG) — SteamOS adaptation

Source: `external/bc250-dual-audio/` (vendored from https://github.com/MastaG/bc250-dual-audio)

## Current state

- **Upstream version tracked:** v0.15 (commit 02f7319)
- **Local revision:** v0.15 (SteamOS-adapted)
- **E-AC-3:** removed entirely (still absent upstream v0.15)
- **AC-3 bitrate:** 640 kbps (ALSA a52 `bitrate 640`)
- **WirePlumber required:** 0.5.17 (stock SteamOS ships 0.5.15; toolkit installs the CachyOS 0.5.17 packages from `deps/`)

## SteamOS-specific adaptations (DO NOT remove)

These differ from upstream CachyOS and are intentional for SteamOS:

1. **Sink name:** `dolby_digital_ac3` (upstream uses `bc250_ac3`). More readable in the SteamOS Game Mode / gamescope sink picker.
2. **Sink visibility in Game Mode:** `60-bc250-ac3-output.conf` sets `node.virtual = false`, `device.class = "sound"`, `device.bus = "pci"`, `device.api = "alsa"`. Upstream uses `node.virtual = true`. SteamOS/gamescope filters out virtual sinks, so this workaround is required.
3. **Config file locations:** pipewire/wireplumber confs go in `~/.config/` (user), not `/etc/` (system). SteamOS has a read-only root; `/etc/` is volatile (symlinked to /run/ or restored on reboot). Only the ALSA conf (`/etc/alsa/conf.d/`) and WirePlumber scripts (`/usr/local/share/wireplumber/scripts/`) go in system paths, installed with `steamos-readonly disable/enable` gating.
4. **Audio positions:** `audio.position = [ FL FR RL RR FC LFE ]` (ALSA 5.1 order for the a52 encoder). This matches upstream and must NOT be changed.
5. **steamos-readonly trap:** `install.sh` and `rollback.sh` disable steamos-readonly in a trap and re-enable on EXIT.

## Timing parameters (unchanged v0.14→v0.15, aligned with upstream)

These were restored from v0.13's reduced values to fix intermittent sync loss / clipping.
Upstream v0.15 did not touch `50-bc250-audio.conf`; values carry over:

| Parameter | v0.13 (old) | v0.14/v0.15 (current) | Purpose |
|---|---|---|---|
| `switch-delay-ms` | 500 | **1000** | Guard interval between native HDMI releasing hw and AC-3 backend opening hw:Generic,3 |
| `api-alsa-start-delay` | 1024 | **1536** | ALSA startup delay before opening the PCM |
| `startup-settle-ms` | 1000 | **1500** | Graph stabilization time before evaluating the configured mode |

The v0.13 values were too short and likely caused EBUSY races / clipping when the hardware wasn't fully released.

## File map

| File | Location (installed) | Notes |
|---|---|---|
| `61-bc250-a52.conf` | `/etc/alsa/conf.d/` | ALSA a52 PCM, `bitrate 640`, IEC61937 channel status |
| `60-bc250-ac3-output.conf` | `~/.config/pipewire/pipewire.conf.d/` | NULL sink `dolby_digital_ac3`, SteamOS visibility workaround |
| `50-bc250-audio.conf` | `~/.config/wireplumber/wireplumber.conf.d/` | WirePlumber policy, timing params, schema settings |
| `90-bc250-audio-mode.lua` | `/usr/local/share/wireplumber/scripts/` | Arbiter (1255 lines, AC-3 only) |
| `monitors/alsa.lua` | `/usr/local/share/wireplumber/scripts/monitors/` | Patched ALSA monitor with BC-250 hardware lock |
| `install.sh` | — | Installer, v0.15, no ffmpeg/aplay/dd deps |
| `rollback.sh` | — | Restores backup, cleans EAC3 leftovers |
| `check.sh` | — | Diagnostics (AC-3 only, no EAC3 sections) |

## E-AC-3 removal (v0.14)

The following were deleted from the vendored tree:
- `usr/local/libexec/bc250-eac3-backend` (378-line helper binary)
- `etc/systemd/user/bc250-eac3-backend.service`

The following were removed from `90-bc250-audio-mode.lua`:
- `create_eac3_backend()`, `wait_eac3_helper_release()`, `grant_eac3_permit()`, `clear_eac3_permit()`, `eac3_helper_session_active()`
- `EAC3_FRONTEND`, `EAC3_PIPE_BACKEND_NAME`, `EAC3_FIFO`, `EAC3_PERMIT_KEY`, `EAC3_SESSION_KEY`, `EAC3_HARDWARE_KEY`
- `EAC3_RELEASE_WARN_MS`, `EAC3_ATTACH_TIMEOUT_MS`
- `eac3_pipe_backend` state, EAC3 branches in `is_encoded_mode`, `frontend_for_mode`, `create_backend_for_mode`, `stop_encoded_then`, `refresh_native_during_encoded`, `refresh_desired_from_authority`
- `metadata_key_present()`, stale permit cleanup in `attach_default_metadata`

`install.sh` and `rollback.sh` still **clean up** EAC3 artifacts from v0.12/v0.13 installs (service, helper, FIFO, pipe-size) — this is migration code, not EAC3 functionality.

## Installer dependencies (v0.14)

Required commands: `pactl wpctl pw-metadata sha256sum grep tr awk`

Removed (were only needed for E-AC-3): `ffmpeg aplay dd stat`

## v0.15 upstream change ("hold the automatic output across native HDMI hotplug")

Only `90-bc250-audio-mode.lua` changed functionally. In
`refresh_desired_from_authority()`, when authority is `automatic/effective`
(no `default.configured.audio.sink` user pick):

- New state: `automatic_mode`, `automatic_native_name`, `last_authority`.
- On entering automatic authority, the learned choice is reset.
- While the native node is present: `mode == "other"` (USB DAC/BT default) is
  still followed; first election is learned; a re-election to a different mode
  after hotplug is ignored (`automatic re-election … ignored; holding …`).
- While the native node is absent: an encoded mode is kept (frontend is
  permanent, `return` early); native mode still follows the fallback so
  streams have a sink and is restored on return.

Our three adaptation hunks (sink name `dolby_digital_ac3`, backend name,
READY log line) are untouched — the upstream diff applied cleanly.

## start.sh integration

- `install_dual_audio()` — installs files, prints "v0.15", "AC3 640 kbps"
- `run_revert_dual_audio()` — removes files, cleans EAC3 leftovers
- Status line shows `installed (v0.15)`
- Menu item 12 description: `MastaG v0.15`
- `dual_audio_installed()` detects via presence of `50-bc250-audio.conf` in `~/.config/wireplumber/`

## Known symptoms addressed

- **Sync loss / clipping during use:** likely caused by v0.13's shortened `switch-delay-ms=500` and `api-alsa-start-delay=1024`. Restored to v0.14 values (1000/1536).
- **Stale EAC3 state:** v0.13 arbiter had EAC3 permit/session handshake code that could interfere even when only AC-3 was selected. Removed in v0.14.
