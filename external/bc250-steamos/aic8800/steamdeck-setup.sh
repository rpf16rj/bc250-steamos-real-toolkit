#!/bin/bash
# One-shot (re)setup of the AIC8800D80 USB WiFi dongle on the Steam Deck.
# Run:  sudo bash steamdeck-setup.sh
#
# SteamOS updates/reinstalls wipe /usr (build tools + installed modules).
# This script restores everything:
#   1. unlock the read-only rootfs
#   2. install build tools (make/gcc/...)
#   3. fetch kernel headers matching the running kernel (into the repo, no rootfs pollution)
#   4. build aic_load_fw.ko + aic8800_fdrv.ko
#   5. install them to /usr/lib/modules/$(uname -r)/updates/aic8800 + depmod
#   6. write /etc configs (usb_modeswitch, udev rule, modprobe firmware path)
#   7. relock the rootfs and switch the dongle to WiFi mode
#
# The setup registers its /etc files in SteamOS's atomic-update keep list.
# Run setup after a kernel update; the boot service can also rebuild when its
# matching headers and toolchain are available locally.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Please run with sudo."; exit 1; }

REAL_USER="${SUDO_USER:-deck}"
REAL_HOME="${REAL_HOME:-$(getent passwd "$REAL_USER" | cut -d: -f6)}"
[ -n "$REAL_HOME" ] || { echo "Could not resolve home for $REAL_USER"; exit 1; }
FIXES_REPO_DIR="${FIXES_REPO_DIR:-$REAL_HOME/.local/share/bc250-fixes/bc250-steamos}"
[ "$FIXES_REPO_DIR" = "${FIXES_REPO_DIR%[[:space:]]*}" ] \
    && [ "${FIXES_REPO_DIR#/}" != "$FIXES_REPO_DIR" ] \
    || { echo "FIXES_REPO_DIR must be an absolute path without whitespace."; exit 1; }
SCRIPT_REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
UPDATE_PERSIST_SH="$SCRIPT_REPO_DIR/bc250-update-persistence.sh"
STORAGE_SH="$SCRIPT_REPO_DIR/bc250-storage.sh"
[ -f "$UPDATE_PERSIST_SH" ] \
    || { echo "Update persistence helper missing: $UPDATE_PERSIST_SH"; exit 1; }
if [ -d "$FIXES_REPO_DIR/aic8800" ]; then
    REPO="$FIXES_REPO_DIR/aic8800"
else
    REPO="$SCRIPT_REPO_DIR/aic8800"
fi
[ "$REPO" = "${REPO%[[:space:]]*}" ] \
    || { echo "The AIC8800 source path cannot contain whitespace."; exit 1; }
DRV=$REPO/src/USB/driver_fw/drivers/aic8800
FW_SOURCE=$REPO/src/USB/driver_fw/fw/aic8800D80
ROOT_DATA_DIR=/var/lib/bc250-control
FW=$ROOT_DATA_DIR/aic8800/firmware/aic8800D80
ROOT_SOURCE=$ROOT_DATA_DIR/aic8800/source
ROOT_HELPER=$ROOT_DATA_DIR/helper/aic8800-ensure-modules
BUILD_USER=$REAL_USER
KREL=$(uname -r)

[ -d "$DRV" ] || { echo "Driver source not found at $DRV"; exit 1; }
[ -d "$FW_SOURCE" ] || { echo "Firmware source not found at $FW_SOURCE"; exit 1; }
[ -f "$STORAGE_SH" ] || { echo "Storage helper missing: $STORAGE_SH"; exit 1; }
if find "$DRV" "$FW_SOURCE" -type l -print -quit | grep -q .; then
    echo "Refusing to install AIC8800 source containing symlinks."
    exit 1
fi
bash "$STORAGE_SH" install

ROOTFS_WAS_READONLY=0
unlock_rootfs() {
    if steamos-readonly status 2>/dev/null | grep -qi enabled; then
        steamos-readonly disable
        ROOTFS_WAS_READONLY=1
    fi
}
relock_rootfs() {
    if [ "$ROOTFS_WAS_READONLY" = 1 ]; then
        steamos-readonly enable
        ROOTFS_WAS_READONLY=0
    fi
}
trap relock_rootfs EXIT

find_storage_device() {
    local device vendor product

    for device in /sys/bus/usb/devices/*; do
        [ -r "$device/idVendor" ] && [ -r "$device/idProduct" ] || continue
        vendor=$(<"$device/idVendor")
        product=$(<"$device/idProduct")
        if [ "$vendor:$product" = 1111:1111 ]; then
            printf '%s\n' "${device##*/}"
            return 0
        fi
    done
    return 1
}

find_wifi_device_id() {
    local expected_device="${1:-}" device vendor product vendor_upper product_upper alias

    for device in /sys/bus/usb/devices/*; do
        [ -r "$device/idVendor" ] && [ -r "$device/idProduct" ] || continue
        if [ -n "$expected_device" ] && [ "${device##*/}" != "$expected_device" ]; then
            continue
        fi

        vendor=$(<"$device/idVendor")
        product=$(<"$device/idProduct")
        vendor_upper=$(printf '%s' "$vendor" | tr '[:lower:]' '[:upper:]')
        product_upper=$(printf '%s' "$product" | tr '[:lower:]' '[:upper:]')
        while IFS= read -r alias; do
            case "$alias" in
                "usb:v${vendor_upper}p${product_upper}"*)
                    printf '%s:%s\n' "$vendor" "$product"
                    return 0
                    ;;
            esac
        done < <(modinfo -F alias aic8800_fdrv 2>/dev/null)
    done
    return 1
}

echo "== [1/7] Unlocking rootfs =="
unlock_rootfs

echo "== [2/7] Installing build tools =="
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinux holo >/dev/null 2>&1 || true
pacman -Sy --noconfirm --needed base-devel

echo "== [3/7] Kernel headers for $KREL =="
if [ ! -d "$DRV/steamos-headers/usr/lib/modules/$KREL/build" ]; then
    runuser -u "$BUILD_USER" -- make -C "$DRV" steamos-headers
else
    echo "already present, skipping download"
fi

echo "== [4/7] Building driver =="
runuser -u "$BUILD_USER" -- make -C "$DRV" clean
runuser -u "$BUILD_USER" -- make -C "$DRV"

echo "== [5/7] Installing modules =="
make -C "$DRV" install

echo "== [6/7] Writing /etc configuration =="
mkdir -p /etc/usb_modeswitch.d /etc/udev/rules.d /etc/modprobe.d

# Dongle enumerates as fake USB mass-storage 1111:1111 (removable disk, so
# the standard CD-ROM eject doesn't work). This vendor SCSI message switches
# it to its actual firmware-loader and WiFi device IDs.
cat > '/etc/usb_modeswitch.d/1111:1111' <<'EOF'
# AIC8800D80 WiFi dongle: fake mass-storage -> WiFi mode
MessageContent="555342431234567800000000000010fd0000000000000000000000000000f2"
ResetUSB=1
EOF

cat > /etc/udev/rules.d/40-aic8800-modeswitch.rules <<'EOF'
# AIC8800D80 WiFi dongle: auto-switch from fake mass-storage to WiFi mode
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="1111", ATTR{idProduct}=="1111", RUN+="/usr/lib/udev/usb_modeswitch '%b/%k'"
EOF

cat > /etc/modprobe.d/aic8800.conf <<EOF
options aic_load_fw aic_fw_path=$FW
EOF

rm -rf "$FW" "$ROOT_SOURCE"
install -d -o root -g root -m 0755 "$FW" "$ROOT_SOURCE" \
    "$(dirname "$ROOT_HELPER")"
cp -RL "$FW_SOURCE"/. "$FW"/
cp -a "$DRV"/. "$ROOT_SOURCE"/
chown -R root:root "$ROOT_DATA_DIR/aic8800"
chmod -R go-w "$ROOT_DATA_DIR/aic8800"
install -o root -g root -m 0755 "$REPO/aic8800-ensure-modules.sh" "$ROOT_HELPER"
install -m 644 "$REPO/aic8800-modules.service" /etc/systemd/system/aic8800-modules.service
sed -i "/^RequiresMountsFor=/c RequiresMountsFor=$ROOT_DATA_DIR" /etc/systemd/system/aic8800-modules.service
rm -f /etc/aic8800-ensure-modules.sh
rm -f /etc/aic8800-paths.conf

udevadm control --reload
systemctl daemon-reload
systemctl enable aic8800-modules.service >/dev/null
bash "$UPDATE_PERSIST_SH" install aic

echo "== [7/7] Relocking rootfs =="
relock_rootfs

if storage_device=$(find_storage_device); then
    echo "Switching dongle to WiFi mode..."
    usb_modeswitch -v 1111 -p 1111 \
        -M "555342431234567800000000000010fd0000000000000000000000000000f2" -R || true

    wifi_id=
    for _ in {1..15}; do
        if wifi_id=$(find_wifi_device_id "$storage_device"); then
            break
        fi
        sleep 1
    done
    if [ -n "$wifi_id" ]; then
        echo "Dongle switched to WiFi mode as $wifi_id."
    else
        echo "WiFi device did not appear; check: journalctl -k -u systemd-udevd"
    fi
elif wifi_id=$(find_wifi_device_id); then
    echo "Dongle already in WiFi mode as $wifi_id; reloading driver..."
    modprobe -r aic8800_fdrv aic_load_fw 2>/dev/null || true
    modprobe aic8800_fdrv
else
    echo "Dongle not detected - plug it in and it will switch automatically."
fi

echo "Done."
