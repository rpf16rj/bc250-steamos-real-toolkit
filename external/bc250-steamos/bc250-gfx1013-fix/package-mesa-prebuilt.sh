#!/bin/bash
# Package the installed patched Mesa prefix as a prebuilt tarball and
# optionally upload it to the rolling `prebuilt` GitHub release.
#
#   ./package-mesa-prebuilt.sh [--upload] [--mastag-mesh|--native-mesh]
#
# Produces in ./prebuilt/:
#   mesa-<mesaver>-bc250.<toolkitver>-<meshmode>.tar.zst
#   <same>.sha256
#   <same>.flags          — manifest: mesa/mesh exact + glibc MINIMUM
#
# glibc is a minimum, not an exact match: a build linked against 2.41 runs
# on 2.43+ (glibc is forward-compatible). Keeping it out of the asset name
# lets a client on any glibc find the file; the manifest check rejects it
# when the user's glibc is older than the build's.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=$(<"${HERE}/VERSION")
MESA_PREFIX="/opt/bc250-gfx1013/${VERSION}"
OUT=$HERE/prebuilt
REPO="rpf16rj/bc250-steamos-real-toolkit"
TAG="prebuilt"

die() { echo "FATAL: $*" >&2; exit 1; }

[ -d "$MESA_PREFIX" ] || die "$MESA_PREFIX not found — run ./build-mesa.sh first"
[ -f "$MESA_PREFIX/share/vulkan/icd.d/radeon_icd.x86_64.json" ] \
    || die "no patched 64-bit ICD under $MESA_PREFIX — incomplete Mesa install?"
[ -d "$MESA_PREFIX/lib32" ] \
    || echo "warning: no lib32 in the prefix — 32-bit Vulkan apps will use stock Mesa"

UPLOAD=0
MESH_MODE=""
for a in "$@"; do
    case "$a" in
        --upload)      UPLOAD=1 ;;
        --mastag-mesh) MESH_MODE=mastag ;;
        --native-mesh) MESH_MODE=native ;;
        *)             die "unknown arg: $a" ;;
    esac
done
[ -n "$MESH_MODE" ] || die "mesh mode required: --mastag-mesh or --native-mesh (what was this prefix built with?)"

# Mesa version from the driver itself (the build writes it into VERSION's
# first line of the mesa tree); fall back to the build script's constant.
MESA_VER=$(sed -n 's/^MESA_VERSION=//p' "$HERE/build-mesa.sh" | head -n1)
# capture ldd fully first — `ldd | head` under pipefail dies on SIGPIPE
GLIBC_VER=$(ldd --version)
GLIBC_VER=$(echo "$GLIBC_VER" | grep -oE '[0-9]+\.[0-9]+' | head -n1)
[ -n "$MESA_VER" ] && [ -n "$GLIBC_VER" ] || die "could not determine mesa/glibc version"

ASSET="mesa-${MESA_VER}-bc250.${VERSION}-${MESH_MODE}"
mkdir -p "$OUT"

echo "==> packing $MESA_PREFIX → $OUT/$ASSET.tar.zst"
# -C / keeps the opt/bc250-gfx1013/<VERSION>/... paths absolute-inside-tar;
# --owner/group so the extracted tree is root-owned even though we read as
# the normal user (the prefix is world-readable).
tar --owner=root --group=root -C / -cf - "opt/bc250-gfx1013/${VERSION}" | zstd -19 -f -o "$OUT/$ASSET.tar.zst"

(cd "$OUT" && sha256sum "$ASSET.tar.zst" > "$ASSET.tar.zst.sha256")
cat > "$OUT/$ASSET.flags" <<EOF
mesa=$MESA_VER mesh=$MESH_MODE glibc=$GLIBC_VER lib32=$([ -d "$MESA_PREFIX/lib32" ] && echo yes || echo no)
EOF

echo "packaged: $OUT/$ASSET.tar.zst ($(du -h "$OUT/$ASSET.tar.zst" | cut -f1))"
echo "  flags:  $(cat "$OUT/$ASSET.flags")"

[ "$UPLOAD" = 1 ] || { echo; echo "to publish: $0 --upload --${MESH_MODE}-mesh"; exit 0; }

GH=gh
command -v gh >/dev/null || GH="$HOME/.local/bin/gh"
[ -x "$GH" ] || command -v "$GH" >/dev/null || die "gh CLI not found — install it or run gh auth login first"

"$GH" release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
    || "$GH" release create "$TAG" --repo "$REPO" --title "Prebuilt amdgpu modules" \
       --notes "Prebuilt amdgpu.ko.zst per kernel release and patched Mesa tarballs. patch-driver.sh / start.sh install only exact kernel+glibc+flag-set matches."
"$GH" release upload "$TAG" --repo "$REPO" --clobber \
    "$OUT/$ASSET.tar.zst" "$OUT/$ASSET.tar.zst.sha256" "$OUT/$ASSET.flags"
echo "uploaded to release '$TAG'"
