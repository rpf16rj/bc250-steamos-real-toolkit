#!/bin/bash
# Remove the patched amdgpu override and restore the stock module.
# Run as: sudo ./rollback.sh [kernel-release]
#
# IMPORTANT if running from a recovery-USB chroot: uname -r reports the
# USB's kernel, not the installed one, so the release is auto-detected
# from /usr/lib/modules instead. Pass it explicitly if detection fails.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

REL="${1:-$(uname -r)}"
if [ ! -d "/usr/lib/modules/$REL/kernel" ]; then
    # uname -r doesn't match this system (recovery chroot) — detect instead
    CANDIDATES=()
    for candidate in /usr/lib/modules/*/; do
        [ ! -d "$candidate" ] || CANDIDATES+=("${candidate%/}")
    done
    CANDIDATES=("${CANDIDATES[@]##*/}")
    if [ "${#CANDIDATES[@]}" = 1 ]; then
        REL="${CANDIDATES[0]}"
        echo "note: using detected kernel '$REL' (uname -r reports a different kernel)"
    else
        echo "ERROR: cannot determine kernel release. Available in /usr/lib/modules:"
        printf '  %s\n' "${CANDIDATES[@]:-none}"
        echo "Re-run as: sudo ./rollback.sh <kernel-release>"
        exit 1
    fi
fi

ROOTFS_WAS_READONLY=0
if steamos-readonly status 2>/dev/null | grep -qi enabled; then
    steamos-readonly disable
    ROOTFS_WAS_READONLY=1
fi
trap 'if [ "$ROOTFS_WAS_READONLY" = 1 ]; then steamos-readonly enable || true; fi' EXIT

rm -f "/usr/lib/modules/$REL/updates/amdgpu.ko.zst"
depmod "$REL"
echo "amdgpu now resolves to: $(modinfo -k "$REL" -F filename amdgpu)"

# Preset name follows the kernel package (linux-neptune-616 -> -618 across
# SteamOS 3.8 -> 3.9), so derive it from the kernel release being rolled back.
[[ "$REL" =~ neptune-[0-9]+ ]] && PRESET=linux-${BASH_REMATCH[0]} || PRESET=
[ -n "$PRESET" ] && [ -f "/etc/mkinitcpio.d/$PRESET.preset" ] || {
    echo "cannot find an mkinitcpio preset for '$REL' — available:"
    ls /etc/mkinitcpio.d/
    echo "stock module restored and depmod done; rerun after fixing: mkinitcpio -p <preset>"
    exit 1
}
mkinitcpio -p "$PRESET"
echo "OK — stock amdgpu restored. Reboot to apply."
