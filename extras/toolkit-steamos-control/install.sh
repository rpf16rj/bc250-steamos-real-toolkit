#!/usr/bin/env bash
set -euo pipefail

PLUGIN_NAME="Toolkit SteamOS Control"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$HOME/homebrew/plugins"
DEST_DIR="$PLUGINS_DIR/$PLUGIN_NAME"
DECKY_INSTALLER="https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/install_release.sh"

[[ $EUID -ne 0 ]] || { echo "Run this installer as the SteamOS desktop user, not root." >&2; exit 1; }
[[ -f "$SOURCE_DIR/plugin.json" && -f "$SOURCE_DIR/main.py" && -f "$SOURCE_DIR/fan_manager.py" && -f "$SOURCE_DIR/dist/index.js" ]] || {
    echo "Toolkit SteamOS Control artifact is incomplete." >&2
    exit 1
}

if [[ ! -d "$PLUGINS_DIR" ]]; then
    echo "Decky Loader not found. Installing the latest stable release..."
    curl -fsSL "$DECKY_INSTALLER" | sh
fi
[[ -d "$PLUGINS_DIR" ]] || { echo "Decky Loader installation did not create $PLUGINS_DIR." >&2; exit 1; }

sudo rm -rf "$DEST_DIR"
sudo install -d -m 0755 "$DEST_DIR/dist"
sudo install -m 0644 "$SOURCE_DIR/plugin.json" "$SOURCE_DIR/main.py" "$DEST_DIR/"
sudo install -m 0755 "$SOURCE_DIR/fan_manager.py" "$DEST_DIR/"
sudo install -m 0644 "$SOURCE_DIR/dist/index.js" "$DEST_DIR/dist/index.js"
sudo chown -R "$USER":"$USER" "$DEST_DIR"

if systemctl is-active --quiet plugin_loader.service 2>/dev/null; then
    sudo systemctl restart plugin_loader.service
elif systemctl --user is-active --quiet plugin_loader.service 2>/dev/null; then
    systemctl --user restart plugin_loader.service
fi

echo "Toolkit SteamOS Control installed. Open it from Decky's Quick Access Menu."
