#!/bin/bash
# Build and install a patched hid-playstation.ko for DS5-Linux-Bridge
# compatibility.
#
# The DS5-Linux-Bridge (https://github.com/kungaa/DS5-Linux-Bridge/) presents
# the DualSense controller via USB with VID 054c / PID 0ce6, but does not
# implement feature report 0x09 (pairing info, 20 bytes). The hid-playstation
# driver aborts probing when this report fails, causing the device to fall
# back to the generic usbhid driver — which does not declare BTN_MODE in the
# evdev capabilities bitfield, preventing Steam/Gamescope chord combos
# (Guide + A for Quick Access Menu) from working.
#
# This patch makes the pairing info, firmware info, and calibration data
# feature reports non-fatal, allowing the driver to create the input device
# with BTN_MODE properly mapped even when the bridge doesn't implement them.
#
#   ./patch-driver.sh [kernel-tree]     Fetch, build, and install
#   ./patch-driver.sh status            Report installed module status
#   ./patch-driver.sh uninstall         Restore stock module
#
# Run as the normal user; sudo is invoked for the install step.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
AUDIO_FIX_DIR="$HERE/../bc250-audio-fix"
REL=$(uname -r)
MARKER="/usr/lib/modules/$REL/updates/.bc250-ds5-bridge-fix"
MODULE_DST="/usr/lib/modules/$REL/updates/hid-playstation.ko.zst"
STOCK_MODULE="/usr/lib/modules/$REL/kernel/drivers/hid/hid-playstation.ko.zst"

die()  { echo "FATAL: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

# --- status ---
show_status() {
    if [ -f "$MODULE_DST" ] && [ -f "$MARKER" ]; then
        local resolved
        resolved=$(modinfo -k "$REL" -F filename hid_playstation 2>/dev/null || true)
        if [[ "$resolved" == */updates/* ]]; then
            echo "[ds5-bridge] $REL: patched module installed ($resolved)"
            return 0
        else
            echo "[ds5-bridge] $REL: module present but not selected by depmod"
            return 1
        fi
    elif [ -f "$MARKER" ]; then
        echo "[ds5-bridge] $REL: marker exists but module missing — incomplete install"
        return 1
    else
        echo "[ds5-bridge] $REL: not installed"
        return 1
    fi
}

# --- uninstall ---
do_uninstall() {
    [ "$(id -u)" != 0 ] || die "run as the logged-in user; this command requests sudo"
    if [ ! -f "$MODULE_DST" ] && [ ! -f "$MARKER" ]; then
        echo "[ds5-bridge] not installed; nothing to remove."
        exit 0
    fi
    echo "[ds5-bridge] removing patched module and restoring stock..."
    sudo bash -c '
        set -e
        REL="'"$REL"'"
        MODULE_DST="'"$MODULE_DST"'"
        MARKER="'"$MARKER"'"
        STOCK="'"$STOCK_MODULE"'"
        ROOTFS_RO=0
        if steamos-readonly status 2>/dev/null | grep -qi enabled; then
            steamos-readonly disable
            ROOTFS_RO=1
        fi
        rm -f "$MODULE_DST" "$MARKER"
        depmod "$REL"
        RESOLVED=$(modinfo -k "$REL" -F filename hid_playstation 2>/dev/null || true)
        echo "[ds5-bridge] hid_playstation now resolves to: $RESOLVED"
        if [ -f "$STOCK" ]; then
            echo "[ds5-bridge] stock module restored. Reboot to apply."
        else
            echo "[ds5-bridge] WARNING: stock module not found at $STOCK"
        fi
        if [ "$ROOTFS_RO" = 1 ]; then steamos-readonly enable || true; fi
    '
    echo "[ds5-bridge] source and build output preserved."
}

# --- main build+install ---
case "${1:-}" in
    status)    show_status; exit $? ;;
    uninstall) do_uninstall; exit 0 ;;
    help|-h|--help)
        cat <<EOF
Usage: $0 [kernel-tree]    Fetch, build, and install
       $0 status           Report installed module status
       $0 uninstall        Restore stock module
EOF
        exit 0 ;;
esac

[ "$(id -u)" != 0 ] || die "run as the normal user; sudo is used only for the install step"
command -v flock >/dev/null || die "flock is required"
exec 9>"$HERE/.patch-driver.lock"
flock 9

KERNEL_TREE="${1:-$AUDIO_FIX_DIR/valve-kernel}"

# --- 1. Ensure kernel source is available ---
step "ensure kernel source tree"
if [ ! -f "$KERNEL_TREE/drivers/hid/hid-playstation.c" ]; then
    step "fetching kernel source (via audio fix infrastructure)"
    "$AUDIO_FIX_DIR/fetch-sources.sh" "$KERNEL_TREE"
fi
[ -f "$KERNEL_TREE/drivers/hid/hid-playstation.c" ] \
    || die "hid-playstation.c not found in $KERNEL_TREE after fetch"

# --- 2. Prepare build tree if needed ---
step "check kernel build tree preparation"
if [ ! -f "$KERNEL_TREE/include/generated/autoconf.h" ] || \
   [ ! -f "$KERNEL_TREE/include/generated/utsrelease.h" ]; then
    step "preparing kernel build tree (modules_prepare via audio fix)"
    "$AUDIO_FIX_DIR/build.sh" --prepare-only "$KERNEL_TREE"
fi

# Verify tree matches running kernel
grep -qF "\"$REL\"" "$KERNEL_TREE/include/generated/utsrelease.h" \
    || die "kernel tree does not match running kernel $REL — re-fetch sources"

# --- 3. Apply our patch ---
step "apply DS5 Bridge compatibility patch"
PATCH="$HERE/hid-playstation-bridge-compat.patch"
cd "$KERNEL_TREE"
if patch -p1 -R --dry-run --fuzz=3 -s -f < "$PATCH" >/dev/null 2>&1; then
    echo "patch already applied"
elif patch -p1 --dry-run --fuzz=3 -s -f < "$PATCH" >/dev/null 2>&1; then
    patch -p1 --fuzz=3 -s < "$PATCH"
    echo "patch applied"
else
    die "patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
fi

# --- 4. Build hid-playstation.ko ---
step "build hid-playstation.ko"
# Source the build environment (PATH, LD_LIBRARY_PATH for pahole, bc, etc.)
source "$AUDIO_FIX_DIR/build-env.sh"

# Clean stale objects and build
make M=drivers/hid clean 2>/dev/null || true
make -j"$(nproc)" M=drivers/hid modules

KO="drivers/hid/hid-playstation.ko"
[ -f "$KO" ] || die "build produced no $KO"

# --- 5. Package and verify ---
step "package and verify module"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
cp "$KO" "$OUT/hid-playstation.ko"
strip --strip-debug "$OUT/hid-playstation.ko"
zstd -19 -q -f "$OUT/hid-playstation.ko" -o "$OUT/hid-playstation.ko.zst"

# Verify vermagic matches running kernel
MODVER=$(modinfo -F vermagic "$OUT/hid-playstation.ko" 2>/dev/null || true)
echo "vermagic: $MODVER"
[[ "$MODVER" == *"$REL"* ]] || die "vermagic mismatch: expected $REL, got $MODVER"

# --- 6. Install ---
step "install module (sudo required)"
sudo bash -c '
    set -e
    REL="'"$REL"'"
    MODULE_DST="'"$MODULE_DST"'"
    MARKER="'"$MARKER"'"
    SRC="'"$OUT/hid-playstation.ko.zst"'"
    ROOTFS_RO=0
    if steamos-readonly status 2>/dev/null | grep -qi enabled; then
        steamos-readonly disable
        ROOTFS_RO=1
    fi
    mkdir -p "$(dirname "$MODULE_DST")"
    install -D -m644 "$SRC" "$MODULE_DST"
    sha256sum "$MODULE_DST" | awk "{print \$1}" > "$MARKER"
    chmod 644 "$MARKER"
    depmod "$REL"
    RESOLVED=$(modinfo -k "$REL" -F filename hid_playstation 2>/dev/null || true)
    echo "hid_playstation now resolves to: $RESOLVED"
    if [[ "$RESOLVED" != */updates/* ]]; then
        echo "WARNING: override not winning — check depmod configuration"
    fi
    if [ "$ROOTFS_RO" = 1 ]; then steamos-readonly enable || true; fi
'

echo
echo "OK — patched hid-playstation.ko installed for $REL."
echo "Reboot to activate (or: sudo modprobe -r hid_playstation && sudo modprobe hid_playstation)."
echo "After reboot, connect the DS5 Bridge and verify:"
echo "  lsmod | grep hid_playstation    (should show 1 user)"
echo "  evtest /dev/input/eventN        (BTN_MODE should be in capabilities)"
