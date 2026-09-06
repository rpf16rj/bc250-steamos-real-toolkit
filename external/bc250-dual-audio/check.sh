#!/usr/bin/env bash
set -u

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
systemctl --user --no-pager --full status bc250-eac3-backend.service | sed -n '1,14p' || true

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
echo "=== recent BC-250 WirePlumber log ==="
journalctl --user -u wireplumber --since "10 minutes ago" --no-pager | \
  grep -E 'BC-250|s-bc250-audio|s-monitors|Holding native|reprobe|A52|AC3|EAC3|encoded|busy|error|Failed' || true

echo
echo "=== recent PipeWire hardware errors ==="
journalctl --user -u pipewire --since "10 minutes ago" --no-pager | \
  grep -Ei 'busy|EBUSY|playback open failed|Start error' || true

echo
echo "=== recent EAC3 helper log ==="
journalctl --user -u bc250-eac3-backend --since "10 minutes ago" --no-pager | tail -40 || true
