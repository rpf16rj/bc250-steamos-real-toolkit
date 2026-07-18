#!/usr/bin/env bash
# bc250-40cu.sh  (40 CU unlock, v2 battle-tested)
#
# All-in-one BC-250 40 CU unlock for SteamOS 3.8.x via the runtime UMR route.
#
# Runtime assets are split between the home-backed source tree and root storage:
#   ~/.local/share/bc250-fixes/bc250-steamos  source/build tree
#   /var/lib/bc250-control                    trusted executables + UMR database
#   /etc                                      systemd unit + boot table config
# SteamOS updates replace /usr and selectively retain /etc. The installer adds
# toolkit-owned system files to SteamOS's atomic-update keep list.
#
# Lessons baked in from getting this working on a real SteamOS 3.8.10 box:
#   * SteamOS strips headers and .pc files from image packages, including
#     GLIBC'S OWN HEADERS. Explicit pacman reinstalls restore full file sets.
#   * pkgconf resolves packages interactively but fails under cmake's
#     pkg_check_modules on this image. We bypass pkg-config entirely with
#     auto-generated hardcoded stub Find modules (prefix parsed from the
#     originals so variable names always match).
#   * The stubs satisfy configure+compile but not the link stage; libs are
#     injected via CMAKE_EXE_LINKER_FLAGS with -Wl,--no-as-needed.
#   * A binary-only umr copy has an EMPTY ASIC database and fails every
#     named-register read. cmake --install with our prefix installs
#     share/umr/database alongside the binary.
#   * bc250-cu-live-manager's find_umr() NEVER consults PATH -- it checks
#     the $UMR env var, then /usr/bin, /usr/local/bin, /opt/umr/... .
#     We always launch it with UMR= set, and quarantine stale copies.
#   * The manager's write-service-table saves UMR=<path> into the conf the
#     service loads via EnvironmentFile, so the umr path self-persists.
#   * The manager's install-service copies itself to /usr/local/bin
#     (read-only AND update-wiped on SteamOS): install needs the rootfs
#     unlocked, and the binary must be relocated afterwards ('persist').
#   * Check the dashboard's harvest map BEFORE full dispatch. Scattered
#     patterns (a mid-row WGP the factory routed around) likely mark bad
#     silicon -- enable selectively with [e] instead of [f].
#
# Usage (run as root):
#   ./bc250-40cu.sh check      board / debugfs / install state
#   ./bc250-40cu.sh prep       deps + build umr into the persistent checkout
#   ./bc250-40cu.sh manager    launch the live-manager TUI correctly
#   ./bc250-40cu.sh persist    relocate service off the wipeable rootfs
#   ./bc250-40cu.sh verify     registers + service + guidance
#   ./bc250-40cu.sh revert     disable service (reboot -> stock 24 CU)
#   ./bc250-40cu.sh all        check + prep + manager
#
set -euo pipefail

REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
if [[ "$REAL_USER" == root ]] && getent passwd deck >/dev/null 2>&1; then
    REAL_USER=deck
fi
REAL_HOME="${REAL_HOME:-$(getent passwd "$REAL_USER" | cut -d: -f6)}"
[[ "$REAL_HOME" == /* ]] || { echo "Could not resolve the real user's home directory." >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXES_REPO_DIR="${FIXES_REPO_DIR:-$REAL_HOME/.local/share/bc250-fixes/bc250-steamos}"
[[ "$FIXES_REPO_DIR" == /* && "$FIXES_REPO_DIR" != *[$'\n\r\t ']* ]] \
    || { echo "FIXES_REPO_DIR must be an absolute path without whitespace." >&2; exit 1; }
PREFIX="$FIXES_REPO_DIR"
ROOT_DATA_DIR="/var/lib/bc250-control"
COMPUTE_MIGRATION_MARKER="$ROOT_DATA_DIR/.legacy-compute-migrated"
POWER_MIGRATION_MARKER="$ROOT_DATA_DIR/.legacy-power-migrated"
UMR_PREFIX="$ROOT_DATA_DIR/umr"
UMR_BIN="$UMR_PREFIX/bin/umr"
UMR_DATABASE="$UMR_PREFIX/share/umr/database"
OLD_UMR_PREFIX="$PREFIX"
LEGACY_ETC_UMR_PREFIX="/etc/bc250-control/umr"
MANAGER_SH="$PREFIX/bc250-cu-live-manager.sh"
MANAGER_URL="https://raw.githubusercontent.com/WinnieLV/bc250-cu-live-manager/refs/heads/main/bc250-cu-live-manager.sh"
UMR_GIT="https://gitlab.freedesktop.org/tomstdenis/umr.git"
SRC="$PREFIX/.build/umr"
BLD="$SRC/b"
SERVICE="/etc/systemd/system/bc250-cu-live-manager.service"
SERVICE_CONF="/etc/bc250-cu-live-manager.conf"
ROOTFS_MANAGER_BIN="/usr/local/bin/bc250-cu-live-manager"
PERSIST_MANAGER_BIN="$ROOT_DATA_DIR/helper/bc250-cu-live-manager"
LEGACY_PREFIX="/var/lib/bc250-40cu"
STORAGE_SH="$SCRIPT_DIR/bc250-storage.sh"
UPDATE_PERSIST_SH="$SCRIPT_DIR/bc250-update-persistence.sh"
UPDATE_KEEP_FILE="/etc/atomic-update.conf.d/bc250-compute.conf"

log()  { echo -e "\033[1;32m[bc250]\033[0m $*"; }
warn() { echo -e "\033[1;33m[bc250]\033[0m $*"; }
die()  { echo -e "\033[1;31m[bc250]\033[0m $*" >&2; exit 1; }
require_root() { [[ $EUID -eq 0 ]] || die "Run as root (sudo)."; }
install_update_persistence() {
    [[ -f "$UPDATE_PERSIST_SH" ]] \
        || die "Update persistence helper missing: $UPDATE_PERSIST_SH"
    bash "$UPDATE_PERSIST_SH" install compute
}
recover_update_settings() {
    [[ -f "$UPDATE_PERSIST_SH" ]] \
        || die "Update persistence helper missing: $UPDATE_PERSIST_SH"
    bash "$UPDATE_PERSIST_SH" recover compute
}

migrate_legacy_data() {
    [[ -f "$STORAGE_SH" ]] || die "Storage helper missing: $STORAGE_SH"
    bash "$STORAGE_SH" install
    if [[ ! -e "$PERSIST_MANAGER_BIN" ]]; then
        if [[ -f "$LEGACY_PREFIX/bc250-cu-live-manager" ]]; then
            install -D -o root -g root -m 0755 \
                "$LEGACY_PREFIX/bc250-cu-live-manager" "$PERSIST_MANAGER_BIN"
        elif [[ -f "$LEGACY_PREFIX/bc250-cu-live-manager.sh" ]]; then
            install -D -o root -g root -m 0755 \
                "$LEGACY_PREFIX/bc250-cu-live-manager.sh" "$PERSIST_MANAGER_BIN"
        fi
    fi
}

cleanup_legacy_data() {
    local file
    [[ -d "$LEGACY_PREFIX" ]] || return 0
    for file in "$SERVICE" "$SERVICE_CONF" \
        /etc/systemd/system/bc250-acpi-heal.service \
        /etc/systemd/system/cyan-skillfish-governor-smu.service \
        /etc/systemd/system/bc250-gpu-freq-restore.service \
        /etc/systemd/system/bc250-smu-oc.service; do
        if [[ -f "$file" ]] && grep -qF "$LEGACY_PREFIX" "$file"; then
            warn "Legacy data retained while $file still references it."
            return 0
        fi
    done
    [[ -e "$COMPUTE_MIGRATION_MARKER" && -e "$POWER_MIGRATION_MARKER" ]] || return 0
    rm -rf "$LEGACY_PREFIX" "$ROOT_DATA_DIR/legacy-bc250-40cu"
    log "Removed fully migrated legacy data at $LEGACY_PREFIX."
}

migrate_home_umr() {
    local source="" candidate stage
    if [[ -x "$UMR_BIN" \
        && -f "$UMR_DATABASE/cyan_skillfish.asic" \
        && -f "$UMR_DATABASE/cyan_skillfish.soc15" ]]; then
        touch "$COMPUTE_MIGRATION_MARKER"
        return 0
    fi
    for candidate in "$LEGACY_ETC_UMR_PREFIX" "$OLD_UMR_PREFIX" "$LEGACY_PREFIX"; do
        if [[ -x "$candidate/bin/umr" \
            && -f "$candidate/share/umr/database/cyan_skillfish.asic" \
            && -f "$candidate/share/umr/database/cyan_skillfish.soc15" ]]; then
            source="$candidate"
            break
        fi
    done
    [[ -n "$source" ]] || return 0
    log "Migrating umr and its ASIC database to trusted storage at $UMR_PREFIX..."
    stage=$(mktemp -d "$ROOT_DATA_DIR/.umr-migrate.XXXXXX")
    install -d -o root -g root -m 0755 "$stage/bin" "$stage/share/umr/database"
    install -o root -g root -m 0755 "$source/bin/umr" "$stage/bin/umr"
    cp -RL "$source/share/umr/database"/. "$stage/share/umr/database/"
    chown -R root:root "$stage"
    chmod -R go-w "$stage"
    rm -rf "$UMR_PREFIX"
    mv "$stage" "$UMR_PREFIX"
    if [[ "$source" == "$LEGACY_ETC_UMR_PREFIX" ]]; then
        rm -rf "$LEGACY_ETC_UMR_PREFIX"
    fi
    touch "$COMPUTE_MIGRATION_MARKER"
}

RO_WAS_DISABLED=0
DEBUGFS_MOUNTED=0
unlock_rootfs() {
    if steamos-readonly status 2>/dev/null | grep -qi enabled; then
        log "Disabling read-only rootfs (temporary)..."
        steamos-readonly disable
        RO_WAS_DISABLED=1
    fi
}
relock_rootfs() {
    if [[ $RO_WAS_DISABLED -eq 1 ]]; then
        log "Re-enabling read-only rootfs."
        steamos-readonly enable
        RO_WAS_DISABLED=0
    fi
}
cleanup() {
    tui_show_cursor
    if [[ $DEBUGFS_MOUNTED -eq 1 ]]; then
        umount /sys/kernel/debug 2>/dev/null || true
        DEBUGFS_MOUNTED=0
    fi
    relock_rootfs || true
}
trap cleanup EXIT

# ========================= pure-bash TUI menu =============================
# Zero dependencies: ANSI colors + read -rsn1 keyboard handling. The guided
# menu (run with no arguments) is a thin skin -- every action calls the same
# cmd_* function as the CLI, so nothing is menu-only.
C0=$'\033[0m'; CB=$'\033[1m'; CD=$'\033[2m'; CI=$'\033[7m'
CG=$'\033[32m'; CY=$'\033[33m'; CR=$'\033[31m'; CC=$'\033[36m'

TUI_CURSOR_HIDDEN=0
tui_show_cursor() {
    if [[ $TUI_CURSOR_HIDDEN -eq 1 ]]; then printf '\033[?25h'; TUI_CURSOR_HIDDEN=0; fi
}

# menu_select "Title" "label|badge|hint" ...
# up/down or j/k to move, Enter selects (MENU_CHOICE=index), q/Esc backs out
# (returns 1). Redraws in place; hint line describes the highlighted item.
menu_select() {
    local title="$1"; shift
    local items=("$@") n=$# cur=0 drawn=0 key rest i label badge hint
    local lines=$((n + 4))
    printf '\033[?25l'; TUI_CURSOR_HIDDEN=1
    while true; do
        if [[ $drawn -eq 1 ]]; then printf '\033[%dA' "$lines"; fi
        printf '\r\033[K%s\n' "${CB}${CC}${title}${C0}"
        printf '\033[K%s\n' "${CD}  up/down move - Enter select - q back${C0}"
        for i in "${!items[@]}"; do
            IFS='|' read -r label badge hint <<< "${items[$i]}"
            if [[ $i -eq $cur ]]; then
                printf '\033[K%s\n' "  ${CI}${CB} > ${label} ${C0} ${badge}"
            else
                printf '\033[K%s\n' "     ${label}  ${badge}"
            fi
        done
        IFS='|' read -r label badge hint <<< "${items[$cur]}"
        printf '\033[K\n\033[K%s\n' "  ${CD}${hint}${C0}"
        drawn=1
        IFS= read -rsn1 key || { tui_show_cursor; return 1; }
        if [[ $key == $'\033' ]]; then
            rest=""
            IFS= read -rsn2 -t 0.05 rest || true
            key+="$rest"
        fi
        case "$key" in
            $'\033[A'|k) if (( cur > 0 ));   then cur=$((cur-1)); else cur=$((n-1)); fi ;;
            $'\033[B'|j) if (( cur < n-1 )); then cur=$((cur+1)); else cur=0; fi ;;
            "")          MENU_CHOICE=$cur; tui_show_cursor; return 0 ;;
            q|Q|$'\033') tui_show_cursor; return 1 ;;
        esac
    done
}

pause_key() {
    echo
    printf '%s' "${CD}-- press any key to return to the menu --${C0}"
    IFS= read -rsn1 || true
    printf '\r\033[K'
}

ask() {   # ask "Prompt" [default] -> REPLY
    local prompt="$1" def="${2:-}"
    REPLY=""
    if [[ -n "$def" ]]; then
        read -rp "  $prompt [$def]: " REPLY || true
        [[ -n "$REPLY" ]] || REPLY="$def"
    else
        read -rp "  $prompt: " REPLY || true
    fi
}

# run a cmd_* in a subshell with its own cleanup trap: a die() inside an
# action drops back to the menu instead of killing it, and the subshell
# still relocks the rootfs on the way out
run_action() {
    local rc=0
    ( trap cleanup EXIT; "$@" ) || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo -e "${CR}${CB}[bc250]${C0} action failed (exit $rc) -- see message above."
    fi
    pause_key
}

b_ok()   { printf '%s' "${CG}[$1]${C0}"; }
b_mid()  { printf '%s' "${CY}[$1]${C0}"; }
b_off()  { printf '%s' "${CD}[$1]${C0}"; }

badge_umr() {
    if [[ -x "$UMR_BIN" ]]; then b_ok "installed"; else b_off "not installed"; fi
}
badge_service() {
    if [[ "$(systemctl is-active bc250-cu-live-manager.service 2>/dev/null)" == active ]]; then b_ok "service active"
    elif [[ -f "$SERVICE" ]]; then b_mid "service installed - inactive"
    else b_off "no service yet"; fi
}
badge_persist() {
    if [[ -f "$PERSIST_MANAGER_BIN" && -f "$UPDATE_KEEP_FILE" ]]; then b_ok "update protected"
    elif [[ -f "$PERSIST_MANAGER_BIN" ]]; then b_mid "keep list pending"
    elif [[ -f "$ROOTFS_MANAGER_BIN" ]]; then b_mid "on wipeable rootfs"
    else b_off "nothing to persist yet"; fi
}
CU_STATUS_SH="$SCRIPT_DIR/bc250-cu-status.sh"
cu_count() {   # "38/40" on stdout; fails without root / umr / sibling script
    [[ $EUID -eq 0 && -f "$CU_STATUS_SH" && -x "$UMR_BIN" ]] || return 1
    bash "$CU_STATUS_SH" -q 2>/dev/null
}
badge_cu() {   # live routed-CU count read from the SPI dispatch registers
    local st
    if st=$(cu_count) && [[ -n "$st" ]]; then
        case "$st" in
            24/40) b_mid "stock $st" ;;
            *)     b_ok "$st routed" ;;
        esac
    else
        b_off "CU count: root only"
    fi
}

# Prefer bare .so symlink; fall back to highest versioned .so.N present.
resolve_lib() {
    local base="$1"
    if [[ -e "${base}.so" ]]; then echo "${base}.so"; return; fi
    local best matches=("${base}".so.*)
    [[ -e "${matches[0]}" ]] || return 1
    best=$(printf '%s\n' "${matches[@]}" | sort -V | tail -1)
    [[ -n "$best" ]] || return 1
    echo "$best"
}

# Overwrite a pkg_check_modules-based Find module with a hardcoded stub.
# Variable prefix is parsed from the original so names match CMakeLists.
stub_find_module() {
    local file="$1" fallback="$2" incdirs="$3" cflags="$4"; shift 4
    local libs="$*" prefix
    prefix=$(grep -oP 'pkg_check_modules\(\s*\K[A-Za-z0-9_]+' "$file" | head -1 || true)
    [[ -n "$prefix" ]] || prefix="$fallback"
    log "Stubbing $(basename "$file") (prefix: $prefix)"
    cat > "$file" << EOF
# Auto-generated stub (SteamOS pkgconf-under-cmake bypass).
set(${prefix}_FOUND TRUE)
set(${prefix}_INCLUDE_DIR ${incdirs})
set(${prefix}_INCLUDE_DIRS ${incdirs})
set(${prefix}_LIBRARY ${libs})
set(${prefix}_LIBRARIES ${libs})
set(${prefix}_LDFLAGS ${libs})
set(${prefix}_LINK_LIBRARIES ${libs})
set(${prefix}_CFLAGS "${cflags}")
set(${prefix}_CFLAGS_OTHER "${cflags}")
set(${prefix}_VERSION 99.0)
mark_as_advanced(${prefix}_INCLUDE_DIR ${prefix}_LIBRARY)
EOF
}

# Stale umr copies on the manager's hardcoded search paths cause it to
# silently pick the wrong binary. Quarantine them.
quarantine_stale_umr() {
    local p
    for p in /usr/bin/umr /usr/local/bin/umr /opt/umr/build/src/app/umr; do
        if [[ -e "$p" && "$p" != "$UMR_BIN" ]]; then
            warn "Stale umr at $p -- renaming to ${p}.stale (manager would pick it up)"
            mv -f "$p" "${p}.stale" 2>/dev/null || warn "  could not rename (rootfs locked?); UMR env var still overrides it."
        fi
    done
}

# ================================ check ===================================
cmd_check() {
    require_root   # debugfs mount + globbing inside /sys/kernel/debug need root
    log "Board:"
    if lspci -n | grep -qi '1002:13fe'; then
        log "  BC-250 (0x13FE / Cyan Skillfish) detected."
    else
        die "  No 1002:13FE device found."
    fi
    log "Kernel: $(uname -r)"

    if ! mount | grep -q 'debugfs on /sys/kernel/debug'; then
        warn "debugfs not mounted; mounting..."
        mount -t debugfs none /sys/kernel/debug || die "Could not mount debugfs."
        DEBUGFS_MOUNTED=1
    fi
    # NOTE: glob must run as root -- deck can't read inside /sys/kernel/debug
    if compgen -G '/sys/kernel/debug/dri/*/amdgpu_regs2' >/dev/null; then
        log "amdgpu debugfs register interface present."
    else
        warn "amdgpu_regs2 not found under /sys/kernel/debug/dri -- umr banked reads may fail."
    fi

    if [[ -x "$UMR_BIN" ]]; then log "Persistent umr: $UMR_BIN"
    else warn "No umr at $UMR_BIN -- run: $0 prep"; fi
    if [[ -f "$PERSIST_MANAGER_BIN" ]]; then log "Trusted manager installed."
    elif [[ -f "$MANAGER_SH" ]]; then warn "Manager is cached but not installed to trusted storage."
    else warn "Manager not fetched yet."; fi
    if [[ -f "$SERVICE" ]]; then
        log "Boot service installed: $(systemctl is-enabled bc250-cu-live-manager.service 2>/dev/null || echo present)"
    else
        warn "Boot service not installed yet."
    fi
    [[ -f "$SERVICE_CONF" ]] && log "Boot table saved: $(grep BC250_WGP_MASKS "$SERVICE_CONF" || true)"
}

# ================================ prep ====================================
cmd_prep() {
    require_root
    migrate_legacy_data
    migrate_home_umr
    mkdir -p "$UMR_PREFIX/bin" "$PREFIX/.build"
    unlock_rootfs

    if ! pacman-key --list-keys >/dev/null 2>&1; then
        log "Initialising pacman keyring..."
        pacman-key --init
        pacman-key --populate archlinux holo 2>/dev/null || pacman-key --populate
    fi

    log "Installing/reinstalling build deps (explicit installs restore"
    log "headers and .pc files that the SteamOS image strips)..."
    pacman -Sy
    pacman -S --needed --noconfirm base-devel cmake git pkgconf || true
    pacman -S --noconfirm glibc linux-api-headers ncurses libpciaccess libdrm

    local f
    for f in /usr/include/stdio.h /usr/include/unistd.h /usr/include/linux/types.h \
             /usr/include/curses.h /usr/include/pciaccess.h /usr/include/xf86drm.h; do
        [[ -e "$f" ]] || die "Missing $f after reinstall -- investigate before continuing."
    done
    log "All required headers verified on disk."

    if [[ ! -d "$SRC/.git" ]]; then
        log "Cloning umr..."
        rm -rf "$SRC"
        git clone --depth 1 "$UMR_GIT" "$SRC"
    else
        log "Reusing existing umr clone at $SRC"
    fi

    local MODDIR="$SRC/cmake_modules"
    [[ -d "$MODDIR" ]] || die "No cmake_modules dir in umr source (layout changed?)"

    local PCI_LIB DRM_LIB DRM_AMDGPU_LIB
    PCI_LIB=$(resolve_lib /usr/lib/libpciaccess)        || die "libpciaccess lib not found"
    DRM_LIB=$(resolve_lib /usr/lib/libdrm)              || die "libdrm lib not found"
    DRM_AMDGPU_LIB=$(resolve_lib /usr/lib/libdrm_amdgpu)|| die "libdrm_amdgpu lib not found"
    log "Libs: $PCI_LIB | $DRM_LIB | $DRM_AMDGPU_LIB"

    local pci_mod drm_mod
    pci_mod=$(find "$MODDIR" -iname '*pciaccess*.cmake' | head -1 || true)
    drm_mod=$(find "$MODDIR" -iname '*drm*.cmake' | head -1 || true)
    [[ -n "$pci_mod" ]] && stub_find_module "$pci_mod" "PCIACCESS" \
        "/usr/include" "" "$PCI_LIB"
    [[ -n "$drm_mod" ]] && stub_find_module "$drm_mod" "LIBDRM" \
        "/usr/include /usr/include/libdrm" "-I/usr/include/libdrm" \
        "$DRM_LIB $DRM_AMDGPU_LIB"

    log "Configuring umr (fresh build dir)..."
    rm -rf "$BLD"
    env PKG_CONFIG_PATH=/usr/lib/pkgconfig:/usr/share/pkgconfig \
        CFLAGS="-I/usr/include/libdrm ${CFLAGS:-}" \
        cmake -S "$SRC" -B "$BLD" \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX="$UMR_PREFIX" \
          -DCMAKE_PREFIX_PATH=/usr \
          -DCMAKE_EXE_LINKER_FLAGS="-Wl,--no-as-needed $PCI_LIB $DRM_LIB $DRM_AMDGPU_LIB" \
          -DCURSES_NEED_NCURSES=TRUE \
          -DCURSES_INCLUDE_PATH=/usr/include \
          -DCURSES_NCURSES_LIBRARY=/usr/lib/libncursesw.so \
          -DUMR_NO_GUI=ON -DUMR_NO_LLVM=ON -DUMR_NO_SERVER=ON

    log "Building..."
    cmake --build "$BLD" -j"$(nproc)"
    log "Installing (binary + ASIC database) to $UMR_PREFIX..."
    cmake --install "$BLD"
    chown -R root:root "$UMR_PREFIX"
    chmod -R go-w "$UMR_PREFIX"
    install_update_persistence

    quarantine_stale_umr
    relock_rootfs

    [[ -x "$UMR_BIN" ]] || die "Install finished but $UMR_BIN missing."
    log "Enumeration check ('-e'; --list-asics does not exist on this umr):"
    if "$UMR_BIN" --database-path "$UMR_DATABASE" -e 2>/dev/null | grep -qi 'cyan_skillfish'; then
        log "SUCCESS -- board enumerates as cyan_skillfish. Next: $0 manager"
    else
        warn "Live enumeration didn't match; run: sudo $UMR_BIN -e   and inspect."
    fi
}

# =============================== manager ==================================
cmd_manager() {
    require_root
    migrate_legacy_data
    migrate_home_umr
    recover_update_settings
    [[ -x "$UMR_BIN" ]] || die "No umr at $UMR_BIN -- run: $0 prep"

    if [[ ! -f "$MANAGER_SH" ]]; then
        log "Fetching bc250-cu-live-manager..."
        curl -fL -o "$MANAGER_SH" "$MANAGER_URL"
        chmod +x "$MANAGER_SH"
    fi
    install -D -o root -g root -m 0755 "$MANAGER_SH" "$PERSIST_MANAGER_BIN"

    cat << 'EOT'
------------------------------------------------------------------------
 READ THE DASHBOARD TABLE BEFORE ENABLING ANYTHING.

 Contiguous factory pattern (WGP0-2 on, 3-4 off, ALL four rows identical):
   -> [f] full dispatch is reasonable.

 Scattered pattern (any row where the factory skipped a mid-row WGP and
 substituted a later one, e.g. D+ D+ -- D+ --):
   -> the skipped WGP likely FAILED FACTORY TEST. Do NOT use [f].
   -> use [e] and enable only the policy-harvested WGPs; leave the
      factory-skipped one off. Test it separately later with a Vulkan
      compute-correctness run before ever saving it into the boot table.

 Sequence: inspect -> [e] or [f] -> apply -> STRESS TEST WITH TEMPS IN
 VIEW (cap governor ~1500MHz first) -> [w] write table -> [i] install
 service (script unlocks rootfs for this) -> quit -> run 'persist'.

 Note: active_cu_number in the header stays 24 with the runtime route.
 That's the boot-time driver snapshot. Benchmark; don't trust it.
------------------------------------------------------------------------
EOT
    # install-service writes to /usr/local/bin -> rootfs must be unlocked.
    # Quarantine also needs it unlocked to rename stale /usr/bin copies.
    unlock_rootfs
    quarantine_stale_umr
    # find_umr() ignores PATH; the UMR env var is the supported override
    # and write-service-table persists it into the EnvironmentFile conf.
    UMR="$UMR_BIN" UMR_DATABASE_PATH="$UMR_DATABASE" "$PERSIST_MANAGER_BIN" "$@"
    relock_rootfs
    log "If you installed the service ('i'), now run: $0 persist"
}

# =============================== persist ==================================
cmd_persist() {
    require_root
    migrate_legacy_data
    migrate_home_umr
    [[ -f "$SERVICE" ]] || die "No service at $SERVICE -- install from the manager first ('i')."

    if [[ -f "$ROOTFS_MANAGER_BIN" ]]; then
        log "Relocating service binary off the wipeable rootfs..."
        install -D -o root -g root -m 0755 "$ROOTFS_MANAGER_BIN" "$PERSIST_MANAGER_BIN"
    elif [[ -f "$MANAGER_SH" && ! -f "$PERSIST_MANAGER_BIN" ]]; then
        warn "/usr/local copy missing (already wiped?); using cached manager script."
        install -D -o root -g root -m 0755 "$MANAGER_SH" "$PERSIST_MANAGER_BIN"
    fi
    [[ -f "$PERSIST_MANAGER_BIN" ]] \
        || die "No manager binary found anywhere ($ROOTFS_MANAGER_BIN, $MANAGER_SH). Re-run: $0 manager"
    chown root:root "$PERSIST_MANAGER_BIN"
    chmod 755 "$PERSIST_MANAGER_BIN"

    sed -i "s|$ROOTFS_MANAGER_BIN|$PERSIST_MANAGER_BIN|g" "$SERVICE"
    sed -i "s|/var/usrlocal/bin/bc250-cu-live-manager|$PERSIST_MANAGER_BIN|g" "$SERVICE"
    sed -i "s|$LEGACY_PREFIX/bc250-cu-live-manager|$PERSIST_MANAGER_BIN|g" "$SERVICE"
    if grep -q '^RequiresMountsFor=' "$SERVICE"; then
        sed -i "s|^RequiresMountsFor=.*|RequiresMountsFor=$ROOT_DATA_DIR|" "$SERVICE"
    else
        sed -i "/^\[Unit\]/a RequiresMountsFor=$ROOT_DATA_DIR" "$SERVICE"
    fi

    # Belt-and-suspenders: ensure the conf pins our persistent umr.
    # NB: sed exits 0 even with no match, so test with grep before choosing
    # replace-vs-append (an '|| append' after sed is dead code).
    if [[ -f "$SERVICE_CONF" ]] && ! grep -q "^UMR=$UMR_BIN$" "$SERVICE_CONF"; then
        warn "Conf's UMR path differs or is missing; pinning to $UMR_BIN"
        if grep -q '^UMR=' "$SERVICE_CONF"; then
            sed -i "s|^UMR=.*|UMR=$UMR_BIN|" "$SERVICE_CONF"
        else
            echo "UMR=$UMR_BIN" >> "$SERVICE_CONF"
        fi
    fi
    if [[ -f "$SERVICE_CONF" ]] && ! grep -q "^UMR_DATABASE_PATH=$UMR_DATABASE$" "$SERVICE_CONF"; then
        if grep -q '^UMR_DATABASE_PATH=' "$SERVICE_CONF"; then
            sed -i "s|^UMR_DATABASE_PATH=.*|UMR_DATABASE_PATH=$UMR_DATABASE|" "$SERVICE_CONF"
        else
            echo "UMR_DATABASE_PATH=$UMR_DATABASE" >> "$SERVICE_CONF"
        fi
    fi

    systemctl daemon-reload
    systemctl enable bc250-cu-live-manager.service
    install_update_persistence
    cleanup_legacy_data
    log "Persisted. Unit + conf are protected by the SteamOS atomic-update keep list."
    log "Verify after an update: $0 verify"
}

# =============================== verify ===================================
cmd_verify() {
    require_root
    [[ -x "$UMR_BIN" ]] || die "No umr at $UMR_BIN"
    log "Live SPI dispatch masks per shader array (0x1f = all 5 WGPs routed):"
    local se sh
    for se in 0 1; do for sh in 0 1; do
        printf '  SE%s.SH%s: ' "$se" "$sh"
        "$UMR_BIN" --database-path "$UMR_DATABASE" \
            -r cyan_skillfish.gfx1013.mmSPI_PG_ENABLE_STATIC_WGP_MASK \
            -b "$se" "$sh" 0xffffffff 2>/dev/null | grep -o '0x[0-9a-f]*' | tail -1
    done; done

    systemctl is-enabled bc250-cu-live-manager.service 2>/dev/null \
        && systemctl status bc250-cu-live-manager.service --no-pager -l | head -5 || true

    log "Reminder: dmesg active_cu_number stays 24 on the runtime route."
    log "Real proof = compute benchmark (llama-bench pp512 Vulkan): expect"
    log "~1.5-1.6x vs stock at matched clocks. Watch temps; cap 1500MHz/900mV"
    log "for sustained loads."
}

# =============================== revert ===================================
cmd_revert() {
    require_root
    systemctl disable --now bc250-cu-live-manager.service 2>/dev/null || true
    log "Boot service disabled. Reboot returns to stock 24 CU dispatch."
    log "(Table kept at $SERVICE_CONF; re-enable the service to restore.)"
}

# ================================ help ====================================
cmd_help() {
    cat << 'EOF'
bc250-40cu.sh -- BC-250 40 CU unlock for SteamOS
============================================================
Re-enables the factory-harvested compute units at RUNTIME (no kernel
rebuild) by writing the CC/SPI/RLC dispatch registers via umr, using
WinnieLV's bc250-cu-live-manager. A boot service replays the saved WGP
table every boot. SteamOS's atomic-update keep list retains the unit and
configuration and mount unit. Trusted UMR data and the CU manager live in
the root-owned, SteamOS-offloaded /var/lib/bc250-control tree.

GUIDED MENU
  Run with no arguments (or 'menu') in a terminal for an interactive,
  color-coded menu: arrow keys / j k to move, Enter to run, q to back
  out. Shows live install state per step and walks the setup order.

Background: the BC-250 ships 24 of 40 RDNA2 CUs active. Two registers
gate them (CC = enumeration, SPI = wave dispatch); the runtime route
flips dispatch after boot. Compute scales ~1.6x; graphics only ~+4%.
Research: duggasco/bc250-40cu-unlock.

COMMANDS (setup order)
  check     Preflight: BC-250 PCI ID present, debugfs + amdgpu register
            interface available, what's installed so far. Needs root.

  prep      Build umr from source into /var/lib/bc250-control. Handles
            every SteamOS landmine found the hard way:
              - reinstalls glibc/ncurses/libpciaccess/libdrm because the
                SteamOS image STRIPS their headers and .pc files
              - bypasses pkgconf (broken under cmake on this image) with
                auto-generated stub Find modules
              - injects libs into the link line (--no-as-needed)
              - installs the ASIC DATABASE next to the binary; a
                binary-only umr knows zero ASICs and fails every read
            Verify with: sudo /var/lib/bc250-control/umr/bin/umr -e
            (this umr has no --list-asics; -e enumerates live hardware)

  manager   Launch the live-manager TUI the RIGHT way: UMR env var set
            (its find_umr() ignores PATH), stale /usr/bin copies
            quarantined, rootfs unlocked so [i] can install the service.
            In the TUI:
              READ THE HARVEST MAP FIRST. Uniform rows (WGP0-2 on,
              3-4 off) -> [f] full dispatch is fine. A row where the
              factory SKIPPED a mid-row WGP (e.g. D+ D+ -- D+ --) means
              that WGP likely failed factory test: use [e], enable only
              the policy-harvested WGPs, leave the skipped one off.
              Then: apply -> stress test w/ temps -> [w] write table ->
              [i] install service -> quit -> run 'persist'.
            Extra args pass through to the manager CLI, e.g.:
              manager status
              manager enable-wgp 0.0.3 0.0.4 1.0.3 ...

  persist   Protect the boot service across updates: relocates the manager
            binary to root-owned storage, rewrites the unit, pins UMR=
            in the conf, installs the atomic-update keep list, and enables
            the service. Run once after [i].

  verify    Read the live SPI dispatch masks per shader array
            (0x1f = all 5 WGPs; 0x1b = WGP2 masked) + service state.
            NOTE: dmesg active_cu_number stays 24 on the runtime route
            -- that's the boot-time driver snapshot, not the truth.
            A compute benchmark (~1.5-1.6x vs stock) is the real proof.

  revert    Disable the boot service; reboot returns to stock 24 CU.
            The saved table is kept -- re-enable the service to restore.

  all       check + prep + manager.

FILE MAP
  /var/lib/bc250-control/umr/bin/umr     trusted umr build
  /var/lib/bc250-control/umr/share/umr/  ASIC database
  /var/lib/bc250-control/helper/bc250-cu-live-manager
                                         trusted manager
  /etc/systemd/system/bc250-cu-live-manager.service   (atomic-update keep list)
  /etc/bc250-cu-live-manager.conf        WGP table + UMR=   (atomic-update keep list)
  /usr/*                                 disposable -- wiped by updates
                                         and that's fine

  NB: umr links base-image libs (libdrm.so.2, libncursesw.so.6). Point
  releases keep sonames stable; after a MAJOR SteamOS version jump run
  'verify' -- if register reads fail, re-run 'prep' to rebuild umr.

RELATED
  bc250-cu-status.sh          read-only CU dispatch report (-q for N/40)
  bc250-power.sh      ACPI C/P-states + GPU governor + freq ctl
EOF
}

# ============================ guided menu =================================
cmd_menu() {
    [[ -t 0 && -t 1 ]] || die "The menu needs an interactive terminal. See '$0 help' for CLI commands."
    if [[ $EUID -ne 0 ]]; then
        warn "Not running as root -- setup actions will fail."
        ask "Restart with sudo? [Y/n]" "Y"
        if [[ "$REPLY" =~ ^[Yy] ]]; then exec sudo "$0" menu; fi
        echo
    fi
    while true; do
        local items=(
            "Board / install check||Read-only report: board, debugfs, umr, service. Start here."
            "Step 1 - Build umr|$(badge_umr)|Deps + build under the hidden toolkit directory. Unlocks rootfs; takes a few minutes."
            "Step 2 - Live CU manager|$(badge_service)|Dashboard TUI. READ the harvest map first: contiguous -> [f], scattered -> [e]."
            "Step 3 - Persist across updates|$(badge_persist)|Relocate the service off the wipeable rootfs. Run after 'i' in the manager."
            "Verify|$(badge_cu)|Read the live dispatch registers: routed CU count + guidance."
            "Revert to stock 24 CU||Disable the boot service; stock dispatch after reboot."
            "Full help||Complete walkthrough, including the harvest-map guide."
        )
        menu_select "BC-250 40 CU unlock  ${CD}(SteamOS)${C0}" "${items[@]}" || { echo; break; }
        case $MENU_CHOICE in
            0) run_action cmd_check ;;
            1) run_action cmd_prep ;;
            2) run_action cmd_manager ;;
            3) run_action cmd_persist ;;
            4) run_action cmd_verify ;;
            5) run_action cmd_revert ;;
            6) cmd_help; pause_key ;;
        esac
    done
}

# ================================ main ====================================
if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    cmd_menu
    exit 0
fi
case "${1:-}" in
    check)   cmd_check ;;
    prep)    cmd_prep ;;
    manager) shift; cmd_manager "$@" ;;
    persist) cmd_persist ;;
    verify)  cmd_verify ;;
    revert)  cmd_revert ;;
    all)     cmd_check; cmd_prep; cmd_manager ;;
    menu)    cmd_menu ;;
    help|-h|--help) cmd_help ;;
    *) echo "Usage: $0 {check|prep|manager|persist|verify|revert|all|menu|help}"
       echo "  (no arguments on a terminal opens the guided menu)"
       echo "Run '$0 help' for the full walkthrough of every command."
       exit 1 ;;
esac
