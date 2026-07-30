# shellcheck shell=bash
# Source this before ANY make invocation in valve-kernel/.
# The build deps (bc, pahole, libelf, openssl) live in deps/, not on the
# system. If pahole is not visible to Kconfig, syncconfig SILENTLY disables
# CONFIG_DEBUG_INFO_BTF and with it CONFIG_SCHED_CLASS_EXT, which shifts
# task_struct offsets — the module then loads (vermagic still matches) and
# silently corrupts memory. This is what black-screened the 2026-07-05 boot.
DEPS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deps"
export PATH="$DEPS/usr/bin:$PATH"
export LD_LIBRARY_PATH="$DEPS/usr/lib"
export C_INCLUDE_PATH="$DEPS/usr/include"
export LIBRARY_PATH="$DEPS/usr/lib"
export PKG_CONFIG_PATH="$DEPS/usr/lib/pkgconfig"

for tool in make gcc ld ar nm objcopy objdump strip patch perl python3 cpio \
            flex bison msgfmt pkg-config pahole bc zstd modinfo; do
    command -v "$tool" >/dev/null \
        || { echo "FATAL: $tool not on PATH"; return 1; }
done
