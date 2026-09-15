#!/usr/bin/env bash
set -u

echo "=== versions ==="
wireplumber --version 2>/dev/null || true
pipewire --version 2>/dev/null || true

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
echo "  configured AC3 bitrate: $(grep -E '^[[:space:]]*bitrate' \
  /etc/alsa/conf.d/61-bc250-a52.conf 2>/dev/null | tr -s ' ' || echo '(unknown)')"

echo
echo "=== recent BC-250 WirePlumber log ==="
journalctl --user -u wireplumber --since "10 minutes ago" --no-pager | \
  grep -E 'BC-250|s-bc250-audio|s-monitors|Holding native|reprobe|A52|AC3|encoded|busy|error|Failed' || true

echo
echo "=== recent PipeWire hardware errors ==="
PW_ERRORS=$(journalctl --user -u pipewire --since "10 minutes ago" --no-pager 2>/dev/null | \
  grep -Ei 'busy|EBUSY|playback open failed|Start error' || true)
if [[ -n "$PW_ERRORS" ]]; then
  echo "$PW_ERRORS"
else
  echo "None."
fi
