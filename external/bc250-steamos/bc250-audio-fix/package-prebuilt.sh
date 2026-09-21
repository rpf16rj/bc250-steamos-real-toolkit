#!/bin/bash
# Package the built amdgpu.ko.zst as a prebuilt artifact for the EXACT running
# kernel, and optionally upload it to the rolling `prebuilt` GitHub release.
#
#   ./package-prebuilt.sh [--upload] [-- <build flags>]
#
# The flag manifest is read from prebuilt/amdgpu-<rel>.flags, which
# patch-driver.sh writes after every source build with the REAL effective
# signature — no manual flags needed. Flags after `--` are only a fallback
# for packaging a module built before that recording existed; they are
# normalized the same way (including the >=7.2 no-ss no-op rule).
#
# Produces in ./prebuilt/:
#   amdgpu-<uname -r>.ko.zst         the module
#   amdgpu-<uname -r>.ko.zst.sha256  checksum (sha256sum -c format)
#   amdgpu-<uname -r>.flags          normalized flag signature
#
# --upload uses gh (GitHub CLI) against tag `prebuilt`, creating it if needed.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REL=$(uname -r)
SRC=$HERE/amdgpu.ko.zst
OUT=$HERE/prebuilt
ASSET="amdgpu-${REL}"
REPO="rpf16rj/bc250-steamos-real-toolkit"
TAG="prebuilt"

[ -f "$SRC" ] || { echo "missing $SRC — run ./build.sh (via patch-driver.sh) first"; exit 1; }

UPLOAD=0
BUILD_FLAGS=()
for a in "$@"; do
    case "$a" in
        --upload) UPLOAD=1 ;;
        --)       ;;  # optional separator — remaining args are build flags anyway
        *)        BUILD_FLAGS+=("$a") ;;
    esac
done

# Prefer the signature recorded by patch-driver.sh at build time — it is the
# ground truth. Manual `-- <flags>` only when that file is missing.
if [ -f "$OUT/$ASSET.flags" ] && [ ${#BUILD_FLAGS[@]} -eq 0 ]; then
    sig=$(cat "$OUT/$ASSET.flags")
else
    # Same normalization as patch-driver.sh's kernel_flags_sig — keep in sync.
    sig=""
    for a in "${BUILD_FLAGS[@]:-}"; do
        case "$a" in
            --audio|--gfx1013|--dsc|--dsc-pcon|--vcn|--no-ss|--no-telemetry|--no-ttm|--no-sclk|--no-kfd) ;;
            *) continue ;;
        esac
        [ "$a" = "--dsc-pcon" ] && a=--dsc
        case " $sig " in *" ${a#--} "*) ;; *) sig="$sig ${a#--}" ;; esac
    done
    # Reorder into the canonical order used by kernel_flags_sig.
    canonical=""
    for k in audio gfx1013 dsc vcn no-ss no-telemetry no-ttm no-sclk no-kfd; do
        case " $sig " in *" $k "*) canonical="$canonical $k" ;; esac
    done
    sig="${canonical# }"
    # --no-ss is a no-op on >=7.2 (patch upstream, build.sh force-skips it) —
    # drop it so the signature matches what consumers compute.
    kmaj=$(uname -r | cut -d. -f1)
    kmin=$(uname -r | cut -d. -f2 | cut -d- -f1)
    if [ "$kmaj" -gt 7 ] 2>/dev/null || { [ "$kmaj" -eq 7 ] 2>/dev/null && [ "$kmin" -ge 2 ] 2>/dev/null; }; then
        sig=$(echo " $sig " | sed 's/ no-ss / /;s/^ //;s/ $//')
    fi
fi

mkdir -p "$OUT"
cp "$SRC" "$OUT/$ASSET.ko.zst"
(cd "$OUT" && sha256sum "$ASSET.ko.zst" > "$ASSET.ko.zst.sha256")
echo "$sig" > "$OUT/$ASSET.flags"

echo "packaged: $OUT/$ASSET.ko.zst"
echo "  flags:  ${sig:-<none>}"
echo "  sha256: $(cut -d' ' -f1 "$OUT/$ASSET.ko.zst.sha256")"

[ "$UPLOAD" = 1 ] || { echo; echo "to publish: $0 --upload -- ${BUILD_FLAGS[*]:-<flags>}"; exit 0; }

GH=gh
command -v gh >/dev/null || GH="$HOME/.local/bin/gh"
[ -x "$GH" ] || command -v "$GH" >/dev/null || { echo "gh CLI not found — install it or run gh auth login first"; exit 1; }

"$GH" release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
    || "$GH" release create "$TAG" --repo "$REPO" --title "Prebuilt amdgpu modules" \
       --notes "Prebuilt amdgpu.ko.zst per kernel release. Each asset carries a .flags manifest and .sha256; patch-driver.sh installs only an exact uname -r + flag-set match."
"$GH" release upload "$TAG" --repo "$REPO" --clobber \
    "$OUT/$ASSET.ko.zst" "$OUT/$ASSET.ko.zst.sha256" "$OUT/$ASSET.flags"
echo "uploaded to release '$TAG'"
