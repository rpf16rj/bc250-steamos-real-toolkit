#!/bin/bash
# Remove patched amdgpu overrides and restore the stock module.
# Run as: sudo ./rollback.sh [kernel-release|--all]
# --all is noninteractive and covers every installed kernel with this override.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

PRIORITY_FILE=/usr/lib/depmod.d/10-bc250-audio-fix.conf
LEGACY_PRIORITY_FILE=/usr/lib/depmod.d/10-updates.conf
HERE=$(cd "$(dirname "$0")" && pwd)
ROOTFS_WAS_READONLY=0
PRIORITY_REMOVED=0
TARGETS=()
PRESENT=()
PRESETS=()
ADOPT_LEGACY=0

valid_release() {
    [[ "$1" =~ ^[A-Za-z0-9._+-]+$ ]]
}

add_target() {
    local candidate="$1" existing
    for existing in "${TARGETS[@]}"; do
        [ "$existing" != "$candidate" ] || return 0
    done
    TARGETS+=("$candidate")
}

module_owned() {
    local module="$1" marker="$2" expected actual artifact
    if [ -e "$marker" ] || [ -L "$marker" ]; then
        [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
        read -r expected < "$marker" || return 1
        [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
        actual=$(sha256sum "$module" | awk '{print $1}')
        [ "$actual" = "$expected" ]
        return
    fi
    # Pre-marker releases are recognized only when the installed bytes still
    # match a module artifact produced by this checkout.
    for artifact in "$HERE/amdgpu.ko.zst" "$HERE"/amdgpu-*.ko.zst; do
        [ -f "$artifact" ] || continue
        cmp -s "$module" "$artifact" && return 0
    done
    [ "$ADOPT_LEGACY" = 1 ] && return 0
    return 1
}

priority_owned() {
    local path="$1"
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    case "$path" in
        "$PRIORITY_FILE")
            cmp -s "$path" <(printf '%s\n' '# Managed by bc250-audio-fix/install.sh' 'search updates built-in')
            ;;
        "$LEGACY_PRIORITY_FILE")
            cmp -s "$path" <(printf '%s\n' 'search updates built-in')
            ;;
        *) return 1 ;;
    esac
}

restore_rootfs() {
    local rc=$?
    trap - EXIT
    if [ "$ROOTFS_WAS_READONLY" = 1 ]; then
        steamos-readonly enable || rc=1
        ROOTFS_WAS_READONLY=0
    fi
    exit "$rc"
}

if [ "${1:-}" = --all ]; then
    [ "$#" -le 2 ] || { echo "Usage: $0 [kernel-release|--all] [--adopt-legacy]" >&2; exit 2; }
    if [ "${2:-}" = --adopt-legacy ]; then ADOPT_LEGACY=1
    elif [ "$#" = 2 ]; then echo "Usage: $0 --all [--adopt-legacy]" >&2; exit 2
    fi
    for candidate in /usr/lib/modules/*/updates/amdgpu.ko.zst \
                     /usr/lib/modules/*/updates/.bc250-audio-fix \
                     /usr/lib/modules/*/updates/.bc250-metrics-fix; do
        [ -e "$candidate" ] || [ -L "$candidate" ] || continue
        rel=${candidate#/usr/lib/modules/}
        rel=${rel%%/*}
        valid_release "$rel" || { echo "ERROR: unsafe kernel release '$rel'" >&2; exit 1; }
        add_target "$rel"
    done
else
    [ "$#" -le 2 ] || { echo "Usage: $0 [kernel-release] [--adopt-legacy]" >&2; exit 2; }
    REL="${1:-$(uname -r)}"
    if [ "${2:-}" = --adopt-legacy ]; then ADOPT_LEGACY=1
    elif [ "$#" = 2 ]; then echo "Usage: $0 [kernel-release] [--adopt-legacy]" >&2; exit 2
    fi
    valid_release "$REL" || { echo "ERROR: unsafe kernel release '$REL'" >&2; exit 1; }
    if [ ! -d "/usr/lib/modules/$REL/kernel" ]; then
        # In a recovery chroot uname reports the recovery kernel. Preserve the
        # prior single-installed-kernel fallback for explicit recovery use.
        CANDIDATES=()
        for candidate in /usr/lib/modules/*/; do
            [ ! -d "$candidate/kernel" ] || CANDIDATES+=("${candidate%/}")
        done
        CANDIDATES=("${CANDIDATES[@]##*/}")
        if [ "${#CANDIDATES[@]}" = 1 ]; then
            REL="${CANDIDATES[0]}"
            echo "note: using detected kernel '$REL' (uname -r reports a different kernel)"
        else
            echo "ERROR: cannot determine kernel release. Available in /usr/lib/modules:"
            printf '  %s\n' "${CANDIDATES[@]:-none}"
            echo "Re-run as: sudo $0 <kernel-release>"
            exit 1
        fi
    fi
    add_target "$REL"
fi

for rel in "${TARGETS[@]}"; do
    module="/usr/lib/modules/$rel/updates/amdgpu.ko.zst"
    marker="/usr/lib/modules/$rel/updates/.bc250-audio-fix"
    metrics_marker="/usr/lib/modules/$rel/updates/.bc250-metrics-fix"
    if [ ! -e "$module" ] && [ ! -L "$module" ] \
       && [ ! -e "$marker" ] && [ ! -L "$marker" ] \
       && [ ! -e "$metrics_marker" ] && [ ! -L "$metrics_marker" ]; then
        echo "amdgpu override is not installed for $rel"
        continue
    fi
    if [ -e "$module" ] || [ -L "$module" ]; then
        [ -f "$module" ] && [ ! -L "$module" ] \
            || { echo "ERROR: refusing unsafe module path: $module" >&2; exit 1; }
        ownership_marker=$marker
        [ -e "$ownership_marker" ] || [ -L "$ownership_marker" ] \
            || ownership_marker=$metrics_marker
        module_owned "$module" "$ownership_marker" || {
            echo "ERROR: refusing unrecognized AMDGPU override: $module" >&2
            echo "Re-run with --adopt-legacy only after confirming this is an older BC-250 patch." >&2
            exit 3
        }
        if [ "$ownership_marker" != "$metrics_marker" ] \
           && { [ -e "$metrics_marker" ] || [ -L "$metrics_marker" ]; }; then
            module_owned "$module" "$metrics_marker" \
                || { echo "ERROR: invalid metrics marker: $metrics_marker" >&2; exit 1; }
        fi
    else
        rollback_marker=$marker
        [ -e "$rollback_marker" ] || rollback_marker=$metrics_marker
        [ -f "$rollback_marker" ] && [ ! -L "$rollback_marker" ] \
            || { echo "ERROR: refusing unsafe rollback marker: $rollback_marker" >&2; exit 1; }
        read -r expected < "$rollback_marker" || { echo "ERROR: unreadable rollback marker: $rollback_marker" >&2; exit 1; }
        [[ "$expected" =~ ^[0-9a-f]{64}$ ]] \
            || { echo "ERROR: invalid rollback marker: $rollback_marker" >&2; exit 1; }
        echo "$rel: resuming an interrupted rollback"
    fi
    stock="/usr/lib/modules/$rel/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst"
    [ -f "$stock" ] && [ ! -L "$stock" ] \
        || { echo "ERROR: stock amdgpu module is missing or unsafe for '$rel'" >&2; exit 1; }
    [[ "$rel" =~ neptune-[0-9]+ ]] && preset=linux-${BASH_REMATCH[0]} || preset=
    [ -n "$preset" ] && [ -f "/etc/mkinitcpio.d/$preset.preset" ] \
        || { echo "ERROR: cannot find an mkinitcpio preset for '$rel'" >&2; exit 1; }
    PRESENT+=("$rel")
    PRESETS+=("$preset")
done

if [ "${#PRESENT[@]}" = 0 ] && [ ! -e "$PRIORITY_FILE" ] \
   && [ ! -e "$LEGACY_PRIORITY_FILE" ]; then
    echo "OK - BC-250 amdgpu patch is not installed; nothing to remove."
    exit 0
fi
for priority in "$PRIORITY_FILE" "$LEGACY_PRIORITY_FILE"; do
    [ ! -e "$priority" ] && [ ! -L "$priority" ] && continue
    priority_owned "$priority" \
        || { echo "ERROR: refusing unrecognized depmod configuration: $priority" >&2; exit 1; }
done
command -v depmod >/dev/null || { echo "ERROR: depmod is required" >&2; exit 1; }
if [ "${#PRESENT[@]}" -gt 0 ]; then
    command -v modinfo >/dev/null || { echo "ERROR: modinfo is required" >&2; exit 1; }
    command -v mkinitcpio >/dev/null || { echo "ERROR: mkinitcpio is required" >&2; exit 1; }
fi

trap restore_rootfs EXIT
if steamos-readonly status 2>/dev/null | grep -qi enabled; then
    steamos-readonly disable
    ROOTFS_WAS_READONLY=1
fi

# Adopt recognized pre-marker installs before deleting their module. The marker
# is retained until initramfs regeneration succeeds, making rollback retry-safe.
for rel in "${PRESENT[@]}"; do
    module="/usr/lib/modules/$rel/updates/amdgpu.ko.zst"
    marker="/usr/lib/modules/$rel/updates/.bc250-audio-fix"
    if [ -e "$module" ] && [ ! -e "$marker" ]; then
        sha256sum "$module" | awk '{print $1}' > "$marker"
        chmod 0644 "$marker"
    fi
done

for rel in "${PRESENT[@]}"; do
    rm -f "/usr/lib/modules/$rel/updates/amdgpu.ko.zst"
done

remaining=0
for module in /usr/lib/modules/*/updates/amdgpu.ko.zst; do
    [ ! -e "$module" ] && [ ! -L "$module" ] || remaining=1
done
if [ "$remaining" = 0 ]; then
    for priority in "$PRIORITY_FILE" "$LEGACY_PRIORITY_FILE"; do
        if [ -e "$priority" ]; then
            rm -f "$priority"
            PRIORITY_REMOVED=1
        fi
    done
fi

if [ "$PRIORITY_REMOVED" = 1 ]; then
    # The depmod search rule applies globally, so refresh every installed
    # kernel after removing it, including kernels without this override.
    for directory in /usr/lib/modules/*/; do
        [ -d "$directory" ] || continue
        rel=${directory%/}
        rel=${rel##*/}
        valid_release "$rel" || { echo "ERROR: unsafe kernel release '$rel'" >&2; exit 1; }
        depmod "$rel"
    done
else
    for rel in "${PRESENT[@]}"; do
        depmod "$rel"
    done
fi

for index in "${!PRESENT[@]}"; do
    rel=${PRESENT[$index]}
    preset=${PRESETS[$index]}
    resolved=$(modinfo -k "$rel" -F filename amdgpu)
    echo "$rel: amdgpu now resolves to $resolved"
    [[ "$resolved" != */updates/* ]] \
        || { echo "ERROR: override still selected for '$rel'" >&2; exit 1; }
    mkinitcpio -p "$preset"
    rm -f "/usr/lib/modules/$rel/updates/.bc250-audio-fix" \
        "/usr/lib/modules/$rel/updates/.bc250-metrics-fix"
    rmdir "/usr/lib/modules/$rel/updates" 2>/dev/null || true
done

if [ "${#PRESENT[@]}" = 0 ]; then
    if [ "$PRIORITY_REMOVED" = 1 ]; then
        echo "OK - BC-250 amdgpu patch is not installed; stale depmod configuration removed."
    else
        echo "OK - BC-250 amdgpu patch is not installed for the selected kernel; nothing to remove."
    fi
    exit 0
fi
echo "OK - stock amdgpu restored for ${#PRESENT[@]} kernel(s). Reboot to apply."
echo "Source, downloads, and build output were preserved."
