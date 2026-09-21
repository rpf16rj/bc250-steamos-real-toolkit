#!/bin/bash
# Install a prebuilt patched Mesa tarball produced by package-mesa-prebuilt.sh.
# Run as the normal user; privileged steps use sudo.
#
#   ./install-mesa-prebuilt.sh <tarball.tar.zst>
#
# Extracts the Mesa prefix to /opt/bc250-gfx1013/<VERSION> and points
# VK_DRIVER_FILES at the patched ICDs — the same end state as a local
# build-mesa.sh run, minus the build.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=$(<"${HERE}/VERSION")
MESA_PREFIX="/opt/bc250-gfx1013/${VERSION}"

die() { echo "FATAL: $*" >&2; exit 1; }

TARBALL=${1:-}
[ -n "$TARBALL" ] && [ -f "$TARBALL" ] || die "usage: $0 <mesa-prebuilt.tar.zst>"
command -v zstd >/dev/null || die "zstd not found — needed to decompress the tarball"

# The tarball must contain the prefix rooted at opt/bc250-gfx1013/<VERSION>.
# No -z flag: GNU tar auto-detects zstd via magic bytes. List once into a
# variable — `tar -tf | grep -q` under pipefail dies on SIGPIPE (141) because
# grep exits on the first match while tar is still listing.
LISTING=$(tar -tf "$TARBALL" 2>/dev/null) || die "cannot read $TARBALL"
[[ "$LISTING" == *"opt/bc250-gfx1013/${VERSION}/"* ]] \
    || die "tarball does not contain opt/bc250-gfx1013/${VERSION}/ — wrong toolkit/Mesa version?"

PATCHED_ICD_64="opt/bc250-gfx1013/${VERSION}/share/vulkan/icd.d/radeon_icd.x86_64.json"
[[ "$LISTING" == *"$PATCHED_ICD_64"* ]] \
    || die "tarball lacks the 64-bit patched ICD — refusing to install"

if steamos-readonly status 2>/dev/null | grep -qi enabled; then
    sudo steamos-readonly disable
    trap 'sudo steamos-readonly enable || true' EXIT
fi

echo "==> extracting Mesa prebuilt to / (prefix ${MESA_PREFIX})"
sudo tar -xf "$TARBALL" -C /

# Same VK_DRIVER_FILES logic as build-mesa.sh: prefer the patched 32-bit ICD,
# fall back to stock when the tarball has no lib32.
PATCHED_ICD_64_ABS="${MESA_PREFIX}/share/vulkan/icd.d/radeon_icd.x86_64.json"
PATCHED_ICD_32_ABS="${MESA_PREFIX}/share/vulkan/icd.d/radeon_icd.i686.json"
STOCK_32BIT_ICD="/usr/share/vulkan/icd.d/radeon_icd.i686.json"

if [[ -f "$PATCHED_ICD_32_ABS" ]]; then
    VK_DRIVER_FILES_VALUE="${PATCHED_ICD_64_ABS}:${PATCHED_ICD_32_ABS}"
elif [[ -f "$STOCK_32BIT_ICD" ]]; then
    echo "Warning: patched 32-bit ICD not in tarball; 32-bit Vulkan apps will use stock unpatched driver."
    VK_DRIVER_FILES_VALUE="${PATCHED_ICD_64_ABS}:${STOCK_32BIT_ICD}"
else
    echo "Warning: no 32-bit ICD found at all; 32-bit Vulkan apps may not find a driver."
    VK_DRIVER_FILES_VALUE="$PATCHED_ICD_64_ABS"
fi

ENV_FILE="/etc/environment"
if grep -q "VK_DRIVER_FILES" "$ENV_FILE" 2>/dev/null; then
    echo "Updating existing VK_DRIVER_FILES entry in $ENV_FILE"
    sudo sed -i "s#^VK_DRIVER_FILES=.*#VK_DRIVER_FILES=${VK_DRIVER_FILES_VALUE}#" "$ENV_FILE"
else
    echo "Adding VK_DRIVER_FILES to $ENV_FILE"
    echo "VK_DRIVER_FILES=${VK_DRIVER_FILES_VALUE}" | sudo tee -a "$ENV_FILE"
fi

echo ""
echo "==> Mesa prebuilt installed to ${MESA_PREFIX}"
echo "   VK_DRIVER_FILES=${VK_DRIVER_FILES_VALUE}"
echo "   Reboot required for VK_DRIVER_FILES to take effect."
