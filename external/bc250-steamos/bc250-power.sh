#!/usr/bin/env bash
# bc250-power.sh
#
# Complete power-management setup for the BC-250 on SteamOS 3.8.x:
#
#   ACPI fix (bc250-collective/bc250-acpi-fix):
#     SSDT-CST -> CPU C-states (C1/C2/C3 idle sleep)
#     SSDT-PST -> CPU P-states (800-3200 MHz cpufreq scaling)
#     Loaded as an early-initrd ACPI override via GRUB. The BC-250 BIOS
#     ships no CPU power tables at all -- without this, cores never idle.
#
#   GPU governor (filippor/cyan-skillfish-governor, SMU variant):
#     Dynamic freq/voltage via SMU firmware calls. NO kernel patch needed.
#     Without a governor the GPU is locked at 1500 MHz and idles hot.
#
# SteamOS persistence model used throughout:
#   ~/.local/share/bc250-fixes/bc250-steamos  source and build inputs
#   /var/lib/bc250-control                    trusted executables and state
#   /etc                                      configs and units, retained by an
#                                             atomic-update keep list
#   /boot                cpio must live here for GRUB           -- WIPED by updates
#                        -> a boot-time self-heal service restores it
#
# Usage (root):
#   ./bc250-power.sh acpi          install ACPI override + self-heal
#   ./bc250-power.sh governor      install SMU GPU governor (test-start)
#   ./bc250-power.sh enable        enable governor + cpufreq at boot
#   ./bc250-power.sh status        clocks, C-states, temps, services
#   ./bc250-power.sh all           acpi + governor
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
LEGACY_PREFIX="/var/lib/bc250-40cu"
BIN_DIR="$ROOT_DATA_DIR/bin"
ACPI_DIR="$ROOT_DATA_DIR/acpi"
CPIO_MASTER="$ACPI_DIR/acpi_override.cpio"
CPIO_BOOT="/boot/acpi_override.cpio"
ACPI_RAW_BASE="https://raw.githubusercontent.com/bc250-collective/bc250-acpi-fix/main"

GOV_BIN="$BIN_DIR/cyan-skillfish-governor-smu"
PERF_BIN="$BIN_DIR/cyan-skillfish-performance-mode"
GOV_CONF_DIR="/etc/cyan-skillfish-governor-smu"
GOV_CONF="$GOV_CONF_DIR/config.toml"
GOV_UNIT="/etc/systemd/system/cyan-skillfish-governor-smu.service"
GOV_SVC="cyan-skillfish-governor-smu.service"
DBUS_POLICY="/etc/dbus-1/system.d/com.cyan.SkillFishGovernor.conf"
GOV_API="https://api.github.com/repos/filippor/cyan-skillfish-governor/releases/latest"
GOV_RAW="https://raw.githubusercontent.com/filippor/cyan-skillfish-governor/smu"

HEAL_UNIT="/etc/systemd/system/bc250-acpi-heal.service"
HEAL_HELPER="$ROOT_DATA_DIR/helper/bc250-acpi-heal"
CPUFREQ_UNIT="/etc/systemd/system/bc250-cpufreq.service"

FREQ_STATE="$ROOT_DATA_DIR/governor/freq-state"
RESTORE_BIN="$BIN_DIR/bc250-gpu-freq-restore"
RESTORE_UNIT="/etc/systemd/system/bc250-gpu-freq-restore.service"
RESTORE_SVC="bc250-gpu-freq-restore.service"

# CPU OC (bc250-collective/bc250_smu_oc) -- fetched from upstream at a pinned
# commit, then our SteamOS patches (shipped in smu-oc-patches/ next to this
# script) are overlaid. No local clone is kept.
OC_PIN="43d6b4c6e38c57bc9ec8908c44675ce7d5fd3d2f"
OC_TARBALL="https://github.com/bc250-collective/bc250_smu_oc/archive/$OC_PIN.tar.gz"
OC_PATCH_DIR="$SCRIPT_DIR/smu-oc-patches"
OC_DIR="${BC250_OC_DIR:-$ROOT_DATA_DIR/smu-oc}"
OC_STAGE_CONF="$OC_DIR/overclock.conf"
OC_CONF="/etc/bc250-smu-oc.conf"
OC_UNIT="/etc/systemd/system/bc250-smu-oc.service"
OC_SVC="bc250-smu-oc.service"
UPDATE_PERSIST_SH="$SCRIPT_DIR/bc250-update-persistence.sh"
STORAGE_SH="$SCRIPT_DIR/bc250-storage.sh"

log()  { echo -e "\033[1;32m[power]\033[0m $*"; }
warn() { echo -e "\033[1;33m[power]\033[0m $*"; }
die()  { echo -e "\033[1;31m[power]\033[0m $*" >&2; exit 1; }
require_root() { [[ $EUID -eq 0 ]] || die "Run as root (sudo)."; }
install_update_persistence() {
    [[ -f "$UPDATE_PERSIST_SH" ]] \
        || die "Update persistence helper missing: $UPDATE_PERSIST_SH"
    bash "$UPDATE_PERSIST_SH" install power
}
recover_update_settings() {
    [[ -f "$UPDATE_PERSIST_SH" ]] \
        || die "Update persistence helper missing: $UPDATE_PERSIST_SH"
    bash "$UPDATE_PERSIST_SH" recover power
}

migrate_legacy_data() {
    local file marker="$POWER_MIGRATION_MARKER"
    [[ -f "$STORAGE_SH" ]] || die "Storage helper missing: $STORAGE_SH"
    bash "$STORAGE_SH" install
    install -d -o root -g root -m 0755 "$BIN_DIR" "$ACPI_DIR" \
        "$ROOT_DATA_DIR/helper" "$ROOT_DATA_DIR/governor" "$OC_DIR"
    if [[ -d "$LEGACY_PREFIX" && ! -e "$marker" ]]; then
        [[ ! -d "$LEGACY_PREFIX/acpi" ]] \
            || cp -a "$LEGACY_PREFIX/acpi"/. "$ACPI_DIR"/
        [[ ! -d "$LEGACY_PREFIX/smu-oc" ]] \
            || cp -a "$LEGACY_PREFIX/smu-oc"/. "$OC_DIR"/
        for file in cyan-skillfish-governor-smu cyan-skillfish-performance-mode \
            bc250-gpu-freq-restore; do
            if [[ ! -e "$BIN_DIR/$file" && -f "$LEGACY_PREFIX/bin/$file" ]]; then
                install -o root -g root -m 0755 "$LEGACY_PREFIX/bin/$file" "$BIN_DIR/$file"
            fi
        done
        touch "$marker"
    fi
    if [[ ! -e "$FREQ_STATE" && -f "$GOV_CONF_DIR/freq-state" && ! -L "$GOV_CONF_DIR/freq-state" ]]; then
        install -o root -g root -m 0644 "$GOV_CONF_DIR/freq-state" "$FREQ_STATE"
        rm -f "$GOV_CONF_DIR/freq-state"
    fi
}

cleanup_legacy_data() {
    local file
    [[ -d "$LEGACY_PREFIX" ]] || return 0
    for file in /etc/systemd/system/bc250-cu-live-manager.service \
        /etc/bc250-cu-live-manager.conf "$HEAL_UNIT" "$GOV_UNIT" \
        "$RESTORE_UNIT" "$OC_UNIT"; do
        if [[ -f "$file" ]] && grep -qF "$LEGACY_PREFIX" "$file"; then
            warn "Legacy data retained while $file still references it."
            return 0
        fi
    done
    [[ -e "$COMPUTE_MIGRATION_MARKER" && -e "$POWER_MIGRATION_MARKER" ]] || return 0
    rm -rf "$LEGACY_PREFIX" "$ROOT_DATA_DIR/legacy-bc250-40cu"
    log "Removed fully migrated legacy data at $LEGACY_PREFIX."
}

RO_WAS_DISABLED=0
unlock_rootfs() {
    if steamos-readonly status 2>/dev/null | grep -qi enabled; then
        steamos-readonly disable; RO_WAS_DISABLED=1
    fi
}
# NB: must return 0 when idle -- a nonzero return from the EXIT trap under
# set -e overrides the script's real exit status (every run would exit 1)
relock_rootfs() {
    if [[ $RO_WAS_DISABLED -eq 1 ]]; then
        steamos-readonly enable
        RO_WAS_DISABLED=0
    fi
}

# Both the GPU governor and the CPU OC tool drive the SMU through the same
# PCI-config indirect window (0xB8/0xBC) -- never let them run concurrently.
GOV_STOPPED=0
pause_governor() {
    if systemctl is-active "$GOV_SVC" >/dev/null 2>&1; then
        log "Pausing GPU governor while touching the SMU..."
        systemctl stop "$GOV_SVC"; GOV_STOPPED=1
    fi
}
resume_governor() {
    if [[ $GOV_STOPPED -eq 1 ]]; then
        if systemctl start "$GOV_SVC"; then
            log "GPU governor resumed."
            GOV_STOPPED=0
            if [[ -f "$FREQ_STATE" && -f "$RESTORE_UNIT" ]]; then
                systemctl restart "$RESTORE_SVC" \
                    || warn "GPU governor resumed, but the saved frequency range was not restored."
            fi
        else
            warn "GPU governor failed to resume; run: systemctl start $GOV_SVC"
            return 1
        fi
    fi
}

TEMP_DIRS=()
cleanup() {
    local temp_dir
    tui_show_cursor
    resume_governor || true
    for temp_dir in "${TEMP_DIRS[@]-}"; do
        [[ -z "$temp_dir" ]] || rm -rf "$temp_dir"
    done
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
# still relocks the rootfs / resumes the governor on the way out
run_action() {
    local rc=0
    ( trap cleanup EXIT; "$@" ) || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo -e "${CR}${CB}[power]${C0} action failed (exit $rc) -- see message above."
    fi
    pause_key
}

b_ok()   { printf '%s' "${CG}[$1]${C0}"; }
b_mid()  { printf '%s' "${CY}[$1]${C0}"; }
b_off()  { printf '%s' "${CD}[$1]${C0}"; }

c_state() {   # colorize systemctl is-enabled / is-active words
    case "$1" in
        enabled|active|running) printf '%s' "${CG}$1${C0}" ;;
        failed|masked)          printf '%s' "${CR}$1${C0}" ;;
        disabled|inactive|-)    printf '%s' "${CD}$1${C0}" ;;
        *)                      printf '%s' "${CY}$1${C0}" ;;
    esac
}

badge_acpi() {
    if compgen -G /sys/devices/system/cpu/cpu0/cpufreq >/dev/null; then b_ok "active"
    elif [[ -f "$HEAL_UNIT" ]]; then b_mid "installed - reboot pending"
    else b_off "not installed"; fi
}
badge_governor() {
    if systemctl is-active "$GOV_SVC" >/dev/null 2>&1; then b_ok "running"
    elif [[ -x "$GOV_BIN" ]]; then b_mid "installed - not running"
    else b_off "not installed"; fi
}
badge_gov_boot() {
    if [[ "$(systemctl is-enabled "$GOV_SVC" 2>/dev/null)" == enabled ]]; then b_ok "enabled"
    else b_off "not enabled"; fi
}
badge_freq() {
    if [[ -f "$FREQ_STATE" ]]; then
        # shellcheck source=/dev/null
        b_mid "saved: $(tr '\n' ' ' < "$FREQ_STATE" | xargs || true)"
    else b_off "config defaults"; fi
}
badge_load_target() {
    local cfg=""
    cfg=$(lt_config_get)
    if [[ -z "$cfg" ]]; then b_off "governor built-ins"
    elif [[ "$cfg" == "$LT_DEF_UPPER $LT_DEF_LOWER" ]]; then b_ok "tuned default ${cfg/ /\/}"
    else b_mid "custom: ${cfg/ /\/}"; fi
    return 0
}
badge_ramp() {
    local adj n ms step
    adj=$(toml_get timing.intervals adjust)
    n=$(toml_get timing.ramp-rates normal)
    if [[ -z "$adj" || -z "$n" ]]; then b_off "governor built-ins"
    else
        ms=$(( adj / 1000 ))
        step=$(awk -v n="$n" -v m="$ms" 'BEGIN{ printf "%d", n * m }')
        if [[ "$ms" == "$RAMP_DEF_ADJ_MS" && "$n" == "$RAMP_DEF_NORMAL" ]]; then
            b_ok "default: ${step} MHz/${ms} ms"
        else
            b_mid "custom: ${step} MHz/${ms} ms"
        fi
    fi
    return 0
}
badge_oc() {
    local d=""
    d=$(oc_detected_result "$OC_CONF")
    if [[ -z "$d" && -f "$OC_CONF" ]]; then
        d="$(sed -n 's/^frequency = //p' "$OC_CONF" | head -1) MHz"
    fi
    if [[ "$(systemctl is-enabled "$OC_SVC" 2>/dev/null)" == enabled ]]; then b_ok "enabled${d:+ - $d}"
    elif [[ -f "$OC_CONF" || -f "$OC_STAGE_CONF" ]]; then b_mid "detected - not enabled"
    else b_off "stock"; fi
}
badge_oc_saved() {   # persistence verdict, for the enable row
    case "$(oc_persist_state)" in
        none)  b_off "nothing detected yet" ;;
        saved) b_ok "saved - applies at boot" ;;
        stale) b_mid "NOT saved - boot config older" ;;
        live)  b_mid "NOT saved - live only" ;;
    esac
    return 0
}
badge_oc_last() {   # last measured detect result, for the detect row
    local f res
    for f in "$OC_STAGE_CONF" "$OC_CONF"; do
        res=$(oc_detected_result "$f")
        if [[ -n "$res" ]]; then b_mid "last: $res"; break; fi
    done
    return 0
}
badge_oc_live() {   # live CPU voltage, for the status row
    local mv_=""
    mv_=$(oc_live_mv) || mv_=""
    if [[ -n "$mv_" ]]; then b_ok "CPU now: ${mv_} mV"; else b_off "live mV: root only"; fi
    return 0
}

# ============================== ACPI fix ==================================
cmd_acpi() {
    require_root
    install_update_persistence
    migrate_legacy_data
    mkdir -p "$ACPI_DIR"

    # --- fetch SSDTs and build the persistent override cpio ---------------
    if [[ ! -f "$CPIO_MASTER" ]]; then
        log "Fetching SSDT tables (bc250-collective/bc250-acpi-fix)..."
        local work
        work=$(mktemp -d /tmp/bc250-acpi.XXXXXX)
        TEMP_DIRS+=("$work")
        mkdir -p "$work/kernel/firmware/acpi"
        curl -fL -o "$work/kernel/firmware/acpi/SSDT-CST.aml" "$ACPI_RAW_BASE/SSDT-CST.aml"
        curl -fL -o "$work/kernel/firmware/acpi/SSDT-PST.aml" "$ACPI_RAW_BASE/SSDT-PST.aml"
        # keep master copies of the raw tables too
        cp "$work"/kernel/firmware/acpi/*.aml "$ACPI_DIR/"

        command -v cpio >/dev/null 2>&1 || {
            unlock_rootfs
            pacman -Sy --noconfirm cpio || die "cpio unavailable and pacman install failed."
        }
        log "Building early-initrd ACPI override cpio..."
        ( cd "$work" && find kernel | cpio -o -H newc > "$CPIO_MASTER" )
        log "Master cpio -> $CPIO_MASTER"
    else
        log "Master cpio already built at $CPIO_MASTER"
    fi

    # --- install into /boot and wire up GRUB ------------------------------
    unlock_rootfs
    cp -f "$CPIO_MASTER" "$CPIO_BOOT"
    log "Installed -> $CPIO_BOOT"

    # Upstream grub-mkconfig honors GRUB_EARLY_INITRD_LINUX_CUSTOM (the file
    # must sit in /boot). The heal helper recreates this setting after updates.
    if grep -q '^GRUB_EARLY_INITRD_LINUX_CUSTOM=' /etc/default/grub 2>/dev/null; then
        sed -i 's|^GRUB_EARLY_INITRD_LINUX_CUSTOM=.*|GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"|' \
            /etc/default/grub
    else
        echo 'GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"' >> /etc/default/grub
    fi
    log "GRUB_EARLY_INITRD_LINUX_CUSTOM set in /etc/default/grub"

    log "Regenerating GRUB config..."
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    else
        grub-mkconfig -o /boot/grub/grub.cfg
    fi

    if grep -q 'acpi_override.cpio' /boot/grub/grub.cfg 2>/dev/null; then
        log "grub.cfg references the override -- good."
    else
        warn "grub.cfg does NOT reference acpi_override.cpio."
        warn "Your SteamOS grub build may ignore GRUB_EARLY_INITRD_LINUX_CUSTOM."
        warn "Fallback: manually prepend it on the initrd line(s) in /boot/grub/grub.cfg:"
        warn "    initrd /acpi_override.cpio /initramfs-...img"
        warn "(the self-heal service checks the cpio file, not the cfg edit)"
    fi

    # --- self-heal service: SteamOS updates wipe /boot --------------------
    log "Installing boot-time self-heal service..."
    cat > "$HEAL_HELPER" << EOF
#!/usr/bin/env bash
set -euo pipefail
ROOTFS_WAS_READONLY=0
relock() {
    if [[ \$ROOTFS_WAS_READONLY -eq 1 ]]; then
        steamos-readonly enable || true
    fi
}
trap relock EXIT

if [[ ! -f $CPIO_BOOT ]] || ! cmp -s "$CPIO_MASTER" "$CPIO_BOOT" \
   || ! grep -q '^GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"' /etc/default/grub 2>/dev/null \
   || ! grep -q acpi_override.cpio /boot/grub/grub.cfg 2>/dev/null; then
    if steamos-readonly status 2>/dev/null | grep -qi enabled; then
        steamos-readonly disable
        ROOTFS_WAS_READONLY=1
    fi
    cp -f "$CPIO_MASTER" "$CPIO_BOOT"
    if grep -q '^GRUB_EARLY_INITRD_LINUX_CUSTOM=' /etc/default/grub 2>/dev/null; then
        sed -i 's|^GRUB_EARLY_INITRD_LINUX_CUSTOM=.*|GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"|' /etc/default/grub
    else
        printf '%s\n' 'GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"' >> /etc/default/grub
    fi
    if command -v update-grub >/dev/null; then
        update-grub
    else
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
    if grep -q acpi_override.cpio /boot/grub/grub.cfg 2>/dev/null; then
        echo "bc250: ACPI override restored after OS update; REBOOT to re-activate C/P-states" | systemd-cat -p warning
    else
        echo "bc250: grub.cfg still lacks acpi_override.cpio after regen -- add the initrd line manually (see bc250-power.sh acpi output)" | systemd-cat -p err
        exit 1
    fi
fi
EOF
    chmod 755 "$HEAL_HELPER"
    rm -f /etc/bc250-acpi-heal.sh

    cat > "$HEAL_UNIT" << EOF
[Unit]
Description=BC-250 ACPI override self-heal (restore after SteamOS updates)
After=local-fs.target
RequiresMountsFor=$ROOT_DATA_DIR

[Service]
Type=oneshot
ExecStart=$HEAL_HELPER
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # --- cpufreq governor setter (schedutil once P-states exist) ----------
    cat > "$CPUFREQ_UNIT" << 'EOF'
[Unit]
Description=BC-250 set schedutil cpufreq governor (needs ACPI P-states)
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
  if compgen -G /sys/devices/system/cpu/cpu0/cpufreq >/dev/null; then \
    echo schedutil | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null; \
  else \
    echo "bc250: cpufreq not present -- ACPI override not active this boot" | systemd-cat -p warning; \
  fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable bc250-acpi-heal.service bc250-cpufreq.service
    cleanup_legacy_data
    relock_rootfs

    log "ACPI fix installed. REBOOT required, then verify:"
    log "  ls /sys/devices/system/cpu/cpu0/cpuidle/          # state0..state3"
    log "  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies"
    log "  (expect 800 MHz .. 3200 MHz steps)"
}

# ============================ GPU governor ================================
# Single source for the tuned voltage curve: written on governor install and
# restored by 'gpu-volt reset'.
default_safe_points() {
    cat << 'EOF'
# Voltage curve: flat 1000 mV ceiling (2026 community finding: most boards
# hold it; bump the TOP point +15-25 mV only if yours proves unstable there)
[[safe-points]]
frequency = 1000
voltage = 800

[[safe-points]]
frequency = 1500
voltage = 900

[[safe-points]]
frequency = 2000
voltage = 1000

[[safe-points]]
frequency = 2150
voltage = 1000
EOF
}

check_conflicts() {
    local s
    for s in cyan-skillfish-governor.service cyan-skillfish-governor-tt.service \
             oberon-governor.service; do
        if systemctl is-active "$s" >/dev/null 2>&1; then
            warn "Conflicting governor $s active -- disabling (two controllers fight)."
            systemctl disable --now "$s"
        fi
    done
}

cmd_governor() {
    require_root
    migrate_legacy_data
    recover_update_settings
    mkdir -p "$BIN_DIR" "$GOV_CONF_DIR"
    check_conflicts

    log "Resolving latest cyan-skillfish-governor-smu release..."
    local url api_json rel_tag
    api_json=$(curl -fsSL "$GOV_API") || die "GitHub API request failed (network?)."
    # Pin any raw-file fallback fetches to the SAME release as the binary --
    # branch HEAD can have renamed D-Bus interfaces vs the release binary.
    rel_tag=$(grep -oP '"tag_name":\s*"\K[^"]+' <<< "$api_json" | head -1 || true)
    [[ -n "$rel_tag" ]] && GOV_RAW="https://raw.githubusercontent.com/filippor/cyan-skillfish-governor/$rel_tag"
    log "Release: ${rel_tag:-unknown} (raw fallbacks pinned to it)"
    # NB: '|| true' guards are load-bearing -- under set -e/pipefail a
    # non-matching grep would otherwise kill the script silently.
    url=$(grep -oP '"browser_download_url":\s*"\K[^"]*smu[^"]*x86_64[^"]*\.tar\.gz' \
              <<< "$api_json" | head -1 || true)
    [[ -n "$url" ]] || url=$(grep -oP '"browser_download_url":\s*"\K[^"]*\.tar\.gz' \
              <<< "$api_json" | head -1 || true)
    [[ -n "$url" ]] || die "No .tar.gz asset found in the latest release. Assets were:
$(grep -oP '"browser_download_url":\s*"\K[^"]*' <<< "$api_json" || echo '  (none / API rate-limited)')"
    log "  $url"

    local work
    work=$(mktemp -d /tmp/csg-install.XXXXXX)
    TEMP_DIRS+=("$work")
    curl -fL -o "$work/csg.tar.gz" "$url"
    tar -xf "$work/csg.tar.gz" -C "$work"

    local bin perf
    bin=$(find "$work" -type f -name 'cyan-skillfish-governor-smu' \
              ! -name '*.service' ! -name '*.spec' | head -1 || true)
    [[ -n "$bin" ]] || die "No prebuilt binary in archive. Contents:
$(find "$work" -type f | head -20)"
    install -m 755 "$bin" "$GOV_BIN";  log "Binary -> $GOV_BIN"

    # perf-mode helper + D-Bus policy: not always in the tarball -- fall
    # back to fetching them straight from the smu branch of the repo.
    perf=$(find "$work" -type f -name 'cyan-skillfish-performance-mode*' | head -1 || true)
    if [[ -n "$perf" ]]; then
        install -m 755 "$perf" "$PERF_BIN"
    else
        log "Helper not in tarball; fetching from repo..."
        curl -fL -o "$PERF_BIN" "$GOV_RAW/scripts/cyan-skillfish-performance-mode" \
            || warn "Could not fetch perf-mode helper; busctl SetRange works as a substitute."
        if [[ -s "$PERF_BIN" ]]; then chmod 755 "$PERF_BIN"
        else rm -f "$PERF_BIN"; fi
    fi
    [[ -x "$PERF_BIN" ]] && log "Perf-mode helper -> $PERF_BIN"

    # D-Bus policy: upstream's shipped policy file is STALE vs its own binary
    # (file grants com.cyan.SkillFishGovernor; the v0.4.x binary requests
    # com.cyanskillfish.Governor -- verified via strings on the binary).
    # Write our own policy granting both names.
    mkdir -p /etc/dbus-1/system.d
    cat > "$DBUS_POLICY" << 'EOF'
<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root">
    <allow own="com.cyan.SkillFishGovernor"/>
    <allow own="com.cyanskillfish.Governor"/>
    <allow send_destination="com.cyan.SkillFishGovernor"/>
    <allow send_destination="com.cyanskillfish.Governor"/>
  </policy>
  <policy context="default">
    <allow send_destination="com.cyan.SkillFishGovernor"/>
    <allow send_destination="com.cyanskillfish.Governor"/>
    <allow send_interface="com.cyan.SkillFishGovernor.PerformanceMode"/>
    <allow send_interface="com.cyanskillfish.Governor.PerformanceMode"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
  </policy>
</busconfig>
EOF
    log "D-Bus policy (dual-name) -> $DBUS_POLICY"
    # dbus-broker only reliably reloads files in dirs it saw at launch; try a
    # reload, and warn that a reboot may be needed if the dir is brand new.
    busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig \
        2>/dev/null || warn "D-Bus policy reload failed; a reboot will activate it."

    if [[ -f "$GOV_CONF" ]]; then
        warn "Existing config kept at $GOV_CONF"
    else
        log "Writing tuned config (38/40 CU, docs-schema) -> $GOV_CONF"
        cat > "$GOV_CONF" << 'EOF'
# BC-250 SMU governor -- tuned for the 38/40 CU unlock on stock-class cooling.
# Full community voltage curve; operating range capped at 1500 MHz (the
# unlock sweet spot). Raise live without restart when cooling allows:
#   cyan-skillfish-performance-mode --range 0 2000
# Thermal throttling applies regardless of range.

[timing.intervals]
sample = 500
adjust = 200_000

[gpu-usage]
fix-metrics = true          # also fixes MangoHud/radeontop 655% bug
method = "busy-flag"
flush-every = 10

[gpu]
set-method = "smu"          # firmware calls; no kernel patch

[dbus]
enabled = true

[timing.ramp-rates]
normal = 1
burst = 50

[timing]
burst-samples = 60
down-events = 5

[frequency-thresholds]
adjust = 10

[load-target]
upper = 0.80
lower = 0.65

[frequency-range]
max = 1500                  # sustained-safe with 38 CUs routed

[temperature]
throttling = 85
throttling_recovery = 75

EOF
        default_safe_points >> "$GOV_CONF"
    fi

    log "Writing systemd unit (persistent paths) -> $GOV_UNIT"
    cat > "$GOV_UNIT" << EOF
[Unit]
Description=Cyan Skillfish GPU governor (SMU) -- BC-250
After=multi-user.target bc250-cu-live-manager.service
RequiresMountsFor=$ROOT_DATA_DIR

[Service]
Type=simple
ExecStart=$GOV_BIN $GOV_CONF
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload

    install_freq_persistence force
    install_update_persistence

    log "Test-starting (not yet enabled at boot)..."
    systemctl restart "$GOV_SVC"; sleep 2
    systemctl is-active "$GOV_SVC" >/dev/null || {
        journalctl -u "$GOV_SVC" -n 30 --no-pager
        die "Governor failed to start -- log above."
    }
    systemctl restart "$RESTORE_SVC" \
        || warn "Governor started, but the saved frequency range was not restored."
    cleanup_legacy_data
    log "Running. Load the GPU for a few minutes; watch clocks and temps:"
    log "  watch -n1 'cat /sys/class/drm/card*/device/pp_dpm_sclk 2>/dev/null; sensors | grep -E \"edge|PPT\"'"
    log "Then lock it in: sudo $0 enable"
}

# ================================ misc ====================================
# Live GPU frequency control. Prefers the perf-mode helper; falls back to
# direct busctl using the bus name the v0.4.x binary ACTUALLY registers
# (com.cyanskillfish.Governor -- not the documented com.cyan.SkillFishGovernor).
BUS_NAME="com.cyanskillfish.Governor"
BUS_PATH="/com/cyanskillfish/Governor"
BUS_IFACE="com.cyanskillfish.Governor.PerformanceMode"

gov_dbus() { busctl --system call "$BUS_NAME" "$BUS_PATH" "$BUS_IFACE" "$@"; }

# --- freq persistence: save the last applied setting and reapply at boot ---
# The governor's D-Bus state is runtime-only; a restart/reboot reverts to
# config.toml. We record the last 'freq' command in a state file and a
# oneshot service replays it once the governor's bus name is up.
install_freq_persistence() {
    # fast path for everyday 'freq' calls; 'force' (used by installs)
    # rewrites the files so script updates propagate
    if [[ "${1:-}" != force && -x "$RESTORE_BIN" && -f "$RESTORE_UNIT" ]] \
       && [[ "$(systemctl is-enabled "$RESTORE_SVC" 2>/dev/null)" == enabled ]]; then
        return 0
    fi

    mkdir -p "$BIN_DIR" "$ROOT_DATA_DIR/governor"
    cat > "$RESTORE_BIN" << EOF
#!/usr/bin/env bash
# bc250: reapply the saved GPU freq setting after the governor starts.
# Written by bc250-power.sh -- do not edit; it gets regenerated.
set -u
STATE="$FREQ_STATE"
PERF="$PERF_BIN"
BUS_NAME="$BUS_NAME"; BUS_PATH="$BUS_PATH"; BUS_IFACE="$BUS_IFACE"
[[ -f "\$STATE" ]] || exit 0
MODE= A= B=
while IFS='=' read -r key value; do
    case "\$key" in
        MODE) MODE="\$value" ;;
        A) A="\$value" ;;
        B) B="\$value" ;;
    esac
done < "\$STATE"
case "\$MODE" in
    max) A= B= ;;
    pin) [[ "\$A" =~ ^[0-9]+$ ]] || exit 1; B= ;;
    range) [[ "\$A" =~ ^[0-9]+$ && "\$B" =~ ^[0-9]+$ ]] || exit 1 ;;
    *) exit 1 ;;
esac
# governor registers its bus name shortly after start; give it up to 30 s
for _ in \$(seq 1 30); do
    busctl --system status "\$BUS_NAME" >/dev/null 2>&1 && break
    sleep 1
done
if ! busctl --system status "\$BUS_NAME" >/dev/null 2>&1; then
    echo "bc250: governor bus name never appeared -- GPU freq state NOT restored" \
        | systemd-cat -p warning
    exit 1
fi
if [[ -x "\$PERF" ]]; then
    case "\$MODE" in
        max)   "\$PERF" --on ;;
        pin)   "\$PERF" --fixed-frequency "\$A" ;;
        range) "\$PERF" --range "\$A" "\$B" ;;
        *)     exit 0 ;;
    esac
else
    case "\$MODE" in
        max)   busctl --system set-property "\$BUS_NAME" "\$BUS_PATH" "\$BUS_IFACE" Enabled b true ;;
        pin)   busctl --system call "\$BUS_NAME" "\$BUS_PATH" "\$BUS_IFACE" SetFixedFrequency u "\$A" ;;
        range) busctl --system call "\$BUS_NAME" "\$BUS_PATH" "\$BUS_IFACE" SetRange uu "\$A" "\$B" ;;
        *)     exit 0 ;;
    esac
fi && echo "bc250: restored GPU freq setting (\$MODE \${A:-} \${B:-})" | systemd-cat -p info
EOF
    chmod 755 "$RESTORE_BIN"

    cat > "$RESTORE_UNIT" << EOF
[Unit]
Description=BC-250 restore saved GPU freq setting (survives reboots)
After=$GOV_SVC
PartOf=$GOV_SVC
RequiresMountsFor=$ROOT_DATA_DIR

[Service]
Type=oneshot
ExecStart=$RESTORE_BIN
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$RESTORE_SVC" >/dev/null 2>&1
    log "Boot-time freq restore installed ($RESTORE_SVC)."
}

save_freq_state() {           # save_freq_state <max|pin|range> [a] [b]
    install_freq_persistence
    install -d -o root -g root -m 0755 "$(dirname "$FREQ_STATE")"
    printf 'MODE=%s\nA=%s\nB=%s\n' "$1" "${2:-}" "${3:-}" > "$FREQ_STATE"
    chown root:root "$FREQ_STATE"
    chmod 0644 "$FREQ_STATE"
    log "Saved -- reapplied automatically at boot ('$0 freq auto' to clear)."
}

clear_freq_state() {
    if [[ -f "$FREQ_STATE" ]]; then
        rm -f "$FREQ_STATE"
        log "Saved freq state cleared -- boots return to config defaults."
    fi
}

cmd_freq() {
    require_root
    systemctl is-active "$GOV_SVC" >/dev/null 2>&1 \
        || die "Governor not running -- freq control goes through it."

    local a="${1:-}" b="${2:-}"
    # Helper handles everything including status; use it when available.
    if [[ -x "$PERF_BIN" ]]; then
        case "$a" in
            "")            "$PERF_BIN" --status ;;
            status)        "$PERF_BIN" --status ;;
            auto|off)      "$PERF_BIN" --off && clear_freq_state ;;
            max|on)        "$PERF_BIN" --on  && save_freq_state max ;;
            [0-9]*)
                if [[ -n "$b" ]]; then "$PERF_BIN" --range "$a" "$b" && save_freq_state range "$a" "$b"
                else                   "$PERF_BIN" --fixed-frequency "$a" && save_freq_state pin "$a"; fi ;;
            *) die "Usage: $0 freq [status|auto|max|<MHz>|<min> <max>]" ;;
        esac
        return
    fi

    # busctl fallback (helper missing)
    case "$a" in
        ""|status)
            busctl --system get-property "$BUS_NAME" "$BUS_PATH" "$BUS_IFACE" Enabled \
                || warn "Bus name absent -- D-Bus policy not active? (reboot after policy install)" ;;
        auto|off)  busctl --system set-property "$BUS_NAME" "$BUS_PATH" "$BUS_IFACE" Enabled b false \
                       && log "Adaptive scaling restored (config defaults apply)." \
                       && clear_freq_state ;;
        max|on)    busctl --system set-property "$BUS_NAME" "$BUS_PATH" "$BUS_IFACE" Enabled b true \
                       && log "Performance mode ON (max frequency, no idle downscale)." \
                       && save_freq_state max ;;
        [0-9]*)
            if [[ -n "$b" ]]; then
                gov_dbus SetRange uu "$a" "$b" && log "Range set: ${a}-${b} MHz (0 = no limit)." \
                    && save_freq_state range "$a" "$b"
            else
                gov_dbus SetFixedFrequency u "$a" && log "Pinned at $a MHz ('$0 freq auto' when done)." \
                    && save_freq_state pin "$a"
            fi ;;
        *) die "Usage: $0 freq [status|auto|max|<MHz>|<min> <max>]" ;;
    esac
}

# ========================= GPU voltage control ============================
# GPU voltage belongs to the governor's safe-points curve (it applies mV per
# frequency continuously); forcing vid directly over SMU would fight it.
# These commands edit the curve in config.toml, restart the governor, and
# reapply the saved freq setting (a restart otherwise drops runtime state).
VOLT_MIN=700    # below: artifact/crash territory even at low clocks
VOLT_MAX=1050   # above the community flat-1000 ceiling + small margin

restart_governor_reapply() {
    systemctl restart "$GOV_SVC"
    log "Governor restarted with the new curve."
    if [[ -f "$FREQ_STATE" && -x "$RESTORE_BIN" ]]; then
        if "$RESTORE_BIN"; then log "Saved freq setting reapplied."
        else warn "Could not reapply saved freq setting -- check 'freq status'."; fi
    fi
}

volt_show() {
    [[ -f "$GOV_CONF" ]] || die "No governor config at $GOV_CONF -- run '$0 governor' first."
    echo -e "${CB}=== GPU voltage curve ($GOV_CONF) ===${C0}"
    awk '/^frequency = /{f=$3} /^voltage = /{printf "  %4d MHz -> %4d mV\n", f, $3}' "$GOV_CONF"
    local live
    live=$(sensors 2>/dev/null | grep -im1 vddgfx || true)
    [[ -n "$live" ]] && echo "  live: $live"
    echo "  (any frequency you run needs a point at or above it)"
}

volt_check_bounds() {   # validate every voltage in a candidate config
    local bad
    bad=$(awk -v lo="$VOLT_MIN" -v hi="$VOLT_MAX" \
        '/^voltage = /{ if ($3 < lo || $3 > hi) printf "%s ", $3 }' "$1")
    [[ -z "$bad" ]] || { rm -f "$1"; die "Voltage(s) outside safe ${VOLT_MIN}-${VOLT_MAX} mV range: $bad"; }
}

volt_offset() {
    require_root
    local delta="${1:-}"
    [[ "$delta" =~ ^[+-]?[0-9]+$ ]] || die "Usage: $0 gpu-volt offset <±mV>   (e.g. offset -25)"
    [[ -f "$GOV_CONF" ]] || die "No governor config -- run '$0 governor' first."
    awk -v d="$delta" '/^voltage = /{ print "voltage = " $3+d; next } { print }' \
        "$GOV_CONF" > "$GOV_CONF.tmp"
    volt_check_bounds "$GOV_CONF.tmp"
    mv "$GOV_CONF.tmp" "$GOV_CONF"
    log "Whole curve shifted ${delta} mV:"
    volt_show
    restart_governor_reapply
    warn "Stress test now -- undervolts that boot fine can still crash under load."
}

volt_set() {
    require_root
    local freq="${1:-}" mv_="${2:-}"
    [[ "$freq" =~ ^[0-9]+$ && "$mv_" =~ ^[0-9]+$ ]] || die "Usage: $0 gpu-volt set <freqMHz> <mV>"
    [[ -f "$GOV_CONF" ]] || die "No governor config -- run '$0 governor' first."
    grep -q "^frequency = ${freq}\$" "$GOV_CONF" \
        || die "No curve point at $freq MHz. Existing points: $(awk '/^frequency = /{printf "%s ", $3}' "$GOV_CONF")"
    awk -v f="$freq" -v m="$mv_" '
        /^frequency = /{cur=$3}
        /^voltage = / && cur==f { print "voltage = " m; next }
        { print }' "$GOV_CONF" > "$GOV_CONF.tmp"
    volt_check_bounds "$GOV_CONF.tmp"
    mv "$GOV_CONF.tmp" "$GOV_CONF"
    log "Point $freq MHz -> $mv_ mV."
    restart_governor_reapply
    warn "Stress test now -- undervolts that boot fine can still crash under load."
}

volt_reset() {
    require_root
    [[ -f "$GOV_CONF" ]] || die "No governor config -- run '$0 governor' first."
    # our generated config keeps the curve last; cut it off and re-append
    awk '/^# Voltage curve/ || /^\[\[safe-points\]\]/{ exit } { print }' \
        "$GOV_CONF" > "$GOV_CONF.tmp"
    default_safe_points >> "$GOV_CONF.tmp"
    mv "$GOV_CONF.tmp" "$GOV_CONF"
    log "Curve reset to tuned defaults."
    volt_show
    restart_governor_reapply
}

cmd_gpu_volt() {
    local sub="${1:-show}"
    shift || true
    case "$sub" in
        ""|show)  volt_show ;;
        offset)   volt_offset "$@" ;;
        set)      volt_set "$@" ;;
        reset)    volt_reset ;;
        *) die "Usage: $0 gpu-volt {show | offset <±mV> | set <freqMHz> <mV> | reset}" ;;
    esac
}

# ========================= GPU load-target control ========================
# The governor only clocks UP when sampled GPU busy% exceeds load-target
# upper -- a frame-capped light game can sit at 60-75% busy at idle clocks
# forever and never trigger a ramp. These commands edit [load-target] in
# config.toml (persists) and push the same values live over D-Bus
# (SetLoadTarget -- no restart, saved freq state untouched).
LT_DEF_UPPER=0.80    # tuned defaults written by 'governor'
LT_DEF_LOWER=0.65
LT_EAGER_UPPER=0.40  # light-load preset: ramps on loads the default ignores
LT_EAGER_LOWER=0.10

lt_norm() {   # "60" or "0.60" -> "0.60"; rejects junk and out-of-range
    awk -v v="${1:-}" 'BEGIN{
        if (v !~ /^[0-9]+(\.[0-9]+)?$/) exit 1
        v += 0; if (v > 1) v /= 100
        if (v < 0.05 || v > 0.99) exit 1
        printf "%.2f", v }'
}

lt_config_get() {   # config values as "upper lower", normalized; empty if absent
    [[ -f "$GOV_CONF" ]] || return 0
    awk '/^\[/{ lt = ($0=="[load-target]") }
         lt && /^upper = /{u=$3} lt && /^lower = /{l=$3}
         END{ if (u!="" && l!="") printf "%.2f %.2f", u, l }' "$GOV_CONF"
}

lt_live_get() {   # live values from the governor as "upper lower"; empty if down
    local u l
    u=$(busctl --system get-property "$BUS_NAME" "$BUS_PATH" "$BUS_IFACE" \
            LoadTargetMax 2>/dev/null | awk '{printf "%.2f", $2}') || true
    l=$(busctl --system get-property "$BUS_NAME" "$BUS_PATH" "$BUS_IFACE" \
            LoadTargetMin 2>/dev/null | awk '{printf "%.2f", $2}') || true
    [[ -n "$u" && -n "$l" ]] && echo "$u $l"
    return 0
}

lt_show() {
    [[ -f "$GOV_CONF" ]] || die "No governor config at $GOV_CONF -- run '$0 governor' first."
    echo -e "${CB}=== GPU load targets ===${C0}"
    local cfg live
    cfg=$(lt_config_get)
    if [[ -n "$cfg" ]]; then
        echo "  config (applies at boot):  upper ${cfg% *}  lower ${cfg#* }"
    else
        echo "  config: no [load-target] section -- governor built-ins apply (0.95/0.80)"
    fi
    live=$(lt_live_get)
    if [[ -n "$live" ]]; then
        echo "  live (governor, running):  upper ${live% *}  lower ${live#* }"
    else
        echo "  live: governor not running (or D-Bus down)"
    fi
    echo "  clocks UP when GPU busy% stays above upper; steps DOWN below lower."
    echo "  Lower upper = lighter loads trigger a ramp off idle clocks."
}

lt_apply_live() {   # push to the running governor; restart only as fallback
    local upper="$1" lower="$2"
    if ! systemctl is-active "$GOV_SVC" >/dev/null 2>&1; then
        warn "Governor not running -- values take effect when it starts."
        return 0
    fi
    # D-Bus signature is SetLoadTarget(min, max) = (lower, upper)
    if gov_dbus SetLoadTarget dd "$lower" "$upper" >/dev/null 2>&1; then
        log "Applied live -- no restart needed."
    else
        warn "D-Bus call failed -- restarting the governor to load the new config."
        restart_governor_reapply
    fi
}

lt_set() {
    require_root
    local usage="Usage: $0 load-target set <upper> <lower>   (percent 60 45, or fractions 0.60 0.45)"
    local upper lower
    upper=$(lt_norm "${1:-}") || die "$usage"
    lower=$(lt_norm "${2:-}") || die "$usage"
    awk -v u="$upper" -v l="$lower" 'BEGIN{ exit !(l+0 < u+0) }' \
        || die "lower ($lower) must be below upper ($upper)."
    [[ -f "$GOV_CONF" ]] || die "No governor config -- run '$0 governor' first."
    if grep -q '^\[load-target\]' "$GOV_CONF"; then
        awk -v u="$upper" -v l="$lower" '
            /^\[/{ lt = ($0=="[load-target]") }
            lt && /^upper = /{ print "upper = " u; next }
            lt && /^lower = /{ print "lower = " l; next }
            { print }' "$GOV_CONF" > "$GOV_CONF.tmp"
    else
        # section missing (hand-edited config): insert ahead of the voltage
        # curve, or append -- both are valid TOML table placements
        awk -v u="$upper" -v l="$lower" '
            !done && (/^# Voltage curve/ || /^\[\[safe-points\]\]/) {
                print "[load-target]"; print "upper = " u
                print "lower = " l; print ""; done=1 }
            { print }
            END{ if (!done) { print "[load-target]"; print "upper = " u; print "lower = " l } }' \
            "$GOV_CONF" > "$GOV_CONF.tmp"
    fi
    mv "$GOV_CONF.tmp" "$GOV_CONF"
    log "Load targets saved: upper = $upper, lower = $lower (persists across reboots)."
    awk -v u="$upper" 'BEGIN{ exit !(u+0 < 0.40) }' \
        && warn "Upper below 0.40: very eager -- expect higher idle clocks/power."
    lt_apply_live "$upper" "$lower"
}

cmd_load_target() {
    local sub="${1:-show}"
    shift || true
    case "$sub" in
        ""|show)  lt_show ;;
        set)      lt_set "$@" ;;
        eager)    lt_set "$LT_EAGER_UPPER" "$LT_EAGER_LOWER" ;;
        reset)    lt_set "$LT_DEF_UPPER" "$LT_DEF_LOWER" ;;
        *) die "Usage: $0 load-target {show | set <upper> <lower> | eager | reset}" ;;
    esac
}

# =========================== GPU ramp behavior ============================
# Every [timing.intervals] adjust cycle the governor moves its target by
# ramp-rates.normal x adjust_ms MHz. So climb SPEED is 'normal' alone
# (MHz/ms, interval-independent) and 'adjust' only sets step GRANULARITY.
# 'ramp set T' takes one number -- the idle-to-max climb time in ms -- and
# derives the smoothest step that cannot hunt: GPU busy% ~ 1/freq, so a
# step of S MHz at frequency f moves load by ~S/f; keeping
#   S <= f_min x (upper - lower) / upper
# means no single step can jump across the whole load-target band and
# oscillate. These are startup-only params (no D-Bus): governor restarts.
RAMP_DEF_ADJ_MS=200; RAMP_DEF_NORMAL=1; RAMP_DEF_BURST=50; RAMP_DEF_DE=5
RAMP_FALLBACK_MIN=500; RAMP_FALLBACK_MAX=2200

toml_get() {   # toml_get <section> <key> [file] -- value, underscores stripped
    local f="${3:-$GOV_CONF}"
    [[ -f "$f" ]] || return 0
    awk -v sec="[$1]" -v key="$2" '
        /^\[/{ insec = ($0 == sec) }
        insec && $1 == key && $2 == "=" { gsub("_", "", $3); print $3; exit }
    ' "$f"
}

toml_set() {   # toml_set <section> <key> <value> <file> -- edits file in place
    local f="$4"
    awk -v sec="[$1]" -v key="$2" -v val="$3" '
        function emit() { print key " = " val; done = 1 }
        /^\[/{ if (insec && !done) emit()             # leaving section, key absent
               insec = ($0 == sec); if (insec) found = 1 }
        insec && !done && $1 == key && $2 == "=" { emit(); next }
        { print }
        END{ if (!done) { if (!found) { print ""; print sec }; emit() } }
    ' "$f" > "$f.n" && mv "$f.n" "$f"
}

ramp_allowed_range() {   # hardware range from the running governor; empty if down
    local mn mx
    mn=$(busctl --system get-property "$BUS_NAME" "$BUS_PATH/Range/Allowed" \
             "$BUS_NAME.Range" min 2>/dev/null | awk '{print $2}') || true
    mx=$(busctl --system get-property "$BUS_NAME" "$BUS_PATH/Range/Allowed" \
             "$BUS_NAME.Range" max 2>/dev/null | awk '{print $2}') || true
    [[ -n "$mn" && -n "$mx" ]] && echo "$mn $mx"
    return 0
}

ramp_range() {   # "fmin fmax [assumed]" -- config range clamped by hw allowed
    local cmin cmax amin amax fmin fmax note=""
    cmin=$(toml_get frequency-range min)
    cmax=$(toml_get frequency-range max)
    read -r amin amax <<< "$(ramp_allowed_range)"
    if   [[ -n "$cmin" && -n "$amin" ]]; then fmin=$(( cmin > amin ? cmin : amin ))
    elif [[ -n "$cmin$amin" ]];          then fmin="${cmin:-$amin}"
    else fmin=$RAMP_FALLBACK_MIN; note=assumed; fi
    if   [[ -n "$cmax" && -n "$amax" ]]; then fmax=$(( cmax < amax ? cmax : amax ))
    elif [[ -n "$cmax$amax" ]];          then fmax="${cmax:-$amax}"
    else fmax=$RAMP_FALLBACK_MAX; note=assumed; fi
    echo "$fmin $fmax $note"
}

ramp_lt() {   # load targets from config as "upper lower", defaults if absent
    local lt
    lt=$(lt_config_get)
    echo "${lt:-$LT_DEF_UPPER $LT_DEF_LOWER}"
}

ramp_restart_if_active() {   # ramp params are read at startup only
    if systemctl is-active "$GOV_SVC" >/dev/null 2>&1; then
        restart_governor_reapply
    else
        warn "Governor not running -- new ramp params load when it starts."
    fi
}

ramp_show() {
    [[ -f "$GOV_CONF" ]] || die "No governor config at $GOV_CONF -- run '$0 governor' first."
    local adj_us sample normal de bs fmin fmax note upper lower
    adj_us=$(toml_get timing.intervals adjust);  adj_us=${adj_us:-20000}
    sample=$(toml_get timing.intervals sample);  sample=${sample:-2000}
    normal=$(toml_get timing.ramp-rates normal); normal=${normal:-1}
    de=$(toml_get timing down-events);           de=${de:-10}
    bs=$(toml_get timing burst-samples)
    read -r fmin fmax note <<< "$(ramp_range)"
    read -r upper lower   <<< "$(ramp_lt)"
    echo -e "${CB}=== GPU ramp behavior ===${C0}"
    awk -v aus="$adj_us" -v n="$normal" -v de="$de" -v fmin="$fmin" -v fmax="$fmax" \
        -v up="$upper" -v lo="$lower" -v bs="${bs:-0}" -v sus="$sample" 'BEGIN{
        ms = aus / 1000.0
        S = n * ms
        ceil = fmin * (up - lo) / up
        printf "  step:      %.0f MHz every %.0f ms  (rate %g MHz/ms)\n", S, ms, n
        printf "  climb:     idle->max ~%.0f ms across %d-%d MHz\n", (fmax - fmin) / n, fmin, fmax
        printf "  downhold:  %.0f ms of low load before stepping down (down-events %d)\n", de * ms, de
        if (bs > 0) printf "  burst:     jump to max after %.0f ms of saturated load\n", bs * sus / 1000.0
        else        printf "  burst:     disabled\n"
        printf "  hunting:   step ceiling %.0f MHz at load targets %.2f/%.2f -> %s\n", ceil, up, lo,
            (S <= ceil + 0.5) ? "OK, cannot oscillate" \
                              : "AT RISK -- may bounce at steady load (run: ramp set)"
    }'
    [[ -n "$note" ]] && echo "  (hardware floor assumed ${fmin} MHz -- start the governor for the real one)"
    return 0
}

ramp_set() {
    require_root
    local T="${1:-}"
    [[ "$T" =~ ^[0-9]+$ ]] || die "Usage: $0 ramp set <climb-ms>   (idle-to-max climb time, e.g. 500)"
    (( T >= 200 && T <= 5000 )) || die "Climb time $T ms outside the sane 200-5000 ms window."
    [[ -f "$GOV_CONF" ]] || die "No governor config -- run '$0 governor' first."

    local fmin fmax note upper lower
    read -r fmin fmax note <<< "$(ramp_range)"
    [[ -n "$note" ]] && warn "Governor not running -- assuming a ${fmin} MHz hardware floor."
    (( fmax > fmin )) || die "Bad operating range ${fmin}-${fmax} MHz."
    local R=$(( fmax - fmin ))
    read -r upper lower <<< "$(ramp_lt)"

    # speed normal = R/T; hunting-safe step S <= fmin*(upper-lower)/upper;
    # interval = S/normal clamped to 50-200 ms (>= ~3 frames per load
    # average, still responsive). If the clamp pushes S past the ceiling,
    # slow the climb to the smallest hunting-free time instead of hunting.
    local calc normal adjust_ms step de teff capped
    calc=$(awk -v R="$R" -v T="$T" -v fmin="$fmin" -v up="$upper" -v lo="$lower" 'BEGIN{
        normal = R / T
        ceil = fmin * (up - lo) / up
        S = 0.7 * ceil
        if (S < 30) S = 30                       # dither floor: 3x apply threshold
        adj = S / normal
        if (adj < 50) adj = 50; if (adj > 200) adj = 200
        adj = int(adj + 0.5)
        S = normal * adj
        capped = 0
        if (S > ceil && ceil >= 30) { S = ceil; normal = S / adj; capped = 1 }
        de = int(1000.0 / adj + 0.5); if (de < 2) de = 2
        printf "%.3g %d %d %d %d %d", normal, adj, int(S + 0.5), de, int(R / normal + 0.5), capped
    }')
    read -r normal adjust_ms step de teff capped <<< "$calc"
    if [[ "$capped" == 1 ]]; then
        warn "At load targets $upper/$lower a hunting-free step maxes out at $step MHz:"
        warn "climb time extended $T -> ~$teff ms. (Wider load-target band or a"
        warn "higher freq floor would allow faster smooth climbs.)"
    fi

    # upstream rejects burst <= normal; keep the config's burst rate otherwise
    local burst
    burst=$(toml_get timing.ramp-rates burst); burst=${burst:-$RAMP_DEF_BURST}
    if awk -v b="$burst" -v n="$normal" 'BEGIN{ exit !(b + 0 <= n + 0) }'; then
        burst=$(awk -v n="$normal" 'BEGIN{ printf "%g", 200 * n }')
        warn "Burst rate raised to $burst (must stay above the normal rate)."
    fi

    cp "$GOV_CONF" "$GOV_CONF.tmp"
    toml_set timing.intervals adjust "${adjust_ms}_000" "$GOV_CONF.tmp"
    toml_set timing.ramp-rates normal "$normal"         "$GOV_CONF.tmp"
    toml_set timing.ramp-rates burst  "$burst"          "$GOV_CONF.tmp"
    toml_set timing down-events "$de"                   "$GOV_CONF.tmp"
    mv "$GOV_CONF.tmp" "$GOV_CONF"
    log "Ramp saved: $step MHz steps every $adjust_ms ms -> idle-to-max in ~$teff ms,"
    log "downscale after $(( de * adjust_ms )) ms of low load (down-events $de)."
    ramp_restart_if_active
}

ramp_reset() {
    require_root
    [[ -f "$GOV_CONF" ]] || die "No governor config -- run '$0 governor' first."
    cp "$GOV_CONF" "$GOV_CONF.tmp"
    toml_set timing.intervals adjust "${RAMP_DEF_ADJ_MS}_000" "$GOV_CONF.tmp"
    toml_set timing.ramp-rates normal "$RAMP_DEF_NORMAL"      "$GOV_CONF.tmp"
    toml_set timing.ramp-rates burst  "$RAMP_DEF_BURST"       "$GOV_CONF.tmp"
    toml_set timing down-events "$RAMP_DEF_DE"                "$GOV_CONF.tmp"
    mv "$GOV_CONF.tmp" "$GOV_CONF"
    log "Ramp params reset to install defaults (200 MHz steps / 200 ms, 1 s hold)."
    ramp_restart_if_active
}

cmd_ramp() {
    local sub="${1:-show}"
    shift || true
    case "$sub" in
        ""|show)  ramp_show ;;
        set)      ramp_set "$@" ;;
        reset)    ramp_reset ;;
        *) die "Usage: $0 ramp {show | set <climb-ms> | reset}" ;;
    esac
}

cmd_helpers() {
    require_root
    migrate_legacy_data
    install_update_persistence
    mkdir -p "$BIN_DIR" /etc/dbus-1/system.d
    # Pin to the latest release tag so helper and installed binary agree on
    # the D-Bus interface name (HEAD renamed it after v0.4.x).
    local rel_tag
    rel_tag=$(curl -fsSL "$GOV_API" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1 || true)
    [[ -n "$rel_tag" ]] && GOV_RAW="https://raw.githubusercontent.com/filippor/cyan-skillfish-governor/$rel_tag"
    log "Fetching helpers from ${rel_tag:-smu branch HEAD}..."
    if curl -fL -o "$PERF_BIN" "$GOV_RAW/scripts/cyan-skillfish-performance-mode"; then
        chmod 755 "$PERF_BIN"
        log "  -> $PERF_BIN"
    else
        warn "Helper fetch failed; check the scripts/ dir name on the smu branch."
    fi
    if [[ ! -s "$DBUS_POLICY" ]] || ! grep -q 'com.cyanskillfish.Governor' "$DBUS_POLICY"; then
        log "Writing dual-name D-Bus policy (upstream's is stale vs its binary)..."
        cat > "$DBUS_POLICY" << 'EOF'
<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root">
    <allow own="com.cyan.SkillFishGovernor"/>
    <allow own="com.cyanskillfish.Governor"/>
    <allow send_destination="com.cyan.SkillFishGovernor"/>
    <allow send_destination="com.cyanskillfish.Governor"/>
  </policy>
  <policy context="default">
    <allow send_destination="com.cyan.SkillFishGovernor"/>
    <allow send_destination="com.cyanskillfish.Governor"/>
    <allow send_interface="com.cyan.SkillFishGovernor.PerformanceMode"/>
    <allow send_interface="com.cyanskillfish.Governor.PerformanceMode"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
  </policy>
</busconfig>
EOF
        busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig \
            2>/dev/null || warn "D-Bus reload failed; reboot to activate the policy."
        systemctl restart "$GOV_SVC" 2>/dev/null || true
    else
        log "Dual-name D-Bus policy already present."
    fi
    log "Test: sudo $PERF_BIN --status"
}

cmd_enable() {
    require_root
    migrate_legacy_data
    install_freq_persistence force
    systemctl enable "$GOV_SVC"
    if systemctl is-active "$GOV_SVC" >/dev/null 2>&1; then
        systemctl restart "$RESTORE_SVC" \
            || warn "Governor enabled, but the saved frequency range was not restored."
    fi
    install_update_persistence
    log "Governor enabled at boot (order: CU table -> governor)."
    log "cpufreq + ACPI self-heal were enabled during 'acpi'. All set."
}

# ============================ CPU overclock ===============================
# Wraps bc250-collective/bc250_smu_oc: CPU max boost clock + vid-curve
# undervolt via SMU mailbox messages (queue 3). CPU only -- it never touches
# GPU clocks/voltage, so it coexists with the GPU governor; the only shared
# resource is the SMU indirect window, handled by pause_governor + unit
# ordering. SteamOS-friendly: pure-stdlib python run straight from files
# (no pip/git), sources fetched as a pinned-commit tarball with our patches
# overlaid (see smu-oc-patches/README.md), master copies in the hidden toolkit,
# with the config and unit retained through the atomic-update keep list.

fetch_oc_sources() {
    migrate_legacy_data
    [[ -f "$OC_PATCH_DIR/transport.py" && -f "$OC_PATCH_DIR/stress_helper.py" ]] \
        || die "Patch overlays not found at $OC_PATCH_DIR (should ship next to this script)."
    local work
    work=$(mktemp -d /tmp/bc250-smu-oc.XXXXXX)
    TEMP_DIRS+=("$work")
    log "Fetching bc250_smu_oc @ ${OC_PIN:0:7} (pinned)..."
    curl -fsSL "$OC_TARBALL" | tar -xz -C "$work" --strip-components=1 \
        || die "Fetch failed (network?): $OC_TARBALL"
    log "Overlaying SteamOS patches (transaction flock, no-'stress' fallback)..."
    install -m 644 "$OC_PATCH_DIR/transport.py"     "$work/bc250_smu/transport.py"
    install -m 644 "$OC_PATCH_DIR/stress_helper.py" "$work/stress_helper.py"
    mkdir -p "$OC_DIR/bc250_smu"
    install -m 644 "$work"/bc250_apply.py "$work"/bc250_detect.py \
                   "$work"/bc250_limits.py "$work"/stress_helper.py "$OC_DIR/"
    install -m 644 "$work"/bc250_smu/*.py "$OC_DIR/bc250_smu/"
    python3 -m py_compile "$OC_DIR"/*.py "$OC_DIR"/bc250_smu/*.py \
        || die "Staged sources do not compile -- bad fetch or patch/pin mismatch."
    rm -rf "$work"
    log "Staged -> $OC_DIR"
}

install_oc_files() {
    if [[ ! -f "$OC_DIR/bc250_apply.py" || "${1:-}" == force ]]; then
        fetch_oc_sources
    fi
    grep -q 'lock across the whole pair' "$OC_DIR/bc250_smu/transport.py" \
        || warn "transport.py missing the transaction-flock patch -- SMU races with the governor possible; run '$0 cpu-oc update'."
    grep -q '_burn' "$OC_DIR/stress_helper.py" \
        || warn "stress_helper.py missing the no-'stress' fallback -- 'cpu-oc detect' needs the stress binary; run '$0 cpu-oc update'."
}

# detect prefers the real `stress` tool; pacman packages are wiped by SteamOS
# updates, so this may reinstall later. The python burner fallback in
# stress_helper.py covers a failed/unavailable install either way.
ensure_stress() {
    command -v stress >/dev/null 2>&1 && return 0
    log "Installing 'stress' via pacman (SteamOS updates wipe it; will reinstall then)..."
    unlock_rootfs
    pacman -Sy --noconfirm stress \
        || warn "pacman install failed -- detect will use the python burner fallback."
    relock_rootfs
}

oc_detect() {
    require_root
    local freq="${1:-}" vid="${2:-}" temp="${3:-90}"
    [[ -n "$freq" && -n "$vid" ]] || die "Usage: $0 cpu-oc detect <targetMHz> <vidLimit_mV> [tempC]
Community reference: 4000 1275 (retry at 1300 mV if it crashes).
NEVER above 1325 mV -- exceeding it has bricked boards."
    [[ "$freq" =~ ^[0-9]+$ && "$vid" =~ ^[0-9]+$ && "$temp" =~ ^[0-9]+$ ]] \
        || die "Frequency, voltage, and temperature must be positive integers."
    (( freq >= 3500 && freq <= 4500 )) \
        || die "Target frequency must be between 3500 and 4500 MHz."
    (( vid >= 950 && vid <= 1325 )) \
        || die "VID limit must be between 950 and the hard safety limit of 1325 mV."
    (( temp >= 50 && temp <= 100 )) \
        || die "Temperature limit must be between 50 and 100 C."
    install_oc_files
    ensure_stress
    warn "This stress-steps the CPU in 100 MHz increments and CAN hard-crash"
    warn "the system if pushed too far. Close everything else first."
    warn "The result stays applied afterwards: 'cpu-oc enable' to persist,"
    warn "'cpu-oc off' to revert to stock."
    pause_governor
    # log lives in the tool's own root-owned dir: a fixed /tmp path breaks
    # under fs.protected_regular once any other user has created it, and
    # this way the last detect transcript sticks around for reference
    local rc=0 dlog="$OC_DIR/last-detect.log"
    python3 "$OC_DIR/bc250_detect.py" -f "$freq" -v "$vid" -t "$temp" \
            --keep -c "$OC_STAGE_CONF" 2>&1 | tee "$dlog" || rc=$?
    resume_governor
    [[ $rc -eq 0 ]] || die "Detection failed (rc=$rc)."
    # stamp the measured result into the config (the file only stores the
    # abstract vid-curve scale; the mV number is what humans care about)
    local res
    res=$(grep -oP 'Final Result: \K.*' "$dlog" | tail -1 || true)
    if [[ -n "$res" && -f "$OC_STAGE_CONF" ]]; then
        sed -i '/^# detected/d' "$OC_STAGE_CONF"
        echo "# detected: $res ($(date +%Y-%m-%d))" >> "$OC_STAGE_CONF"
    fi
    log "Detected config -> $OC_STAGE_CONF"
    oc_persist_report
    log "Stability-test now (games / OCCT), watch: grep MHz /proc/cpuinfo"
}

oc_apply() {
    require_root
    install_oc_files
    local conf="$OC_CONF"
    [[ -f "$conf" ]] || conf="$OC_STAGE_CONF"
    [[ -f "$conf" ]] || die "No overclock config -- run '$0 cpu-oc detect' first."
    pause_governor
    python3 "$OC_DIR/bc250_apply.py" --apply "$conf"
    resume_governor
}

oc_enable() {
    require_root
    recover_update_settings
    install_oc_files
    [[ -f "$OC_STAGE_CONF" || -f "$OC_CONF" ]] \
        || die "No overclock config -- run '$0 cpu-oc detect' first."
    if [[ -f "$OC_STAGE_CONF" ]]; then
        cp -f "$OC_STAGE_CONF" "$OC_CONF"
        log "Config -> $OC_CONF"
    fi
    cat > "$OC_UNIT" << EOF
[Unit]
Description=BC-250 CPU overclock/undervolt (bc250_smu_oc, SMU)
# strictly before the GPU governor: both drive the same SMU indirect window
Before=$GOV_SVC
RequiresMountsFor=$ROOT_DATA_DIR

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/python3 $OC_DIR/bc250_apply.py --apply $OC_CONF

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$OC_SVC"
    install_update_persistence
    log "CPU OC enabled at boot (ordered before the GPU governor)."
    oc_apply
}

oc_off() {
    require_root
    systemctl disable --now "$OC_SVC" 2>/dev/null || true
    install_oc_files
    if [[ -d "$OC_DIR/bc250_smu" ]]; then
        pause_governor
        PYTHONPATH="$OC_DIR" python3 - << 'EOF'
from bc250_smu import Bc250Smu
smu = Bc250Smu(use_flock=True)
smu.check_test_message()
smu.q3_0x8f_set_max_cpu_boost_clk(3500)
smu.q3_0x50_scale_f_vid_curve(0)
smu.disable_extra_cpu_gpu_voltage(False)
smu.q3_0x8b_set_cpu_max_temperature(100)
smu.q3_0x8c_set_gpu_max_temperature(100)
print("CPU restored to stock: 3500 MHz, factory vid curve, 100 C limits")
EOF
        resume_governor
    fi
    log "CPU OC disabled at boot and reverted to stock. Config kept --"
    log "re-activate any time with '$0 cpu-oc enable'."
}

# staged (fresh detect) vs installed boot config, comments ignored
oc_confs_match() {
    [[ -f "$OC_STAGE_CONF" && -f "$OC_CONF" ]] || return 1
    cmp -s <(grep -E '^[a-z]' "$OC_STAGE_CONF") <(grep -E '^[a-z]' "$OC_CONF")
}

# persistence state token: none | saved | stale | live
oc_persist_state() {
    local enabled=0
    [[ "$(systemctl is-enabled "$OC_SVC" 2>/dev/null)" == enabled ]] && enabled=1
    if [[ ! -f "$OC_STAGE_CONF" && ! -f "$OC_CONF" ]]; then echo none
    elif [[ $enabled -eq 0 ]]; then echo live
    elif [[ ! -f "$OC_STAGE_CONF" ]] || oc_confs_match; then echo saved
    else echo stale
    fi
}

# one-line verdict on whether the current OC settings survive a reboot
oc_persist_report() {
    case "$(oc_persist_state)" in
        none)  ;;
        saved) log "Saved: this config is enabled and reapplies at every boot." ;;
        stale) warn "NOT saved: the boot config is OLDER than this detect result."
               warn "Run '$0 cpu-oc enable' to save the new settings." ;;
        live)  warn "NOT saved: applied live only -- a reboot reverts to stock."
               warn "Run '$0 cpu-oc enable' to keep it." ;;
    esac
}

oc_detected_result() {   # "3800 MHz @ 1176 mV" from a conf's detect stamp
    if [[ -f "${1:-}" ]]; then
        grep -oP '^# detected: \K[0-9]+ MHz @ [0-9]+ mV' "$1" | tail -1 || true
    fi
    return 0
}

oc_live_mv() {   # current CPU voltage over SMU; needs root + staged tool
    [[ $EUID -eq 0 && -f "$OC_DIR/bc250_smu/api.py" ]] || return 1
    PYTHONPATH="$OC_DIR" python3 - << 'EOF' 2>/dev/null
from bc250_smu import Bc250Smu
print(Bc250Smu(use_flock=True).q3_0x36_get_current_cpu_voltage())
EOF
}

oc_status() {
    echo -e "${CB}=== CPU OC (bc250_smu_oc) ===${C0}"
    local en ac
    en=$(systemctl is-enabled "$OC_SVC" 2>/dev/null) || en=-
    ac=$(systemctl is-active "$OC_SVC" 2>/dev/null) || ac=-
    printf '  %-38s %s / %s\n' "$OC_SVC" "$(c_state "$en")" "$(c_state "$ac")"
    if [[ -f "$OC_CONF" ]]; then
        echo "  boot config ($OC_CONF):"
        sed 's/^/    /' "$OC_CONF"
        if [[ -f "$OC_STAGE_CONF" ]] && ! oc_confs_match; then
            echo "  newer detect result, not yet enabled ($OC_STAGE_CONF):"
            sed 's/^/    /' "$OC_STAGE_CONF"
        fi
    elif [[ -f "$OC_STAGE_CONF" ]]; then
        echo "  detected config, not yet enabled ($OC_STAGE_CONF):"
        sed 's/^/    /' "$OC_STAGE_CONF"
    else
        echo "  no config -- start with: sudo $0 cpu-oc detect 4000 1275"
    fi
    local live
    if live=$(oc_live_mv) && [[ -n "$live" ]]; then
        echo "  live CPU voltage: ${live} mV (idle unless loaded)"
    fi
    oc_persist_report
    echo "  effective clocks: watch -n1 'grep MHz /proc/cpuinfo'"
}

cmd_cpu_oc() {
    local sub="${1:-status}"
    shift || true
    case "$sub" in
        detect)  oc_detect "$@" ;;
        apply)   oc_apply ;;
        enable)  oc_enable ;;
        off)     oc_off ;;
        status)  oc_status ;;
        update)  require_root; install_oc_files force ;;
        *) die "Usage: $0 cpu-oc {detect <MHz> <mV> [tempC] | enable | apply | off | status | update}" ;;
    esac
}

cmd_status() {
    echo -e "${CB}=== Services ===${C0}"
    local s en ac
    for s in bc250-cu-live-manager "$GOV_SVC" bc250-acpi-heal bc250-cpufreq "$RESTORE_SVC" "$OC_SVC"; do
        en=$(systemctl is-enabled "$s" 2>/dev/null) || en=-
        ac=$(systemctl is-active "$s" 2>/dev/null) || ac=-
        printf '  %-38s %s / %s\n' "$s" "$(c_state "$en")" "$(c_state "$ac")"
    done
    echo
    echo "=== GPU ==="
    if [[ -f "$FREQ_STATE" ]]; then
        echo "  saved freq setting (reapplied at boot): $(tr '\n' ' ' < "$FREQ_STATE")"
    else
        echo "  no saved freq setting -- config defaults apply at boot"
    fi
    cat /sys/class/drm/card*/device/pp_dpm_sclk 2>/dev/null || echo "  pp_dpm_sclk not exposed"
    echo
    echo "=== CPU (ACPI fix active if these exist) ==="
    if compgen -G /sys/devices/system/cpu/cpu0/cpufreq >/dev/null; then
        echo "  governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
        echo "  current:  $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) kHz"
        local state states=""
        for state in /sys/devices/system/cpu/cpu0/cpuidle/*; do
            [[ -e "$state" ]] && states+="${state##*/} "
        done
        echo "  c-states: $states"
    else
        echo "  cpufreq absent -- ACPI override not active (not installed, or reboot pending)"
    fi
    echo
    sensors 2>/dev/null | grep -E 'edge|junction|PPT|Tctl|power' || true
}

# ============================ guided menu =================================
menu_freq() {
    while true; do
        local items=(
            "Show current state|$(badge_freq)|Ask the governor for its performance-mode status."
            "Adaptive (auto)||Back to config defaults; clears the saved boot setting."
            "Set max cap||Raise/lower the ceiling, keep adaptive scaling + idle savings."
            "Set min + max range||Floor AND ceiling, adaptive in between."
            "Pin a frequency||Fixed clock, perf mode ON -- no idle downscale. For testing."
            "Max performance||Top of the voltage curve until you switch back to auto."
            "Show voltage curve||Current freq -> mV safe-points + live vddgfx reading."
            "Offset voltage curve||Undervolt/overvolt every point by +-mV. Small steps, stress test."
            "Set one voltage point||Change the mV at a single frequency point."
            "Reset voltage curve||Restore the tuned 800/900/1000/1000 mV defaults."
        )
        menu_select "GPU frequency & voltage  ${CD}(persists across reboots)${C0}" "${items[@]}" || return 0
        case $MENU_CHOICE in
            0) run_action cmd_freq status ;;
            1) run_action cmd_freq auto ;;
            2) ask "Max MHz (0-2150 curve, 1500 = tuned default)" "2000"
               run_action cmd_freq 0 "$REPLY" ;;
            3) ask "Min MHz" "1200"; local mn="$REPLY"
               ask "Max MHz" "1800"
               run_action cmd_freq "$mn" "$REPLY" ;;
            4) ask "Pin at MHz" "1800"
               run_action cmd_freq "$REPLY" ;;
            5) run_action cmd_freq max ;;
            6) run_action volt_show ;;
            7) ask "Offset mV (negative = undervolt)" "-15"
               run_action volt_offset "$REPLY" ;;
            8) ask "Frequency point MHz" "2000"; local vf="$REPLY"
               ask "Voltage mV ($VOLT_MIN-$VOLT_MAX)" "1000"
               run_action volt_set "$vf" "$REPLY" ;;
            9) run_action volt_reset ;;
        esac
    done
}

menu_load_target() {
    while true; do
        local items=(
            "Show load targets|$(badge_load_target)|Config + live values, and what upper/lower mean."
            "Eager preset (0.40 / 0.10)||Light-load games clock up off idle. Fixes 'stuck at low clocks'."
            "Tuned default (0.80 / 0.65)||Install default: full ramps under real load, best idle savings."
            "Custom values||Set your own thresholds (percent or fraction)."
        )
        menu_select "GPU load targets  ${CD}(when the governor clocks up/down)${C0}" "${items[@]}" || return 0
        case $MENU_CHOICE in
            0) run_action lt_show ;;
            1) run_action lt_set "$LT_EAGER_UPPER" "$LT_EAGER_LOWER" ;;
            2) run_action lt_set "$LT_DEF_UPPER" "$LT_DEF_LOWER" ;;
            3) ask "Upper -- clock UP above this GPU busy% (10-99)" "60"; local u="$REPLY"
               ask "Lower -- step DOWN below this GPU busy%" "45"
               run_action lt_set "$u" "$REPLY" ;;
        esac
    done
}

menu_ramp() {
    while true; do
        local items=(
            "Show ramp behavior|$(badge_ramp)|Step size, climb time, downhold + hunting verdict from the config."
            "Responsive (climb in 500 ms)||Smoothest hunting-free step for a half-second idle-to-max climb."
            "Relaxed (climb in 1000 ms)||Install-default speed, but finer steps derived for smoothness."
            "Custom climb time||You pick idle-to-max ms; step, interval, down-events are derived."
            "Reset install defaults||200 MHz steps every 200 ms, 1 s hold before downscaling."
        )
        menu_select "GPU ramp behavior  ${CD}(how fast + how granular clocks move)${C0}" "${items[@]}" || return 0
        case $MENU_CHOICE in
            0) run_action ramp_show ;;
            1) run_action ramp_set 500 ;;
            2) run_action ramp_set 1000 ;;
            3) ask "Idle-to-max climb time ms (200-5000)" "500"
               run_action ramp_set "$REPLY" ;;
            4) run_action ramp_reset ;;
        esac
    done
}

menu_cpu_oc() {
    while true; do
        local items=(
            "Show OC status|$(badge_oc_live)|Full report: configs, measured + live mV, saved verdict."
            "Detect stable overclock|$(badge_oc_last)|Guided stress-stepped search. Start here. CAN hard-crash if pushed."
            "Enable at boot|$(badge_oc_saved)|Persist the detected config; applies before the GPU governor."
            "Apply now||Re-apply the saved config immediately."
            "Revert to stock||Disable at boot + back to 3500 MHz / factory curve now."
            "Update tool sources||Re-fetch bc250_smu_oc (pinned commit + our patches)."
        )
        menu_select "CPU overclock / undervolt  ${CD}(bc250_smu_oc)${C0}" "${items[@]}" || return 0
        case $MENU_CHOICE in
            0) run_action oc_status ;;
            1) echo
               echo -e "  ${CR}${CB}Vid limit is the safety-critical number. NEVER above 1325 mV --${C0}"
               echo -e "  ${CR}${CB}exceeding it has bricked boards. 1275 is the community reference;${C0}"
               echo -e "  ${CR}${CB}pure undervolt: target 3500 MHz with a 1000 mV limit.${C0}"
               echo
               ask "Target frequency MHz" "4000"; local f="$REPLY"
               ask "Vid limit mV (max 1325)" "1275"; local v="$REPLY"
               ask "Temp limit C" "90"
               run_action oc_detect "$f" "$v" "$REPLY" ;;
            2) run_action oc_enable ;;
            3) run_action oc_apply ;;
            4) run_action oc_off ;;
            5) run_action install_oc_files force ;;
        esac
    done
}

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
            "Status overview||Health check of every service, clock and temp. Always safe."
            "Step 1 - ACPI fix: CPU idle + scaling|$(badge_acpi)|SSDT override via GRUB + self-heal. Reboot needed after install."
            "Step 2 - GPU governor|$(badge_governor)|Adaptive GPU freq/voltage via SMU. Test under load before step 3."
            "Step 3 - Enable governor at boot|$(badge_gov_boot)|Lock it in once step 2 proves stable."
            "GPU frequency & voltage|$(badge_freq)|Pin / cap / range + voltage curve. Settings survive reboots."
            "GPU load targets|$(badge_load_target)|When to clock up/down. Fixes light games stuck at idle clocks."
            "GPU ramp behavior|$(badge_ramp)|How fast + how granular clocks move. One number, rest derived."
            "CPU overclock / undervolt|$(badge_oc)|bc250_smu_oc: ~200 mV undervolt even at stock clocks."
            "Reinstall D-Bus helpers||Fixes 'name is not activatable' errors from freq control."
            "Full help||The complete manual for every CLI command."
        )
        menu_select "BC-250 power setup  ${CD}(SteamOS)${C0}" "${items[@]}" || { echo; break; }
        case $MENU_CHOICE in
            0) run_action cmd_status ;;
            1) run_action cmd_acpi ;;
            2) run_action cmd_governor ;;
            3) run_action cmd_enable ;;
            4) menu_freq ;;
            5) menu_load_target ;;
            6) menu_ramp ;;
            7) menu_cpu_oc ;;
            8) run_action cmd_helpers ;;
            9) cmd_help; pause_key ;;
        esac
    done
}

cmd_help() {
    cat << 'EOF'
bc250-power.sh -- BC-250 power management for SteamOS
==============================================================
CPU C/P-states via ACPI SSDT override + adaptive GPU governor (SMU).
Toolkit-owned /etc files are registered in SteamOS's atomic-update keep list.
Privileged binaries and state live in root-owned, offloaded /var/lib storage.

GUIDED MENU
  Run with no arguments (or 'menu') in a terminal for an interactive,
  color-coded menu: arrow keys / j k to move, Enter to run, q to back
  out. Shows live install/active state per step and walks the setup
  order. Every menu action is one of the CLI commands below.

SETUP COMMANDS (run once, in this order)
  acpi        Install the ACPI fix: SSDT-CST (CPU idle C-states) and
              SSDT-PST (CPU 800-3200 MHz scaling) loaded via GRUB
              early-initrd. Also installs two boot services:
                bc250-acpi-heal  -- restores the override if a SteamOS
                                    update wipes /boot
                bc250-cpufreq    -- sets the schedutil CPU governor
              REBOOT REQUIRED before it takes effect.

  governor    Install cyan-skillfish-governor-smu (filippor): adaptive
              GPU freq/voltage via SMU firmware calls, no kernel patch.
              Downloads the latest release, writes a tuned config
              (voltage curve to 2150 MHz, operating cap 1500 MHz,
              thermal throttle 85C), TEST-STARTS the service but does
              not enable it at boot -- verify under load first.

  helpers     (Re)install the perf-mode helper script and the D-Bus
              policy. Fixes 'name is not activatable' errors. Note the
              policy grants BOTH bus names (upstream's shipped policy
              is stale vs its own binary).

  enable      Enable the governor at boot. Run after you've load-tested
              a 'governor' install.

  all         acpi + governor in sequence.

CPU OVERCLOCK / UNDERVOLT (bc250-collective/bc250_smu_oc, CPU only)
  cpu-oc detect <MHz> <mV> [tempC]
              Find a stable OC: steps up from 3.5 GHz while scaling the
              vid curve to stay under <mV>. Stress-tests each step -- CAN
              hard-crash if pushed. Community reference: detect 4000 1275.
              HARD LIMIT 1325 mV (higher has bricked boards). Even at
              stock 3500 this nets a ~200 mV undervolt = thermal headroom.
              The GPU governor is paused during the run (shared SMU
              mailbox window) and resumed after. Installs the 'stress'
              load tool via pacman if missing (SteamOS updates wipe it;
              it just reinstalls on the next detect run -- and a python
              burner fallback covers it if pacman fails).
  cpu-oc enable     Persist the detected config: /etc/bc250-smu-oc.conf +
                    boot service ordered BEFORE the GPU governor.
  cpu-oc apply      Re-apply the saved config right now.
  cpu-oc off        Disable at boot + revert to stock live (3500 MHz,
                    factory curve, 100 C). Config is kept for re-enable.
  cpu-oc status     Service state, configs (incl. the measured mV noted
                    by the last detect), live CPU voltage via SMU, and a
                    clear saved / NOT-saved-at-boot verdict.
  cpu-oc update     Re-fetch the tool sources. They come from upstream
                    (bc250-collective/bc250_smu_oc) at a pinned commit
                    with our patches overlaid from smu-oc-patches/ --
                    no local clone, no pip, no git needed. The first
                    detect/apply/enable fetches automatically (network).

EVERYDAY COMMANDS
  status      One-screen health check: all services, GPU DPM level
              table (* = active), CPU cpufreq/C-states (present only if
              the ACPI override loaded this boot), temps and power.

  freq        Live GPU frequency control (through the governor, D-Bus):
    freq              show performance-mode state
    freq 1800         pin at 1800 MHz  (perf mode ON: no idle downscale,
                      remember 'freq auto' when done)
    freq 0 2000       range 0-2000: raises the cap, keeps adaptive
                      scaling and idle savings (0 = no limit)
    freq 1200 1800    floor AND ceiling
    freq max          performance mode at the top of the voltage curve
    freq auto         back to adaptive + config defaults (1500 cap)
              Settings PERSIST across reboots: each set is saved to
              /var/lib/bc250-control/governor/freq-state and the
              bc250-gpu-freq-restore service reapplies it once the
              governor is up. 'freq auto' clears the saved state.
              Thermal throttling (85C) applies no matter what you set.

  gpu-volt    GPU voltage curve control. Edits the governor's safe-points
              (the layer that owns GPU voltage), restarts it, reapplies
              your saved freq setting:
    gpu-volt              show curve + live vddgfx
    gpu-volt offset -25   undervolt the whole curve 25 mV
    gpu-volt set 2000 985 change one point
    gpu-volt reset        restore the tuned default curve
              Bounds 700-1050 mV enforced. Small steps (10-25 mV) and
              stress test after -- undervolts that boot fine can still
              crash under load. Changes are permanent (config.toml).

  load-target GPU load targets: the busy% band the governor keeps the GPU
              in. It only clocks UP above 'upper' -- frame-capped light
              games can sit below it at idle clocks forever. Values go to
              config.toml (persist) AND apply live via D-Bus (no restart):
    load-target             show config + live values
    load-target eager       0.40/0.10 -- light loads ramp off idle clocks
    load-target reset       0.80/0.65 tuned defaults (best idle savings)
    load-target set 70 55   custom upper/lower (percent or fraction)
              Alternative for single problem games -- per-game floor via
              Steam launch options (see STEAM LAUNCH OPTION below), which
              leaves global idle behavior untouched.

  ramp        GPU ramp behavior: how fast AND how granular clocks move.
              'set' takes ONE number -- idle-to-max climb time in ms --
              and derives the rest for smoothness: climb speed = range/T;
              step capped by the no-hunting bound (busy% ~ 1/freq, so a
              step above f_min x (upper-lower)/upper can oscillate at
              steady load = the notchy feel); interval clamped 50-200 ms;
              down-events scaled to keep a 1 s hold before downscaling.
              Startup-only params -> the governor restarts (saved freq
              setting reapplied automatically):
    ramp                    show step, climb time, hunting verdict
    ramp set 500            idle-to-max in 500 ms, smoothest safe steps
    ramp reset              install defaults (200 MHz / 200 ms, 1 s hold)
              Re-run after changing load-target or the freq range -- the
              derived step depends on both. Burst mode is left alone: 30 ms
              of saturated load still jumps straight to max.

PERMANENT TUNING (config file, not this script)
  /etc/cyan-skillfish-governor-smu/config.toml
    [frequency-range] max = 1500     <- permanent ceiling
    [[safe-points]]                  <- the freq/voltage curve; anything
                                        you want to run must have a
                                        voltage point at or above it
  then: systemctl restart cyan-skillfish-governor-smu

STEAM LAUNCH OPTION (per-game max clocks, auto-restores on exit)
  /var/lib/bc250-control/bin/cyan-skillfish-performance-mode %command%
  /var/lib/bc250-control/bin/cyan-skillfish-performance-mode --range 0 2000 %command%

FILE MAP
  /var/lib/bc250-control/bin/
                               governor + helper binaries   (persists)
  /var/lib/bc250-control/acpi/
                               SSDTs + master override cpio (persists)
  /var/lib/bc250-control/smu-oc/
                               CPU OC tool (fetched @ pinned commit,
                               patched from smu-oc-patches/)
  /etc/bc250-smu-oc.conf       CPU OC config       (atomic-update keep list)
  /etc/cyan-skillfish-governor-smu/config.toml     (atomic-update keep list)
  /var/lib/bc250-control/governor/freq-state  last 'freq' setting,
                               replayed at boot by bc250-gpu-freq-restore
  /etc/systemd/system/*.service, /etc/dbus-1/system.d/
                                      retained by atomic-update keep list
  /boot/acpi_override.cpio     WIPED by updates -- bc250-acpi-heal
                               restores it and warns in the journal

RELATED (separate scripts, same family)
  bc250-40cu.sh     the 38/40 CU unlock (umr + live manager)
  bc250-cu-status.sh           read-only CU dispatch report
EOF
}

if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    cmd_menu
    exit 0
fi
case "${1:-}" in
    acpi)         cmd_acpi ;;
    governor)     cmd_governor ;;
    helpers)      cmd_helpers ;;
    freq)         shift; cmd_freq "$@" ;;
    gpu-volt)     shift; cmd_gpu_volt "$@" ;;
    load-target)  shift; cmd_load_target "$@" ;;
    ramp)         shift; cmd_ramp "$@" ;;
    cpu-oc)       shift; cmd_cpu_oc "$@" ;;
    enable)       cmd_enable ;;
    status)       cmd_status ;;
    all)          cmd_acpi; cmd_governor ;;
    menu)         cmd_menu ;;
    help|-h|--help) cmd_help ;;
    *) echo "Usage: $0 {acpi|governor|helpers|freq|gpu-volt|load-target|ramp|cpu-oc|enable|status|all|menu|help}"
       echo "  (no arguments on a terminal opens the guided menu)"
       echo "  freq                 show performance-mode state"
       echo "  freq 1800            pin GPU at 1800 MHz (perf mode)"
       echo "  freq 0 2000          range: no floor, 2000 MHz cap, adaptive"
       echo "  freq auto            back to adaptive + config defaults"
       echo "  freq max             performance mode, full-curve max"
       echo
       echo "Run '$0 help' for the full explanation of every command."
       exit 1 ;;
esac
