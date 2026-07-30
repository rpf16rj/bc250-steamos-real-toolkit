#!/bin/bash
# Remove the patched amdgpu override from the OTHER SteamOS slot (the one
# that black-screened on 2026-07-03) and regenerate its initramfs.
#
# Background: install.sh was run while booted into the other slot, so the
# patched module + initramfs live there. After the black screen the system
# failed over to this slot, so rollback.sh here was a no-op. This script
# chroots into the other slot and does the rollback where it's needed.
#
# Run as: sudo ./cleanup-other-slot.sh [--skip-current]
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

REL=$(uname -r)
HERE=$(cd "$(dirname "$0")" && pwd)
ROLLBACK="$HERE/rollback.sh"
SKIP_CURRENT=0
ADOPT_ARGS=()
for argument in "$@"; do
    case "$argument" in
        --skip-current) SKIP_CURRENT=1 ;;
        --adopt-legacy) ADOPT_ARGS=(--adopt-legacy) ;;
        *) echo "Usage: $0 [--skip-current] [--adopt-legacy]" >&2; exit 2 ;;
    esac
done
[[ "$ROLLBACK" == /home/* && -f "$ROLLBACK" && ! -L "$ROLLBACK" ]] \
    || { echo "rollback helper must be a regular file under /home: $ROLLBACK" >&2; exit 1; }

echo "== current slot: $(findmnt -no SOURCE /) =="
if [ "$SKIP_CURRENT" = 0 ]; then
    "$ROLLBACK" --all "${ADOPT_ARGS[@]}"
fi

echo "== entering other slot chroot =="
steamos-chroot --partset other -- /bin/bash "$ROLLBACK" --all "${ADOPT_ARGS[@]}"

echo "== verifying other slot initramfs is fresh =="
OTHER_ROOT=$(readlink -f /dev/disk/by-partsets/other/rootfs)
MNT=$(mktemp -d)
cleanup_mount() {
    if mountpoint -q "$MNT"; then umount "$MNT" || true; fi
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup_mount EXIT
mount -o ro "$OTHER_ROOT" "$MNT"
for image in "$MNT"/boot/initramfs* "$MNT"/boot/vmlinuz*; do
    [ ! -e "$image" ] || ls -la "$image"
done
umount "$MNT"
rmdir "$MNT"
trap - EXIT

echo "OK — other slot cleaned. It should now boot with the stock amdgpu."
