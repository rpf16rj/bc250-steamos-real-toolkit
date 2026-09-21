#!/bin/bash
# Single entry point: fetch sources, build, install — the full cycle after a
# SteamOS update. Run as the normal user; sudo is invoked for missing build
# prerequisites and installation.
#
#   ./patch-driver.sh [--gfx1013] [--audio] [--dsc] [--dsc-pcon] [--no-ss] [--no-telemetry] [--no-ttm] [--no-sclk] [--no-kfd] [kernel-tree]  (default: ./valve-kernel)
#   ./patch-driver.sh status
#   ./patch-driver.sh uninstall
#
# --gfx1013 is forwarded to build.sh (GFX1013 compute queue fix patches for
# async compute support on BC-250). When --gfx1013 is used alone, audio fix
# patches are NOT applied. Use --gfx1013 --audio to apply both sets of patches.
# --dsc applies the DCN201 DSC + PCON HDMI 2.1 patch pair (Display Stream
# Compression and HDMI 2.1 FRL PCON, both gated at runtime by
# amdgpu.bc250_hdmi21, on by default; amdgpu.bc250_hdmi21=0 disables them).
# --dsc-pcon is accepted as an alias for --dsc.
# --no-ss skips the DP spread spectrum disable patch (within --audio).
# --no-telemetry skips the Cyan Skillfish telemetry+cache patch (within --audio).
# --no-ttm skips the TTM NULL-page guard patch.
# --no-sclk skips the SCLK range patch.
# --no-kfd skips the KFD flush-TLB-by-runlist patch.
# --vcn applies the experimental VCN 2.0.3 ungate patch (direct MMIO bring-up;
# for ACL/clamp investigation only — not part of the stable feature set).
# --no-prebuilt forces a local source build even when a published prebuilt
# module matches the running kernel.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)

usage() {
    cat <<EOF
Usage: $0 [--gfx1013] [--audio] [--dsc] [--dsc-pcon] [--no-ss] [--no-telemetry] [--no-ttm] [--no-sclk] [--no-kfd] [--vcn] [--no-prebuilt] [kernel-tree]
       $0 status
       $0 uninstall

Run as the logged-in user. The build requests sudo if a SteamOS update removed
its host toolchain. Install and uninstall also request sudo for privileged
steps. Uninstall preserves source, downloads, and build output.
EOF
}

show_status() {
    local module rel resolved marker metrics_marker expected actual found=0 failed=0

    for module in /usr/lib/modules/*/updates/amdgpu.ko.zst; do
        [ -e "$module" ] || [ -L "$module" ] || continue
        found=1
        rel=${module#/usr/lib/modules/}
        rel=${rel%%/*}
        marker="/usr/lib/modules/$rel/updates/.bc250-audio-fix"
        metrics_marker="/usr/lib/modules/$rel/updates/.bc250-metrics-fix"
        if [ ! -f "$module" ] || [ -L "$module" ]; then
            echo "[bc250-audio] $rel: unsafe or incomplete override ($module)"
            failed=1
            continue
        fi
        if [ ! -f "$marker" ] || [ -L "$marker" ]; then
            echo "[bc250-audio] $rel: unmarked override requires ownership review"
            failed=1
            continue
        fi
        if resolved=$(modinfo -k "$rel" -F filename amdgpu 2>/dev/null) \
           && [[ "$resolved" == */updates/amdgpu.ko* ]]; then
            if [ -f "$metrics_marker" ] && [ ! -L "$metrics_marker" ]; then
                read -r expected < "$metrics_marker" || expected=
                actual=$(sha256sum "$module" | awk '{print $1}')
                if [[ "$expected" =~ ^[0-9a-f]{64}$ ]] && [ "$actual" = "$expected" ]; then
                    echo "[bc250-audio] $rel: installed, metrics-aware ($resolved)"
                else
                    echo "[bc250-audio] $rel: invalid metrics marker"
                    failed=1
                fi
            else
                echo "[bc250-audio] $rel: installed, legacy audio-only build"
                failed=1
            fi
        else
            echo "[bc250-audio] $rel: override present but not selected"
            failed=1
        fi
    done
    for marker in /usr/lib/modules/*/updates/.bc250-audio-fix \
                  /usr/lib/modules/*/updates/.bc250-metrics-fix; do
        [ -e "$marker" ] || [ -L "$marker" ] || continue
        module=${marker%/.bc250-audio-fix}
        module="${module%/.bc250-metrics-fix}/amdgpu.ko.zst"
        [ -e "$module" ] || { found=1; failed=1; echo "[bc250-audio] pending rollback marker: $marker"; }
    done
    if [ "$found" = 0 ]; then
        echo "[bc250-audio] state: not-installed"
        return 1
    fi
    [ "$failed" = 0 ] \
        && echo "[bc250-audio] state: installed" \
        || echo "[bc250-audio] state: incomplete"
    return "$failed"
}

confirm_legacy_adoption() {
    local answer
    [ -t 0 ] && [ -t 1 ] || return 1
    printf '%s' 'Type ADOPT LEGACY AUDIO to remove an unmarked older override: '
    IFS= read -r answer
    [ "$answer" = "ADOPT LEGACY AUDIO" ]
}

run_audio_rollback() {
    local rc=0 adopted=0
    sudo "$HERE/rollback.sh" --all || rc=$?
    if [ "$rc" = 3 ]; then
        confirm_legacy_adoption || return "$rc"
        adopted=1
        sudo "$HERE/rollback.sh" --all --adopt-legacy
    elif [ "$rc" != 0 ]; then
        return "$rc"
    fi

    rc=0
    if [ "$adopted" = 1 ]; then
        sudo "$HERE/cleanup-other-slot.sh" --skip-current --adopt-legacy || rc=$?
    else
        sudo "$HERE/cleanup-other-slot.sh" --skip-current || rc=$?
    fi
    if [ "$rc" = 3 ] && [ "$adopted" = 0 ]; then
        confirm_legacy_adoption || return "$rc"
        sudo "$HERE/cleanup-other-slot.sh" --skip-current --adopt-legacy
    elif [ "$rc" != 0 ]; then
        return "$rc"
    fi
}

case "${1:-}" in
    status)
        [ "$#" = 1 ] || { usage >&2; exit 2; }
        show_status
        exit
        ;;
    uninstall)
        [ "$#" = 1 ] || { usage >&2; exit 2; }
        [ "$(id -u)" != 0 ] || { echo "run as the logged-in user; this command requests sudo for rollback" >&2; exit 1; }
        command -v flock >/dev/null || { echo "flock is required" >&2; exit 1; }
        exec 9>"$HERE/.prepare-kernel.lock"
        flock 9
        run_audio_rollback
        echo "[bc250-audio] source, downloads, and build output were preserved"
        exit
        ;;
    help|-h|--help)
        usage
        exit
        ;;
esac

[ "$(id -u)" != 0 ] || { echo "run as the normal user - sudo is used only for privileged steps"; exit 1; }
"$HERE/ensure-build-prereqs.sh"
command -v flock >/dev/null || { echo "flock is required" >&2; exit 1; }
exec 9>"$HERE/.prepare-kernel.lock"
flock 9

WITH_GFX1013=()
WITH_AUDIO=()
WITH_DSC=()
NO_SS=()
NO_TELEMETRY=()
NO_TTM=()
NO_SCLK=()
NO_KFD=()
WITH_VCN=()
USE_PREBUILT=1
ARGS=()
for a in "$@"; do
    case "$a" in
        --gfx1013)        WITH_GFX1013=(--gfx1013) ;;
        --audio)          WITH_AUDIO=(--audio) ;;
        --dsc)            WITH_DSC=(--dsc) ;;
        --dsc-pcon)       WITH_DSC=(--dsc) ;;
        --no-ss)          NO_SS=(--no-ss) ;;
        --no-telemetry)   NO_TELEMETRY=(--no-telemetry) ;;
        --no-ttm)         NO_TTM=(--no-ttm) ;;
        --no-sclk)        NO_SCLK=(--no-sclk) ;;
        --no-kfd)         NO_KFD=(--no-kfd) ;;
        --vcn)            WITH_VCN=(--vcn) ;;
        --no-prebuilt)    USE_PREBUILT=0 ;;
        *)                ARGS+=("$a") ;;
    esac
done

# --- Prebuilt module fast path ---------------------------------------------
# A published prebuilt amdgpu.ko.zst may replace the whole fetch+build cycle,
# but ONLY for the exact running kernel release AND the exact flag signature
# it was built with — anything else falls back to the normal source build.
# Assets live on the rolling `prebuilt` GitHub release, one set per kernel:
#   amdgpu-<uname -r>.ko.zst        the module
#   amdgpu-<uname -r>.ko.zst.sha256 checksum (verified before install)
#   amdgpu-<uname -r>.flags         the normalized flag signature
# install.sh then re-verifies vermagic + task_struct ABI before touching /usr.
kernel_flags_sig() {
    local sig="" kmaj kmin
    [ ${#WITH_AUDIO[@]} -gt 0 ] && sig="$sig audio"
    [ ${#WITH_GFX1013[@]} -gt 0 ] && sig="$sig gfx1013"
    [ ${#WITH_DSC[@]} -gt 0 ] && sig="$sig dsc"
    [ ${#WITH_VCN[@]} -gt 0 ] && sig="$sig vcn"
    # --no-ss is a no-op on kernels >= 7.2 (the DP spread-spectrum disable is
    # upstream and build.sh force-skips it), so it must not enter the
    # signature — otherwise the Combined Fix on 7.2+ always misses the
    # prebuilt artifact even though the binary is identical.
    kmaj=$(uname -r | cut -d. -f1)
    kmin=$(uname -r | cut -d. -f2 | cut -d- -f1)
    if [ ${#NO_SS[@]} -gt 0 ] && ! { [ "$kmaj" -gt 7 ] 2>/dev/null || { [ "$kmaj" -eq 7 ] 2>/dev/null && [ "$kmin" -ge 2 ] 2>/dev/null; }; }; then
        sig="$sig no-ss"
    fi
    [ ${#NO_TELEMETRY[@]} -gt 0 ] && sig="$sig no-telemetry"
    [ ${#NO_TTM[@]} -gt 0 ] && sig="$sig no-ttm"
    [ ${#NO_SCLK[@]} -gt 0 ] && sig="$sig no-sclk"
    [ ${#NO_KFD[@]} -gt 0 ] && sig="$sig no-kfd"
    echo "${sig# }"
}

try_prebuilt() {
    [ "$USE_PREBUILT" = 1 ] || return 1
    command -v curl >/dev/null || return 1
    local rel asset base
    rel=$(uname -r)
    asset="amdgpu-${rel}"
    base="https://github.com/rpf16rj/bc250-steamos-real-toolkit/releases/download/prebuilt"

    # The flag manifest is checked first — a matching kernel with a different
    # patch set must not silently install the wrong module.
    curl -fsSL --max-time 15 -o "$HERE/$asset.flags" "$base/$asset.flags" || return 1
    [ "$(cat "$HERE/$asset.flags")" = "$(kernel_flags_sig)" ] || return 1

    curl -fsSL --max-time 120 -o "$HERE/$asset.ko.zst" "$base/$asset.ko.zst" || return 1
    curl -fsSL --max-time 15 -o "$HERE/$asset.ko.zst.sha256" "$base/$asset.ko.zst.sha256" || return 1
    (cd "$HERE" && sha256sum -c "$asset.ko.zst.sha256" >/dev/null) || return 1

    cp "$HERE/$asset.ko.zst" "$HERE/amdgpu.ko.zst"
    echo "[prebuilt] $rel: flag set '$(cat "$HERE/$asset.flags")' matches — installing prebuilt module"
    sudo "$HERE/install.sh"
}

if try_prebuilt; then
    exit 0
fi
[ "$USE_PREBUILT" = 1 ] && echo "[prebuilt] no matching artifact for $(uname -r) — building from source"

"$HERE/fetch-sources.sh" "${ARGS[@]}"
"$HERE/build.sh" "${WITH_GFX1013[@]}" "${WITH_AUDIO[@]}" "${WITH_DSC[@]}" "${NO_SS[@]}" "${NO_TELEMETRY[@]}" "${NO_TTM[@]}" "${NO_SCLK[@]}" "${NO_KFD[@]}" "${WITH_VCN[@]}" "${ARGS[@]}"

# Record the flag signature this binary was actually built with so
# package-prebuilt.sh never has to guess it from manual arguments.
mkdir -p "$HERE/prebuilt"
kernel_flags_sig > "$HERE/prebuilt/amdgpu-$(uname -r).flags"

sudo "$HERE/install.sh"
