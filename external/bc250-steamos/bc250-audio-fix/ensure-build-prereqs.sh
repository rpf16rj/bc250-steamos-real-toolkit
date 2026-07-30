#!/bin/bash
# Restore the host toolchain that SteamOS updates may remove. Kernel-specific
# libraries and headers remain isolated under deps/ by fetch-sources.sh.
set -euo pipefail

REQUIRED_TOOLS=(
    curl git make gcc ld ar nm objcopy objdump strip patch tar zstd zcat flock
    modinfo
)
# Name the concrete toolchain packages as well as base-devel so pacman repairs
# files stripped from packages that may still be recorded as installed.
PACKAGES=(
    base-devel make gcc binutils patch pkgconf git curl tar zstd gzip util-linux
    kmod
)

missing_tools() {
    local tool missing=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    [ "${#missing[@]}" = 0 ] || printf '%s\n' "${missing[@]}"
}

mapfile -t MISSING < <(missing_tools)
[ "${#MISSING[@]}" -gt 0 ] || exit 0

if [ "$(id -u)" != 0 ]; then
    command -v sudo >/dev/null 2>&1 \
        || { echo "FATAL: missing build prerequisites (${MISSING[*]}) and sudo is unavailable" >&2; exit 1; }
    echo "Missing build prerequisites: ${MISSING[*]}"
    echo "Restoring the SteamOS build toolchain (sudo required)..."
    exec sudo "$0"
fi

for tool in steamos-readonly pacman pacman-key; do
    command -v "$tool" >/dev/null 2>&1 \
        || { echo "FATAL: $tool is required to install build prerequisites" >&2; exit 1; }
done

ROOTFS_WAS_READONLY=0
restore_rootfs() {
    local rc=$?
    trap - EXIT
    if [ "$ROOTFS_WAS_READONLY" = 1 ]; then
        steamos-readonly enable || rc=1
    fi
    exit "$rc"
}
trap restore_rootfs EXIT

STATUS=$(steamos-readonly status 2>/dev/null || true)
if [[ "${STATUS,,}" == *enabled* ]]; then
    steamos-readonly disable
    ROOTFS_WAS_READONLY=1
fi

pacman-key --init
pacman-key --populate archlinux holo 2>/dev/null || pacman-key --populate
pacman -Sy --noconfirm "${PACKAGES[@]}"

mapfile -t MISSING < <(missing_tools)
[ "${#MISSING[@]}" = 0 ] \
    || { echo "FATAL: prerequisites are still missing after package installation: ${MISSING[*]}" >&2; exit 1; }

echo "SteamOS build toolchain is ready."
