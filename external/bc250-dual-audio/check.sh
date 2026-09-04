#!/usr/bin/env bash
set -u

echo '=== versions ==='
pipewire --version 2>/dev/null || true
wireplumber --version 2>/dev/null || true

echo
echo '=== ALSA A52 PCM ==='
aplay -L 2>/dev/null | grep -A2 -E '^bc250_a52$' || true

echo
echo '=== sinks ==='
pactl list sinks short || true

echo
echo '=== active card profile (native card should remain stock ACP) ==='
pactl list cards | grep -E 'Name: alsa_card.pci-0000_01_00.1|Active Profile' || true

echo
echo '=== BC-250 policy log ==='
journalctl --user -u wireplumber --since '10 minutes ago' --no-pager | \
  grep -E 's-bc250-audio|BC-250|A52|AC3|sink-monitor|Holding native|reprobe|busy|EBUSY|playback open failed|Start error|stack traceback' || true

echo
echo '=== PipeWire EBUSY/errors ==='
journalctl --user -u pipewire --since '10 minutes ago' --no-pager | \
  grep -Ei 'busy|EBUSY|playback open failed|Start error' || true

echo
echo '=== BC-250 internal runtime settings ==='
wpctl settings bc250.audio.ac3-hardware-lock 2>/dev/null || true
wpctl settings bc250.audio.native-probe-request 2>/dev/null || true


echo
echo '=== configured vs effective default sink metadata ==='
pw-metadata -n default 0 2>/dev/null | \
  grep -E 'default\.configured\.audio\.sink|default\.audio\.sink' || true


echo
echo '=== ALSA monitor base / override hashes ==='
sha256sum /usr/share/wireplumber/scripts/monitors/alsa.lua 2>/dev/null || true
sha256sum /usr/local/share/wireplumber/scripts/monitors/alsa.lua 2>/dev/null || true
