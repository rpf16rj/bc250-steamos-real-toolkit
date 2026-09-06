#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this as the desktop/Steam user, NOT with sudo." >&2
  exit 1
fi

STATE="$HOME/.local/state/bc250-audio-last-backup"
if [[ ! -f "$STATE" ]]; then
  echo "No installer backup pointer found at $STATE" >&2
  exit 1
fi
BACKUP=$(cat "$STATE")
if [[ ! -d "$BACKUP" ]]; then
  echo "Backup directory missing: $BACKUP" >&2
  exit 1
fi

echo "Rolling back from $BACKUP"

# Stop any leftover EAC3 backend before restoring previous audio policy.
systemctl --user disable --now bc250-eac3-backend.service 2>/dev/null || true

# SteamOS ships with a read-only root filesystem; disable it so we can
# write to /etc and /usr/local. Re-enabled in a trap on exit.
BC250_READONLY_WAS_ON=0
if command -v steamos-readonly &>/dev/null && ! sudo steamos-readonly status 2>/dev/null | grep -q 'disabled'; then
  BC250_READONLY_WAS_ON=1
  sudo steamos-readonly disable
fi
restore_readonly() {
  if [[ $BC250_READONLY_WAS_ON -eq 1 ]]; then
    sudo steamos-readonly enable 2>/dev/null || true
  fi
}
trap restore_readonly EXIT

# Remove files installed by dual-audio.
sudo rm -f /etc/alsa/conf.d/61-bc250-a52.conf
sudo rm -f /usr/local/share/wireplumber/scripts/90-bc250-audio-mode.lua
sudo rm -f /usr/local/share/wireplumber/scripts/monitors/alsa.lua
sudo rm -f /usr/local/libexec/bc250-eac3-backend
sudo rm -f /etc/systemd/user/bc250-eac3-backend.service
rm -f "$HOME/.config/wireplumber/wireplumber.conf.d/50-bc250-audio.conf" 2>/dev/null || true
rm -f "$HOME/.config/pipewire/pipewire.conf.d/60-bc250-ac3-output.conf" 2>/dev/null || true

restore_user() {
  local tag=$1
  local dest=$2
  if [[ -e "$BACKUP/user/$tag" || -L "$BACKUP/user/$tag" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp -a "$BACKUP/user/$tag" "$dest"
  fi
}

restore_system() {
  local tag=$1
  local dest=$2
  if [[ -e "$BACKUP/system/$tag" || -L "$BACKUP/system/$tag" ]]; then
    sudo install -d -m 0755 "$(dirname "$dest")"
    sudo cp -a "$BACKUP/system/$tag" "$dest"
  fi
}

restore_user "user-50-bc250-audio.conf" "$HOME/.config/wireplumber/wireplumber.conf.d/50-bc250-audio.conf"
restore_user "user-60-bc250-ac3-output.conf" "$HOME/.config/pipewire/pipewire.conf.d/60-bc250-ac3-output.conf"
restore_user "user-50-bc250-ac3.conf" "$HOME/.config/wireplumber/wireplumber.conf.d/50-bc250-ac3.conf"
restore_user "user-alsa.lua" "$HOME/.local/share/wireplumber/scripts/monitors/alsa.lua"
restore_user "user-ac3-sink.conf" "$HOME/.config/pipewire/pipewire.conf.d/ac3-sink.conf"

restore_system "system-hdmi-ac3.conf" "/etc/alsa-card-profile/mixer/profile-sets/hdmi-ac3.conf"
restore_system "system-61-bc250-a52.conf" "/etc/alsa/conf.d/61-bc250-a52.conf"
restore_system "system-90-bc250-audio-mode.lua" "/usr/local/share/wireplumber/scripts/90-bc250-audio-mode.lua"
restore_system "system-alsa.lua" "/usr/local/share/wireplumber/scripts/monitors/alsa.lua"
restore_system "system-bc250-eac3-backend" "/usr/local/libexec/bc250-eac3-backend"
restore_system "system-bc250-eac3-backend.service" "/etc/systemd/user/bc250-eac3-backend.service"
systemctl --user daemon-reload

# If the backup already contained an EAC3 service (rollback between two future
# v0.8+ installs), restore its enable/runtime state sensibly.
if [[ -f /etc/systemd/user/bc250-eac3-backend.service ]]; then
  systemctl --user enable --now bc250-eac3-backend.service || true
fi

systemctl --user restart pipewire pipewire-pulse wireplumber
sleep 3
pactl list sinks short || true

restore_readonly
trap - EXIT

echo "Rollback complete."
