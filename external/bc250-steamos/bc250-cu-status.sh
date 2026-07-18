#!/usr/bin/env bash
# bc250-cu-status.sh -- read-only CU dispatch report for the BC-250.
# No writes, no TUI, safe to run any time (cron, ssh, scripts).
#
# Usage: sudo ./bc250-cu-status.sh [-q]
#   -q   quiet: print only the total, e.g. "38/40"
set -euo pipefail

REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
if [[ "$REAL_USER" == root ]] && getent passwd deck >/dev/null 2>&1; then
    REAL_USER=deck
fi
REAL_HOME="${REAL_HOME:-$(getent passwd "$REAL_USER" | cut -d: -f6)}"
[[ "$REAL_HOME" == /* ]] || { echo "cannot resolve the real user's home" >&2; exit 1; }
FIXES_REPO_DIR="${FIXES_REPO_DIR:-$REAL_HOME/.local/share/bc250-fixes/bc250-steamos}"
DEFAULT_UMR=/var/lib/bc250-control/umr/bin/umr
if [[ ! -x "$DEFAULT_UMR" && -x "$FIXES_REPO_DIR/bin/umr" ]]; then
    DEFAULT_UMR="$FIXES_REPO_DIR/bin/umr"
elif [[ ! -x "$DEFAULT_UMR" && -x /var/lib/bc250-40cu/bin/umr ]]; then
    DEFAULT_UMR=/var/lib/bc250-40cu/bin/umr
fi
UMR="${UMR:-$DEFAULT_UMR}"
UMR_DATABASE_PATH="${UMR_DATABASE_PATH:-/var/lib/bc250-control/umr/share/umr/database}"
ASIC="${UMR_ASIC:-cyan_skillfish.gfx1013}"
REG_SPI="mmSPI_PG_ENABLE_STATIC_WGP_MASK"
REG_CC="mmCC_GC_SHADER_ARRAY_CONFIG"
QUIET=0
[[ "${1:-}" == "-q" ]] && QUIET=1

[[ $EUID -eq 0 ]] || { echo "needs root for register access" >&2; exit 1; }
[[ -x "$UMR" ]] || { echo "umr not found at $UMR (set UMR=...)" >&2; exit 1; }

read_bank() {  # read_bank REG SE SH -> hex value
    "$UMR" --database-path "$UMR_DATABASE_PATH" \
        -r "$ASIC.$1" -b "$2" "$3" 0xffffffff 2>/dev/null \
        | grep -o '0x[0-9a-fA-F]*' | tail -1
}

cu_count() {  # cu_count SPI_MASK -> number of routed CUs (2 per WGP bit)
    local mask=$(( $1 & 0x1f )) wgp n=0
    for wgp in 0 1 2 3 4; do
        (( mask & (1 << wgp) )) && n=$((n + 2))
    done
    echo "$n"
}

wgp_row() {  # wgp_row SPI_MASK -> "on on on -- --"
    local mask=$(( $1 & 0x1f )) wgp out=""
    for wgp in 0 1 2 3 4; do
        if (( mask & (1 << wgp) )); then out+=" on"; else out+=" --"; fi
    done
    echo "$out"
}

total=0
rows=()
for se in 0 1; do
    for sh in 0 1; do
        spi=$(read_bank "$REG_SPI" "$se" "$sh")
        [[ -n "$spi" ]] || { echo "register read failed (SE$se SH$sh) -- amdgpu loaded? debugfs?" >&2; exit 1; }
        cc=$(read_bank "$REG_CC" "$se" "$sh")
        n=$(cu_count "$spi")
        total=$((total + n))
        rows+=("SE${se}.SH${sh}  W:$(wgp_row "$spi")   SPI=$(printf '0x%02x' $((spi & 0x1f)))  CC=${cc:-?}  ${n}/10")
    done
done

if [[ $QUIET -eq 1 ]]; then
    echo "${total}/40"
    exit 0
fi

echo "BC-250 CU dispatch status   ($(date '+%Y-%m-%d %H:%M'))"
echo "           WGP: 0  1  2  3  4"
for r in "${rows[@]}"; do echo "  $r"; done
echo "  ---------------------------------------------"
echo "  Routed total: ${total}/40 CUs"

# context, best-effort
drv=$(dmesg 2>/dev/null | grep -o 'active_cu_number [0-9]*' | tail -1 | awk '{print $2}' || true)
[[ -n "$drv" ]] && echo "  Driver topology (boot snapshot): ${drv} CU -- stays 24 on runtime route, expected"
svc=$(systemctl is-enabled bc250-cu-live-manager.service 2>/dev/null || true)
[[ -n "$svc" ]] && echo "  Boot service: ${svc}"
