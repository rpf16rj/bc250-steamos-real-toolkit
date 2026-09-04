#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this as the desktop/Steam user, NOT with sudo. The script calls sudo itself." >&2
  exit 1
fi

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$HOME/.local/state/bc250-audio-backup/$STAMP"
mkdir -p "$BACKUP/user" "$BACKUP/system"

echo "BC-250 dual-output AC3 installer"
echo "Backup: $BACKUP"

WP_VERSION=$(wireplumber --version 2>/dev/null | grep -Eo '0\.5\.[0-9]+' | head -1 || true)
EXPECTED_WP_VERSION="0.5.17"
EXPECTED_STOCK_ALSA_SHA256="b0f15addcd2b36a8a5cd87555b9cbd822de1b8663545e5add2faf3d2f4c50211"
STOCK_ALSA="/usr/share/wireplumber/scripts/monitors/alsa.lua"

if [[ "$WP_VERSION" != "$EXPECTED_WP_VERSION" && "${BC250_ALLOW_UNTESTED_WP:-0}" != "1" ]]; then
  echo "ERROR: this package is currently rebased and tested for WirePlumber $EXPECTED_WP_VERSION." >&2
  echo "Detected: ${WP_VERSION:-unknown}" >&2
  echo "Set BC250_ALLOW_UNTESTED_WP=1 only if you intentionally want to test another version." >&2
  exit 2
fi

if [[ -f "$STOCK_ALSA" && "${BC250_ALLOW_UNTESTED_WP:-0}" != "1" ]]; then
  STOCK_ALSA_SHA256=$(sha256sum "$STOCK_ALSA" | awk '{print $1}')
  if [[ "$STOCK_ALSA_SHA256" != "$EXPECTED_STOCK_ALSA_SHA256" ]]; then
    echo "ERROR: distro stock alsa.lua does not match the WirePlumber 0.5.17 base used by v0.7." >&2
    echo "Expected: $EXPECTED_STOCK_ALSA_SHA256" >&2
    echo "Found:    $STOCK_ALSA_SHA256" >&2
    echo "Refusing to install a full monitor override onto an unknown base." >&2
    echo "Set BC250_ALLOW_UNTESTED_WP=1 only for deliberate testing." >&2
    exit 3
  fi
fi

backup_user_file() {
  local path=$1
  local tag=$2
  if [[ -e "$path" || -L "$path" ]]; then
    cp -a "$path" "$BACKUP/user/$tag"
  else
    : > "$BACKUP/user/$tag.missing"
  fi
}

backup_system_file() {
  local path=$1
  local tag=$2
  if sudo test -e "$path"; then
    sudo cp -a "$path" "$BACKUP/system/$tag"
    sudo chown "$USER":"$(id -gn)" "$BACKUP/system/$tag"
  else
    : > "$BACKUP/system/$tag.missing"
  fi
}

# Back up the prototype/profile-based setup currently in use.
backup_user_file "$HOME/.config/wireplumber/wireplumber.conf.d/50-bc250-ac3.conf" "user-50-bc250-ac3.conf"
backup_user_file "$HOME/.local/share/wireplumber/scripts/monitors/alsa.lua" "user-alsa.lua"
backup_user_file "$HOME/.config/pipewire/pipewire.conf.d/ac3-sink.conf" "user-ac3-sink.conf"

backup_system_file "/etc/alsa-card-profile/mixer/profile-sets/hdmi-ac3.conf" "system-hdmi-ac3.conf"
backup_system_file "/etc/alsa/conf.d/61-bc250-a52.conf" "system-61-bc250-a52.conf"
backup_system_file "/etc/pipewire/pipewire.conf.d/60-bc250-ac3-output.conf" "system-60-bc250-ac3-output.conf"
backup_system_file "/etc/wireplumber/wireplumber.conf.d/50-bc250-audio.conf" "system-50-bc250-audio.conf"
backup_system_file "/usr/local/share/wireplumber/scripts/90-bc250-audio-mode.lua" "system-90-bc250-audio-mode.lua"
backup_system_file "/usr/local/share/wireplumber/scripts/monitors/alsa.lua" "system-alsa.lua"

echo "$BACKUP" > "$HOME/.local/state/bc250-audio-last-backup"

# Remove higher-priority user overrides from the old prototype so the new
# host-wide image configuration is actually authoritative.
rm -f "$HOME/.config/wireplumber/wireplumber.conf.d/50-bc250-ac3.conf"
rm -f "$HOME/.config/pipewire/pipewire.conf.d/ac3-sink.conf"
rm -f "$HOME/.local/share/wireplumber/scripts/monitors/alsa.lua"

# The profile-based AC3 mapping is no longer used. Native ACP is explicitly
# forced back to default.conf by 50-bc250-audio.conf.
sudo rm -f /etc/alsa-card-profile/mixer/profile-sets/hdmi-ac3.conf

sudo install -d -m 0755 /etc/alsa/conf.d
sudo install -d -m 0755 /etc/pipewire/pipewire.conf.d
sudo install -d -m 0755 /etc/wireplumber/wireplumber.conf.d
sudo install -d -m 0755 /usr/local/share/wireplumber/scripts/monitors

sudo install -m 0644 "$ROOT_DIR/etc/alsa/conf.d/61-bc250-a52.conf" \
  /etc/alsa/conf.d/61-bc250-a52.conf
sudo install -m 0644 "$ROOT_DIR/etc/pipewire/pipewire.conf.d/60-bc250-ac3-output.conf" \
  /etc/pipewire/pipewire.conf.d/60-bc250-ac3-output.conf
sudo install -m 0644 "$ROOT_DIR/etc/wireplumber/wireplumber.conf.d/50-bc250-audio.conf" \
  /etc/wireplumber/wireplumber.conf.d/50-bc250-audio.conf
sudo install -m 0644 "$ROOT_DIR/usr/local/share/wireplumber/scripts/90-bc250-audio-mode.lua" \
  /usr/local/share/wireplumber/scripts/90-bc250-audio-mode.lua
sudo install -m 0644 "$ROOT_DIR/usr/local/share/wireplumber/scripts/monitors/alsa.lua" \
  /usr/local/share/wireplumber/scripts/monitors/alsa.lua

echo
echo "Installed. Restarting the user audio stack..."
systemctl --user restart pipewire pipewire-pulse wireplumber
sleep 3

echo
echo "=== WirePlumber ==="
systemctl --user --no-pager --full status wireplumber | sed -n '1,14p' || true

echo
echo "=== sinks ==="
pactl list sinks short || true

echo
echo "=== recent BC-250 policy log ==="
journalctl --user -u wireplumber --since "1 minute ago" --no-pager | \
  grep -E 'BC-250|s-bc250-audio|A52|AC3|Failed|error|Error' || true

echo
echo "Done. Reboot before the real Steam/KDE test."
echo "Rollback with: $ROOT_DIR/rollback.sh"
