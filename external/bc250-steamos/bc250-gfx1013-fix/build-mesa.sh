#!/bin/bash
# Build patched Mesa/RADV for GFX1013 compute queue fix
# Adapted from bc250-gfx1013-fix install.sh for SteamOS
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=$(<"${HERE}/VERSION")
MESA_VERSION=26.2.0-rc3
MESA_TARBALL_URL=https://archive.mesa3d.org/mesa-${MESA_VERSION}.tar.xz
MESA_TARBALL_SHA256=f733c005660d342a51c6727d1ad481f43d05b4c601ac72247fa641e1d73a8ad1
BUILD_ROOT="${HERE}/build-mesa"
MESA_PREFIX="/opt/bc250-gfx1013/${VERSION}"

die() { echo "FATAL: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

WITH_FSR4=0
for a in "$@"; do
    case "$a" in
        --fsr4) WITH_FSR4=1 ;;
    esac
done

# Check dependencies
for cmd in meson ninja sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command missing: $cmd"
done

# Check Python packaging module
if ! python3 -c "import packaging" 2>/dev/null; then
    die "Python packaging module not found. Install it with: sudo pacman -S python-packaging"
fi

step "Download Mesa ${MESA_VERSION}"
mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"
if [[ -f "mesa-${MESA_VERSION}.tar.xz" ]]; then
    echo "Tarball already downloaded"
else
    if ! wget -O "mesa-${MESA_VERSION}.tar.xz" "$MESA_TARBALL_URL"; then
        die "Failed to download Mesa tarball"
    fi
fi

step "Verify Mesa tarball checksum"
if ! echo "${MESA_TARBALL_SHA256}  mesa-${MESA_VERSION}.tar.xz" | sha256sum -c -; then
    die "Mesa tarball checksum verification failed"
fi

step "Extract Mesa tarball"
if [[ -d "mesa-${MESA_VERSION}" ]]; then
    echo "Already extracted, removing old directory"
    rm -rf "mesa-${MESA_VERSION}"
fi
tar xf "mesa-${MESA_VERSION}.tar.xz"
cd "mesa-${MESA_VERSION}"

step "Apply Mesa patches from bc250-gfx1013-fix"
SERIES_FILE="${HERE}/patches/mesa/series"
if [[ ! -f "$SERIES_FILE" ]]; then
    die "Mesa series file not found: $SERIES_FILE"
fi

# Build the effective series: uncomment the FSR4 patch if --fsr4 was passed
if [ "$WITH_FSR4" = 1 ]; then
    echo "FSR4 optimization enabled (--fsr4)"
    EFFECTIVE_SERIES=$(sed 's/^#0005-bc250-fsr4-i24.patch/0005-bc250-fsr4-i24.patch/' "$SERIES_FILE")
else
    EFFECTIVE_SERIES=$(cat "$SERIES_FILE")
fi

while IFS= read -r patch_file; do
    [[ "$patch_file" =~ ^# ]] && continue
    [[ -z "$patch_file" ]] && continue
    patch_path="${HERE}/patches/mesa/${patch_file}"
    if [[ ! -f "$patch_path" ]]; then
        die "Patch file not found: $patch_path"
    fi
    echo "Applying $patch_file"
    if patch -p1 --dry-run -s -f < "$patch_path" >/dev/null 2>&1; then
        patch -p1 -s < "$patch_path"
        echo "Applied: $patch_file"
    elif patch -p1 -R --dry-run -s -f < "$patch_path" >/dev/null 2>&1; then
        echo "Already applied: $patch_file"
    else
        die "Patch neither applies nor reverses cleanly: $patch_file"
    fi
done <<< "$EFFECTIVE_SERIES"

step "Configure Mesa build"
if [[ -d build ]]; then
    echo "Removing old build directory"
    rm -rf build
fi

# Mesa's meson.build has a fallback for systems without ETIME (e.g. FreeBSD):
#   if cc.get_define('ETIME', prefix : '#include <errno.h>') == ''
#     pre_args += '-DETIME=ETIMEDOUT'
#   endif
# But on Meson 1.8.2 + GCC 15.x + glibc 2.43, cc.get_define() errors out
# instead of returning '' when the define is missing (glibc hides ETIME behind
# _GNU_SOURCE). Patch the check to use cc.has_define() which returns a bool
# instead of throwing, so the fallback actually works.
if ! echo '#include <errno.h>' | cc -dM -E -x c - 2>/dev/null | grep -qw ETIME; then
    echo "ETIME not visible from <errno.h>; patching meson.build to use has_define()"
    sed -i "/# Support systems without ETIME/,/^endif$/ {
        s/cc\.get_define('ETIME', prefix : '#include <errno\.h>') == ''/not cc.has_define('ETIME', prefix : '#include <errno.h>')/
    }" meson.build
fi

meson setup build \
    -Dvulkan-drivers=amd \
    -Dgallium-drivers= \
    -Dplatforms=x11,wayland \
    -Dglx=disabled \
    -Dllvm=disabled \
    -Dbuildtype=release \
    -Dprefix="$MESA_PREFIX"

step "Build Mesa"
ninja -C build

step "Install Mesa to ${MESA_PREFIX}"
sudo ninja -C build install

step "Set VK_DRIVER_FILES environment variable"
# Only the 64-bit ICD is patched; list the stock 32-bit ICD alongside it so
# 32-bit Vulkan processes (some game launchers/anti-cheat components) keep
# working via the unpatched driver instead of losing Vulkan entirely.
STOCK_32BIT_ICD="/usr/share/vulkan/icd.d/radeon_icd.i686.json"
PATCHED_ICD="${MESA_PREFIX}/share/vulkan/icd.d/radeon_icd.x86_64.json"
if [[ -f "$STOCK_32BIT_ICD" ]]; then
    VK_DRIVER_FILES_VALUE="${PATCHED_ICD}:${STOCK_32BIT_ICD}"
else
    echo "Warning: stock 32-bit ICD not found at $STOCK_32BIT_ICD; 32-bit Vulkan apps may not find a driver."
    VK_DRIVER_FILES_VALUE="$PATCHED_ICD"
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
echo "==> Mesa build complete!"
echo "   Installed to: ${MESA_PREFIX}"
echo "   VK_DRIVER_FILES set to: ${VK_DRIVER_FILES_VALUE}"
echo ""
echo "   Reboot required for VK_DRIVER_FILES to take effect."
