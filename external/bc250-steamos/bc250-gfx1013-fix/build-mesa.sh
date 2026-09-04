#!/bin/bash
# Build patched Mesa/RADV for GFX1013 compute queue fix
# Adapted from bc250-gfx1013-fix install.sh for SteamOS
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=$(<"${HERE}/VERSION")
MESA_VERSION=26.2.2
MESA_TARBALL_URL=https://archive.mesa3d.org/mesa-${MESA_VERSION}.tar.xz
MESA_TARBALL_SHA256=eeb29ca7e56cfaa8e8a79538dcf834e3b18e501c31bef5145e959ea437cc4216
BUILD_ROOT="${HERE}/build-mesa"
MESA_PREFIX="/opt/bc250-gfx1013/${VERSION}"

# Mesh shader mode: "mastag" (default, GFX10.3 spoof + mesh/task) or "native" (lonewolf, MESH only)
MESH_MODE="mastag"

die() { echo "FATAL: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --native-mesh)
            MESH_MODE="native"
            shift
            ;;
        --mastag-mesh)
            MESH_MODE="mastag"
            shift
            ;;
        *)
            die "Unknown argument: $1\nUsage: $0 [--native-mesh|--mastag-mesh]"
            ;;
    esac
done

echo "Mesh shader mode: ${MESH_MODE}"

# Check dependencies
for cmd in meson ninja sha256sum wget cc; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command missing: $cmd"
done

# Check Python modules required by Mesa's meson build
for mod in mako packaging yaml; do
    python3 -c "import $mod" 2>/dev/null || die "Python module '$mod' not found. Install it with: sudo pacman -S python-mako python-packaging python-yaml"
done

# Check for glslangValidator (needed for shader compilation)
command -v glslangValidator >/dev/null 2>&1 || die "glslangValidator not found. Install it with: sudo pacman -S glslang"

step "Download Mesa ${MESA_VERSION}"
mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"
if [[ -f "mesa-${MESA_VERSION}.tar.xz" ]]; then
    echo "Tarball already downloaded"
elif [[ -f "${HERE}/vendor/mesa-${MESA_VERSION}.tar.xz" ]]; then
    echo "Using vendored tarball"
    cp "${HERE}/vendor/mesa-${MESA_VERSION}.tar.xz" .
else
    if ! wget -O "mesa-${MESA_VERSION}.tar.xz" "$MESA_TARBALL_URL"; then
        die "Failed to download Mesa tarball from ${MESA_TARBALL_URL}. The server may be offline. A vendored copy can be placed at ${HERE}/vendor/mesa-${MESA_VERSION}.tar.xz"
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

step "Apply Mesa patches from bc250-gfx1013-fix (mode: ${MESH_MODE})"
if [[ "$MESH_MODE" == "native" ]]; then
    PATCH_DIR="${HERE}/patches/mesa-native-mesh"
else
    PATCH_DIR="${HERE}/patches/mesa"
fi
SERIES_FILE="${PATCH_DIR}/series"
if [[ ! -f "$SERIES_FILE" ]]; then
    die "Mesa series file not found: $SERIES_FILE"
fi

while IFS= read -r patch_file; do
    [[ "$patch_file" =~ ^# ]] && continue
    [[ -z "$patch_file" ]] && continue
    patch_path="${PATCH_DIR}/${patch_file}"
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
done < "$SERIES_FILE"

step "Configure Mesa build"
if [[ -d build ]]; then
    echo "Removing old build directory"
    rm -rf build
fi

# Mesa's meson.build has a fallback for systems without ETIME (e.g. FreeBSD):
#   if cc.get_define('ETIME', prefix : '#include <errno.h>') == ''
#     pre_args += '-DETIME=ETIMEDOUT'
#   endif
# On glibc 2.43, ETIME is hidden behind _GNU_SOURCE. Mesa builds with
# _GNU_SOURCE (added to pre_args), so ETIME is available at compile time —
# but Meson's get_define() checks using only the prefix string, which does
# NOT include _GNU_SOURCE. The preprocessor fails with
# "Could not get define 'ETIME'" instead of returning empty.
# cc.has_define() doesn't help because it calls get_define() internally.
#
# Strategy:
# 1. If ETIME is visible without _GNU_SOURCE → no patch needed (our case,
#    glibc 2.41).
# 2. If ETIME is visible WITH _GNU_SOURCE → patch the get_define prefix in
#    meson.build to include '#define _GNU_SOURCE\n' before the #include.
#    Meson interprets \n in single-quoted strings as a newline. get_define
#    then finds ETIME=62 and the fallback is not triggered. No redefinition
#    risk.
# 3. If ETIME is truly absent (even with _GNU_SOURCE, e.g. FreeBSD) →
#    replace the block with unconditional -DETIME=ETIMEDOUT.
if ! echo '#include <errno.h>' | cc -dM -E -x c - 2>/dev/null | grep -qw ETIME; then
    if echo '#define _GNU_SOURCE
#include <errno.h>' | cc -dM -E -x c - 2>/dev/null | grep -qw ETIME; then
        echo "ETIME visible only with _GNU_SOURCE; patching meson.build get_define prefix"
        sed -i "s|cc\.get_define('ETIME', prefix : '#include <errno\.h>')|cc.get_define('ETIME', prefix : '#define _GNU_SOURCE\\\\n#include <errno.h>')|" meson.build
    else
        echo "ETIME not visible even with _GNU_SOURCE; replacing check with unconditional -DETIME=ETIMEDOUT"
        sed -i '/# Support systems without ETIME/,/^endif$/c\
  pre_args += '"'"'-DETIME=ETIMEDOUT'"'"'' meson.build
    fi
fi

# Include package release in version string so Chromium invalidates
# its GPU cache; otherwise it can cause pages to render incorrectly.
echo "${MESA_VERSION}-bc250.${VERSION}" >VERSION

step "Configure Mesa 64-bit build"
if [[ -d build64 ]]; then
    echo "Removing old 64-bit build directory"
    rm -rf build64
fi

meson setup build64 \
    -Dvulkan-drivers=amd \
    -Dgallium-drivers=radeonsi \
    -Dvideo-codecs=all \
    -Dvulkan-layers=device-select,overlay \
    -Dplatforms=x11,wayland \
    -Dglx=disabled \
    -Dllvm=disabled \
    -Dgles1=disabled \
    -Dbuildtype=release \
    -Dprefix="$MESA_PREFIX" \
    -Dlibdir=lib

step "Build Mesa 64-bit"
ninja -C build64

step "Install Mesa 64-bit to ${MESA_PREFIX}"
sudo ninja -C build64 install

step "Configure Mesa 32-bit build"
CROSS_FILE="/usr/share/meson/cross/lib32"
if [[ ! -f "$CROSS_FILE" ]]; then
    echo "Warning: meson cross file for lib32 not found at $CROSS_FILE; skipping 32-bit build."
    echo "32-bit Vulkan apps will use the stock unpatched driver."
else
    if [[ -d build32 ]]; then
        echo "Removing old 32-bit build directory"
        rm -rf build32
    fi

    meson setup build32 \
        --cross-file "$CROSS_FILE" \
        -Dvulkan-drivers=amd \
        -Dgallium-drivers=radeonsi \
        -Dvideo-codecs=all \
        -Dvulkan-layers=device-select,overlay \
        -Dplatforms=x11,wayland \
        -Dglx=disabled \
        -Dllvm=disabled \
        -Dgles1=disabled \
        -Dbuildtype=release \
        -Dprefix="$MESA_PREFIX" \
        -Dlibdir=lib32

    step "Build Mesa 32-bit"
    ninja -C build32

    step "Install Mesa 32-bit to ${MESA_PREFIX}"
    sudo ninja -C build32 install
fi

step "Set VK_DRIVER_FILES environment variable"
# Both 64-bit and 32-bit ICDs are patched. If 32-bit build was skipped,
# fall back to the stock 32-bit ICD so 32-bit Vulkan processes keep working.
PATCHED_ICD_64="${MESA_PREFIX}/share/vulkan/icd.d/radeon_icd.x86_64.json"
PATCHED_ICD_32="${MESA_PREFIX}/share/vulkan/icd.d/radeon_icd.i686.json"
STOCK_32BIT_ICD="/usr/share/vulkan/icd.d/radeon_icd.i686.json"

if [[ -f "$PATCHED_ICD_32" ]]; then
    VK_DRIVER_FILES_VALUE="${PATCHED_ICD_64}:${PATCHED_ICD_32}"
elif [[ -f "$STOCK_32BIT_ICD" ]]; then
    echo "Warning: patched 32-bit ICD not found; 32-bit Vulkan apps will use stock unpatched driver."
    VK_DRIVER_FILES_VALUE="${PATCHED_ICD_64}:${STOCK_32BIT_ICD}"
else
    echo "Warning: no 32-bit ICD found at all; 32-bit Vulkan apps may not find a driver."
    VK_DRIVER_FILES_VALUE="$PATCHED_ICD_64"
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
echo "   Mesh shader mode: ${MESH_MODE}"
echo "   Mesa version: ${MESA_VERSION}"
echo "   Installed to: ${MESA_PREFIX}"
echo "   VK_DRIVER_FILES set to: ${VK_DRIVER_FILES_VALUE}"
if [[ -f "$PATCHED_ICD_32" ]]; then
    echo "   32-bit: patched (async compute + FSR4 active)"
else
    echo "   32-bit: stock (unpatched — async compute + FSR4 NOT active)"
fi
echo ""
if [[ "$MESH_MODE" == "mastag" ]]; then
    echo "   To enable mesh/task shaders per-game, set:"
    echo "     RADV_GFX103=1"
else
    echo "   Native mesh shaders (MESH only, no TASK) are always available."
    echo "   No RADV_GFX103 env var needed."
fi
echo ""
echo "   Reboot required for VK_DRIVER_FILES to take effect."
