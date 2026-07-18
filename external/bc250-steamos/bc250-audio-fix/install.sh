#!/bin/bash
# Install the patched amdgpu.ko (BC-250 DP audio clock fix) via the
# modules updates/ override. Run as: sudo ./install.sh
set -euo pipefail

REL=$(uname -r)
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/amdgpu.ko.zst
DST=/usr/lib/modules/$REL/updates/amdgpu.ko.zst

[ -f "$SRC" ] || { echo "missing $SRC — the module is not shipped in the repo; build it against your running kernel first: ./fetch-sources.sh && ./build.sh"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

[[ "$REL" =~ neptune-[0-9]+ ]] && PRESET=linux-${BASH_REMATCH[0]} || PRESET=
[ -n "$PRESET" ] && [ -f "/etc/mkinitcpio.d/$PRESET.preset" ] || {
    echo "cannot find an mkinitcpio preset for '$REL' — available:"
    ls /etc/mkinitcpio.d/
    exit 1
}

# Both guards (vermagic + task_struct ABI offsets) live in check-module.sh,
# shared with build.sh — see the comments there for why each exists.
# Any nonzero result is fatal. Vermagic alone cannot detect the task_struct
# layout mismatch that previously produced a boot-time black screen.
rc=0
"$HERE/check-module.sh" "$SRC" "$REL" || rc=$?
if [ "$rc" != 0 ]; then
    echo "Refusing to install. Rebuild against the running kernel first (./build.sh)."
    exit 1
fi

ROOTFS_WAS_READONLY=0
INSTALL_STARTED=0
INSTALL_OK=0
TMPD=$(mktemp -d)
PRIORITY_FILE=/usr/lib/depmod.d/10-updates.conf
cleanup() {
    if [ "$INSTALL_STARTED" = 1 ] && [ "$INSTALL_OK" = 0 ]; then
        echo "install failed; restoring the previous module override" >&2
        if [ -f "$TMPD/original.ko.zst" ]; then
            install -D -m644 "$TMPD/original.ko.zst" "$DST"
        else
            rm -f "$DST"
        fi
        if [ -f "$TMPD/original-priority.conf" ]; then
            install -D -m644 "$TMPD/original-priority.conf" "$PRIORITY_FILE"
        else
            rm -f "$PRIORITY_FILE"
        fi
        depmod "$REL" || true
        mkinitcpio -p "$PRESET" >/dev/null 2>&1 || true
    fi
    rm -rf "$TMPD"
    if [ "$ROOTFS_WAS_READONLY" = 1 ]; then steamos-readonly enable || true; fi
}
trap cleanup EXIT
if [ -f "$DST" ]; then cp -a "$DST" "$TMPD/original.ko.zst"; fi
if [ -f "$PRIORITY_FILE" ]; then cp -a "$PRIORITY_FILE" "$TMPD/original-priority.conf"; fi
if steamos-readonly status 2>/dev/null | grep -qi enabled; then
    steamos-readonly disable
    ROOTFS_WAS_READONLY=1
fi

INSTALL_STARTED=1
install -D -m644 "$SRC" "$DST"
depmod "$REL"

RESOLVED=$(modinfo -k "$REL" -F filename amdgpu)
echo "amdgpu now resolves to: $RESOLVED"
if [[ "$RESOLVED" != *"/updates/"* ]]; then
    echo "ERROR: updates/ override not winning; forcing depmod priority"
    mkdir -p /usr/lib/depmod.d
    echo "search updates built-in" > "$PRIORITY_FILE"
    depmod "$REL"
    RESOLVED=$(modinfo -k "$REL" -F filename amdgpu)
    echo "amdgpu now resolves to: $RESOLVED"
    [[ "$RESOLVED" == *"/updates/"* ]] || { echo "still losing — aborting before initramfs"; rm -f "$DST"; depmod "$REL"; exit 1; }
fi

mkinitcpio -p "$PRESET"
INSTALL_OK=1
echo "OK — patched amdgpu installed. Reboot to activate."
