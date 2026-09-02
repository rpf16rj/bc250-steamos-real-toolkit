#!/bin/bash
# Build the patched amdgpu.ko against the RUNNING kernel — README runbook
# ("Rebuilding after a SteamOS update") steps 3-8 as code, with every step's
# postcondition asserted. Steps 1-2 stay manual (fetch Valve's source for the
# running kernel, extract the dep packages into deps/); this script verifies
# their results and refuses to continue on any mismatch.
#
#   ./build.sh [--prepare-only]
#              [--allow-missing-symvers] [kernel-tree]
#
# --prepare-only stops after producing an exact external-module Kbuild tree;
# AIC8800 uses this when Valve omitted the matching headers package.
# --allow-missing-symvers is the AIC8800-only fast path. It requires
# --prepare-only and is safe only when CONFIG_MODVERSIONS is disabled.
#
# --gfx1013 applies the GFX1013 compute queue fix patches (3 patches from
# bc250-gfx1013-fix): repairs compute queue lifecycle on BC-250 for async
# compute support on BC-250. When --gfx1013 is used alone, audio fix
# patches are NOT applied. Use --gfx1013 --audio to apply both sets of patches.
# --vrr applies the VRR PCON FreeSync fallback + range extending patch.
# --allm applies the ALLM-via-DP patch (HF-VSIF for DP-to-HDMI PCON).
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

# modules_prepare builds host-side tools (notably tools/bpf/resolve_btfids,
# needed when CONFIG_DEBUG_INFO_BTF_MODULES is set) against tools/lib/bpf/,
# whose Makefile hardcodes -Werror with no WERROR=0 escape hatch (unlike its
# sibling tools/lib/{subcmd,api}/Makefile, which already guard it). libbpf.c's
# kallsyms/path-resolution helpers trip -Wdiscarded-qualifiers on some
# gcc/glibc combinations (varies with the exact kernel commit fetched for the
# running release, and the host toolchain snapshot), turning a harmless
# warning in a build-only helper binary into a fatal error that aborts the
# whole module build before amdgpu is even touched. Relax -Werror for this
# host tool only; it has no bearing on the compiled amdgpu.ko.
relax_libbpf_host_tool_werror() {
    local mk="tools/lib/bpf/Makefile"
    [ -f "$mk" ] || return 0
    grep -q '^override CFLAGS += -Werror -Wall$' "$mk" || return 0
    sed -i 's/^override CFLAGS += -Werror -Wall$/override CFLAGS += -Wall/' "$mk"
    echo "relaxed -Werror in tools/lib/bpf/Makefile (host-tool build only, does not affect amdgpu.ko)"
}

WITH_GFX1013=0
WITH_AUDIO=0
WITH_VRR=0
WITH_ALLM=0
NO_AUDIO_CLOCK=0
NO_SS=0
NO_TELEMETRY=0
NO_TTM=0
NO_SCLK=0
NO_KFD=0
NO_FRL_HP=0
NO_YCBCR444=0
PREPARE_ONLY=0
ALLOW_MISSING_SYMVERS=0
ARGS=()
for a in "$@"; do
    case "$a" in
        --gfx1013)        WITH_GFX1013=1 ;;
        --audio)          WITH_AUDIO=1 ;;
        --vrr)            WITH_VRR=1 ;;
        --allm)           WITH_ALLM=1 ;;
        --no-audio-clock) NO_AUDIO_CLOCK=1 ;;
        --no-ss)          NO_SS=1 ;;
        --no-telemetry)   NO_TELEMETRY=1 ;;
        --no-ttm)         NO_TTM=1 ;;
        --no-sclk)        NO_SCLK=1 ;;
        --no-kfd)         NO_KFD=1 ;;
        --no-frl-hp)      NO_FRL_HP=1 ;;
        --no-ycbcr444)    NO_YCBCR444=1 ;;
        --prepare-only)   PREPARE_ONLY=1 ;;
        --allow-missing-symvers) ALLOW_MISSING_SYMVERS=1 ;;
        *)                ARGS+=("$a") ;;
    esac
done

# Default: apply audio fix patches unless --gfx1013 is used alone
if [ "$WITH_GFX1013" = 1 ] && [ "$WITH_AUDIO" = 0 ]; then
    WITH_AUDIO=0
else
    WITH_AUDIO=1
fi
[ "${#ARGS[@]}" -le 1 ] || die "usage: $0 [--prepare-only] [--allow-missing-symvers] [kernel-tree]"
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
# Clean stale kconfig artifacts — if the tree was previously built with a
# different flex/bison, the generated .o files won't link (undefined refs to
# zconf_fopen, yylineno, cur_filename, etc). Force regeneration.
rm -f scripts/kconfig/*.o scripts/kconfig/conf \
      scripts/kconfig/lexer.lex.c scripts/kconfig/parser.tab.[ch]
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
    relax_libbpf_host_tool_werror
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
if [ "$WITH_AUDIO" = 1 ]; then
    git --git-dir="$PARKED" --work-tree="$TREE" checkout -f -- \
        drivers/gpu/drm/amd/pm/swsmu/smu11/cyan_skillfish_ppt.c \
        drivers/gpu/drm/amd/pm/swsmu/inc/pmfw_if/smu11_driver_if_cyan_skillfish.h \
        drivers/gpu/drm/amd/display/dc/clk_mgr/dcn201/dcn201_clk_mgr.c \
        drivers/gpu/drm/amd/display/dc/clk_mgr/clk_mgr.c \
        drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm.c
fi
if [ "$WITH_GFX1013" = 1 ]; then
    git --git-dir="$PARKED" --work-tree="$TREE" checkout -f -- \
        drivers/gpu/drm/amd/amdgpu/gmc_v10_0.c \
        drivers/gpu/drm/amd/amdgpu/amdgpu_amdkfd.c \
        drivers/gpu/drm/amd/amdkfd/kfd_chardev.c \
        drivers/gpu/drm/amd/amdkfd/kfd_device_queue_manager.c \
        drivers/gpu/drm/amd/amdkfd/kfd_device_queue_manager.h
fi

# 0007 TTM NULL-page guard, 0008 SCLK range are always applied
git --git-dir="$PARKED" --work-tree="$TREE" checkout -f -- \
    drivers/gpu/drm/amd/amdgpu/amdgpu_ttm.c \
    drivers/gpu/drm/amd/pm/swsmu/smu11/cyan_skillfish_ppt.c \
    drivers/gpu/drm/amd/pm/swsmu/inc/pmfw_if/smu11_driver_if_cyan_skillfish.h \
    drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm.c \
    drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm_helpers.c \
    drivers/gpu/drm/amd/display/dc/core/dc_resource.c \
    drivers/gpu/drm/amd/display/dc/dio/dcn10/dcn10_stream_encoder.c \
    drivers/gpu/drm/amd/display/dc/dio/dcn20/dcn20_stream_encoder.h \
    drivers/gpu/drm/amd/display/dc/resource/dcn201/dcn201_resource.c \
    drivers/gpu/drm/amd/display/dc/link/protocols/link_dp_capability.c \
    drivers/gpu/drm/amd/display/dc/link/link_detection.c \
    drivers/gpu/drm/amd/display/dc/link/link_validation.c

if [ "$WITH_AUDIO" = 1 ]; then
    if [ "$NO_AUDIO_CLOCK" = 1 ]; then
        step "skipping DP-audio clock patch (--no-audio-clock requested)"
        # Reverse if leftover from a previous build
        case "$BASE" in
            6.16.*) PATCH=$HERE/bc250-dp-audio-clock-6.16.patch ;;
            6.18.*) PATCH=$HERE/bc250-dp-audio-clock-6.18.patch ;;
            7.2.*)  PATCH=$HERE/bc250-dp-audio-clock-6.18.patch ;;
            *)      PATCH= ;;
        esac
        if [ -n "$PATCH" ] && patch -p1 -R --dry-run --fuzz=3 -s -f < "$PATCH" >/dev/null 2>&1; then
            patch -p1 -R --fuzz=3 -s < "$PATCH"
            echo "DP-audio clock patch REVERSED (leftover from a previous build)"
        fi
    else
        step "apply DP-audio patch (runbook step 7)"
        # SteamOS 3.8.x (6.16) needs both hunks; 3.9.x (6.18) already carries the
        # clk_mgr DCN 2.01 reorder upstream, leaving only the dcn201
        # spread-spectrum-state hunk. New kernel major: check which hunks are upstream
        # before adding a variant here.
        case "$BASE" in
            6.16.*) PATCH=$HERE/bc250-dp-audio-clock-6.16.patch ;;
            6.18.*) PATCH=$HERE/bc250-dp-audio-clock-6.18.patch ;;
            7.2.*)  PATCH=$HERE/bc250-dp-audio-clock-6.18.patch ;;  # same hunk applies to 7.2
            *)      die "no DP-audio patch variant for kernel $BASE — check which hunks are already upstream, then add a case above" ;;
        esac
        echo "kernel $BASE -> $(basename "$PATCH")"
        if patch -p1 -R --dry-run --fuzz=3 -s -f < "$PATCH" >/dev/null 2>&1; then
            echo "patch already applied"
        elif patch -p1 --dry-run --fuzz=3 -s -f < "$PATCH" >/dev/null 2>&1; then
            patch -p1 --fuzz=3 -s < "$PATCH"
            echo "patch applied"
        else
            die "patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
        fi
    fi

    if [ "$NO_TELEMETRY" = 1 ]; then
        step "skipping Cyan Skillfish telemetry+cache patch (--no-telemetry requested)"
        case "$BASE" in
            7.2.*)  METRICS_PATCH=$HERE/bc250-cyan-skillfish-telemetry-cache-7.2.patch ;;
            *)      METRICS_PATCH=$HERE/bc250-cyan-skillfish-telemetry-cache.patch ;;
        esac
        if patch -p1 -R --dry-run --fuzz=3 -s -f < "$METRICS_PATCH" >/dev/null 2>&1; then
            patch -p1 -R --fuzz=3 -s < "$METRICS_PATCH"
            echo "Cyan Skillfish telemetry+cache patch REVERSED (leftover from a previous build)"
        fi
    else
        step "apply Cyan Skillfish consolidated telemetry + cache patch"
        case "$BASE" in
            7.2.*)  METRICS_PATCH=$HERE/bc250-cyan-skillfish-telemetry-cache-7.2.patch ;;
            *)      METRICS_PATCH=$HERE/bc250-cyan-skillfish-telemetry-cache.patch ;;
        esac

        if patch -p1 -R --dry-run --fuzz=3 -s -f < "$METRICS_PATCH" >/dev/null 2>&1; then
            echo "Cyan Skillfish telemetry+cache patch already applied"
        elif patch -p1 --dry-run --fuzz=3 -s -f < "$METRICS_PATCH" >/dev/null 2>&1; then
            patch -p1 --fuzz=3 -s < "$METRICS_PATCH"
            echo "Cyan Skillfish telemetry+cache patch applied"
        else
            die "Cyan Skillfish telemetry+cache patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
        fi
    fi

    if [ "$NO_SS" = 1 ]; then
        step "skipping DP spread spectrum disable patch (--no-ss requested)"
        DM_SS_PATCH=$HERE/bc250-dp-audio-dm-ignore-ss.patch
        if patch -p1 -R --dry-run --fuzz=3 -s -f < "$DM_SS_PATCH" >/dev/null 2>&1; then
            patch -p1 -R --fuzz=3 -s < "$DM_SS_PATCH"
            echo "DM spread spectrum patch REVERSED (leftover from a previous build)"
        fi
    else
        step "apply DP spread spectrum disable patch (amdgpu_dm)"
        DM_SS_PATCH=$HERE/bc250-dp-audio-dm-ignore-ss.patch
        if patch -p1 -R --dry-run --fuzz=3 -s -f < "$DM_SS_PATCH" >/dev/null 2>&1; then
            echo "DM spread spectrum patch already applied"
        elif patch -p1 --dry-run --fuzz=3 -s -f < "$DM_SS_PATCH" >/dev/null 2>&1; then
            patch -p1 --fuzz=3 -s < "$DM_SS_PATCH"
            echo "DM spread spectrum patch applied"
        else
            die "DM spread spectrum patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
        fi
    fi

fi

if [ "$WITH_VRR" = 1 ]; then
    step "apply VRR PCON FreeSync fallback + range extending patch (amdgpu_dm)"
    VRR_PATCH=$HERE/bc250-vrr-pcon-freesync.patch
    # Kernel 7.2+ already includes parse_amd_vsdb_cea_direct in upstream Valve kernel
    if grep -q 'parse_amd_vsdb_cea_direct' drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm.c 2>/dev/null; then
        echo "VRR PCON FreeSync patch already in kernel tree (upstream)"
    elif patch -p1 -R --dry-run --fuzz=3 -s -f < "$VRR_PATCH" >/dev/null 2>&1; then
        echo "VRR PCON FreeSync patch already applied"
    elif patch -p1 --dry-run --fuzz=3 -s -f < "$VRR_PATCH" >/dev/null 2>&1; then
        patch -p1 --fuzz=3 -s < "$VRR_PATCH"
        echo "VRR PCON FreeSync patch applied"
    else
        die "VRR PCON FreeSync patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
    fi
else
    step "skipping VRR PCON FreeSync patch (not requested)"
    VRR_PATCH=$HERE/bc250-vrr-pcon-freesync.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$VRR_PATCH" >/dev/null 2>&1; then
        patch -p1 -R --fuzz=3 -s < "$VRR_PATCH"
        echo "VRR PCON FreeSync patch REVERSED (leftover from a previous build)"
    fi
fi

if [ "$WITH_AUDIO" = 0 ]; then
    step "skipping audio fix patches (--audio not requested)"
fi

step "GFX1013 compute queue fix patches (async compute support)"
# Patches that repair compute queue lifecycle on BC-250. The mmio-pasid-route
# fix (0001) routes PASID TLB flushes through MMIO instead of KIQ for GFX1013,
# preventing soft lockups under sustained compute workloads. The vendored
# valve-kernel tree does NOT include this fix, so it must be applied here.
# Requires matching Mesa/RADV patches for full async compute functionality.
GFX1013_PATCHES=(
    "$HERE/0001-gfx1013-mmio-pasid-route.patch"
    "$HERE/0002-gfx1013-compute-gfxoff-guard.patch"
    "$HERE/0003-gfx1013-scoped-pasid-type0.patch"
)
if [ "$WITH_GFX1013" = 1 ]; then
    for p in "${GFX1013_PATCHES[@]}"; do
        if patch -p1 -R --dry-run --fuzz=3 -s -f < "$p" >/dev/null 2>&1; then
            echo "$(basename "$p") already applied"
        elif patch -p1 --dry-run --fuzz=3 -s -f < "$p" >/dev/null 2>&1; then
            patch -p1 --fuzz=3 -s < "$p"
            echo "$(basename "$p") applied"
        else
            die "$(basename "$p") neither applies nor reverses cleanly — tree has drifted; inspect by hand"
        fi
    done
else
    # Ensure GFX1013 patches are not present from a previous --gfx1013 build
    for p in "${GFX1013_PATCHES[@]}"; do
        if patch -p1 -R --dry-run --fuzz=3 -s -f < "$p" >/dev/null 2>&1; then
            patch -p1 -R --fuzz=3 -s < "$p"
            echo "$(basename "$p") REVERSED (leftover from a previous --gfx1013 build)"
        fi
    done
fi

if [ "$WITH_ALLM" = 1 ]; then
    step "apply ALLM-via-DP patch (HF-VSIF for DP-to-HDMI PCON)"
    ALLM_PATCH=$HERE/bc250-allm-via-dp.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$ALLM_PATCH" >/dev/null 2>&1; then
        echo "ALLM-via-DP patch already applied"
    elif patch -p1 --dry-run --fuzz=3 -s -f < "$ALLM_PATCH" >/dev/null 2>&1; then
        patch -p1 --fuzz=3 -s < "$ALLM_PATCH"
        echo "ALLM-via-DP patch applied"
    else
        die "ALLM-via-DP patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
    fi
else
    step "skipping ALLM-via-DP patch (not requested)"
    ALLM_PATCH=$HERE/bc250-allm-via-dp.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$ALLM_PATCH" >/dev/null 2>&1; then
        patch -p1 -R --fuzz=3 -s < "$ALLM_PATCH"
        echo "ALLM-via-DP patch REVERSED (leftover from a previous build)"
    fi
fi

if [ "$NO_FRL_HP" = 1 ]; then
    step "skipping PCON FRL hotplug preserve patch (--no-frl-hp requested)"
    FRL_HP_PATCH=$HERE/bc250-pcon-frl-hotplug-preserve.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$FRL_HP_PATCH" >/dev/null 2>&1; then
        patch -p1 -R --fuzz=3 -s < "$FRL_HP_PATCH"
        echo "PCON FRL hotplug preserve patch REVERSED (leftover from a previous build)"
    fi
else
    step "apply PCON FRL hotplug preserve patch (link_detection)"
    FRL_HP_PATCH=$HERE/bc250-pcon-frl-hotplug-preserve.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$FRL_HP_PATCH" >/dev/null 2>&1; then
        echo "PCON FRL hotplug preserve patch already applied"
    elif patch -p1 --dry-run --fuzz=3 -s -f < "$FRL_HP_PATCH" >/dev/null 2>&1; then
        patch -p1 --fuzz=3 -s < "$FRL_HP_PATCH"
        echo "PCON FRL hotplug preserve patch applied"
    else
        die "PCON FRL hotplug preserve patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
    fi
fi

if [ "$NO_TTM" = 1 ]; then
    step "skipping TTM NULL-page guard patch (--no-ttm requested)"
    TTM_PATCH=$HERE/bc250-ttm-null-page-guard.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$TTM_PATCH" >/dev/null 2>&1; then
        patch -p1 -R --fuzz=3 -s < "$TTM_PATCH"
        echo "TTM NULL-page guard patch REVERSED (leftover from a previous build)"
    fi
else
    step "apply TTM NULL-page guard patch (defensive)"
    TTM_PATCH=$HERE/bc250-ttm-null-page-guard.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$TTM_PATCH" >/dev/null 2>&1; then
        echo "TTM NULL-page guard already applied"
    elif patch -p1 --dry-run --fuzz=3 -s -f < "$TTM_PATCH" >/dev/null 2>&1; then
        patch -p1 --fuzz=3 -s < "$TTM_PATCH"
        echo "TTM NULL-page guard applied"
    else
        die "TTM NULL-page guard neither applies nor reverses cleanly — tree has drifted; inspect by hand"
    fi
fi

if [ "$NO_SCLK" = 1 ]; then
    step "skipping SCLK range patch (--no-sclk requested)"
    SCLK_PATCH=$HERE/bc250-sclk-range.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$SCLK_PATCH" >/dev/null 2>&1; then
        patch -p1 -R --fuzz=3 -s < "$SCLK_PATCH"
        echo "SCLK range patch REVERSED (leftover from a previous build)"
    fi
else
    step "apply Cyan Skillfish SCLK range patch (350-2230 MHz)"
    SCLK_PATCH=$HERE/bc250-sclk-range.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$SCLK_PATCH" >/dev/null 2>&1; then
        echo "SCLK range patch already applied"
    elif patch -p1 --dry-run --fuzz=3 -s -f < "$SCLK_PATCH" >/dev/null 2>&1; then
        patch -p1 --fuzz=3 -s < "$SCLK_PATCH"
        echo "SCLK range patch applied"
    else
        die "SCLK range patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
    fi
fi

if [ "$NO_KFD" = 1 ]; then
    step "skipping KFD flush-TLB-by-runlist patch (--no-kfd requested)"
    KFD_PATCH=$HERE/bc250-kfd-flush-tlb-by-runlist.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$KFD_PATCH" >/dev/null 2>&1; then
        patch -p1 -R --fuzz=3 -s < "$KFD_PATCH"
        echo "KFD flush-TLB-by-runlist patch REVERSED (leftover from a previous build)"
    fi
else
    step "apply KFD flush-TLB-by-runlist patch (opt-in ROCm/KFD workaround)"
    KFD_PATCH=$HERE/bc250-kfd-flush-tlb-by-runlist.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$KFD_PATCH" >/dev/null 2>&1; then
        echo "KFD flush-TLB-by-runlist patch already applied"
    elif patch -p1 --dry-run --fuzz=3 -s -f < "$KFD_PATCH" >/dev/null 2>&1; then
        patch -p1 --fuzz=3 -s < "$KFD_PATCH"
        echo "KFD flush-TLB-by-runlist patch applied"
    else
        die "KFD flush-TLB-by-runlist patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
    fi
fi

if [ "$NO_YCBCR444" = 1 ]; then
    step "skipping DP-HDMI YCbCr 4:4:4 deep color patch (--no-ycbcr444 requested)"
    YCBCR444_PATCH=$HERE/bc250-dp-hdmi-ycbcr444-deep-color.patch
    if patch -p1 -R --dry-run --fuzz=3 -s -f < "$YCBCR444_PATCH" >/dev/null 2>&1; then
        patch -p1 -R --fuzz=3 -s < "$YCBCR444_PATCH"
        echo "YCbCr 4:4:4 deep color patch REVERSED (leftover from a previous build)"
    fi
else
    step "apply DP-HDMI YCbCr 4:4:4 deep color patch (PCON color quality)"
    YCBCR444_PATCH=$HERE/bc250-dp-hdmi-ycbcr444-deep-color.patch
    YCBCR444_MAJOR=$(echo "$BASE" | cut -d. -f1)
    if [ "$YCBCR444_MAJOR" -lt 7 ]; then
        echo "skipping YCbCr 4:4:4 deep color patch (requires kernel 7.x; running $BASE)"
        # Reverse if leftover from a previous build on a different kernel
        if patch -p1 -R --dry-run --fuzz=3 -s -f < "$YCBCR444_PATCH" >/dev/null 2>&1; then
            patch -p1 -R --fuzz=3 -s < "$YCBCR444_PATCH"
            echo "YCbCr 4:4:4 deep color patch REVERSED (leftover from a previous build)"
        fi
    else
        if patch -p1 -R --dry-run --fuzz=3 -s -f < "$YCBCR444_PATCH" >/dev/null 2>&1; then
            echo "DP-HDMI YCbCr 4:4:4 deep color patch already applied"
        elif patch -p1 --dry-run --fuzz=3 -s -f < "$YCBCR444_PATCH" >/dev/null 2>&1; then
            patch -p1 --fuzz=3 -s < "$YCBCR444_PATCH"
            echo "DP-HDMI YCbCr 4:4:4 deep color patch applied"
        else
            die "DP-HDMI YCbCr 4:4:4 deep color patch neither applies nor reverses cleanly — tree has drifted; inspect by hand"
        fi
    fi
fi

step "modules_prepare + config re-verify (runbook step 7)"
relax_libbpf_host_tool_werror
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
JOBS=$(nproc)
if ! make -j"$JOBS" M=drivers/gpu/drm/amd/amdgpu modules 2>&1; then
    echo "==> build failed with -j$JOBS; retrying with -j1 (GCC 15.x ICE workaround)"
    make M=drivers/gpu/drm/amd/amdgpu clean
    if ! make -j1 M=drivers/gpu/drm/amd/amdgpu modules 2>&1; then
        die "amdgpu module build failed even with -j1 — see GCC bug: pop_scope/pop_file_scope ICE"
    fi
    echo "==> build succeeded with -j1 after retry"
fi
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
