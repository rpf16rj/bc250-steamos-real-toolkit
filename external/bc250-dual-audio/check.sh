#!/usr/bin/env bash
set -u

RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
FIFO="$RUNTIME_DIR/bc250-eac3-768.pcm"
PERMIT_KEY="bc250.eac3.permit"
SESSION_KEY="bc250.eac3.session"
HARDWARE_KEY="bc250.eac3.hardware"

echo "=== versions ==="
wireplumber --version 2>/dev/null || true
pipewire --version 2>/dev/null || true
ffmpeg -version 2>/dev/null | head -1 || true

echo
echo "=== visible sinks ==="
pactl list sinks short || true

echo
echo "=== PipeWire / WirePlumber graph ==="
wpctl status -n || true

echo
echo "=== configured + effective default ==="
pw-metadata -n default 0 2>/dev/null | \
  grep -E 'default\.(configured\.)?audio\.sink' || true

echo
echo "=== EAC3 helper ==="
systemctl --user --no-pager --full status bc250-eac3-backend.service | sed -n '1,16p' || true

echo
echo "=== EAC3 ownership handshake ==="
if [[ -p "$FIFO" ]]; then
  ls -l "$FIFO" 2>/dev/null || true
else
  echo "FIFO absent: $FIFO"
fi
for key in "$PERMIT_KEY" "$SESSION_KEY" "$HARDWARE_KEY"; do
  value=$(pw-metadata -n default 0 "$key" 2>/dev/null | grep -F "key:'$key'" || true)
  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "metadata absent: $key"
  fi
done

echo
echo "=== ELD E-AC3/DD+ advertisement ==="
found=0
for eld in /proc/asound/card*/eld#*; do
  [[ -r "$eld" ]] || continue
  if grep -Eq '^[[:space:]]*monitor_present[[:space:]]+1' "$eld"; then
    found=1
    echo "-- $eld --"
    grep -E 'monitor_name|connection_type|sad[0-9]+_coding_type|sad[0-9]+_rates|sad[0-9]+_channels' "$eld" || true
  fi
done
if (( ! found )); then
  echo "No connected HDMI/DP ELD found."
fi

echo
echo "=== IEC61937 channel status (what the sink is being told) ==="
# Only meaningful while an encoded mode is actually selected and playing.
# Data: non-audio  -> receiver is told to decode this as Dolby (correct)
# Data: audio      -> receiver treats the bitstream as PCM and plays noise
if command -v iecset >/dev/null 2>&1; then
  iecset -c 0 2>/dev/null | grep -E 'Data|Rate' | sed 's/^/  /' || echo "  (unavailable)"
else
  echo "  iecset not installed (alsa-utils)"
fi
echo "  configured AC3 path: $(grep -E '^[[:space:]]*ac3-alsa-path' \
  "$HOME/.config/wireplumber/wireplumber.conf.d/50-bc250-audio.conf" 2>/dev/null | tr -s ' ')"

echo
echo "=== recent BC-250 WirePlumber log ==="
journalctl --user -u wireplumber --since "10 minutes ago" --no-pager | \
  grep -E 'BC-250|s-bc250-audio|s-monitors|Holding native|reprobe|A52|AC3|EAC3|permit|SESSION|acknowledged|encoded|busy|error|Failed' || true

echo
echo "=== recent PipeWire hardware errors ==="
PW_ERRORS=$(journalctl --user -u pipewire --since "10 minutes ago" --no-pager 2>/dev/null | \
  grep -Ei 'busy|EBUSY|playback open failed|Start error' || true)
if [[ -n "$PW_ERRORS" ]]; then
  echo "$PW_ERRORS"
else
  echo "None."
fi

echo
echo "=== recent EAC3 helper log ==="
journalctl --user -u bc250-eac3-backend --since "10 minutes ago" --no-pager | tail -60 || true

echo
echo "=== EAC3 lifecycle / teardown errors ==="
EAC3_ERRORS=$(journalctl --user -u bc250-eac3-backend --since "10 minutes ago" --no-pager 2>/dev/null | \
  grep -Ei 'No such file|Bestand of map bestaat niet|Bad file descriptor|Ongeldige bestandsdescriptor|failed to (open|create) FIFO|Invalid PCM packet|pipeline did not stop|failed to start E-AC-3 pipeline|failed to start EAC3 permit metadata monitor|permit metadata monitor exited' || true)
if [[ -n "$EAC3_ERRORS" ]]; then
  echo "$EAC3_ERRORS"
else
  echo "None."
fi

echo
echo "=== EAC3 permit monitor events ==="
MONITOR_EVENTS=$(journalctl --user -u bc250-eac3-backend --since "10 minutes ago" --no-pager 2>/dev/null | \
  grep -E 'hardware permit observed; metadata monitor armed|hardware permit withdrawal event received' || true)
if [[ -n "$MONITOR_EVENTS" ]]; then
  echo "$MONITOR_EVENTS"
else
  echo "No recent permit-monitor events (normal if EAC3 was not selected)."
fi

echo
echo "=== EAC3 release wait warnings ==="
RELEASE_WARN=$(journalctl --user -u wireplumber --since "10 minutes ago" --no-pager 2>/dev/null | \
  grep -F 'still waiting for EAC3 helper to release HDMI' || true)
if [[ -n "$RELEASE_WARN" ]]; then
  echo "$RELEASE_WARN"
else
  echo "None."
fi
