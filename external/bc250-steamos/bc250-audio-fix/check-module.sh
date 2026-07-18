#!/bin/bash
# Shared guards for a candidate amdgpu module, factored out of install.sh so
# build.sh can run the identical checks at build time.
#
#   check-module.sh <module.ko[.zst]> [kernel-release]   (default: uname -r)
#
# Exit codes:
#   0 — both guards pass
#   1 — a guard FAILED: do not install this module
#   2 — ABI guard could not run (stock module or objdump unavailable);
#       vermagic guard passed. Both build.sh and install.sh treat this as
#       fatal because the unchecked ABI mismatch can black-screen at boot.
set -euo pipefail

MOD=${1:?usage: check-module.sh <module.ko[.zst]> [kernel-release]}
REL=${2:-$(uname -r)}

[ -f "$MOD" ] || { echo "ERROR: no such module: $MOD"; exit 1; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

case "$MOD" in
    *.zst) zstd -dq "$MOD" -o "$TMPD/new.ko" ;;
    *)     cp "$MOD" "$TMPD/new.ko" ;;
esac

# Guard 1: refuse a module whose vermagic does not match the target kernel —
# modprobe would reject it at boot and, with the updates/ override baked into
# the initramfs, leave the system with no GPU driver (this is what forced the
# 2026-07-02 recovery).
VERMAGIC=$(modinfo -F vermagic "$TMPD/new.ko" | awk '{print $1}')
if [ "$VERMAGIC" != "$REL" ]; then
    echo "ERROR: vermagic mismatch — module is for '$VERMAGIC', kernel is '$REL'"
    exit 1
fi
echo "vermagic OK: $VERMAGIC"

# Guard 2: vermagic is only a version-string compare and CONFIG_MODVERSIONS
# is off in this kernel, so nothing else validates ABI. A module built with
# a config missing CONFIG_SCHED_CLASS_EXT (happens silently when pahole is
# absent) has every task_struct offset shifted by 256 bytes — it loads fine
# and then hangs with no log output (the 2026-07-05 black screen). Compare
# compiled task_struct offsets in a known function against the stock module.
STOCK=/usr/lib/modules/$REL/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst
if [ ! -f "$STOCK" ] || ! command -v objdump >/dev/null; then
    echo "WARNING: skipping ABI check (stock module or objdump unavailable)"
    exit 2
fi
zstd -dq "$STOCK" -o "$TMPD/stock.ko"
for m in stock new; do
    objdump -d --no-show-raw-insn --disassemble=amdgpu_vm_set_task_info \
        "$TMPD/$m.ko" | grep -oE '0x[0-9a-f]+\(%r' > "$TMPD/$m.offsets"
done
[ -s "$TMPD/stock.offsets" ] || { echo "ERROR: could not extract reference offsets"; exit 1; }
if ! cmp -s "$TMPD/stock.offsets" "$TMPD/new.offsets"; then
    echo "ERROR: task_struct field offsets differ from the stock module —"
    echo "the module was built against a mismatched config (check pahole/sched_ext)."
    diff "$TMPD/stock.offsets" "$TMPD/new.offsets" | head
    exit 1
fi
echo "ABI OK: task_struct offsets match stock module"
