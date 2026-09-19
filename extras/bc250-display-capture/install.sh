#!/usr/bin/env bash
set -euo pipefail

PLUGIN_NAME="BC-250 Display Capture"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$HOME/homebrew/plugins"
DEST_DIR="$PLUGINS_DIR/$PLUGIN_NAME"
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export PATH="$PNPM_HOME/bin:$PATH"

[[ $EUID -ne 0 ]] || { echo "Run this installer as the SteamOS desktop user, not root." >&2; exit 1; }
[[ -d "$PLUGINS_DIR" ]] || { echo "Decky Loader not found at $PLUGINS_DIR." >&2; exit 1; }
[[ -f "$SOURCE_DIR/plugin.json" && -f "$SOURCE_DIR/main.py" && -f "$SOURCE_DIR/collector.py" ]] || {
    echo "Display capture plugin files are incomplete." >&2
    exit 1
}

if [[ "${1:-}" == "--build" || ! -f "$SOURCE_DIR/dist/index.js" ]]; then
    if ! command -v node >/dev/null 2>&1; then
        echo "node is required to build the frontend; dist/index.js is prebuilt and committed." >&2
        exit 1
    fi
    if ! command -v pnpm >/dev/null 2>&1; then
        curl -fsSL https://get.pnpm.io/install.sh | sh -
        export PATH="$PNPM_HOME/bin:$PATH"
    fi
    cd "$SOURCE_DIR"
    pnpm install
    pnpm run typecheck
    pnpm run build
    [[ -f "$SOURCE_DIR/dist/index.js" ]] || { echo "Build produced no dist/index.js." >&2; exit 1; }
fi

sudo rm -rf "$DEST_DIR"
sudo install -d -m 0755 "$DEST_DIR/dist"
sudo install -m 0644 "$SOURCE_DIR/plugin.json" "$SOURCE_DIR/main.py" "$SOURCE_DIR/collector.py" "$DEST_DIR/"
sudo install -m 0644 "$SOURCE_DIR/dist/index.js" "$DEST_DIR/dist/index.js"
sudo chown -R "$USER":"$USER" "$DEST_DIR"

if systemctl is-active --quiet plugin_loader.service 2>/dev/null; then
    sudo systemctl restart plugin_loader.service
elif systemctl --user is-active --quiet plugin_loader.service 2>/dev/null; then
    systemctl --user restart plugin_loader.service
fi

echo "$PLUGIN_NAME installed. Open it from Decky's Quick Access Menu."
