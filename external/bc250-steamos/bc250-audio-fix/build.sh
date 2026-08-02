#!/bin/bash
# Build the patched amdgpu.ko against the RUNNING kernel — README runbook
# ("Rebuilding after a SteamOS update") steps 3-8 as code, with every step's
# postcondition asserted. Steps 1-2 stay manual (fetch Valve's source for the
# running kernel, extract the dep packages into deps/); this script verifies
# their results and refuses to continue on any mismatch.
#
#   ./build.sh [--cg|--cg-unvalidated] [--prepare-only]
#              [--allow-missing-symvers] [kernel-tree]
#
# --prepare-only stops after producing an exact external-module Kbuild tree;
# AIC8800 uses this when Valve omitted the matching headers package.
# --allow-missing-symvers is the AIC8800-only fast path. It requires
# --prepare-only and is safe only when CONFIG_MODVERSIONS is disabled.
#
# --cg applies the GFX-only clock-gating patch (bc250-cg-flags.patch, idle
# power) — navi1x-validated, EXPERIMENTAL, off by default. --cg-unvalidated
# adds bc250-cg-flags-unvalidated.patch on top (MC/SDMA/ATHUB/HDP/NBIO on
# unvalidated register maps — can black-screen; bisect with amdgpu.cg_mask).
#
# Run on the BC-250 itself, as the normal user: the running kernel's
# /proc/config.gz and `uname -r` are the ground truth everything is checked
# against. On success amdgpu.ko.zst here is replaced — but only after the
# fresh module passes the same guards install.sh runs (check-module.sh).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REL=$(uname -r)

die()  { echo "FATAL: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

WITH_CG=0
WITH_CG_UNVAL=0
PREPARE_ONLY=0
ALLOW_MISSING_SYMVERS=0
ARGS=()
for a in "$@"; do
    case "$a" in
        --cg)             WITH_CG=1 ;;
        --cg-unvalidated) WITH_CG=1; WITH_CG_UNVAL=1 ;;  # implies --cg
        --prepare-only)   PREPARE_ONLY=1 ;;
        --allow-missing-symvers) ALLOW_MISSING_SYMVERS=1 ;;
        *)                ARGS+=("$a") ;;
    esac
done
[ "${#ARGS[@]}" -le 1 ] || die "usage: $0 [--cg|--cg-unvalidated] [--prepare-only] [--allow-missing-symvers] [kernel-tree]"
[ "$ALLOW_MISSING_SYMVERS" = 0 ] || [ "$PREPARE_ONLY" = 1 ] \
    || die "--allow-missing-symvers requires --prepare-only"
TREE_ARG=${ARGS[0]:-$HERE/valve-kernel}
TREE=$(cd "$TREE_ARG" 2>/dev/null && pwd) || die "kernel tree not found: $TREE_ARG"

step "preflight"
[ -r /proc/config.gz ] || die "no /proc/config.gz — run this on the BC-250, not a dev machine"
[ "$(id -u)" != 0 ] || die "build as the normal user; privileged prerequisite and install steps use sudo"
"$HERE/ensure-build-prereqs.sh"
grep -q '^VERSION' "$TREE/Makefile" 2>/dev/null || die "$TREE is not a kernel tree"

# sha embedded in the running release, e.g. ...-g57ac0765fe0d
case "$REL" in
    *-g*) SHA=${REL##*-g} ;;
    *)    die "cannot find -g<sha> suffix in '$REL'" ;;
esac

# The tree's .git may be live or parked (README step 5b). Find it to verify
# the checked-out commit matches the running kernel — the benign-looking
# mismatch here is what turns into a vermagic reject at boot.
PARKED=$TREE-dot-git
[ -d "$TREE/.git" ] && [ -d "$PARKED" ] && die "both $TREE/.git and $PARKED exist — resolve by hand first"
if   [ -d "$TREE/.git" ]; then GITDIR=$TREE/.git
elif [ -d "$PARKED" ];    then GITDIR=$PARKED
else die "no .git for $TREE (live or parked at $PARKED) — need it to verify the checked-out commit"
fi
FULLSHA=$(git --git-dir="$GITDIR" rev-parse HEAD)
[[ "$FULLSHA" == "$SHA"* ]] || die "tree is at $FULLSHA but running kernel is -g$SHA — fetch and check out the matching source (runbook step 1)"
echo "tree commit matches running kernel: $SHA"

step "build environment (runbook step 3)"
# build-env.sh fails loudly if pahole/bc are missing — pahole invisible to
# Kconfig means BTF and with it CONFIG_SCHED_CLASS_EXT get dropped SILENTLY.
# shellcheck source=bc250-audio-fix/build-env.sh
source "$HERE/build-env.sh"
# Ambient cross-build or output-directory settings would silently prepare a
# tree that differs from the native running kernel.
unset LOCALVERSION KERNELRELEASE KBUILD_OUTPUT ARCH SRCARCH CROSS_COMPILE LLVM LLVM_IAS KCONFIG_CONFIG

step "park .git so setlocalversion can't append -dirty (runbook step 5b)"
if [ -d "$TREE/.git" ]; then
    mv "$TREE/.git" "$PARKED"
    echo "parked $TREE/.git -> $PARKED"
else
    echo "already parked: $PARKED"
fi
echo "-g$SHA" > "$TREE/localversion.30-scm"

FULL_BUILD_REQUIRED=$TREE/.bc250-full-build-required
FULL_BUILD_STAMP=$TREE/.bc250-full-build-stamp
FULL_BUILD_PROGRESS=$TREE/.bc250-full-build-in-progress
if [ -f "$FULL_BUILD_REQUIRED" ]; then
    if ! git --git-dir="$GITDIR" --work-tree="$TREE" diff --quiet HEAD -- . \
        && [ "$TREE" != "$HERE/valve-kernel" ] \
        && [ ! -f "$TREE/.bc250-managed-tree" ]; then
        die "$TREE has tracked changes and is not a toolkit-managed tree; refusing to discard them for the full build"
    fi
    git --git-dir="$GITDIR" --work-tree="$TREE" checkout -qf "$FULLSHA"
fi

step "configure from the running kernel (runbook step 4)"
cd "$TREE"
zcat /proc/config.gz > .config.running
cp .config.running .config
make olddefconfig
grep -q '^CONFIG_SCHED_CLASS_EXT=y' .config \
    || die "CONFIG_SCHED_CLASS_EXT lost in olddefconfig — pahole/BTF problem (see README): refusing to build an ABI-incompatible module"
echo "CONFIG_SCHED_CLASS_EXT=y survived olddefconfig"

step "pin the release string (runbook step 5a)"
BASE=$(make -s kernelversion)
[[ "$REL" == "$BASE"* ]] || die "running kernel '$REL' does not start with tree version '$BASE' — wrong source tree"
MIDDLE=${REL#"$BASE"}       # e.g. -1-neptune-616-g<sha>
MIDDLE=${MIDDLE%-g"$SHA"}   # e.g. -1-neptune-616
rm -f localversion.10-pkgrel localversion.20-pkgname
if [[ "$MIDDLE" == *-neptune-616 ]]; then
    # match the Arch packaging's file split (cosmetic — setlocalversion just
    # concatenates localversion* in lexical order)
    echo "${MIDDLE%-neptune-616}" > localversion.10-pkgrel
    echo "-neptune-616"           > localversion.20-pkgname
elif [ -n "$MIDDLE" ]; then
    echo "$MIDDLE" > localversion.10-pkgrel
fi
KREL=$(make -s kernelrelease)
[ "$KREL" = "$REL" ] || die "kernelrelease '$KREL' != running '$REL' — localversion pinning failed"
echo "kernelrelease matches: $KREL"

step "Module.symvers (runbook step 6)"
if [ -f "$FULL_BUILD_REQUIRED" ]; then
    CONFIG_DRIFT=$(scripts/diffconfig .config.running .config) \
        || die "could not compare the running and prepared kernel configs"
    [ -z "$CONFIG_DRIFT" ] \
        || die "olddefconfig changed the running kernel configuration; refusing an ABI-uncertain full build: $CONFIG_DRIFT"
fi
rm -f .config.running
CONFIG_HASH=$(sha256sum .config | awk '{print $1}')
FINGERPRINT=$(printf '%s\n%s\n%s\n' "$REL" "$FULLSHA" "$CONFIG_HASH")

verify_symvers() {
    [ -s Module.symvers ] || return 1
    awk -F '\t' '
        NF >= 4 && $3 == "vmlinux" { builtin=1 }
        NF >= 4 && $3 != "vmlinux" { modular=1 }
        END { exit !(builtin && modular) }
    ' Module.symvers
}

if [ -f "$FULL_BUILD_REQUIRED" ]; then
    CACHED=
    if [ -s "$FULL_BUILD_STAMP" ] \
        && [ "$(cat "$FULL_BUILD_STAMP")" = "$FINGERPRINT" ] \
        && verify_symvers; then
        CACHED=1
        echo "reusing full-build Module.symvers for $REL"
    fi

    if [ -z "$CACHED" ] \
        && [ "$PREPARE_ONLY" = 1 ] \
        && [ "$ALLOW_MISSING_SYMVERS" = 1 ] \
        && grep -qx '# CONFIG_MODVERSIONS is not set' .config; then
        rm -f Module.symvers "$FULL_BUILD_STAMP"
        SYMVERS_OPTIONAL=1
        echo "exact headers are unavailable; preparing the Wi-Fi Kbuild tree without Module.symvers"
        echo "AIC8800 will defer exported-symbol checks to the running kernel"
    elif [ -z "$CACHED" ]; then
        for tool in make gcc ld ar nm objcopy objdump strip perl python3 cpio flex bison msgfmt; do
            command -v "$tool" >/dev/null || die "$tool is required for the full kernel-build fallback"
        done

        MIN_GB=${FULL_BUILD_MIN_FREE_GB:-40}
        [[ "$MIN_GB" =~ ^[0-9]+$ ]] || die "FULL_BUILD_MIN_FREE_GB must be a non-negative integer"
        FREE_KB=$(df -Pk "$TREE" | awk 'NR == 2 { print $4 }')
        [ -n "$FREE_KB" ] || die "could not determine free space for $TREE"
        [ "$FREE_KB" -ge "$((MIN_GB * 1024 * 1024))" ] \
            || die "full kernel build needs about ${MIN_GB} GiB free (override with FULL_BUILD_MIN_FREE_GB)"

        JOBS=${FULL_BUILD_JOBS:-$(nproc)}
        [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "FULL_BUILD_JOBS must be a positive integer"
        if [ -z "${FULL_BUILD_JOBS:-}" ] && [ "$JOBS" -gt 8 ]; then
            JOBS=8
        fi

        if [ -s "$FULL_BUILD_PROGRESS" ] \
            && [ "$(cat "$FULL_BUILD_PROGRESS")" = "$FINGERPRINT" ]; then
            echo "resuming the interrupted full kernel build"
        else
            make clean
            printf '%s' "$FINGERPRINT" > "$FULL_BUILD_PROGRESS"
        fi

        echo "WARNING: exact headers are unavailable; building the complete kernel."
        echo "         This can take hours and use tens of GiB (jobs: $JOBS)."
        make -j"$JOBS" all
        verify_symvers || die "full build did not produce a complete Module.symvers"
        [ "$(cat include/config/kernel.release)" = "$REL" ] \
            || die "full build generated the wrong kernel release"

        cp Module.symvers .bc250-Module.symvers.saved
        make clean
        mv .bc250-Module.symvers.saved Module.symvers
        printf '%s' "$FINGERPRINT" > "$FULL_BUILD_STAMP"
        rm -f "$FULL_BUILD_PROGRESS"
        echo "generated Module.symvers from the exact source"
    fi
fi

if [ -s Module.symvers ]; then
    echo "Module.symvers present ($(wc -l < Module.symvers | tr -d ' ') symbols)"
elif [ "${SYMVERS_OPTIONAL:-0}" = 1 ]; then
    echo "Module.symvers intentionally omitted for Wi-Fi"
else
    die "Module.symvers missing from tree root — the headers package is unavailable and no full-build fallback was requested"
fi

if [ "$PREPARE_ONLY" = 1 ]; then
    step "modules_prepare + config re-verify"
    make -j"$(nproc)" modules_prepare
    grep -q '^#define CONFIG_SCHED_CLASS_EXT 1' include/generated/autoconf.h \
        || die "CONFIG_SCHED_CLASS_EXT missing from autoconf.h after modules_prepare"
    grep -qF "\"$REL\"" include/generated/utsrelease.h \
        || die "utsrelease.h does not carry $REL"
    if [ "${SYMVERS_OPTIONAL:-0}" = 1 ]; then
        grep -qx '# CONFIG_MODVERSIONS is not set' .config \
            || die "CONFIG_MODVERSIONS changed during modules_prepare"
        ! grep -q '^CONFIG_MODVERSIONS=' include/config/auto.conf \
            || die "CONFIG_MODVERSIONS unexpectedly enabled during modules_prepare"
    fi
    echo "prepared exact Kbuild tree: $TREE"
    exit 0
fi

step "reset patched files to pristine before applying the patch stack"
# This tree is reused across runs (fetch-sources.sh skips re-checkout when
# already at the right kernel commit) for speed. If a vendored patch's
# *content* changes between runs -- not just the kernel commit -- the file
# left over from a previous build can be in a state that neither applies
# nor reverses cleanly against the new patch text ("tree has drifted").
# Reset exactly the files our patch stack touches to their pristine
# tree-checked-out state first, so patch application is deterministic no
# matter what a previous run left behind.
git --git-dir="$PARKED" --work-tree="$TREE" checkout -f -- \
    drivers/gpu/drm/amd/pm/swsmu/smu11/cyan_skillfish_ppt.c \
    drivers/gpu/drm/amd/display/dc/clk_mgr/dcn201/dcn201_clk_mgr.c \
    drivers/gpu/drm/amd/display/dc/clk_mgr/clk_mgr.c

step "apply DP-audio patch (runbook step 7)"
# SteamOS 3.8.x (6.16) needs both hunks; 3.9.x (6.18) already carries the
# clk_mgr DCN 2.01 reorder upstream, leaving only the dcn201
# spread-spectrum-state hunk. New kernel major: check which hunks are upstream
# before adding a variant here.
case "$BASE" in
    6.16.*) PATCH=$HERE/bc250-dp-audio-clock-6.16.patch ;;
    6.18.*) PATCH=$HERE/bc250-dp-audio-clock-6.18.patch ;;
    *)      die "no DP-audio patch variant for kernel $BASE — check which hunks are already upstream, then add a case above" ;;
esac
echo "kernel $BASE -> $(basename "$PATCH")"
if patch -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
    echo "patch already applied"
elif patch -p1 --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
    patch -p1 -s < "$PATCH"
    echo "patch applied"
else
    die "patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
fi

step "apply Cyan Skillfish GPU telemetry patch"
METRICS_PATCH=$HERE/bc250-cyan-skillfish-gpu-telemetry.patch

if patch -p1 -R --dry-run -s -f < "$METRICS_PATCH" >/dev/null 2>&1; then
    echo "GPU telemetry patch already applied"
elif patch -p1 --dry-run -s -f < "$METRICS_PATCH" >/dev/null 2>&1; then
    patch -p1 -s < "$METRICS_PATCH"
    echo "GPU telemetry patch applied"
else
    die "GPU telemetry patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
fi

GFXCLK_PATCH=$HERE/bc250-cyan-skillfish-gfxclk.patch
if patch -p1 -R --dry-run -s -f < "$GFXCLK_PATCH" >/dev/null 2>&1; then
    echo "GPU clock query patch already applied"
elif patch -p1 --dry-run -s -f < "$GFXCLK_PATCH" >/dev/null 2>&1; then
    patch -p1 -s < "$GFXCLK_PATCH"
    echo "GPU clock query patch applied"
else
    die "GPU clock query patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
fi

step "apply Cyan Skillfish 8-core (Robin 3.00) per-core metrics patch"
# Reads real per-core power/temp/freq from the PMSTATUSLOG SMU table via direct
# PCIe register access on Robin 3.00 BIOS + 8c/16t (CPU Core Unlock) systems;
# falls back to the stock 6-core metrics table (-ENODEV) on 6c/12t or other
# BIOS/SMU versions, so this is safe to apply unconditionally.
EIGHTCORE_PATCH=$HERE/bc250-cyan-skillfish-8core-metrics.patch
if patch -p1 -R --dry-run -s -f < "$EIGHTCORE_PATCH" >/dev/null 2>&1; then
    echo "8-core metrics patch already applied"
elif patch -p1 --dry-run -s -f < "$EIGHTCORE_PATCH" >/dev/null 2>&1; then
    patch -p1 -s < "$EIGHTCORE_PATCH"
    echo "8-core metrics patch applied"
else
    die "8-core metrics patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
fi

step "clock-gating patches (BC-250 idle power) — EXPERIMENTAL, opt-in"
# Two layers, both off by default (a leftover copy from a previous build is
# actively reversed, not tolerated):
#   bc250-cg-flags.patch              --cg              GFX MGCG/CGCG only.
#                                                       navi1x-validated path.
#   bc250-cg-flags-unvalidated.patch  --cg-unvalidated  MC/SDMA/ATHUB/HDP/NBIO
#                                                       on unvalidated register
#                                                       maps — can black-screen
#                                                       the box; bisect at boot
#                                                       with amdgpu.cg_mask.
# Layer 2's cg_flags hunk sits after external_rev_id (disjoint from layer 1),
# but to keep the tree self-consistent the order is fixed: apply 1 then 2,
# reverse 2 then 1. Version-independent code; if a kernel bump makes a hunk
# fail, they are small — refresh against the new tree.
CGPATCH=$HERE/bc250-cg-flags.patch
CGPATCH_UNVAL=$HERE/bc250-cg-flags-unvalidated.patch

apply_patch() {  # $1=patch file  $2=label
    if patch -p1 -R --dry-run -s -f < "$1" >/dev/null 2>&1; then
        echo "$2 already applied"
    elif patch -p1 --dry-run -s -f < "$1" >/dev/null 2>&1; then
        patch -p1 -s < "$1"; echo "$2 applied"
    else
        die "$2 neither applies nor reverses cleanly — tree has drifted; inspect by hand"
    fi
}
reverse_if_present() {  # $1=patch file  $2=label
    if patch -p1 -R --dry-run -s -f < "$1" >/dev/null 2>&1; then
        patch -p1 -R -s < "$1"; echo "$2 REVERSED (leftover from a previous build)"
    elif patch -p1 --dry-run -s -f < "$1" >/dev/null 2>&1; then
        : # pristine w.r.t. this layer — nothing to do
    else
        die "tree in unknown state w.r.t. $2 (neither applied nor pristine) — inspect by hand"
    fi
}

if [ "$WITH_CG_UNVAL" = 1 ]; then
    apply_patch "$CGPATCH"       "cg-flags (GFX)"
    apply_patch "$CGPATCH_UNVAL" "cg-flags-unvalidated (MC/SDMA/ATHUB/NBIO)"
    echo "WARNING: unvalidated CG layer applied — if the display goes dark, boot with"
    echo "         amdgpu.cg_mask=0x5 (GFX-only) and bisect from there; cg_mask=0 = stock."
elif [ "$WITH_CG" = 1 ]; then
    reverse_if_present "$CGPATCH_UNVAL" "cg-flags-unvalidated"   # drop layer 2 before touching layer 1
    apply_patch        "$CGPATCH"       "cg-flags (GFX)"
else
    reverse_if_present "$CGPATCH_UNVAL" "cg-flags-unvalidated"   # layer 2 first (it stacks on layer 1)
    reverse_if_present "$CGPATCH"       "cg-flags (GFX)"
    echo "clock-gating: not applied (opt in with --cg, or --cg-unvalidated for the experimental MC/SDMA layer)"
fi

step "modules_prepare + config re-verify (runbook step 7)"
make -j"$(nproc)" modules_prepare
grep -q '^#define CONFIG_SCHED_CLASS_EXT 1' include/generated/autoconf.h \
    || die "CONFIG_SCHED_CLASS_EXT missing from autoconf.h after modules_prepare — syncconfig rewrote the config behind your back; check pahole"
grep -qF "\"$REL\"" include/generated/utsrelease.h \
    || die "utsrelease.h does not carry $REL — vermagic would be wrong"
echo "autoconf.h and utsrelease.h verified"

step "build amdgpu (runbook step 7)"
# unconditional clean: syncconfig can regenerate auto.conf without touching
# the include/config/ stamp files, so stale objects would NOT rebuild (README)
make M=drivers/gpu/drm/amd/amdgpu clean
make -j"$(nproc)" M=drivers/gpu/drm/amd/amdgpu modules
KO=drivers/gpu/drm/amd/amdgpu/amdgpu.ko
[ -f "$KO" ] || die "build produced no $KO"

step "package + verify (runbook step 8)"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
cp "$KO" "$OUT/amdgpu.ko"
strip --strip-debug "$OUT/amdgpu.ko"
zstd -19 -q -f "$OUT/amdgpu.ko" -o "$OUT/amdgpu.ko.zst"

# Same guards install.sh runs — fail HERE, at build time, not standing at the
# console with steamos-readonly disabled. Build-time is strict: exit 2
# ("could not check") is also fatal.
"$HERE/check-module.sh" "$OUT/amdgpu.ko.zst" "$REL" \
    || die "module failed guard checks — NOT replacing $HERE/amdgpu.ko.zst"

mv -f "$OUT/amdgpu.ko.zst" "$HERE/amdgpu.ko.zst"
echo
echo "OK — $HERE/amdgpu.ko.zst built and verified for $REL."
echo "Next: sudo $HERE/install.sh"
