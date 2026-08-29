#!/usr/bin/env bash
# ==============================================================================
#  BC-250 SteamOS Real Toolkit
#  SteamOS-focused helper for BC-250 CPU/GPU governors and performance profiles.
# ==============================================================================

set -euo pipefail

# Re-launch with sudo if not already root
if [[ $EUID -ne 0 ]]; then
    sudo -v
    exec sudo "$0" "$@"
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
[[ -z "$REAL_HOME" || ! -d "$REAL_HOME" ]] && REAL_HOME="/root"

SUDO_KEEPALIVE_PID=""
if [[ "$REAL_USER" != "root" ]] && id "$REAL_USER" >/dev/null 2>&1; then
    sudo -u "$REAL_USER" -H bash -c 'sudo -n -v' >/dev/null 2>&1 || true
    sudo -u "$REAL_USER" -H bash -c 'while sleep 60; do sudo -n -v || exit 0; done' \
        >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
fi

cleanup_sudo_keepalive() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}
trap cleanup_sudo_keepalive EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
CU_LIVE_MANAGER="$SCRIPT_DIR/bc250-cu-live-manager.sh"
EXTERNAL_DIR="$SCRIPT_DIR/external"

# If this is a standalone script (e.g. downloaded via curl, no git clone),
# bootstrap the full repository and re-execute.
if [[ ! -d "$SCRIPT_DIR/.git" && ! -d "$EXTERNAL_DIR/bc250_smu_oc" ]]; then
    TOOLKIT_BASE_DIR="${REAL_HOME}/.bc250-toolkit"
    TOOLKIT_REPO_DIR="$TOOLKIT_BASE_DIR/bc250-steamos-real-toolkit"
    mkdir -p "$TOOLKIT_BASE_DIR"
    chown "$REAL_USER":"$REAL_USER" "$TOOLKIT_BASE_DIR"
    rm -rf "$TOOLKIT_REPO_DIR"
    echo "Standalone script detected — fetching the full toolkit repository..."
    if command -v git >/dev/null 2>&1; then
        runuser -u "$REAL_USER" -- git clone --depth 1 "https://github.com/rpf16rj/bc250-steamos-real-toolkit.git" "$TOOLKIT_REPO_DIR" || {
            echo "Error: failed to clone toolkit repository." >&2
            exit 1
        }
    else
        echo "git not found — falling back to curl..."
        TMP_TARBALL="$(mktemp /tmp/bc250-toolkit-XXXXXX.tar.gz)"
        curl -fsSL -o "$TMP_TARBALL" "https://github.com/rpf16rj/bc250-steamos-real-toolkit/archive/refs/heads/main.tar.gz" || {
            echo "Error: failed to download toolkit archive." >&2
            rm -f "$TMP_TARBALL"
            exit 1
        }
        mkdir -p "$TOOLKIT_REPO_DIR"
        tar -xzf "$TMP_TARBALL" -C "$TOOLKIT_REPO_DIR" --strip-components=1 || {
            echo "Error: failed to extract toolkit archive." >&2
            rm -f "$TMP_TARBALL"
            exit 1
        }
        rm -f "$TMP_TARBALL"
    fi
    chown -R "$REAL_USER":"$REAL_USER" "$TOOLKIT_REPO_DIR" 2>/dev/null || true
    exec bash "$TOOLKIT_REPO_DIR/start.sh" "$@"
fi

# Set to 1 when the toolkit is running unattended after a SteamOS update
# re-apply pass. In AUTO mode all confirmations/pauses are skipped.
AUTO="${AUTO:-0}"

# State used to re-apply installed components after a SteamOS atomic update.
PERSIST_STATE_DIR="${REAL_HOME}/.bc250-toolkit"
PERSIST_STATE_FILE="$PERSIST_STATE_DIR/installed-components"
PERSIST_KEEP_FILE="$PERSIST_STATE_DIR/bc250-toolkit-keep.conf"

persist_state_add() {
    local c="$1"
    mkdir -p "$PERSIST_STATE_DIR"
    if [[ -f "$PERSIST_STATE_FILE" ]]; then
        grep -Fxq "$c" "$PERSIST_STATE_FILE" 2>/dev/null && return 0
    fi
    printf '%s\n' "$c" >> "$PERSIST_STATE_FILE"
    chown "$REAL_USER":"$REAL_USER" "$PERSIST_STATE_FILE" 2>/dev/null || true
}

persist_state_remove() {
    local c="$1" tmp
    [[ -f "$PERSIST_STATE_FILE" ]] || return 0
    tmp=$(mktemp)
    grep -Fxv "$c" "$PERSIST_STATE_FILE" > "$tmp" || true
    mv -f "$tmp" "$PERSIST_STATE_FILE"
    chown "$REAL_USER":"$REAL_USER" "$PERSIST_STATE_FILE" 2>/dev/null || true
}

persist_state_has() {
    [[ -f "$PERSIST_STATE_FILE" ]] && grep -Fxq "$1" "$PERSIST_STATE_FILE" 2>/dev/null
}

# Scan the current system and retroactively record any toolkit components that
# are already installed, so enabling persistence does not lose them.
persist_detect_and_record_installed() {
    cpu_governor_installed 2>/dev/null && persist_state_add "cpu"
    gpu_governor_installed 2>/dev/null && persist_state_add "gpu"
    mitigations_currently_off && persist_state_add "mitigations"
    [[ -f /etc/sysctl.d/99-swappiness.conf || -f /home/swapfile || -f /swapfile ]] && persist_state_add "swap"
    [[ -f /etc/default/grub.zram.bak ]] && persist_state_add "zswap"
    acpi_fix_installed 2>/dev/null && persist_state_add "acpi"
    aic8800_installed 2>/dev/null && persist_state_add "aic8800"
    be200_firmware_installed 2>/dev/null && persist_state_add "be200_fw"
    lsmod 2>/dev/null | grep -qE 'nct6687|nct6686' && persist_state_add "sensors"
    coolercontrol_installed 2>/dev/null && persist_state_add "coolercontrol"
    xone_installed 2>/dev/null && persist_state_add "xbox"
    cec_control_installed 2>/dev/null && persist_state_add "cec"
    [[ -f /etc/bc250-cu-live-manager.conf ]] && persist_state_add "cu"
    core_unlock_persist_installed 2>/dev/null && persist_state_add "core_unlock"
    ram_split_installed 2>/dev/null && persist_state_add "ram_split"
    if find "/lib/modules/$(uname -r)/updates" -name 'amdgpu.ko*' 2>/dev/null | grep -q .; then
        persist_state_add "audio"
    fi
    ac3_surround_installed 2>/dev/null && persist_state_add "ac3"
    ds5_bridge_fix_installed 2>/dev/null && persist_state_add "ds5_bridge"
    ds5_chord_vdf_patched 2>/dev/null && persist_state_add "ds5_chord_vdf"
    if compgen -G "/opt/bc250-gfx1013/*/share/vulkan/icd.d/radeon_icd.x86_64.json" >/dev/null 2>&1 \
       && grep -q "VK_DRIVER_FILES=.*bc250-gfx1013" /etc/environment 2>/dev/null; then
        persist_state_add "gfx1013"
    fi
}

# Snapshots of /etc configuration files (custom CoolerControl curves, CPU/GPU
# overclock configs, etc.) so they survive a SteamOS atomic update.
persist_snapshot_configs() {
    local component="$1"
    shift
    local src relpath dest="$PERSIST_STATE_DIR/config-snapshots/$component"
    rm -rf "$dest"
    mkdir -p "$dest"
    for src in "$@"; do
        if [[ -e "$src" ]]; then
            relpath="${src#/}"
            mkdir -p "$(dirname "$dest/$relpath")"
            cp -a "$src" "$dest/$relpath"
        fi
    done
    chown -R "$REAL_USER":"$REAL_USER" "$PERSIST_STATE_DIR/config-snapshots" 2>/dev/null || true
}

persist_restore_all_configs() {
    local snapshot_dir="$PERSIST_STATE_DIR/config-snapshots"
    [[ -d "$snapshot_dir" ]] || return 0
    local component_dir top base
    for component_dir in "$snapshot_dir"/*; do
        [[ -d "$component_dir" ]] || continue
        for top in "$component_dir"/*; do
            [[ -e "$top" ]] || continue
            base="${top##*/}"
            if [[ -d "$top" ]]; then
                mkdir -p "/$base"
                cp -aT "$top" "/$base" 2>/dev/null || true
            else
                cp -a "$top" "/$base" 2>/dev/null || true
            fi
        done
    done
    chown -R "$REAL_USER":"$REAL_USER" "$PERSIST_STATE_DIR/config-snapshots" 2>/dev/null || true
}

# ==============================================================================
# EXECUTION LOGGING
# ==============================================================================
# Capture a hidden trace of every command plus stdout/stderr so the diagnostic
# log can show exactly what the script ran and printed when an error occurs.
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
chown "$REAL_USER":"$REAL_USER" "$LOG_DIR" 2>/dev/null || true
TOOLKIT_RUN_LOG="${LOG_DIR}/bc250-toolkit-run-$(date +%Y%m%d-%H%M%S)-$$.log"
TOOLKIT_TRACE_LOG="${LOG_DIR}/bc250-toolkit-trace-$(date +%Y%m%d-%H%M%S)-$$.log"
INSTALL_ALL_PROGRESS="${LOG_DIR}/install-all-progress"
# Trace goes to fd 5 so it does not clutter the terminal.
exec 5>>"$TOOLKIT_TRACE_LOG"
BASH_XTRACEFD=5
PS4='+ ${BASH_SOURCE:-$0}:${LINENO}:${FUNCNAME[0]:+${FUNCNAME[0]}()} '
set -x
# User-visible output is also saved to the run log.
exec > >(tee -a "$TOOLKIT_RUN_LOG") 2>&1

TOOLKIT_VERSION="v$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "0.0.0")"
REPO_URL="https://github.com/rpf16rj/bc250-steamos-real-toolkit"
MIN_KERNEL_MAJOR=6
MIN_KERNEL_MINOR=18
CHANGELOG_URL="${REPO_URL}/blob/main/CHANGELOG.md"
RELEASES_URL="${REPO_URL}/releases/latest"

# ==============================================================================
# COLORS & FORMATTING
# ==============================================================================
RESET="\e[0m"
BOLD="\e[1m"
DIM="\e[2m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
WHITE="\e[97m"
MAGENTA="\e[35m"
ICON_OK="${GREEN}✓${RESET}"
ICON_WARN="${YELLOW}⚠${RESET}"

print_banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═════════════════════════════════════════════════════════════════════╗"
    echo "  ║                                                                     ║"
    echo "  ║               BC-250 SteamOS Real Toolkit ${TOOLKIT_VERSION}               ║"
    echo "  ║               CPU/GPU Governors & Performance Profiles              ║"
    echo "  ║                                                                     ║"
    echo "  ╚═════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${BOLD}${YELLOW}⚠  SteamOS update notice:${RESET}"
    echo -e "  ${YELLOW}SteamOS updates may require reinstalling toolkit components. Check the toolkit status${RESET}"
    echo -e "  ${YELLOW}after every update, especially when using the Beta channel.${RESET}"
    echo ""
    echo -e "  ${DIM}Compatible with SteamOS kernel ${MIN_KERNEL_MAJOR}.${MIN_KERNEL_MINOR}+ (current: $(uname -r))${RESET}"
    echo ""
}

print_section() {
    echo -e "  ${BOLD}${YELLOW}$1${RESET}"
    echo -e "  ${DIM}─────────────────────────────────────────────────────────────────────${RESET}"
}

print_item() {
    local num="$1" label="$2" desc="$3"
    local label_bytes=${#label}
    local label_visual=$(echo -n "$label" | wc -m)
    local extra=$(( label_bytes - label_visual ))
    local width=$(( 26 + extra ))
    printf "  ${BOLD}${WHITE}[${CYAN}%2s${WHITE}]${RESET}  %-${width}s ${DIM}%s${RESET}\n" "$num" "$label" "$desc"
}

print_success() { echo -e "\n  ${BOLD}${GREEN}✔  $1${RESET}\n"; }
print_error()   { echo -e "\n  ${BOLD}${RED}✘  $1${RESET}\n"; }
print_info()    { echo -e "  ${CYAN}→${RESET}  $1"; }
print_step()    { echo -e "\n  ${BOLD}${MAGENTA}[$1]${RESET}  $2"; }

press_enter() {
    if [[ "$AUTO" == "1" ]]; then
        return 0
    fi
    echo -e "\n  ${DIM}Press Enter to return to the menu...${RESET}"
    read -r
}

confirm() {
    if [[ "$AUTO" == "1" ]]; then
        return 0
    fi
    local prompt="${1:-Are you sure?}"
    echo -e "\n  ${YELLOW}${prompt}${RESET} ${DIM}[y/N]${RESET} "
    read -rp "  → " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

open_url() {
    local url="$1"
    if command -v xdg-open >/dev/null 2>&1; then
        sudo -u "$REAL_USER" xdg-open "$url" >/dev/null 2>&1 &
    fi
    print_info "URL: ${CYAN}${url}${RESET}"
}

run_help() {
    print_step "HLP" "Help"
    print_info "Full documentation, usage instructions and troubleshooting live in the repo README:"
    open_url "$REPO_URL"
}

run_changelog() {
    print_step "LOG" "Changelog"
    print_info "Full list of changes/updates (CHANGELOG.md on GitHub):"
    open_url "$CHANGELOG_URL"
    echo ""
    print_info "To check for a newer version, see the releases page:"
    open_url "$RELEASES_URL"
}

ensure_desktop_shortcut() {
    local desktop_dir
    desktop_dir="$(sudo -u "$REAL_USER" xdg-user-dir DESKTOP 2>/dev/null || echo "")"
    [[ -n "$desktop_dir" ]] || desktop_dir="$REAL_HOME/Desktop"
    [[ -d "$desktop_dir" ]] || mkdir -p "$desktop_dir" 2>/dev/null || return 0

    local shortcut="$desktop_dir/BC-250 Toolkit.desktop"
    if [[ -f "$shortcut" ]] && grep -q '^Exec=konsole --hold -e sudo bash ' "$shortcut"; then
        return 0
    fi

    cat > "$shortcut" <<SHORTCUT_EOF
[Desktop Entry]
Type=Application
Name=BC-250 SteamOS Real Toolkit
Comment=CPU/GPU governors, swap/zswap, sensors and community fixes for the BC-250
Exec=konsole --hold -e sudo bash "$SCRIPT_PATH"
Icon=utilities-terminal
Terminal=false
Categories=System;
SHORTCUT_EOF

    chmod +x "$shortcut"
    chown "$REAL_USER":"$REAL_USER" "$shortcut" 2>/dev/null || true
    sudo -u "$REAL_USER" gio set "$shortcut" metadata::trusted true >/dev/null 2>&1 || true
    print_info "Desktop shortcut created: $shortcut"
}

# ==============================================================================
# HELPERS
# ==============================================================================

aur_helper() {
    if command -v shelly >/dev/null 2>&1; then printf "shelly"
    elif command -v paru >/dev/null 2>&1;  then printf "paru"
    elif command -v yay >/dev/null 2>&1;   then printf "yay"
    else return 1
    fi
}

is_steamos() {
    if [[ -f /etc/os-release ]]; then
        grep -Eqi '^(ID|NAME|PRETTY_NAME)=.*(steamos|steam os)' /etc/os-release && return 0
    fi
    command -v steamos-readonly >/dev/null 2>&1 && return 0
    return 1
}

kernel_version_ok() {
    local kver kmajor kminor
    kver="$(uname -r)"
    kmajor="${kver%%.*}"
    local rest="${kver#*.}"
    kminor="${rest%%.*}"
    [[ "$kmajor" -gt "$MIN_KERNEL_MAJOR" ]] && return 0
    [[ "$kmajor" -eq "$MIN_KERNEL_MAJOR" && "$kminor" -ge "$MIN_KERNEL_MINOR" ]] && return 0
    return 1
}

require_kernel_version() {
    if kernel_version_ok; then return 0; fi
    echo -e "  ${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "  ${BOLD}${RED}Kernel incompatible — SteamOS $(uname -r) detected.${RESET}"
    echo -e "  ${BOLD}${RED}This feature requires SteamOS kernel ${MIN_KERNEL_MAJOR}.${MIN_KERNEL_MINOR} or newer.${RESET}"
    echo -e "  ${BOLD}${YELLOW}Update SteamOS to the Beta channel: Settings → System → System Update Channel → Beta.${RESET}"
    echo -e "  ${BOLD}${YELLOW}Then run a system update and reboot before trying again.${RESET}"
    echo -e "  ${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    return 1
}

# ==============================================================================
# ERROR LOGGING
# ==============================================================================

save_error_log() {
    local context="${1:-Unknown step}"
    local detail="${2:-}"
    local logfile="$LOG_DIR/bc250-toolkit-error-$(date +%Y%m%d-%H%M%S).log"
    {
        echo "BC-250 SteamOS Real Toolkit — Error Report"
        echo "Generated : $(date)"
        echo "Context   : $context"
        [[ -n "$detail" ]] && echo "Detail    : $detail"
        echo "Script    : $SCRIPT_PATH"
        echo "Version   : $TOOLKIT_VERSION"
        echo ""
        echo "== System Info =="
        uname -a
        [[ -f /etc/os-release ]] && cat /etc/os-release
        echo ""
        echo "== Service Status =="
        systemctl status bc250-smu-oc.service --no-pager 2>&1 || true
        echo ""
        systemctl status cyan-skillfish-governor-smu.service --no-pager 2>&1 || true
        echo ""
        echo "== Recent journal (last 150 lines) =="
        journalctl -xe --no-pager -n 150 2>&1 || true
        echo ""
        echo "== Pacman log (last 80 lines) =="
        tail -n 80 /var/log/pacman.log 2>&1 || true
        echo ""
        echo "== Shell Environment =="
        env | sort || true
        echo ""
        echo "== Script Trace (last 1000 lines) =="
        if [[ -s "$TOOLKIT_TRACE_LOG" ]]; then
            tail -n 1000 "$TOOLKIT_TRACE_LOG" 2>&1 || true
        else
            echo "No trace log available."
        fi
        echo ""
        echo "== Script Output (last 500 lines) =="
        if [[ -s "$TOOLKIT_RUN_LOG" ]]; then
            tail -n 500 "$TOOLKIT_RUN_LOG" 2>&1 || true
        else
            echo "No run log available."
        fi
    } > "$logfile" 2>/dev/null
    chown "$REAL_USER":"$REAL_USER" "$logfile" 2>/dev/null || true

    local desktop_dir
    desktop_dir="$(sudo -u "$REAL_USER" xdg-user-dir DESKTOP 2>/dev/null || echo "")"
    [[ -n "$desktop_dir" ]] || desktop_dir="${REAL_HOME}/Desktop"
    if [[ -d "$desktop_dir" ]]; then
        local desktop_log="$desktop_dir/$(basename "$logfile")"
        if cp -f "$logfile" "$desktop_log" 2>/dev/null; then
            chown "$REAL_USER":"$REAL_USER" "$desktop_log" 2>/dev/null || true
            print_info "A copy of the diagnostic log was copied to the Desktop: ${BOLD}${desktop_log}${RESET}"
        fi
    fi

    print_info "A diagnostic log was saved to: ${BOLD}${logfile}${RESET}"
    print_info "Please share this log when asking for help:"
    print_info "  Discord: BC-250 community channel"
    print_info "  GitHub:  ${CYAN}https://github.com/rpf16rj/bc250-steamos-real-toolkit/issues/new${RESET}"
}

fail_with_log() {
    local msg="$1" context="${2:-$1}"
    print_error "$msg"
    save_error_log "$context" "$msg"
}

toolkit_unhandled_error() {
    local failed_command="${1:-unknown command}" rc="${2:-1}"
    print_error "Unexpected error (exit code $rc): $failed_command"
    save_error_log "Unhandled error — $failed_command" "exit code $rc"
}

trap 'toolkit_unhandled_error "$BASH_COMMAND" "$?"' ERR

repair_pacman_keyring() {
    print_info "Detected a pacman keyring problem — attempting automatic repair..."
    rm -rf /etc/pacman.d/gnupg
    LC_ALL=C pacman-key --init
    LC_ALL=C pacman-key --populate archlinux holo 2>/dev/null || LC_ALL=C pacman-key --populate
}

is_network_error() {
    local output="$1"
    grep -qiE "operation too slow|timeout|timed out|connection refused|connection reset|could not resolve|network is unreachable|temporary failure in name resolution|failed to download|failed to retrieve|download.*failed|http.*error|curl.*error|git.*unable to access|git.*failed to connect|socket timed out|transfer closed|validity check|did not pass" <<< "$output"
}

prompt_retry_or_abort() {
    local context="$1"
    if [[ "$AUTO" == "1" ]]; then
        print_info "[${context}] unattended mode: network failure, skipping retry."
        return 1
    fi
    while true; do
        echo -e "\n  ${YELLOW}Network/download failure detected in:${RESET} ${context}"
        echo -e "  ${DIM}[R]etry / [A]bort${RESET}"
        read -rp "  → " ans
        case "${ans,,}" in
            r|retry|"") return 0 ;;
            a|abort|*) return 1 ;;
        esac
    done
}

run_with_retry() {
    local cmd="$1" context="${2:-command}"
    local output rc
    # Force English output for pacman and AUR helper commands so error
    # detection works regardless of the user's system locale (es, pt, uk, etc.)
    if [[ "$cmd" == *pacman* || "$cmd" == *paru* || "$cmd" == *yay* || "$cmd" == *shelly* ]]; then
        cmd="LC_ALL=C $cmd"
    fi
    print_info "[${context}] starting..."
    while true; do
        output="$(eval "$cmd" 2>&1)"
        rc=$?
        echo "$output"
        if [[ $rc -eq 0 ]]; then
            print_info "[${context}] completed."
            return 0
        fi
        # First try the known pacman keyring error path once.
        # run_with_retry prepends LC_ALL=C to pacman commands so output is
        # always in English — no need for localized string matching.
        if echo "$output" | grep -qiE "keyring|invalid or corrupted|signature"; then
            repair_pacman_keyring
            print_info "Retrying the failed command after keyring repair..."
            continue
        fi
        # If it looks like a transient network/download error, ask the user.
        if is_network_error "$output"; then
            # Clean AUR cache on validity-check failures to avoid stale downloads
            if echo "$output" | grep -qiE "validity check|did not pass"; then
                local pkg
                pkg=$(echo "$output" | grep -oiE "cyan-skillfish-governor[a-z-]*" | head -1)
                [[ -n "$pkg" ]] && aur_clean_cache "$pkg"
            fi
            prompt_retry_or_abort "$context" || return 1
            print_info "Retrying ${context}..."
            continue
        fi
        return $rc
    done
}

steamos_writable() {
    local cmd="$1"
    local first_word="${cmd%% *}"
    first_word="${first_word#\"}"
    first_word="${first_word#\'}"
    local label="steamos: ${first_word}"
    if is_steamos; then
        print_info "SteamOS detected: disabling read-only mode..."
        if ! steamos-readonly disable; then
            print_error "Failed to disable SteamOS read-only mode."
            return 1
        fi
        run_with_retry "$cmd" "$label"
        local rc=$?
        print_info "Re-enabling SteamOS read-only mode..."
        steamos-readonly enable || true
        return $rc
    else
        run_with_retry "$cmd" "$label"
    fi
}

ensure_build_deps() {
    local missing=()
    for bin in debugedit fakeroot; do
        command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0

    print_info "Missing makepkg dependencies: ${missing[*]}"
    steamos_writable 'pacman -Syu --noconfirm base-devel debugedit fakeroot' || {
        fail_with_log "Failed to install build dependencies." "Build Dependencies"
        return 1
    }

    for bin in debugedit fakeroot; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            print_error "$bin is still missing after installation."
            return 1
        fi
    done
    print_info "Build dependencies installed."
}

aur_install() {
    local package="$1" helper
    if ! helper="$(aur_helper)"; then
        print_error "No AUR helper found (shelly, paru, or yay). Please install one first."
        return 1
    fi
    print_info "Installing $package via $helper..."
    case "$helper" in
        shelly) sudo -u "$REAL_USER" env LC_ALL=C shelly aur install "$package" ;;
        paru)   sudo -u "$REAL_USER" env LC_ALL=C paru -S --noconfirm "$package" ;;
        yay)    sudo -u "$REAL_USER" env LC_ALL=C yay -S --noconfirm "$package" ;;
    esac
}

aur_clean_cache() {
    local package="$1" helper cache_dir
    if ! helper="$(aur_helper)"; then return 0; fi
    case "$helper" in
        paru) cache_dir="${REAL_HOME}/.cache/paru/clone/${package}" ;;
        yay)  cache_dir="${REAL_HOME}/.cache/yay/${package}" ;;
        *)    return 0 ;;  # shelly manages its own cache
    esac
    if [[ -d "$cache_dir" ]]; then
        print_info "Cleaning stale AUR cache for $package..."
        rm -rf "$cache_dir"
    fi
}

aur_remove() {
    local package="$1" helper
    if ! helper="$(aur_helper)"; then
        print_error "No AUR helper found (shelly, paru, or yay). Please install one first."
        return 1
    fi
    print_info "Removing $package via $helper..."
    case "$helper" in
        shelly) LC_ALL=C shelly remove "$package" ;;
        paru)   LC_ALL=C paru -Rns --noconfirm "$package" 2>/dev/null || true ;;
        yay)    LC_ALL=C yay -Rns --noconfirm "$package" 2>/dev/null || true ;;
    esac
}

# ==============================================================================
# GOVERNORS
# ==============================================================================

cpu_governor_installed() {
    systemctl is-enabled bc250-smu-oc.service &>/dev/null || \
        pipx list 2>&1 | grep -q 'bc250-smu-oc'
}

cpu_governor_venv_healthy() {
    export PATH="$PATH:/root/.local/bin:/home/deck/.local/bin"
    command -v bc250-detect &>/dev/null && bc250-detect --help &>/dev/null
}

cpu_governor_repair_venv() {
    print_info "bc250-detect venv is broken (likely after SteamOS update). Reinstalling..."
    pipx reinstall bc250-smu-oc 2>/dev/null || {
        pipx uninstall bc250-smu-oc 2>/dev/null || true
        local cpu_gov_dir="$EXTERNAL_DIR/bc250_smu_oc"
        if [[ ! -d "$cpu_gov_dir" ]]; then
            fail_with_log "Vendored bc250_smu_oc not found at $cpu_gov_dir." "CPU Governor — missing vendored repo for venv repair"
            return 1
        fi
        pushd "$cpu_gov_dir" >/dev/null || return 1
        run_with_retry "pipx install ." "pipx install bc250_smu_oc" || {
            fail_with_log "Failed to reinstall bc250_smu_oc via pipx." "CPU Governor — pipx reinstall"
            popd >/dev/null || true
            return 1
        }
        popd >/dev/null || true
    }
    pipx ensurepath || true
    export PATH="$PATH:/root/.local/bin"
    print_success "bc250-detect venv repaired."
}

cpu_governor_setup() {
    print_step "01-S" "CPU Governor — Configuration Setup"

    # Ensure pipx-installed binaries are on PATH regardless of install path
    export PATH="$PATH:/root/.local/bin:/home/deck/.local/bin"
    # Also pick up pipx ensurepath output if available
    command -v pipx &>/dev/null && eval "$(pipx ensurepath --shell 2>/dev/null || true)" || true

    if ! command -v bc250-apply &>/dev/null; then
        fail_with_log "bc250-apply not found in PATH. Install the CPU governor package first." "CPU Governor Setup — missing bc250-apply"
        return 1
    fi

    local cpu_dir="$EXTERNAL_DIR/bc250_smu_oc"
    if [[ -d "$cpu_dir" ]]; then
        cd "$cpu_dir" || return 1
        print_info "Running bc250-detect..."
        bc250-detect --frequency 3500 --vid 1000 --keep || {
            fail_with_log "bc250-detect failed." "CPU Governor Setup — bc250-detect"
            cd - >/dev/null || true
            return 1
        }
        print_info "Applying overclock config and installing systemd service..."
        bc250-apply --install overclock.conf || {
            fail_with_log "bc250-apply failed." "CPU Governor Setup — bc250-apply"
            cd - >/dev/null || true
            return 1
        }
        cd - >/dev/null || true
    elif [[ -f /etc/bc250-smu-oc.conf ]]; then
        print_info "Repository directory not found — re-creating systemd service from existing /etc/bc250-smu-oc.conf..."
        bc250-apply --install /etc/bc250-smu-oc.conf || {
            fail_with_log "bc250-apply failed." "CPU Governor Setup — bc250-apply existing config"
            return 1
        }
    else
        fail_with_log "No vendored bc250_smu_oc repository and no existing /etc/bc250-smu-oc.conf to re-apply." "CPU Governor Setup — missing source"
        return 1
    fi

    print_info "Enabling and starting systemd service..."
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now bc250-smu-oc.service || {
        fail_with_log "Failed to enable service." "CPU Governor Setup — enable service"
        return 1
    }
    print_success "CPU Governor configuration applied successfully!"
}

run_cpu_governor() {
    print_step "01" "Installing CPU Governor"

    if cpu_governor_installed; then
        if ! cpu_governor_venv_healthy; then
            print_info "CPU governor is installed but the pipx venv is broken (common after SteamOS updates)."
            cpu_governor_repair_venv || return 1
            cpu_governor_setup || return 1
            print_success "CPU Governor repaired and configured successfully!"
            return 0
        fi
        if confirm "CPU governor is already installed. Reinstall it?"; then
            print_info "Removing existing installation..."
            systemctl stop bc250-smu-oc.service 2>/dev/null || true
            systemctl disable bc250-smu-oc.service 2>/dev/null || true
            pipx uninstall bc250-smu-oc 2>/dev/null || true
            [[ -f /etc/bc250-smu-oc.conf ]] && rm -f /etc/bc250-smu-oc.conf
            [[ -d "bc250_smu_oc" ]] && rm -rf "bc250_smu_oc"
        else
            print_info "Keeping existing installation — running configuration setup instead..."
            cpu_governor_setup
            return $?
        fi
    fi

    print_info "Installing dependencies: python-pipx, stress"
    steamos_writable 'pacman -Syu python-pipx stress --noconfirm' || {
        fail_with_log "Failed to install dependencies." "CPU Governor Install — dependencies"
        return 1
    }

    CPU_GOVERNOR_DIR="$EXTERNAL_DIR/bc250_smu_oc"
    if [[ ! -d "$CPU_GOVERNOR_DIR" ]]; then
        fail_with_log "Vendored bc250_smu_oc not found at $CPU_GOVERNOR_DIR." "CPU Governor Install — missing vendored repo"
        return 1
    fi
    print_info "Using vendored bc250_smu_oc repository..."
    pushd "$CPU_GOVERNOR_DIR" >/dev/null || return 1
    print_info "Installing via pipx..."
    pipx uninstall bc250-smu-oc 2>/dev/null || true
    run_with_retry "pipx install ." "pipx install bc250_smu_oc" || { fail_with_log "Failed to install via pipx." "CPU Governor Install — pipx install"; popd >/dev/null || true; return 1; }
    popd >/dev/null || true
    pipx ensurepath || true
    export PATH="$PATH:/root/.local/bin"

    if ! cpu_governor_venv_healthy; then
        print_info "pipx install completed but bc250-detect is still not working. Attempting reinstall..."
        cpu_governor_repair_venv || return 1
    fi

    cpu_governor_setup || return 1
    print_success "CPU Governor installed successfully!"
    persist_state_add "cpu"
}

gpu_governor_installed() {
    systemctl is-enabled cyan-skillfish-governor-smu.service &>/dev/null || \
        pacman -Qq cyan-skillfish-governor-smu &>/dev/null
}

gpu_governor_setup() {
    print_step "02-S" "GPU Governor — Configuration Setup"
    # The AUR package's default-config.toml ships with dbus.enabled unset
    # (defaults to false) -- the governor needs it true to expose its D-Bus
    # interface. See: https://github.com/filippor/cyan-skillfish-governor
    if [[ -f "$GPU_DEST" ]] && ! grep -q '^\[dbus\]' "$GPU_DEST"; then
        print_info "Enabling dbus.enabled in $GPU_DEST..."
        printf '[dbus]\nenabled = true\n' | cat - "$GPU_DEST" > "${GPU_DEST}.tmp" && mv "${GPU_DEST}.tmp" "$GPU_DEST"
    fi
    print_info "Enabling and starting systemd service..."
    systemctl enable --now cyan-skillfish-governor-smu.service || {
        fail_with_log "Failed to enable GPU governor service." "GPU Governor Setup — enable service"
        return 1
    }
    print_success "GPU Governor configuration applied successfully!"
}

run_gpu_governor() {
    print_step "02" "Installing GPU Governor"

    if gpu_governor_installed; then
        if confirm "GPU governor is already installed. Reinstall it?"; then
            print_info "Removing existing installation..."
            systemctl stop cyan-skillfish-governor-smu.service 2>/dev/null || true
            systemctl disable cyan-skillfish-governor-smu.service 2>/dev/null || true
            steamos_writable 'aur_remove cyan-skillfish-governor-smu' || true
        else
            print_info "Keeping existing installation — running configuration setup instead..."
            gpu_governor_setup
            return $?
        fi
    fi

    print_info "Installing cyan-skillfish-governor-smu via AUR helper..."
    ensure_build_deps || return 1
    aur_clean_cache cyan-skillfish-governor-smu
    steamos_writable 'aur_install cyan-skillfish-governor-smu' || {
        fail_with_log "Failed to install GPU governor." "GPU Governor Install — aur_install"
        return 1
    }

    gpu_governor_setup || return 1
    print_success "GPU Governor installed and started successfully!"
    persist_state_add "gpu"
}

run_revert_cpu_governor() {
    print_step "R-1" "Revert CPU Governor — Removing bc250-smu-oc"

    if ! systemctl is-enabled bc250-smu-oc.service &>/dev/null && \
       ! pipx list 2>/dev/null | grep -q 'bc250-smu-oc'; then
        print_info "CPU governor does not appear to be installed — nothing to revert."
        return 0
    fi

    if ! confirm "This will stop, disable, and remove the bc250-smu-oc service. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    systemctl stop bc250-smu-oc.service 2>/dev/null || true
    systemctl disable bc250-smu-oc.service 2>/dev/null || true
    pipx uninstall bc250-smu-oc 2>/dev/null || true
    [[ -f /etc/bc250-smu-oc.conf ]] && rm -f /etc/bc250-smu-oc.conf
    print_success "CPU governor removed successfully."
    persist_state_remove "cpu"
}

run_revert_gpu_governor() {
    print_step "R-2" "Revert GPU Governor — Removing cyan-skillfish-governor-smu"

    if ! systemctl is-enabled cyan-skillfish-governor-smu.service &>/dev/null && \
       ! pacman -Qq cyan-skillfish-governor-smu &>/dev/null; then
        print_info "GPU governor does not appear to be installed — nothing to revert."
        return 0
    fi

    if ! confirm "This will stop, disable, and remove the cyan-skillfish-governor-smu service. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    systemctl stop cyan-skillfish-governor-smu.service 2>/dev/null || true
    systemctl disable cyan-skillfish-governor-smu.service 2>/dev/null || true
    steamos_writable 'aur_remove cyan-skillfish-governor-smu' || true
    print_success "GPU governor removed successfully."
    persist_state_remove "gpu"
}

# ==============================================================================
# CPU CORE UNLOCK (rw-r-r-0644/bc250-core-unlock)
# ==============================================================================
# BC-250 ships with 2 of its 8 CPU cores gated off (6c/12t as shipped). An
# SMU mailbox message (queue 3, msg 0x98) can overwrite the core presence
# mask directly; AGESA then enumerates all 8 cores on the *next* boot. The
# write only survives warm reboots — a full cold power-off clears the mask
# back to 6c/12t — so a boot-time systemd service re-applies it every start.
# No SteamOS-specific changes were needed: the script only touches the PCI
# config space of the host bridge and the existing cyan-skillfish-governor
# service, both already present on this toolkit's supported systems.
# EXPERIMENTAL: upstream notes these cores may be disabled for a reason
# (silicon binning) — see external/bc250-core-unlock/README.md.

CORE_UNLOCK_DIR="$EXTERNAL_DIR/bc250-core-unlock"
CORE_UNLOCK_SCRIPT="$CORE_UNLOCK_DIR/bc250-unlock-cores.py"
CORE_UNLOCK_SERVICE="/etc/systemd/system/bc250-core-unlock.service"
CORE_UNLOCK_BOOT_WRAPPER="$CORE_UNLOCK_DIR/bc250-core-unlock-boot.sh"
CORE_UNLOCK_CONF="/etc/bc250-core-unlock.conf"

core_unlock_persist_installed() {
    systemctl list-unit-files bc250-core-unlock.service &>/dev/null
}

core_unlock_cores_active() {
    (( $(nproc --all 2>/dev/null || echo 0) >= 16 ))
}

install_core_unlock() {
    local auto="${1:-}"
    print_step "09" "Installing CPU Core Unlock (BC-250 6c/12t -> 8c/16t)"
    echo -e "  ${YELLOW}⚠  EXPERIMENTAL: these 2 cores may be disabled for a reason (silicon binning).${RESET}"
    echo -e "  ${YELLOW}⚠  Stress-test (mprime/stress-ng) for a few hours and check dmesg for MCEs before relying on them.${RESET}"
    echo -e "  ${YELLOW}⚠  Known issue: GPU clock reporting (pp_dpm_sclk / hwmon freq1_input) becomes inaccurate after unlocking.${RESET}"
    echo -e "  ${DIM}Fixed by the DP Audio/Video Fix (Install Manual 7), which queries GFX clock directly from the SMU and${RESET}"
    echo -e "  ${DIM}adds GPU utilization reporting. Not chained automatically here (it rebuilds a kernel module); run it too.${RESET}"
    echo -e "  ${DIM}Volatile: a cold power-off reverts to 6c/12t. A systemd service re-applies the unlock on every boot.${RESET}"
    echo ""

    if [[ ! -f "$CORE_UNLOCK_SCRIPT" ]]; then
        fail_with_log "Vendored bc250-unlock-cores.py not found at $CORE_UNLOCK_SCRIPT." "CPU Core Unlock — missing vendored script"
        return 1
    fi

    if [[ "$auto" != "auto" ]] && ! confirm "Continue with the CPU core unlock?"; then
        print_info "Cancelled."
        return 0
    fi

    local auto_reboot_choice="yes"
    if [[ "$auto" != "auto" ]]; then
        echo ""
        echo -e "  ${DIM}After a cold power-off, the unlock always needs ONE extra reboot to take effect:${RESET}"
        echo -e "  ${DIM}the boot service rewrites the core mask, but AGESA only reads it on the FOLLOWING boot.${RESET}"
        if confirm "Automatically trigger that second reboot when needed?"; then
            auto_reboot_choice="yes"
        else
            auto_reboot_choice="no"
            print_info "Auto-reboot disabled — if status shows 'still 6c/12t' after a cold boot, run 'sudo reboot' yourself to bring up all 8 cores."
        fi
    fi

    print_info "Stopping GPU governor service (shares the SMU mailbox)..."
    local gpu_was_active=0
    systemctl is-active --quiet "$GPU_SERVICE" 2>/dev/null && gpu_was_active=1
    systemctl stop "$GPU_SERVICE" 2>/dev/null || true

    print_info "Running bc250-unlock-cores.py..."
    local unlock_output unlock_rc
    unlock_output="$(python3 "$CORE_UNLOCK_SCRIPT" 2>&1)"
    unlock_rc=$?
    echo "$unlock_output" | sed 's/^/    /'

    if (( gpu_was_active )); then
        systemctl start "$GPU_SERVICE" 2>/dev/null || true
    fi

    if (( unlock_rc != 0 )); then
        fail_with_log "bc250-unlock-cores.py failed — see output above. This is expected if the core presence mask is not 0x77 (already unlocked, or a different board/harvest)." "CPU Core Unlock — bc250-unlock-cores.py"
        return 1
    fi

    # The community reports 8-core operation needs the updated (6c/8c-compatible)
    # ACPI C-/P-state tables — install/update it transparently in the same run.
    print_info "Ensuring the 6c/8c-compatible ACPI fix is installed alongside the core unlock..."
    install_acpi_fix force || print_error "ACPI fix install/update failed — CPU core unlock still applied, but C-/P-states may misbehave with 8 cores active. Retry from Install Manual (6)."

    echo "AUTO_REBOOT=$auto_reboot_choice" > "$CORE_UNLOCK_CONF"

    cat > "$CORE_UNLOCK_BOOT_WRAPPER" <<EOF
#!/usr/bin/env bash
# Generated by bc250-steamos-real-toolkit. Re-applies the CPU core unlock on
# every boot. AGESA only reads the new core presence mask on the boot AFTER
# it is written, so after a cold power-off (mask reset to 6c/12t) this always
# needs one more reboot to actually bring up 8 cores. If AUTO_REBOOT=yes in
# $CORE_UNLOCK_CONF, that second reboot is triggered automatically -- but
# only right after a fresh mask write, never on an already-0xFF boot, so a
# genuine enumeration failure can't turn this into a reboot loop.
set -u

AUTO_REBOOT="no"
[[ -f "$CORE_UNLOCK_CONF" ]] && source "$CORE_UNLOCK_CONF"

output="\$(/usr/bin/python3 "$CORE_UNLOCK_SCRIPT" 2>&1)"
rc=\$?
echo "\$output"

cores_active=0
(( \$(nproc --all 2>/dev/null || echo 0) >= 16 )) && cores_active=1

if (( rc == 0 )) && [[ "\$output" == *"OK. Reboot"* ]] && (( ! cores_active )); then
    if [[ "\$AUTO_REBOOT" == "yes" ]]; then
        echo "bc250-core-unlock: mask just written, auto-rebooting to bring up all 8 cores..."
        systemctl reboot
    else
        echo "bc250-core-unlock: mask written but AUTO_REBOOT=no in $CORE_UNLOCK_CONF -- reboot manually to bring up all 8 cores."
    fi
fi

exit \$rc
EOF
    chmod 755 "$CORE_UNLOCK_BOOT_WRAPPER"
    chown "$REAL_USER":"$REAL_USER" "$CORE_UNLOCK_BOOT_WRAPPER" 2>/dev/null || true

    cat > "$CORE_UNLOCK_SERVICE" <<EOF
[Unit]
Description=Re-apply BC-250 CPU core unlock (volatile across cold boot)
After=sysinit.target

[Service]
Type=oneshot
ExecStartPre=-/usr/bin/systemctl stop cyan-skillfish-governor-smu.service
ExecStart=$CORE_UNLOCK_BOOT_WRAPPER
ExecStartPost=-/usr/bin/systemctl start cyan-skillfish-governor-smu.service
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable bc250-core-unlock.service

    print_success "CPU core unlock applied and boot-time re-apply service installed. Reboot to bring up all 8 cores/16 threads."
    if [[ "$auto_reboot_choice" == "yes" ]]; then
        print_info "Auto-reboot is ON: after a cold power-off, the machine will reboot itself once more automatically to finish bringing up all 8 cores."
    else
        print_info "Auto-reboot is OFF: after a cold power-off, run 'sudo reboot' yourself once status shows 'still 6c/12t'."
    fi
    persist_state_add "core_unlock"
}

# ==============================================================================
# RAM/VRAM SPLIT (fanoush/bc250_memcfg)
# ==============================================================================
# The BC-250 shares 16GB of RAM between CPU and GPU (UMA). The stock BIOS
# reserves a fixed minimum VRAM size (UMA_SIZE, stored in battery-backed
# CMOS) of 8192MB (8GB RAM / 8GB VRAM), locking half the machine's memory to
# the GPU even at idle. Dropping UMA_SIZE to 512 (the documented minimum
# floor) frees nearly all RAM when idle; Linux's amdgpu/ttm driver still
# dynamically grows VRAM above that floor as games need it, up to a
# kernel-enforced ceiling that defaults to roughly half of free RAM. That
# default ceiling can be too low for games wanting 8GB+ VRAM, so we also
# raise it via the ttm.pages_limit kernel parameter. Neither setting needs a
# modded BIOS -- UMA_SIZE is a plain CMOS write via a small vendored tool
# (fanoush/bc250_memcfg), compiled locally from source at install time.
# See: https://elektricm.github.io/amd-bc250-docs/bios/vram/

RAM_SPLIT_DIR="$EXTERNAL_DIR/bc250_memcfg"
RAM_SPLIT_BIN="$RAM_SPLIT_DIR/bc250memcfg"
RAM_SPLIT_DEFAULT_UMA_MB=512
RAM_SPLIT_STOCK_UMA_MB=8192
RAM_SPLIT_DEFAULT_TTM_PAGES=3145728   # ~12GB dynamic VRAM ceiling (4KiB pages)

ram_split_bc250_detected() {
    command -v lspci >/dev/null 2>&1 && lspci -Dn 2>/dev/null | grep -qi '1002:13fe'
}

ram_split_gcc_can_compile() {
    command -v gcc >/dev/null 2>&1 || return 1
    local probe; probe=$(mktemp -u --suffix=.c)
    printf '#include <stdio.h>\nint main(void){return 0;}\n' > "$probe"
    gcc "$probe" -o "${probe%.c}.out" >/dev/null 2>&1
    local rc=$?
    rm -f "$probe" "${probe%.c}.out"
    return $rc
}

ram_split_build_tool() {
    [[ -x "$RAM_SPLIT_BIN" ]] && return 0
    if [[ ! -f "$RAM_SPLIT_DIR/main.cpp" ]]; then
        fail_with_log "Vendored bc250_memcfg source not found at $RAM_SPLIT_DIR." "RAM/VRAM Split — missing vendored source"
        return 1
    fi
    if ! ram_split_gcc_can_compile; then
        # gcc may be present but glibc headers (stdio.h etc.) missing/stripped
        # on the SteamOS overlay -- force-reinstall rather than relying on
        # pacman's "already installed" bookkeeping (which --needed respects).
        print_info "gcc / libc headers missing or broken — (re)installing base-devel + glibc..."
        steamos_writable 'pacman -Sy --noconfirm base-devel glibc' || {
            fail_with_log "Failed to install gcc/glibc." "RAM/VRAM Split — gcc"
            return 1
        }
    fi
    if ! ram_split_gcc_can_compile; then
        fail_with_log "gcc still cannot compile a plain C program after reinstalling base-devel/glibc (missing /usr/include headers on this SteamOS image). Check 'pacman -Qo /usr/include/stdio.h' and 'ls /usr/include/stdio.h'." "RAM/VRAM Split — gcc headers"
        return 1
    fi
    print_info "Building bc250memcfg from vendored source..."
    (cd "$RAM_SPLIT_DIR" && gcc -Os -s main.cpp -o bc250memcfg) || {
        fail_with_log "Failed to build bc250memcfg." "RAM/VRAM Split — build"
        return 1
    }
}

ram_split_current_uma() {
    [[ -x "$RAM_SPLIT_BIN" ]] || return 1
    local val
    val=$(timeout 5 "$RAM_SPLIT_BIN" 2>/dev/null | awk -F= '$1 == "UMA_SIZE" {print $2}' | tr -d ' \r')
    [[ -n "$val" ]] || return 1
    echo "$((10#$val))"
}

ram_split_installed() {
    [[ -f "$GRUB_DEFAULT" ]] && grep -qE 'GRUB_CMDLINE_LINUX_DEFAULT=.*ttm\.pages_limit=' "$GRUB_DEFAULT" 2>/dev/null
}

install_ram_split() {
    local auto="${1:-}"
    print_step "10" "Installing RAM/VRAM Split (UMA_SIZE=${RAM_SPLIT_DEFAULT_UMA_MB}MB dynamic + ttm.pages_limit ceiling)"
    echo -e "  ${YELLOW}⚠  Writes to the BC-250's battery-backed CMOS (BIOS memory config) — no modded BIOS needed.${RESET}"
    echo -e "  ${DIM}Frees nearly all 16GB of RAM at idle (stock BIOS permanently reserves 8GB for VRAM);${RESET}"
    echo -e "  ${DIM}the GPU still dynamically claims up to ~12GB when a game needs it (ttm.pages_limit).${RESET}"
    echo -e "  ${DIM}Recovery if something goes wrong: clear CMOS via the board's jumper/battery.${RESET}"
    echo ""

    if [[ "$auto" != "auto" ]] && ! confirm "Continue with the RAM/VRAM split configuration?"; then
        print_info "Cancelled."
        return 0
    fi

    if ! ram_split_bc250_detected; then
        fail_with_log "BC-250 GPU (PCI ID 1002:13fe) not detected — refusing the CMOS write to avoid corrupting unrelated hardware." "RAM/VRAM Split — hardware check"
        return 1
    fi

    ram_split_build_tool || return 1

    print_info "Writing UMA_SIZE=${RAM_SPLIT_DEFAULT_UMA_MB} to CMOS..."
    local output
    output=$("$RAM_SPLIT_BIN" UMA_SIZE "$RAM_SPLIT_DEFAULT_UMA_MB" 2>&1)
    echo "$output" | sed 's/^/    /'
    [[ "$output" == "setting UMA_SIZE to $RAM_SPLIT_DEFAULT_UMA_MB" ]] || {
        fail_with_log "bc250memcfg did not confirm the UMA_SIZE write." "RAM/VRAM Split — CMOS write"
        return 1
    }
    local readback
    readback=$(ram_split_current_uma)
    [[ "$readback" == "$RAM_SPLIT_DEFAULT_UMA_MB" ]] || {
        fail_with_log "CMOS readback is ${readback:-unknown}MB, not the requested ${RAM_SPLIT_DEFAULT_UMA_MB}MB." "RAM/VRAM Split — CMOS readback"
        return 1
    }

    print_info "Raising the kernel's dynamic VRAM ceiling (ttm.pages_limit)..."
    steamos_writable "
        cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
        sed -i 's/ ttm\\.pages_limit=[0-9]*//g; s/ttm\\.pages_limit=[0-9]* //g; s/ttm\\.pages_limit=[0-9]*//g' \"$GRUB_DEFAULT\"
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\([^\"]*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 ttm.pages_limit=$RAM_SPLIT_DEFAULT_TTM_PAGES\"/' \"$GRUB_DEFAULT\"
        update-grub
    " || {
        fail_with_log "Failed to update GRUB with ttm.pages_limit." "RAM/VRAM Split — grub"
        return 1
    }

    print_success "RAM/VRAM split configured! UMA_SIZE=${RAM_SPLIT_DEFAULT_UMA_MB}MB (CMOS), ttm.pages_limit=$RAM_SPLIT_DEFAULT_TTM_PAGES (~12GB dynamic ceiling). Reboot required."
    persist_state_add "ram_split"
    print_info "After reboot verify: ${CYAN}free -h${RESET} and ${CYAN}cat /sys/class/drm/card0/device/mem_info_vram_total${RESET}"
}

run_revert_ram_split() {
    print_step "R-10" "Revert RAM/VRAM Split — restore stock ${RAM_SPLIT_STOCK_UMA_MB}MB split"

    if ! ram_split_installed; then
        print_info "RAM/VRAM split does not appear to be installed — nothing to revert."
        return 0
    fi

    if ! confirm "This restores the stock UMA_SIZE=${RAM_SPLIT_STOCK_UMA_MB} split and removes ttm.pages_limit from GRUB. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    if [[ -x "$RAM_SPLIT_BIN" ]] && ram_split_bc250_detected; then
        print_info "Restoring stock UMA_SIZE=${RAM_SPLIT_STOCK_UMA_MB} in CMOS..."
        local output
        output=$("$RAM_SPLIT_BIN" UMA_SIZE "$RAM_SPLIT_STOCK_UMA_MB" 2>&1)
        echo "$output" | sed 's/^/    /'
    else
        print_info "bc250memcfg unavailable — skipping CMOS restore (only removing the GRUB ttm.pages_limit override)."
    fi

    steamos_writable "
        cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
        sed -i 's/ ttm\\.pages_limit=[0-9]*//g; s/ttm\\.pages_limit=[0-9]* //g; s/ttm\\.pages_limit=[0-9]*//g' \"$GRUB_DEFAULT\"
        update-grub
    " || {
        fail_with_log "Failed to remove ttm.pages_limit from GRUB." "RAM/VRAM Split — grub revert"
        return 1
    }

    print_success "RAM/VRAM split reverted to stock ${RAM_SPLIT_STOCK_UMA_MB}MB split. Reboot to apply."
    persist_state_remove "ram_split"
}

run_revert_core_unlock() {
    print_step "R-09" "Revert CPU Core Unlock"

    if ! core_unlock_persist_installed; then
        print_info "CPU core unlock service does not appear to be installed — nothing to revert."
        return 0
    fi

    if ! confirm "This will disable the boot-time re-apply service. The core mask itself only reverts to 6c/12t after a cold power-off (not immediately, and not on a warm reboot). Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    systemctl disable --now bc250-core-unlock.service 2>/dev/null || true
    rm -f "$CORE_UNLOCK_SERVICE" "$CORE_UNLOCK_BOOT_WRAPPER" "$CORE_UNLOCK_CONF"
    systemctl daemon-reload

    print_success "CPU core unlock boot service removed. The extra cores remain active until the next cold power-off."
    persist_state_remove "core_unlock"
}

# ==============================================================================
# CPU MITIGATIONS
# ==============================================================================

GRUB_DEFAULT="/etc/default/grub"

mitigations_currently_off() {
    [[ -f "$GRUB_DEFAULT" ]] && grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=.*mitigations=off' "$GRUB_DEFAULT" >/dev/null 2>&1
}

run_disable_mitigations() {
    local auto="${1:-}"
    print_step "T-1" "Disable CPU Mitigations"

    if mitigations_currently_off; then
        print_info "CPU mitigations are already disabled."
        return 0
    fi

    if [[ "$auto" != "auto" ]] && ! confirm "This will add 'mitigations=off' to the GRUB kernel command line and regenerate the bootloader. A reboot is required. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    if [[ ! -f "$GRUB_DEFAULT" ]]; then
        print_error "$GRUB_DEFAULT not found."
        return 1
    fi

    if ! command -v update-grub >/dev/null 2>&1; then
        print_error "update-grub not found. Cannot regenerate GRUB config."
        return 1
    fi

    steamos_writable "
        cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
        if grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=' \"$GRUB_DEFAULT\" | grep -q 'mitigations=off'; then
            :
        else
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\([^\"]*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 mitigations=off\"/' \"$GRUB_DEFAULT\"
        fi
        update-grub
    " || {
        print_error "Failed to disable CPU mitigations."
        return 1
    }

    print_success "CPU mitigations disabled. Reboot to apply."
    persist_state_add "mitigations"
    print_info "Backup saved at $GRUB_DEFAULT.bak"
}

run_revert_mitigations() {
    local auto="${1:-}"
    print_step "T-2" "Re-enable CPU Mitigations"

    if ! mitigations_currently_off; then
        print_info "CPU mitigations are already enabled."
        return 0
    fi

    if [[ "$auto" != "auto" ]] && ! confirm "This will remove 'mitigations=off' from the GRUB kernel command line and regenerate the bootloader. A reboot is required. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    if [[ ! -f "$GRUB_DEFAULT" ]]; then
        print_error "$GRUB_DEFAULT not found."
        return 1
    fi

    if ! command -v update-grub >/dev/null 2>&1; then
        print_error "update-grub not found. Cannot regenerate GRUB config."
        return 1
    fi

    steamos_writable "
        cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
        sed -i 's/ mitigations=off//g; s/mitigations=off //g; s/mitigations=off//g' \"$GRUB_DEFAULT\"
        update-grub
    " || {
        print_error "Failed to re-enable CPU mitigations."
        return 1
    }

    print_success "CPU mitigations re-enabled. Reboot to apply."
    persist_state_remove "mitigations"
    print_info "Backup saved at $GRUB_DEFAULT.bak"
}

# ==============================================================================
# SWAP & ZRAM/ZSWAP
# ==============================================================================
# Adapted from redbeard1083/bc250-toolkit's "Enable Swap" / "ZRAM -> ZSWAP"
# steps. That toolkit targets CachyOS+Limine with a dedicated Btrfs
# /var/swap subvolume; SteamOS already ships its own swapfile mechanism
# (swapfile.service + home-swapfile.swap, 1024M at /home/swapfile on ext4)
# and zram via zram-generator, so this reuses those instead of creating a
# parallel setup: we resize SteamOS's own swapfile in place, and gate ZRAM
# off / ZSWAP on via the systemd.zram=/zswap.* kernel command-line options
# (GRUB) exactly like the upstream repo, since zram-generator itself
# honors systemd.zram=0 to suppress the zram0 device regardless of its
# config file.

SWAPFILE_PATH="/home/swapfile"
SWAPFILE_STOCK_SIZE_MB=1024   # SteamOS's own swapfile.service default
SWAPPINESS_CONF="/etc/sysctl.d/99-bc250-swappiness.conf"
MKINITCPIO_CONF="/etc/mkinitcpio.conf"
ZSWAP_TMPFILES_CONF="/etc/tmpfiles.d/bc250-zswap.conf"

swapfile_size_mb() {
    [[ -f "$SWAPFILE_PATH" ]] || { echo 0; return; }
    echo $(( $(stat -c %s "$SWAPFILE_PATH") / 1024 / 1024 ))
}

zswap_currently_on() {
    # GRUB cmdline is the persistent config, but some SteamOS kernels do not
    # honor zswap.enabled=1 at boot and leave the runtime parameter at N.
    # Treat ZSWAP as ON only when it is configured in GRUB AND enabled now.
    [[ -f "$GRUB_DEFAULT" ]] && grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=.*zswap\.enabled=' "$GRUB_DEFAULT" >/dev/null 2>&1 || return 1
    [[ -r /sys/module/zswap/parameters/enabled ]] || return 1
    grep -qx 'Y' /sys/module/zswap/parameters/enabled 2>/dev/null
}

zswap_enable_runtime() {
    if [[ -w /sys/module/zswap/parameters/enabled ]]; then
        if ! grep -qx 'Y' /sys/module/zswap/parameters/enabled 2>/dev/null; then
            echo Y > /sys/module/zswap/parameters/enabled
            print_info "ZSWAP enabled at runtime immediately."
        fi
    fi
}

zram_currently_disabled() {
    [[ -f "$GRUB_DEFAULT" ]] && grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=.*systemd\.zram=0' "$GRUB_DEFAULT" >/dev/null 2>&1
}

run_configure_swap() {
    local auto="${1:-}"
    print_step "SW-1" "Configure Swap"
    echo -e "  ${DIM}Resizes SteamOS's own swapfile ($SWAPFILE_PATH) and sets vm.swappiness.${RESET}"
    echo ""

    local swap_size swappiness
    if [[ "$auto" == "auto" ]]; then
        swap_size="32"
        swappiness="120"
        print_info "Install All: using defaults (32G, swappiness=120). Use 'Configure Swap' from the menu to customize."
    else
        read -rp "$(echo -e "  ${BOLD}${WHITE}Swap size in GB (default: 32):${RESET} ")" swap_size_input
        if [[ -z "$swap_size_input" ]]; then
            swap_size="32"
        elif [[ "$swap_size_input" =~ ^[0-9]+$ ]] && (( swap_size_input > 0 )); then
            swap_size="$swap_size_input"
        else
            print_error "Invalid size '$swap_size_input' — must be a positive integer. Using default 32G."
            swap_size="32"
        fi

        read -rp "$(echo -e "  ${BOLD}${WHITE}Swappiness value (default: 120):${RESET} ")" swappiness_input
        if [[ -z "$swappiness_input" ]]; then
            swappiness="120"
        elif [[ "$swappiness_input" =~ ^[0-9]+$ ]]; then
            swappiness="$swappiness_input"
        else
            print_error "Invalid swappiness '$swappiness_input' — must be a number. Using default 120."
            swappiness="120"
        fi
    fi

    local free_home_gb
    free_home_gb=$(df --output=avail -BG "$(dirname "$SWAPFILE_PATH")" | tail -1 | tr -dc '0-9')
    if [[ "$auto" != "auto" ]] && ! confirm "This will replace $SWAPFILE_PATH with a ${swap_size}G swapfile and set vm.swappiness=${swappiness} (${free_home_gb}G free on $(dirname "$SWAPFILE_PATH")). Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    print_info "Disabling and removing existing swapfile..."
    swapoff "$SWAPFILE_PATH" 2>/dev/null || true
    rm -f "$SWAPFILE_PATH"

    print_info "Creating ${swap_size}G swapfile at $SWAPFILE_PATH..."
    if findmnt -no FSTYPE "$(dirname "$SWAPFILE_PATH")" 2>/dev/null | grep -q btrfs; then
        btrfs filesystem mkswapfile --size "${swap_size}G" "$SWAPFILE_PATH" || {
            fail_with_log "Failed to create Btrfs swapfile." "Configure Swap — mkswapfile"
            return 1
        }
    else
        fallocate -l "${swap_size}G" "$SWAPFILE_PATH" 2>/dev/null || dd if=/dev/zero of="$SWAPFILE_PATH" bs=1M count=$(( swap_size * 1024 )) status=none
        chmod 600 "$SWAPFILE_PATH"
        mkswap "$SWAPFILE_PATH" || {
            fail_with_log "Failed to format swapfile." "Configure Swap — mkswap"
            return 1
        }
    fi

    print_info "Enabling swapfile..."
    swapon "$SWAPFILE_PATH" || {
        fail_with_log "Failed to enable swap." "Configure Swap — swapon"
        return 1
    }

    print_info "Setting swappiness to ${swappiness}..."
    echo "vm.swappiness = ${swappiness}" > "$SWAPPINESS_CONF"
    sysctl -p "$SWAPPINESS_CONF" >/dev/null

    print_success "Swap configured! Current swap:"
    persist_state_add "swap"
    echo ""
    swapon --show | sed 's/^/    /'
}

run_revert_swap() {
    local auto="${1:-}"
    print_step "R-SW" "Revert Swap to SteamOS Default"

    if (( $(swapfile_size_mb) <= SWAPFILE_STOCK_SIZE_MB )) && [[ ! -f "$SWAPPINESS_CONF" ]]; then
        print_info "Swap already appears to be at SteamOS defaults — nothing to revert."
        return 0
    fi

    if [[ "$auto" != "auto" ]] && ! confirm "This will shrink $SWAPFILE_PATH back to the stock ${SWAPFILE_STOCK_SIZE_MB}M and remove the custom swappiness override. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    print_info "Disabling and removing current swapfile..."
    swapoff "$SWAPFILE_PATH" 2>/dev/null || true
    rm -f "$SWAPFILE_PATH"

    print_info "Recreating stock ${SWAPFILE_STOCK_SIZE_MB}M swapfile (matching swapfile.service)..."
    mkswap --file "$SWAPFILE_PATH" --size "${SWAPFILE_STOCK_SIZE_MB}M" || {
        fail_with_log "Failed to recreate stock swapfile." "Revert Swap — mkswap"
        return 1
    }
    swapon "$SWAPFILE_PATH" || true

    print_info "Removing swappiness override (default: 60)..."
    rm -f "$SWAPPINESS_CONF"
    sysctl vm.swappiness=60 >/dev/null 2>&1 || true

    print_success "Swap reverted to SteamOS default (${SWAPFILE_STOCK_SIZE_MB}M, swappiness=60)."
    persist_state_remove "swap"
}

run_zram_zswap_toggle() {
    local auto="${1:-}"
    print_step "SW-2" "Disable ZRAM & Enable ZSWAP"

    if zram_currently_disabled && zswap_currently_on; then
        print_info "ZRAM is already disabled and ZSWAP is already enabled."
        return 0
    fi

    if [[ "$auto" != "auto" ]] && ! confirm "This will disable ZRAM, enable ZSWAP (lz4, 25% pool) via GRUB kernel parameters, add lz4 modules to the initramfs, and regenerate the bootloader. A reboot is required. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    if [[ ! -f "$GRUB_DEFAULT" ]]; then
        print_error "$GRUB_DEFAULT not found."
        return 1
    fi
    if ! command -v update-grub >/dev/null 2>&1; then
        print_error "update-grub not found. Cannot regenerate GRUB config."
        return 1
    fi

    steamos_writable "
        cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
        if ! grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=' \"$GRUB_DEFAULT\" | grep -q 'systemd.zram=0'; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\([^\"]*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 systemd.zram=0\"/' \"$GRUB_DEFAULT\"
        fi
        if ! grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=' \"$GRUB_DEFAULT\" | grep -q 'zswap.enabled=1'; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\([^\"]*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4\"/' \"$GRUB_DEFAULT\"
        fi
        if ! grep -q 'lz4' \"$MKINITCPIO_CONF\" 2>/dev/null; then
            sed -i 's/^MODULES=(\\(.*\\))/MODULES=(\\1 lz4 lz4_compress)/' \"$MKINITCPIO_CONF\"
            mkinitcpio -P
        fi
        printf '%s\n' 'w /sys/module/zswap/parameters/enabled - - - - Y' > \"$ZSWAP_TMPFILES_CONF\"
        systemd-tmpfiles --create \"$ZSWAP_TMPFILES_CONF\"
        update-grub
    " || {
        fail_with_log "Failed to disable ZRAM / enable ZSWAP." "ZRAM->ZSWAP — grub/mkinitcpio"
        return 1
    }

    # Some SteamOS kernels do not enable the runtime toggle from GRUB alone.
    # Force it on now so the user does not need another reboot.
    zswap_enable_runtime

    print_success "ZRAM disabled and ZSWAP enabled."
    persist_state_add "zswap"
    print_info "Verify with: sudo cat /sys/module/zswap/parameters/enabled"
    print_info "Backup saved at $GRUB_DEFAULT.bak"
}

run_revert_zram_zswap() {
    local auto="${1:-}"
    print_step "R-SW2" "Revert ZRAM/ZSWAP to SteamOS Default"

    if ! zram_currently_disabled && ! zswap_currently_on; then
        print_info "ZRAM/ZSWAP already at SteamOS defaults — nothing to revert."
        return 0
    fi

    if [[ "$auto" != "auto" ]] && ! confirm "This will remove systemd.zram=0 / zswap.* from GRUB, remove lz4 modules from the initramfs, and regenerate the bootloader. A reboot is required. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    if [[ ! -f "$GRUB_DEFAULT" ]]; then
        print_error "$GRUB_DEFAULT not found."
        return 1
    fi
    if ! command -v update-grub >/dev/null 2>&1; then
        print_error "update-grub not found. Cannot regenerate GRUB config."
        return 1
    fi

    steamos_writable "
        cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
        sed -i 's/ systemd\\.zram=0//g; s/systemd\\.zram=0 //g; s/systemd\\.zram=0//g' \"$GRUB_DEFAULT\"
        sed -i 's/ zswap\\.enabled=1 zswap\\.max_pool_percent=25 zswap\\.compressor=lz4//g' \"$GRUB_DEFAULT\"
        sed -i 's/ zswap\\.[a-z_]*=[a-zA-Z0-9]*//g' \"$GRUB_DEFAULT\"
        sed -i 's/ lz4_compress//g; s/ lz4\\b//g' \"$MKINITCPIO_CONF\" 2>/dev/null || true
        mkinitcpio -P 2>/dev/null || true
        rm -f \"$ZSWAP_TMPFILES_CONF\"
        update-grub
    " || {
        fail_with_log "Failed to revert ZRAM/ZSWAP." "Revert ZRAM/ZSWAP — grub/mkinitcpio"
        return 1
    }

    print_success "ZRAM/ZSWAP reverted to SteamOS default. Reboot to apply."
    persist_state_remove "zswap"
    print_info "Backup saved at $GRUB_DEFAULT.bak"
}

# ==============================================================================
# SENSORS & FAN CONTROL (Nuvoton NCT6686D SuperIO)
# ==============================================================================

SENSORS_MODPROBE_CONF="/etc/modprobe.d/sensors.conf"
SENSORS_MODULES_LOAD_CONF="/etc/modules-load.d/99-sensors.conf"
NCT6687D_DIR="$EXTERNAL_DIR/nct6687d"

sensors_driver_loaded() {
    [[ -d /sys/module/nct6683 || -d /sys/module/nct6687 ]]
}

sensors_active_driver() {
    if [[ -d /sys/module/nct6687 ]]; then
        echo "nct6687"
    elif [[ -d /sys/module/nct6683 ]]; then
        echo "nct6683"
    else
        echo "none"
    fi
}

detect_kernel_headers_package() {
    local kernel_pkg
    kernel_pkg=$(pacman -Qoq "/usr/lib/modules/$(uname -r)" 2>/dev/null | head -1)
    [[ -z "$kernel_pkg" ]] && return 1
    echo "${kernel_pkg}-headers"
}

install_sensors_readonly() {
    print_step "SENS" "Installing NCT6683 Read-Only Sensors Driver"

    print_info "Loading nct6683 module..."
    if ! modprobe nct6683 force=true; then
        fail_with_log "Failed to load nct6683 module." "Sensors Install — modprobe nct6683"
        return 1
    fi

    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        print_info "SteamOS detected: disabling read-only mode..."
        if ! steamos-readonly disable; then
            fail_with_log "Failed to disable SteamOS read-only mode." "Sensors Install — readonly disable"
            return 1
        fi
    fi

    echo "options nct6683 force=true" > "$SENSORS_MODPROBE_CONF"
    echo "nct6683" > "$SENSORS_MODULES_LOAD_CONF"

    if (( was_steamos )); then
        print_info "Re-enabling SteamOS read-only mode..."
        steamos-readonly enable || true
    fi

    print_success "NCT6683 read-only sensors driver installed!"
    print_info "Sensors report as ${CYAN}nct6686-isa-0a20${RESET} (temperatures, voltages, fan speeds — no PWM control)."
}

install_sensors_pwm() {
    print_step "PWM" "Installing NCT6687 Full PWM Fan Control Driver"

    require_kernel_version || return 1

    local headers_pkg
    if ! headers_pkg="$(detect_kernel_headers_package)"; then
        fail_with_log "Could not determine the running kernel package for header lookup." "PWM Sensors Install — kernel detection"
        return 1
    fi
    print_info "Detected kernel headers package: $headers_pkg"

    ensure_build_deps || return 1
    steamos_writable "pacman -Syu --noconfirm '$headers_pkg'" || {
        fail_with_log "Failed to install kernel headers ($headers_pkg). A matching headers package may not exist yet for this kernel." "PWM Sensors Install — headers"
        return 1
    }

    if [[ ! -d "/usr/lib/modules/$(uname -r)/build" ]]; then
        fail_with_log "Kernel build directory not found after installing headers." "PWM Sensors Install — build dir missing"
        return 1
    fi

    if [[ ! -d "$NCT6687D_DIR" ]]; then
        fail_with_log "Vendored nct6687d not found at $NCT6687D_DIR." "PWM Sensors Install — missing vendored repo"
        return 1
    fi

    print_info "Using vendored nct6687d driver..."
    print_info "Building kernel module..."
    if ! make -C "$NCT6687D_DIR"; then
        fail_with_log "Failed to build nct6687 module." "PWM Sensors Install — make"
        return 1
    fi

    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        print_info "SteamOS detected: disabling read-only mode..."
        if ! steamos-readonly disable; then
            fail_with_log "Failed to disable SteamOS read-only mode." "PWM Sensors Install — readonly disable"
            return 1
        fi
    fi

    print_info "Installing kernel module..."
    local install_rc=0
    make -C "$NCT6687D_DIR" install || install_rc=1

    if [[ $install_rc -eq 0 ]]; then
        print_info "Blacklisting nct6683 and enabling nct6687 autoload..."
        {
            echo "blacklist nct6683"
            echo "options nct6687 force=true"
        } > "$SENSORS_MODPROBE_CONF"
        echo "nct6687" > "$SENSORS_MODULES_LOAD_CONF"
    fi

    if (( was_steamos )); then
        print_info "Re-enabling SteamOS read-only mode..."
        steamos-readonly enable || true
    fi

    if [[ $install_rc -ne 0 ]]; then
        fail_with_log "Failed to install nct6687 module." "PWM Sensors Install — make install"
        return 1
    fi

    print_info "Unloading nct6683 (if loaded) and loading nct6687..."
    modprobe -r nct6683 2>/dev/null || true
    if ! modprobe nct6687 force=true; then
        fail_with_log "Module built and installed, but failed to load. A reboot may be required." "PWM Sensors Install — modprobe nct6687"
        return 1
    fi

    print_success "NCT6687 PWM fan control driver installed and loaded!"
    persist_state_add "sensors"
    print_info "Sensors report as ${CYAN}nct6686-isa-0a20${RESET}. Run 'sensors' to view readings."
    print_info "PWM control: /sys/class/hwmon/*/pwmN and pwmN_enable (writable)."
    print_info "${YELLOW}Note:${RESET} this module is rebuilt against the current kernel; a kernel update may require reinstalling it."
}

run_revert_sensors() {
    print_step "R-S" "Revert Sensors Driver"

    if ! sensors_driver_loaded && [[ ! -f "$SENSORS_MODPROBE_CONF" && ! -f "$SENSORS_MODULES_LOAD_CONF" ]]; then
        print_info "No sensor driver configuration found — nothing to revert."
        return 0
    fi

    if ! confirm "This will unload nct6683/nct6687 and remove sensor autoload config. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    modprobe -r nct6687 2>/dev/null || true
    modprobe -r nct6683 2>/dev/null || true

    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        steamos-readonly disable || true
    fi

    rm -f "$SENSORS_MODPROBE_CONF" "$SENSORS_MODULES_LOAD_CONF"
    local installed_ko="/usr/lib/modules/$(uname -r)/kernel/drivers/hwmon/nct6687.ko"
    if [[ -f "$installed_ko" ]]; then
        rm -f "$installed_ko"
        depmod
    fi

    if (( was_steamos )); then
        steamos-readonly enable || true
    fi

    print_success "Sensor driver configuration removed."
    persist_state_remove "sensors"
}

# Check if NCT6686/87 SuperIO hardware is present
nct6686_hardware_present() {
    # If a sensor driver is already loaded, hardware is present
    if sensors_driver_loaded; then
        return 0
    fi

    # Check via sysfs or ACPI
    if [[ -d /sys/devices/platform/nct6686.isa || -d /sys/devices/platform/nct6687.isa ]]; then
        return 0
    fi

    # Check ACPI for Nuvoton NCT6686/87
    if [[ -f /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:00/PNP0C09:00/VPC2000:00/hwmon/hwmon*/name ]]; then
        if grep -q "nct6686\|nct6687" /sys/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0A08:00/device:00/PNP0C09:00/VPC2000:00/hwmon/hwmon*/name 2>/dev/null; then
            return 0
        fi
    fi

    # Try probing the in-tree nct6683 module — if it loads, the hardware is there
    if modprobe nct6683 force=true 2>/dev/null; then
        modprobe -r nct6683 2>/dev/null || true
        return 0
    fi

    # Check dmesg for Nuvoton SuperIO detection
    if dmesg 2>/dev/null | grep -qi "nct668[67]"; then
        return 0
    fi

    return 1  # Hardware not found
}

# Ensure NCT6687 PWM sensor driver is installed if hardware is present
ensure_sensors_pwm_installed() {
    if ! nct6686_hardware_present; then
        print_info "NCT6686/87 SuperIO hardware not detected - skipping PWM sensor driver installation"
        return 0  # Hardware not present, nothing to do
    fi

    if sensors_driver_loaded && [[ "$(sensors_active_driver)" == "nct6687" ]]; then
        print_info "NCT6687 PWM sensor driver already loaded - skipping installation"
        return 0  # Already installed and active
    fi

    print_info "NCT6686/87 SuperIO hardware detected - ensuring PWM sensor driver is installed..."
    install_sensors_pwm
    return $?
}

# Ensure CoolerControl is installed if sensor readings are available
ensure_coolercontrol_installed() {
    # Check if we can read sensors (basic functionality)
    if ! sensors_driver_loaded; then
        print_info "No sensor driver loaded - skipping CoolerControl installation"
        return 0  # No sensor driver loaded, nothing to do
    fi

    # Check if CoolerControl is already installed
    if coolercontrol_installed; then
        print_info "CoolerControl already installed - skipping installation"
        return 0  # Already installed
    fi

    print_info "Sensor readings available - ensuring CoolerControl is installed for fan curve control..."
    install_coolercontrol
    return $?
}

# Validate that CPU core unlock was successful (checks for 8c/16t)
validate_core_unlock() {
    local core_count thread_count
    core_count=$(nproc 2>/dev/null || echo "0")
    thread_count=$(nproc --all 2>/dev/null || echo "0")

    # If we have more than 12 threads, assume core unlock worked (6c/12t stock -> 8c/16t unlocked)
    # This is a heuristic - actual threshold may vary but 12 is a safe minimum for unlocked state
    if (( thread_count > 12 )); then
        print_info "CPU core unlock validated: ${thread_count} threads detected (expected >12 for 8c/16t)"
        return 0
    else
        print_warning "CPU core unlock validation: only ${thread_count} threads detected (expected >12 for 8c/16t)"
        print_warning "This may indicate the core unlock did not take effect or requires a cold reboot"
        return 1  # Warning only, don't fail the entire process
    fi
}

run_sensors_menu() {
    while true; do
        print_banner
        print_section "Sensors & Fan Control"
        echo -e "  ${DIM}Nuvoton NCT6686D SuperIO — active driver: $(sensors_active_driver)${RESET}"
        echo ""
        print_item "1" "Read-Only Sensors (nct6683)"    "Monitoring only — temps, voltages, fan RPM"
        print_item "2" "Full PWM Fan Control (nct6687)" "Recommended — builds module, adds writable PWM control"
        print_item "3" "Revert / Remove Sensor Driver"  "Unload driver and remove autoload config"
        print_item "0" "Back" ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" sens_choice

        case "$sens_choice" in
            1) install_sensors_readonly; press_enter ;;
            2) install_sensors_pwm;      press_enter ;;
            3) run_revert_sensors;       press_enter ;;
            0) return 0 ;;
            *)
                print_error "Invalid selection: '$sens_choice'"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# COOLERCONTROL
# ==============================================================================

coolercontrol_installed() {
    pacman -Qq coolercontrold-bin &>/dev/null || pacman -Qq coolercontrold &>/dev/null || \
        systemctl list-unit-files coolercontrold.service &>/dev/null
}

coolercontrol_gui_installed() {
    pacman -Qq coolercontrol-bin &>/dev/null || pacman -Qq coolercontrol &>/dev/null
}

install_coolercontrol() {
    print_step "CC" "Installing CoolerControl (fan & sensor control daemon)"

    if coolercontrol_installed; then
        if ! confirm "CoolerControl daemon is already installed. Reinstall it?"; then
            print_info "Keeping existing installation — ensuring service is enabled..."
            systemctl enable --now coolercontrold.service || {
                fail_with_log "Failed to enable coolercontrold service." "CoolerControl Setup — enable service"
                return 1
            }
            print_success "CoolerControl service is enabled and running!"
            print_info "Web UI: ${CYAN}https://localhost:11987${RESET}"
            return 0
        fi
        systemctl stop coolercontrold.service 2>/dev/null || true
        systemctl disable coolercontrold.service 2>/dev/null || true
    fi

    print_info "Installing coolercontrold-bin via AUR helper..."
    steamos_writable 'aur_install coolercontrold-bin' || {
        fail_with_log "Failed to install coolercontrold-bin." "CoolerControl Install — aur_install"
        return 1
    }

    if confirm "Also install the desktop GUI (coolercontrol-bin)? This pulls in Qt6 WebEngine (larger download)."; then
        print_info "Installing coolercontrol-bin (GUI) via AUR helper..."
        steamos_writable 'aur_install coolercontrol-bin' || {
            fail_with_log "Failed to install coolercontrol-bin (GUI)." "CoolerControl Install — aur_install GUI"
            return 1
        }
    fi

    print_info "Enabling and starting coolercontrold service..."
    systemctl enable --now coolercontrold.service || {
        fail_with_log "Failed to enable coolercontrold service." "CoolerControl Install — enable service"
        return 1
    }

    print_success "CoolerControl installed and running!"
    persist_state_add "coolercontrol"
    if [[ "$AUTO" != "1" ]]; then
        persist_snapshot_configs "coolercontrol" /etc/coolercontrol /etc/coolercontrold
    fi
    print_info "Web UI: ${CYAN}https://localhost:11987${RESET}"
    if coolercontrol_gui_installed; then
        print_info "Desktop GUI installed — launch 'CoolerControl' from your app menu."
    fi
    print_info "${YELLOW}Tip:${RESET} install the NCT6687 PWM driver (menu ${CYAN}F${RESET}) first for full fan-curve control."
}

run_revert_coolercontrol() {
    print_step "R-CC" "Revert CoolerControl"

    if ! coolercontrol_installed && ! coolercontrol_gui_installed; then
        print_info "CoolerControl does not appear to be installed — nothing to revert."
        return 0
    fi

    if ! confirm "This will stop, disable, and remove CoolerControl. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    systemctl stop coolercontrold.service 2>/dev/null || true
    systemctl disable coolercontrold.service 2>/dev/null || true
    steamos_writable 'aur_remove coolercontrol-bin' || true
    steamos_writable 'aur_remove coolercontrol' || true
    steamos_writable 'aur_remove coolercontrold-bin' || true
    steamos_writable 'aur_remove coolercontrold' || true

    print_success "CoolerControl removed successfully."
    persist_state_remove "coolercontrol"
}

coolercontrol_status_label() {
    if systemctl is-active coolercontrold.service &>/dev/null; then
        echo "running"
    elif coolercontrol_installed; then
        echo "installed (not running)"
    else
        echo "not installed"
    fi
}

run_coolercontrol_menu() {
    while true; do
        print_banner
        print_section "CoolerControl"
        echo -e "  ${DIM}Fan curves & sensor dashboard — status: $(coolercontrol_status_label)${RESET}"
        echo ""
        print_item "1" "Install CoolerControl"   "Install coolercontrold (+ optional GUI) and enable service"
        print_item "2" "Revert CoolerControl"    "Stop, disable, and remove CoolerControl"
        print_item "0" "Back" ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" cc_choice

        case "$cc_choice" in
            1) install_coolercontrol;      press_enter ;;
            2) run_revert_coolercontrol;   press_enter ;;
            0) return 0 ;;
            *)
                print_error "Invalid selection: '$cc_choice'"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# XBOX WIRELESS ADAPTER (xone driver)
# ==============================================================================

XONE_MODPROBE_CONF="/etc/modprobe.d/xone-blacklist.conf"

xone_installed() {
    pacman -Qq xone-dkms &>/dev/null
}

install_xbox_adapter() {
    print_step "XBOX" "Installing Xbox Wireless Adapter driver (xone)"

    require_kernel_version || return 1

    if xone_installed; then
        if ! confirm "xone-dkms is already installed. Reinstall it?"; then
            print_info "Keeping existing installation."
            return 0
        fi
    fi

    print_info "Installing dkms (required to build xone against your kernel)..."
    steamos_writable 'pacman -Syu --noconfirm dkms' || {
        fail_with_log "Failed to install dkms." "Xbox Adapter Install — dkms"
        return 1
    }

    ensure_build_deps || return 1

    local headers_pkg
    if ! headers_pkg="$(detect_kernel_headers_package)"; then
        fail_with_log "Could not determine the running kernel package for header lookup." "Xbox Adapter Install — kernel detection"
        return 1
    fi
    print_info "Detected kernel headers package: $headers_pkg"
    if ! pacman -Qq "$headers_pkg" &>/dev/null; then
        steamos_writable "pacman -Syu --noconfirm '$headers_pkg'" || {
            fail_with_log "Failed to install kernel headers ($headers_pkg). A matching headers package may not exist yet for this kernel." "Xbox Adapter Install — headers"
            return 1
        }
    else
        print_info "Kernel headers already installed."
    fi
    if [[ ! -d "/usr/lib/modules/$(uname -r)/build" ]]; then
        fail_with_log "Kernel build directory not found after installing headers." "Xbox Adapter Install — build dir missing"
        return 1
    fi

    print_info "Installing xone-dkms via AUR helper..."
    steamos_writable 'aur_install xone-dkms' || {
        fail_with_log "Failed to install xone-dkms." "Xbox Adapter Install — xone-dkms"
        return 1
    }

    print_info "Installing xone-dongle-firmware via AUR helper..."
    steamos_writable 'aur_install xone-dongle-firmware' || {
        fail_with_log "Failed to install xone-dongle-firmware." "Xbox Adapter Install — xone-dongle-firmware"
        return 1
    }

    print_info "Blacklisting conflicting drivers (xpad, mt76x2u)..."
    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        steamos-readonly disable || true
    fi
    {
        echo "blacklist xpad"
        echo "blacklist mt76x2u"
    } > "$XONE_MODPROBE_CONF"
    if (( was_steamos )); then
        steamos-readonly enable || true
    fi

    print_info "Unloading conflicting drivers (if loaded) and loading xone..."
    modprobe -r mt76x2u 2>/dev/null || true
    modprobe -r xpad 2>/dev/null || true
    modprobe xone 2>/dev/null || true

    print_success "Xbox Wireless Adapter driver installed!"
    persist_state_add "xbox"
    print_info "Unplug and replug the adapter if the controller doesn't pair right away."
}

run_revert_xbox_adapter() {
    print_step "R-XBOX" "Revert Xbox Wireless Adapter driver"

    if ! xone_installed; then
        print_info "xone-dkms does not appear to be installed — nothing to revert."
        return 0
    fi

    if ! confirm "This will remove xone-dkms, xone-dongle-firmware, and the driver blacklist. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    modprobe -r xone 2>/dev/null || true
    steamos_writable 'aur_remove xone-dongle-firmware' || true
    steamos_writable 'aur_remove xone-dkms' || true

    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        steamos-readonly disable || true
    fi
    rm -f "$XONE_MODPROBE_CONF"
    if (( was_steamos )); then
        steamos-readonly enable || true
    fi

    print_success "Xbox Wireless Adapter driver removed."
    persist_state_remove "xbox"
}

xbox_adapter_status_label() {
    if lsmod | grep -q '^xone'; then
        echo "loaded"
    elif xone_installed; then
        echo "installed (not loaded)"
    else
        echo "not installed"
    fi
}

run_ds5_bridge_menu() {
    while true; do
        print_banner
        print_section "DS5 Bridge PS Button Fix"
        echo -e "  ${DIM}Patched hid-playstation.ko + Steam chord config for DualSense PS button${RESET}"
        echo ""
        print_item "1" "Install DS5 Bridge Fix"      "⚠  Patched hid-playstation.ko — exposes BTN_MODE for chord combos"
        print_item "2" "Revert DS5 Bridge Fix"       "Restore stock hid-playstation.ko"
        print_item "3" "Install DS5 Chord Config"    "Patch Steam VDF — PS+Cross=QAM, PS+Triangle=Steam overlay"
        print_item "4" "Revert DS5 Chord Config"     "Restore original Steam PS5 chord config"
        print_item "0" "Back" ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" ds5_choice

        case "$ds5_choice" in
            1) install_ds5_bridge_fix;      press_enter ;;
            2) run_revert_ds5_bridge_fix;   press_enter ;;
            3) run_install_ds5_chord_vdf;   press_enter ;;
            4) run_revert_ds5_chord_vdf;    press_enter ;;
            0) return 0 ;;
            *)
                print_error "Invalid selection: '$ds5_choice'"
                sleep 1
                ;;
        esac
    done
}

run_xbox_adapter_menu() {
    while true; do
        print_banner
        print_section "Xbox Wireless Adapter"
        echo -e "  ${DIM}xone driver for Xbox One / Series X|S wireless adapter — status: $(xbox_adapter_status_label)${RESET}"
        echo ""
        print_item "1" "Install Xbox Adapter Driver"  "Install dkms + xone-dkms + firmware, blacklist xpad/mt76x2u"
        print_item "2" "Revert Xbox Adapter Driver"    "Remove xone driver and undo blacklist"
        print_item "0" "Back" ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" xbox_choice

        case "$xbox_choice" in
            1) install_xbox_adapter;      press_enter ;;
            2) run_revert_xbox_adapter;   press_enter ;;
            0) return 0 ;;
            *)
                print_error "Invalid selection: '$xbox_choice'"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# COMMUNITY FIXES (keyboardspecialist/bc250-steamos)
# ==============================================================================

FIXES_REPO_URL="https://github.com/keyboardspecialist/bc250-steamos.git"
# Keep external scripts/repos under the toolkit tree so they are cached locally
# and executed without repeated runtime downloads.
FIXES_REPO_DIR="$EXTERNAL_DIR/bc250-steamos"

fixes_repo_sync() {
    if [[ ! -d "$FIXES_REPO_DIR" ]]; then
        fail_with_log "Vendored community fixes repo not found at $FIXES_REPO_DIR." "Community Fixes — missing vendored repo"
        return 1
    fi
    print_info "Using vendored community fixes repo..."
    chown -R "$REAL_USER":"$REAL_USER" "$FIXES_REPO_DIR" 2>/dev/null || true
}

# --- ACPI fix: CPU C-states/P-states (idle + cpufreq scaling) --------------
ACPI_FIX_DIR="/var/lib/bc250-acpi-fix"
ACPI_FIX_CPIO_MASTER="$ACPI_FIX_DIR/acpi_override.cpio"
ACPI_FIX_CPIO_BOOT="/boot/acpi_override.cpio"
# mendesrr's updated SSDT tables work with both 6c/12t (stock) and 8c/16t
# (CPU Core Unlock) BC-250 configurations, unlike the original
# bc250-collective tables which only cover 6c/12t. Same filenames, drop-in
# replacement — no other code here needed to change.
ACPI_FIX_RAW_BASE="https://raw.githubusercontent.com/mendesrr/bc250-acpi-fix-updated-8c/main"
ACPI_FIX_SOURCE_MARKER="$ACPI_FIX_DIR/.source"
ACPI_FIX_HEAL_UNIT="/etc/systemd/system/bc250-acpi-heal.service"
ACPI_FIX_CPUFREQ_UNIT="/etc/systemd/system/bc250-cpufreq.service"

acpi_fix_installed() {
    [[ -f "$ACPI_FIX_CPIO_BOOT" ]] || systemctl list-unit-files bc250-acpi-heal.service &>/dev/null
}

acpi_fix_source_current() {
    [[ -f "$ACPI_FIX_SOURCE_MARKER" ]] && [[ "$(cat "$ACPI_FIX_SOURCE_MARKER" 2>/dev/null)" == "$ACPI_FIX_RAW_BASE" ]]
}

install_acpi_fix() {
    local force="${1:-}"
    print_step "ACPI" "Installing ACPI Fix (CPU C-states/P-states, 6c/8c-compatible SSDT tables)"

    if acpi_fix_installed && acpi_fix_source_current; then
        if [[ "$force" == "force" ]]; then
            print_info "ACPI fix already installed and up to date (6c/8c-compatible SSDT tables)."
            return 0
        fi
        if ! confirm "ACPI fix is already installed and up to date. Reinstall it?"; then
            print_info "Keeping existing installation."
            return 0
        fi
    elif acpi_fix_installed; then
        print_info "Updating ACPI override to the 6c/8c-compatible SSDT tables (mendesrr/bc250-acpi-fix-updated-8c)..."
        rm -f "$ACPI_FIX_CPIO_MASTER"
    fi

    mkdir -p "$ACPI_FIX_DIR"
    if [[ ! -f "$ACPI_FIX_CPIO_MASTER" ]]; then
        local work
        work="$(mktemp -d /tmp/bc250-acpi-XXXXXX)"
        mkdir -p "$work/kernel/firmware/acpi"

        print_info "Fetching SSDT tables (mendesrr/bc250-acpi-fix-updated-8c)..."
        if ! run_with_retry "curl -fL -o \"$work/kernel/firmware/acpi/SSDT-CST.aml\" \"$ACPI_FIX_RAW_BASE/SSDT-CST.aml\"" "ACPI Fix SSDT-CST download" || \
           ! run_with_retry "curl -fL -o \"$work/kernel/firmware/acpi/SSDT-PST.aml\" \"$ACPI_FIX_RAW_BASE/SSDT-PST.aml\"" "ACPI Fix SSDT-PST download"; then
            fail_with_log "Failed to download SSDT tables." "ACPI Fix — download"
            rm -rf "$work"
            return 1
        fi
        cp "$work"/kernel/firmware/acpi/*.aml "$ACPI_FIX_DIR/"

        if ! command -v cpio >/dev/null 2>&1; then
            steamos_writable 'pacman -Sy --noconfirm cpio' || {
                fail_with_log "Failed to install cpio." "ACPI Fix — cpio package"
                rm -rf "$work"
                return 1
            }
        fi

        print_info "Building early-initrd ACPI override cpio..."
        if ! (cd "$work" && find kernel | cpio -o -H newc > "$ACPI_FIX_CPIO_MASTER"); then
            fail_with_log "Failed to build the ACPI override cpio." "ACPI Fix — cpio build"
            rm -rf "$work"
            return 1
        fi
        rm -rf "$work"
        echo "$ACPI_FIX_RAW_BASE" > "$ACPI_FIX_SOURCE_MARKER"
    fi

    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        print_info "SteamOS detected: disabling read-only mode..."
        if ! steamos-readonly disable; then
            fail_with_log "Failed to disable SteamOS read-only mode." "ACPI Fix — readonly disable"
            return 1
        fi
    fi

    cp -f "$ACPI_FIX_CPIO_MASTER" "$ACPI_FIX_CPIO_BOOT"

    if grep -q '^GRUB_EARLY_INITRD_LINUX_CUSTOM=' "$GRUB_DEFAULT" 2>/dev/null; then
        sed -i 's|^GRUB_EARLY_INITRD_LINUX_CUSTOM=.*|GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"|' "$GRUB_DEFAULT"
    else
        echo 'GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"' >> "$GRUB_DEFAULT"
    fi

    print_info "Regenerating GRUB config..."
    local grub_rc=0
    if command -v update-grub >/dev/null 2>&1; then
        update-grub || grub_rc=1
    else
        grub-mkconfig -o /boot/grub/grub.cfg || grub_rc=1
    fi
    if [[ $grub_rc -ne 0 ]]; then
        fail_with_log "Failed to regenerate GRUB config." "ACPI Fix — grub-mkconfig"
        (( was_steamos )) && { steamos-readonly enable || true; }
        return 1
    fi

    cat > "$ACPI_FIX_HEAL_UNIT" <<EOF
[Unit]
Description=BC-250 ACPI override self-heal (restore after SteamOS updates)
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\\
  if [[ ! -f $ACPI_FIX_CPIO_BOOT ]] || ! cmp -s "$ACPI_FIX_CPIO_MASTER" "$ACPI_FIX_CPIO_BOOT"; then \\
    steamos-readonly disable; \\
    cp -f "$ACPI_FIX_CPIO_MASTER" "$ACPI_FIX_CPIO_BOOT"; \\
    command -v update-grub >/dev/null && update-grub || grub-mkconfig -o /boot/grub/grub.cfg; \\
    steamos-readonly enable; \\
    echo "bc250: ACPI override restored after OS update; REBOOT to re-activate C/P-states" | systemd-cat -p warning; \\
  fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    cat > "$ACPI_FIX_CPUFREQ_UNIT" <<'EOF'
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

    if (( was_steamos )); then
        print_info "Re-enabling SteamOS read-only mode..."
        steamos-readonly enable || true
    fi

    print_success "ACPI fix installed! Reboot required to activate CPU C-states/P-states."
    persist_state_add "acpi"
    print_info "After reboot verify: ${CYAN}ls /sys/devices/system/cpu/cpu0/cpuidle/${RESET} and ${CYAN}cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies${RESET}"
}

run_revert_acpi_fix() {
    print_step "R-ACPI" "Revert ACPI Fix"

    if ! acpi_fix_installed; then
        print_info "ACPI fix does not appear to be installed — nothing to revert."
        return 0
    fi

    if ! confirm "This will remove the ACPI override and self-heal services. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    systemctl disable --now bc250-acpi-heal.service bc250-cpufreq.service 2>/dev/null || true

    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        steamos-readonly disable || true
    fi

    rm -f "$ACPI_FIX_CPIO_BOOT" "$ACPI_FIX_HEAL_UNIT" "$ACPI_FIX_CPUFREQ_UNIT"
    sed -i '/^GRUB_EARLY_INITRD_LINUX_CUSTOM=/d' "$GRUB_DEFAULT" 2>/dev/null || true
    if command -v update-grub >/dev/null 2>&1; then update-grub || true; else grub-mkconfig -o /boot/grub/grub.cfg || true; fi
    systemctl daemon-reload

    if (( was_steamos )); then
        steamos-readonly enable || true
    fi

    print_success "ACPI fix removed. Reboot to fully revert to stock C/P-state behavior."
    persist_state_remove "acpi"
}

# --- shared kernel-headers-package helpers ----------------------------------
# Several upstream community-fix scripts each derive "the headers package that
# matches the running kernel" and download it from Valve's package mirror, but
# get one or both of the following wrong for non-standard kernel flavors (e.g.
# the "-drm-exec" experimental variant):
#   1. repo channel: hardcode "jupiter-main", which 404s on a system pinned to
#      a versioned branch (e.g. jupiter-3.8) even though the exact package is
#      one repo channel away.
#   2. pkgver derivation: a naive single-hyphen-to-dot substitution mishandles
#      flavors whose own version string contains more than one hyphen (e.g.
#      "drmexec7-valve24.3" needs to become "drmexec7.valve24.3", not just the
#      first hyphen converted).
# These helpers compute the correct package name once and fetch it from
# whatever repo channel actually has it, for reuse by every fix that needs it.

# Echoes the exact headers package filename for the running kernel, or returns
# 1 if $REL doesn't look like a SteamOS neptune kernel release.
bc250_headers_pkg_name() {
    local rel="${1:-$(uname -r)}" sha rest flavor mid pkgrel kver pkgver
    case "$rel" in
        *-neptune-*-g*) ;;
        *) return 1 ;;
    esac
    sha="${rel##*-g}"
    rest="${rel%-g"$sha"}"
    flavor="${rest##*-neptune-}"
    mid="${rest%-neptune-"$flavor"}"
    pkgrel="${mid##*-}"
    kver="${mid%-"$pkgrel"}"
    pkgver="${kver//-/.}"
    echo "linux-neptune-$flavor-headers-$pkgver-$pkgrel-x86_64.pkg.tar.zst"
}

# Downloads $1 (a headers package filename) to $2 (destination path), trying
# this system's actual configured repo channels (from /etc/pacman.conf) before
# falling back to the channels upstream scripts hardcode. Returns 1 if no
# candidate channel has it.
bc250_fetch_headers_pkg() {
    local hdrpkg="$1" dest="$2"
    local mirror="https://steamdeck-packages.steamos.cloud/archlinux-mirror"
    local -a candidates=()
    while IFS= read -r repo; do
        [[ "$repo" == jupiter-* ]] && candidates+=("$repo")
    done < <(sed -n 's/^\[\(.*\)\]$/\1/p' /etc/pacman.conf 2>/dev/null)
    candidates+=(jupiter-main jupiter-beta jupiter-beta-staging)

    local repo
    for repo in "${candidates[@]}"; do
        if curl -fsSL -o "$dest" "$mirror/$repo/os/x86_64/$hdrpkg" 2>/dev/null; then
            print_info "Headers package staged from repo '$repo' -> $hdrpkg"
            return 0
        fi
        rm -f "$dest"
    done
    return 1
}

# --- DisplayPort audio/video clock fix (patched amdgpu.ko) ------------------
# Upstream's own fetch-sources.sh now probes every jupiter-* repo channel
# itself (via its vendored fetch-steamos-package.sh), so this is just a
# redundant-but-harmless pre-stage using this toolkit's shared helpers above:
# if the package is already cached locally, fetch-sources.sh's own idempotent
# check skips re-downloading it.
audio_fix_prefetch_headers() {
    local fix_dir="$1" hdrpkg
    hdrpkg=$(bc250_headers_pkg_name) || return 0
    [[ -f "$fix_dir/$hdrpkg" ]] && return 0
    bc250_fetch_headers_pkg "$hdrpkg" "$fix_dir/$hdrpkg" \
        || print_info "Could not pre-stage the headers package from any known repo channel; letting fetch-sources.sh try (and report) on its own."
}

audio_fix_resolve_fullsha() {
    local rel="${1:-$(uname -r)}" short fullsha
    short="${rel##*-g}"
    [[ "$short" =~ ^[0-9a-fA-F]{7,40}$ ]] || return 1
    fullsha=$(timeout 15 git ls-remote https://github.com/Evlav/linux-integration.git 2>/dev/null \
        | awk -v prefix="$short" '$1 ~ "^" prefix { print $1; exit }')
    [[ "$fullsha" =~ ^[0-9a-fA-F]{40}$ ]] || return 1
    printf '%s\n' "$fullsha"
}

# install.sh/rollback.sh (upstream) hardcode "mkinitcpio -p linux-neptune-616",
# which fails on non-standard kernel flavors whose preset has a suffix (e.g.
# the "-drm-exec" experimental variant: linux-neptune-616-drm-exec.preset).
# The module itself installs fine either way; only the initramfs rebuild at
# the very end needs the right preset name. Symlink the expected name to
# whatever preset actually exists so their hardcoded call works unmodified.
audio_fix_patch_fetch_sources() {
    local fetch_script="$1"
    [[ -f "$fetch_script" ]] || return 1

    # Older upstream revisions had a dependency scan using tar | sed | awk that
    # exited from awk after the first exact match. With pipefail, that made
    # tar receive SIGPIPE and aborted fetch-sources.sh before any dependency
    # was extracted. Upstream has since fixed this directly (no more "exit"
    # in the awk match), so the pattern below is normally absent — patch it
    # only if a stale/older fetch-sources.sh still has it.
    if grep -q 'if (n==p) { print; exit }' "$fetch_script"; then
        print_info "Patching dependency scan to avoid tar SIGPIPE under pipefail."
        sed -i 's/if (n==p) { print; exit }/if (n==p) { print }/' "$fetch_script"
    fi
    return 0
}

audio_fix_ensure_mkinitcpio_preset() {
    local expected="/etc/mkinitcpio.d/linux-neptune-616.preset"
    [[ -e "$expected" ]] && return 0

    local actual
    actual=$(compgen -G "/etc/mkinitcpio.d/linux-neptune-6*.preset" | head -1)
    [[ -n "$actual" ]] || return 0

    print_info "mkinitcpio preset '$expected' missing; linking to '$(basename "$actual")' (non-standard kernel flavor)."
    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        steamos-readonly disable || { print_info "Could not disable read-only mode; skipping preset symlink."; return 1; }
    fi
    ln -sf "$(basename "$actual")" "$expected"
    if (( was_steamos )); then
        steamos-readonly enable || true
    fi
}

audio_fix_pcon_grub_installed() {
    [[ -f "$GRUB_DEFAULT" ]] && grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=.*amdgpu\.freesync_pcon_allow_all=1' "$GRUB_DEFAULT" >/dev/null 2>&1
}

audio_fix_ensure_pcon_grub_param() {
    if audio_fix_pcon_grub_installed; then
        return 0
    fi
    if [[ ! -f "$GRUB_DEFAULT" ]] || ! command -v update-grub >/dev/null 2>&1; then
        print_info "Could not add amdgpu.freesync_pcon_allow_all=1 to GRUB (missing $GRUB_DEFAULT or update-grub)."
        print_info "Add it manually for VRR over PCON: edit $GRUB_DEFAULT and run sudo update-grub."
        return 0
    fi
    steamos_writable "
        cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
        if ! grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=' \"$GRUB_DEFAULT\" | grep -q 'amdgpu.freesync_pcon_allow_all=1'; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\([^\"]*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 amdgpu.freesync_pcon_allow_all=1\"/' \"$GRUB_DEFAULT\"
        fi
        update-grub
    " || {
        print_info "Failed to add amdgpu.freesync_pcon_allow_all=1 to GRUB. Add it manually for VRR over PCON."
        return 0
    }
    print_info "Added amdgpu.freesync_pcon_allow_all=1 to GRUB for VRR over PCON."
}

audio_fix_remove_pcon_grub_param() {
    if ! audio_fix_pcon_grub_installed; then
        return 0
    fi
    if [[ ! -f "$GRUB_DEFAULT" ]] || ! command -v update-grub >/dev/null 2>&1; then
        return 0
    fi
    steamos_writable "
        cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
        sed -i 's/ amdgpu\\.freesync_pcon_allow_all=1//g; s/amdgpu\\.freesync_pcon_allow_all=1 //g; s/amdgpu\\.freesync_pcon_allow_all=1//g' \"$GRUB_DEFAULT\"
        update-grub
    " || {
        print_info "Failed to remove amdgpu.freesync_pcon_allow_all=1 from GRUB."
        return 0
    }
    print_info "Removed amdgpu.freesync_pcon_allow_all=1 from GRUB."
}

audio_fix_cleanup_legacy_edid() {
    local changed=0

    # Remove all legacy EDID firmware binaries (any .bin in /lib/firmware/edid)
    local edid_dir="/lib/firmware/edid"
    if [[ -d "$edid_dir" ]]; then
        local legacy_bins=()
        while IFS= read -r f; do
            legacy_bins+=("$f")
        done < <(find "$edid_dir" -maxdepth 1 -name '*.bin' -type f 2>/dev/null)

        if (( ${#legacy_bins[@]} > 0 )); then
            print_info "Removing legacy EDID firmware: ${legacy_bins[*]}"
            steamos_writable "rm -f ${legacy_bins[*]}" || true
            changed=1
        fi

        # Remove empty edid dir if nothing left
        if [[ -z "$(ls -A "$edid_dir" 2>/dev/null)" ]]; then
            steamos_writable "rmdir '$edid_dir' 2>/dev/null" || true
        fi
    fi

    # Remove any drm.edid_firmware=... from GRUB cmdline (any connector, any path)
    if [[ -f "$GRUB_DEFAULT" ]] && grep -q 'drm\.edid_firmware' "$GRUB_DEFAULT" 2>/dev/null; then
        print_info "Removing drm.edid_firmware from GRUB cmdline (using native EDID now)."
        steamos_writable "
            cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
            sed -i 's/ drm\\.edid_firmware=[^ \"\\t]*//g; s/drm\\.edid_firmware=[^ \"\\t]* //g; s/drm\\.edid_firmware=[^ \"\\t]*//g' \"$GRUB_DEFAULT\"
            update-grub
        " || {
            print_info "Failed to remove drm.edid_firmware from GRUB. Remove it manually."
        }
        changed=1
    fi

    # Remove edid_firmware hook from mkinitcpio config and drop-in configs
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    local mkinitcpio_conf_dir="/etc/mkinitcpio.conf.d"
    local mkinitcpio_files=("$mkinitcpio_conf")
    [[ -d "$mkinitcpio_conf_dir" ]] && while IFS= read -r f; do
        mkinitcpio_files+=("$f")
    done < <(find "$mkinitcpio_conf_dir" -name '*.conf' -type f 2>/dev/null)

    for mc in "${mkinitcpio_files[@]}"; do
        if [[ -f "$mc" ]] && grep -q 'edid_firmware' "$mc" 2>/dev/null; then
            print_info "Removing edid_firmware hook from $mc."
            steamos_writable "
                cp \"$mc\" \"$mc.bak\"
                sed -i 's/ edid_firmware//g; s/edid_firmware //g; s/edid_firmware//g' \"$mc\"
            " || {
                print_info "Failed to remove edid_firmware hook from $mc. Remove it manually."
            }
            changed=1
        fi
    done

    # Remove edid_firmware hook install script and hook itself
    local hook_files=(/etc/initcpio/install/edid_firmware /etc/initcpio/hooks/edid_firmware)
    local existing_hooks=()
    for hf in "${hook_files[@]}"; do
        [[ -f "$hf" ]] && existing_hooks+=("$hf")
    done
    if (( ${#existing_hooks[@]} > 0 )); then
        print_info "Removing edid_firmware mkinitcpio hook files: ${existing_hooks[*]}"
        steamos_writable "rm -f ${existing_hooks[*]}" || true
        changed=1
    fi

    if (( changed )); then
        print_info "Legacy EDID cleanup complete. Native display EDID will be used after reboot."
    fi
}

install_audio_fix() {
    print_step "AUDIO" "Installing DisplayPort Audio/Video Clock + GPU Metrics Fix"

    require_kernel_version || return 1

    audio_fix_cleanup_legacy_edid

    echo -e "  ${YELLOW}⚠  This rebuilds and replaces amdgpu.ko with a kernel-specific patched module.${RESET}"
    echo -e "  ${YELLOW}⚠  A bad build can leave the machine with no display at boot.${RESET}"
    echo -e "  ${DIM}Fixes DisplayPort video/audio played back at ~82% speed (pitched down).${RESET}"
    echo -e "  ${DIM}Also queries GFX clock directly from the SMU and adds GPU utilization reporting${RESET}"
    echo -e "  ${DIM}(needed for correct GPU clock/load readings once CPU Core Unlock is active).${RESET}"
    echo -e "  ${DIM}Disables DP spread spectrum at the display manager layer for cleaner audio output.${RESET}"
    echo -e "  ${DIM}Adds tunable gfxclk/activity cache (cs_gfxclk_cache_ms, cs_activity_cache_ms module params).${RESET}"
    echo -e "  ${DIM}VRR over HDMI via PCON: FreeSync fallback + LFC-aware range extending${RESET}"
    echo -e "  ${DIM}ALLM (Auto Low Latency Mode) via DP for PCON HDMI Game Mode${RESET}"
    echo ""
    if ! confirm "Continue with the DisplayPort audio/video fix?"; then
        print_info "Cancelled."
        return 0
    fi

    fixes_repo_sync || return 1

    local fix_dir="$FIXES_REPO_DIR/bc250-audio-fix"
    if [[ ! -d "$fix_dir" ]]; then
        fail_with_log "bc250-audio-fix directory not found in the fixes repository." "Audio Fix — missing directory"
        return 1
    fi

    print_info "Running patch-driver.sh (fetch-sources.sh && build.sh && install.sh)..."
    print_info "This clones the matching Valve kernel source tree and can take several minutes."
    audio_fix_prefetch_headers "$fix_dir"
    audio_fix_patch_fetch_sources "$fix_dir/fetch-sources.sh" || {
        fail_with_log "Could not prepare the DisplayPort fix dependency fetch script." "Audio Fix — fetch-sources compatibility patch"
        return 1
    }
    audio_fix_ensure_mkinitcpio_preset
    # patch-driver.sh refuses to run as root (it calls sudo itself for the
    # install step only) -- run it as the real user; you may be prompted for
    # your sudo password when it reaches install.sh.
    chown -R "$REAL_USER":"$REAL_USER" "$fix_dir"
    local fullsha patch_env=""
    fullsha=$(audio_fix_resolve_fullsha || true)
    if [[ -n "$fullsha" ]]; then
        print_info "Resolved kernel commit ${fullsha:0:12}; passing full SHA to patch-driver.sh."
        patch_env="export FULLSHA='$fullsha';"
    else
        print_info "Could not resolve the short kernel commit locally; patch-driver.sh will use its normal source lookup."
    fi
    if ! runuser -u "$REAL_USER" -- bash -c "cd '$fix_dir' && ${patch_env} ./patch-driver.sh"; then
        fail_with_log "DisplayPort audio/video fix build/install failed. The built-in vermagic/ABI guards refuse to install a mismatched module, so your display driver should be unchanged." "Audio Fix — patch-driver.sh"
        return 1
    fi

    print_success "DisplayPort audio/video fix installed! Reboot required."
    persist_state_add "audio"
    print_info "After reboot, verify DisplayPort video/audio play back at normal speed."
    print_info "${YELLOW}If anything misbehaves:${RESET} use the Revert option, then reboot."

    echo ""
    echo -e "  ${CYAN}The patched amdgpu.ko also includes VRR and ALLM support for DP→HDMI PCON adapters.${RESET}"
    echo -e "  ${DIM}VRR: FreeSync fallback + HDMI VRR (VTEM) with improved range extending (LFC-aware).${RESET}"
    echo -e "  ${DIM}ALLM: Auto Low Latency Mode via AVI content_type hint to PCON.${RESET}"
    echo -e "  ${DIM}Requires amdgpu.freesync_pcon_allow_all=1 in the kernel command line for PCON VRR bypass.${RESET}"
    echo ""
    if audio_fix_pcon_grub_installed; then
        print_info "amdgpu.freesync_pcon_allow_all=1 is already in GRUB — VRR/ALLM ready."
    elif confirm "Add amdgpu.freesync_pcon_allow_all=1 to GRUB for VRR over PCON?"; then
        audio_fix_ensure_pcon_grub_param
    else
        print_info "Skipped GRUB param. Add amdgpu.freesync_pcon_allow_all=1 manually for VRR over PCON."
    fi
}

run_revert_audio_fix() {
    print_step "R-AUDIO" "Revert DisplayPort Audio/Video Fix"

    local fix_dir="$FIXES_REPO_DIR/bc250-audio-fix"
    if [[ ! -d "$fix_dir" ]]; then
        print_info "Fixes repository not found locally — nothing to revert."
        return 0
    fi

    if ! confirm "This will restore the stock amdgpu.ko module. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    audio_fix_ensure_mkinitcpio_preset

    if ! (cd "$fix_dir" && ./rollback.sh); then
        fail_with_log "Failed to roll back the DisplayPort audio/video fix." "Audio Fix — rollback.sh"
        return 1
    fi

    print_success "DisplayPort audio/video fix reverted to stock amdgpu.ko. Reboot to apply."
    persist_state_remove "audio"

    if audio_fix_pcon_grub_installed; then
        echo ""
        if confirm "Also remove amdgpu.freesync_pcon_allow_all=1 from GRUB (was added for VRR over PCON)?"; then
            audio_fix_remove_pcon_grub_param
        else
            print_info "GRUB param kept. Remove manually if no longer needed."
        fi
    fi
}

# --- DS5 Bridge PS Button Fix (patched hid-playstation.ko) --------------------
# The DS5-Linux-Bridge (https://github.com/kungaa/DS5-Linux-Bridge/) presents
# the DualSense via USB with VID 054c/PID 0ce6 but does not implement feature
# report 0x09 (pairing info). The hid-playstation driver aborts probing on
# this failure, falling back to generic usbhid — which doesn't declare BTN_MODE
# in the evdev capabilities, preventing Steam/Gamescope chord combos like
# Guide+A (Quick Access Menu) from working. This patches hid-playstation to
# make the pairing info, firmware info, and calibration feature reports
# non-fatal, allowing the driver to bind and expose BTN_MODE correctly.
ds5_bridge_fix_installed() {
    local rel marker module
    rel=$(uname -r)
    marker="/usr/lib/modules/$rel/updates/.bc250-ds5-bridge-fix"
    module="/usr/lib/modules/$rel/updates/hid-playstation.ko.zst"
    [[ -f "$module" ]] && [[ -f "$marker" ]]
}

ds5_chord_vdf_path() {
    local steam_cfg="$REAL_HOME/.local/share/Steam/steamapps/common/Steam Controller Configs"
    local steam_id dir
    for dir in "$steam_cfg"/*/config/443510/controller_ps5.vdf; do
        [[ -f "$dir" ]] || continue
        steam_id="$(basename "$(dirname "$(dirname "$(dirname "$dir")")")")"
        echo "$steam_cfg/$steam_id/config/443510/controller_ps5.vdf"
        return 0
    done
    return 1
}

ds5_chord_vdf_patched() {
    local vdf
    vdf="$(ds5_chord_vdf_path 2>/dev/null)" || return 1
    [[ -f "$vdf" ]] && grep -q 'system_key_1' "$vdf" && grep -q 'button_a' "$vdf"
}

install_ds5_chord_vdf() {
    local fix_dir="$1"
    local template="$fix_dir/controller_ps5_chord.vdf"
    local vdf steam_id steam_cfg

    steam_cfg="$REAL_HOME/.local/share/Steam/steamapps/common/Steam Controller Configs"
    vdf="$(ds5_chord_vdf_path 2>/dev/null)"

    if [[ -z "$vdf" || ! -f "$vdf" ]]; then
        print_info "Steam PS5 chord config not found yet — will be applied on next Steam restart."
        # Install to a well-known location; Steam will pick it up when it creates the config
        local steam_id
        steam_id="$(ls "$steam_cfg" 2>/dev/null | head -1)"
        if [[ -n "$steam_id" ]]; then
            local dest_dir="$steam_cfg/$steam_id/config/443510"
            mkdir -p "$dest_dir"
            vdf="$dest_dir/controller_ps5.vdf"
        else
            print_info "Steam user config directory not found. Skipping VDF patch."
            return 0
        fi
    fi

    if [[ ! -f "$template" ]]; then
        print_info "VDF template not found in toolkit. Skipping VDF patch."
        return 0
    fi

    # Backup original if not already backed up
    if [[ -f "$vdf" && ! -f "${vdf}.bc250-bak" ]]; then
        cp "$vdf" "${vdf}.bc250-bak"
        chown "$REAL_USER":"$REAL_USER" "${vdf}.bc250-bak"
    fi

    # Get the Steam ID from the path to fix the url field
    local steam_id_from_path
    steam_id_from_path="$(basename "$(dirname "$(dirname "$(dirname "$vdf")")")")"

    # Copy template and fix the url path with the actual Steam ID
    sed "s|autosave:///home/deck/.local/share/Steam/steamapps/common/Steam Controller Configs/[0-9]*/config/443510/controller_ps5.vdf|autosave:///home/deck/.local/share/Steam/steamapps/common/Steam Controller Configs/$steam_id_from_path/config/443510/controller_ps5.vdf|" "$template" > "$vdf"
    chown "$REAL_USER":"$REAL_USER" "$vdf"

    print_info "PS5 chord config patched: button_a -> system_key_1 (QAM)"
    print_info "Restart Steam (or reboot) to apply the chord config."
}

revert_ds5_chord_vdf() {
    local vdf backup
    vdf="$(ds5_chord_vdf_path 2>/dev/null)" || return 0
    backup="${vdf}.bc250-bak"

    if [[ -f "$backup" ]]; then
        cp "$backup" "$vdf"
        chown "$REAL_USER":"$REAL_USER" "$vdf"
        rm -f "$backup"
        print_info "PS5 chord config restored to original."
    fi
}

run_install_ds5_chord_vdf() {
    print_step "DS5-CHORD-VDF" "Install DS5 Chord Config (Steam VDF patch)"

    echo -e "  ${DIM}Patches the Steam PS5 chord config to map PS+Cross -> QAM (system_key_1).${RESET}"
    echo -e "  ${DIM}Requires: DS5 Bridge PS Button fix already installed (for BTN_MODE events).${RESET}"
    echo ""

    fixes_repo_sync || return 1

    local fix_dir="$FIXES_REPO_DIR/ds5-bridge-fix"
    if [[ ! -f "$fix_dir/controller_ps5_chord.vdf" ]]; then
        fail_with_log "VDF template not found: $fix_dir/controller_ps5_chord.vdf" "DS5 Chord VDF — missing template"
        return 1
    fi

    if ds5_chord_vdf_patched 2>/dev/null; then
        print_info "PS5 chord config is already patched."
        return 0
    fi

    install_ds5_chord_vdf "$fix_dir"
    persist_state_add "ds5_chord_vdf"
    print_success "DS5 Chord Config installed! Restart Steam (or reboot) to apply."
}

run_revert_ds5_chord_vdf() {
    print_step "R-DS5-CHORD-VDF" "Revert DS5 Chord Config (Steam VDF patch)"

    if ! ds5_chord_vdf_patched 2>/dev/null; then
        print_info "PS5 chord config is not patched."
        return 0
    fi

    if ! confirm "Restore the original Steam PS5 chord config?"; then
        print_info "Cancelled."
        return 0
    fi

    revert_ds5_chord_vdf
    persist_state_remove "ds5_chord_vdf"
    print_success "DS5 Chord Config reverted. Restart Steam (or reboot) to apply."
}

install_ds5_bridge_fix() {
    print_step "DS5-BRIDGE" "Installing DS5 Bridge PS Button Fix (patched hid-playstation.ko)"

    echo -e "  ${YELLOW}⚠  This builds and installs a patched hid-playstation.ko kernel module.${RESET}"
    echo -e "  ${YELLOW}⚠  A bad build can prevent the DualSense driver from loading at boot.${RESET}"
    echo -e "  ${DIM}Fixes: DS5-Linux-Bridge PS button not working for chord combos (Guide+A for QAM).${RESET}"
    echo -e "  ${DIM}The hid-playstation driver currently fails to probe the bridge device because${RESET}"
    echo -e "  ${DIM}it doesn't implement feature report 0x09 (pairing info). This patch makes${RESET}"
    echo -e "  ${DIM}that and two other feature reports non-fatal, allowing the driver to bind${RESET}"
    echo -e "  ${DIM}and expose BTN_MODE correctly for Steam/Gamescope chord combos.${RESET}"
    echo ""
    if ! confirm "Continue with the DS5 Bridge PS Button fix?"; then
        print_info "Cancelled."
        return 0
    fi

    fixes_repo_sync || return 1

    local fix_dir="$FIXES_REPO_DIR/ds5-bridge-fix"
    if [[ ! -d "$fix_dir" ]]; then
        fail_with_log "ds5-bridge-fix directory not found in the fixes repository." "DS5 Bridge Fix — missing directory"
        return 1
    fi

    print_info "Running patch-driver.sh (fetch sources && build && install)..."
    print_info "This reuses the audio fix's kernel source tree and can take several minutes."
    chown -R "$REAL_USER":"$REAL_USER" "$fix_dir"
    if ! runuser -u "$REAL_USER" -- bash -c "cd '$fix_dir' && ./patch-driver.sh"; then
        fail_with_log "DS5 Bridge PS Button fix build/install failed." "DS5 Bridge Fix — patch-driver.sh"
        return 1
    fi

    print_success "DS5 Bridge PS Button fix installed! Reboot required."
    persist_state_add "ds5_bridge"

    print_info "After reboot, connect the DS5 Bridge and verify:"
    print_info "  ${CYAN}lsmod | grep hid_playstation${RESET}    (should show 1 user)"
    print_info "  ${CYAN}evtest /dev/input/eventN${RESET}        (BTN_MODE should be in capabilities)"
    print_info "${YELLOW}If anything misbehaves:${RESET} use the Revert option, then reboot."
}

run_revert_ds5_bridge_fix() {
    print_step "R-DS5-BRIDGE" "Revert DS5 Bridge PS Button Fix"

    local fix_dir="$FIXES_REPO_DIR/ds5-bridge-fix"
    if [[ ! -d "$fix_dir" ]]; then
        print_info "Fixes repository not found locally — nothing to revert."
        return 0
    fi

    if ! ds5_bridge_fix_installed; then
        print_info "DS5 Bridge fix is not installed."
        return 0
    fi

    if ! confirm "This will restore the stock hid-playstation.ko module. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    if ! (cd "$fix_dir" && ./patch-driver.sh uninstall); then
        fail_with_log "Failed to roll back the DS5 Bridge PS Button fix." "DS5 Bridge Fix — uninstall"
        return 1
    fi

    print_success "DS5 Bridge PS Button fix reverted to stock hid-playstation.ko. Reboot to apply."
    persist_state_remove "ds5_bridge"
}

# --- HDMI AC-3 Surround Encoding (Dolby Digital via eARC) --------------------
# The BC-250's DMI identifies as "AMD BC-250" instead of "OEM F7F", so
# SteamOS's valve-fremont hardware profile (which enables AC3 profiles) is
# never loaded. This installs a udev rule + WirePlumber config to enable the
# hdmi-ac3.conf profile set, giving a 5.1 sink that encodes to AC-3 via the
# a52 ALSA plugin. Zero latency, minimal CPU overhead (libavcodec a52enc).
# Requires: alsa-plugins (a52 plugin), ffmpeg (libavcodec for encoding).
AC3_UDEV_RULE="/etc/udev/rules.d/91-ac3-audio.rules"
AC3_WP_CONF_DIR="${REAL_HOME}/.config/wireplumber/wireplumber.conf.d"
AC3_WP_CONF="$AC3_WP_CONF_DIR/ac3-profile.conf"

ac3_surround_installed() {
    [[ -f "$AC3_UDEV_RULE" ]] && [[ -f "$AC3_WP_CONF" ]]
}

ac3_profile_active() {
    ac3_pactl list cards 2>/dev/null | grep "Active Profile" | grep -q "ac3"
}

ac3_pactl() {
    local uid
    uid=$(id -u "$REAL_USER")
    sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" pactl "$@"
}

AC3_USER_SCRIPT="$SCRIPT_DIR/extras/hdmi-ac3-encoding/ac3-user-setup.sh"

install_ac3_surround() {
    local auto="${1:-}"
    print_step "AC3" "Installing HDMI AC-3 Surround Encoding (Dolby Digital)"

    echo -e "  ${DIM}Enables AC-3 (Dolby Digital) encoding over HDMI/DP for 5.1 surround${RESET}"
    echo -e "  ${DIM}via eARC. Bypasses TV LPCM downmix — receiver gets true 5.1 DD.${RESET}"
    echo -e "  ${DIM}Zero latency, minimal CPU overhead (native a52 encoding).${RESET}"
    echo -e "  ${DIM}Requires: Combined Audio+GFX1013 Fix (option 10), alsa-plugins (a52), ffmpeg (libavcodec).${RESET}"
    echo ""

    # Check that the DP Audio/Video Fix is installed (this feature depends on it)
    print_info "Checking DP Audio/Video Fix (amdgpu patched module)..."
    local resolved_amdgpu
    resolved_amdgpu=$(modinfo -F filename amdgpu 2>/dev/null || echo "")
    if [[ "$resolved_amdgpu" != *"/updates/"* ]]; then
        print_error "The Combined Audio+GFX1013 Fix (option 10) is required for AC-3 Surround."
        print_info "The BC-250 has no native HDMI output — audio goes through DisplayPort,"
        print_info "and the Combined Fix patches the amdgpu driver to fix audio clock issues."
        print_info "Please install option 10 (Combined Audio+GFX1013) first, reboot, then try again."
        fail_with_log "DP Audio/Video Fix not installed — AC-3 Surround requires it" "AC-3 install — missing DP audio patch"
        return 1
    fi
    print_info "DP Audio/Video Fix detected: $resolved_amdgpu"

    # Check and install dependencies
    print_info "Checking dependencies (alsa-plugins, ffmpeg)..."
    local missing=()
    [[ -f /usr/lib/alsa-lib/libasound_module_pcm_a52.so ]] || missing+=("alsa-plugins")
    ldconfig -p 2>/dev/null | grep -q libavcodec || missing+=("ffmpeg")
    if (( ${#missing[@]} > 0 )); then
        print_info "Installing missing dependencies: ${missing[*]}"
        local was_steamos_deps=0
        if is_steamos; then
            was_steamos_deps=1
            steamos-readonly disable || { print_error "Could not disable read-only mode."; return 1; }
        fi
        if ! LC_ALL=C pacman -S --needed --noconfirm "${missing[@]}" 2>&1 | tail -5; then
            print_error "Failed to install dependencies: ${missing[*]}"
            (( was_steamos_deps )) && steamos-readonly enable || true
            return 1
        fi
        (( was_steamos_deps )) && steamos-readonly enable || true
    else
        print_info "All dependencies already installed."
    fi

    # Check that an HDMI/DP audio card exists
    print_info "Detecting HDMI/DP audio card..."
    local uid
    uid=$(id -u "$REAL_USER")
    local detect_output
    detect_output=$(sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" bash "$AC3_USER_SCRIPT" detect 2>/dev/null || true)
    local hdmi_card_name
    hdmi_card_name=$(echo "$detect_output" | grep "^CARD=" | cut -d= -f2)
    if [[ -z "$hdmi_card_name" ]]; then
        print_error "No HDMI/DP audio card found."
        print_info "The BC-250 outputs audio through DisplayPort. If you're using a"
        print_info "DP-to-HDMI adapter, make sure it's an active adapter and is connected."
        fail_with_log "No HDMI/DP audio card found" "AC-3 install — no audio card"
        return 1
    fi
    print_info "Found audio card: $hdmi_card_name"

    if [[ "$auto" != "auto" ]]; then
        if ! confirm "Continue with AC-3 Surround Encoding installation?"; then
            print_info "Cancelled."
            return 0
        fi
    fi

    # 1. Install udev rule to set ACP_PROFILE_SET for the HDMI audio card
    print_info "Installing udev rule for ACP_PROFILE_SET=hdmi-ac3.conf..."
    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        steamos-readonly disable || { print_error "Could not disable read-only mode."; return 1; }
    fi
    echo 'SUBSYSTEM=="sound", KERNEL=="card0", ENV{ACP_PROFILE_SET}="hdmi-ac3.conf"' > "$AC3_UDEV_RULE"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger /sys/class/sound/card0 2>/dev/null || true
    if (( was_steamos )); then
        steamos-readonly enable || true
    fi

    # 2-4. Run user-session setup (WirePlumber config, restart, profile selection)
    #    These must run as the real user to access PipeWire.
    print_info "Installing WirePlumber config and selecting AC-3 profile..."
    local user_output
    user_output=$(sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" bash "$AC3_USER_SCRIPT" install 2>&1 || true)
    echo "$user_output" | grep -v "^CARD=\|^SINK=\|^SUCCESS=\|^ERROR=\|^REVERTED=" || true

    local card_name ac3_sink
    card_name=$(echo "$user_output" | grep "^CARD=" | cut -d= -f2)
    ac3_sink=$(echo "$user_output" | grep "^SINK=" | cut -d= -f2)

    if echo "$user_output" | grep -q "^SUCCESS"; then
        print_success "AC-3 Surround Encoding installed! Profile: output:hdmi-ac3-surround"
        print_info "Default sink set to: $ac3_sink"
        print_info "Receiver should show Dolby Digital (DD/DD+) when audio plays."
        print_info "The sink stays active for 1 hour after last sound to prevent PCM fallback."
    else
        print_error "AC-3 installation failed."
        echo "$user_output" | grep "^ERROR:" | sed 's/^ERROR:/  Error:/' || true
        fail_with_log "AC-3 install failed" "${user_output}"
        return 1
    fi

    persist_state_add "ac3"

    # Post-install audio test
    ac3_post_install_test "$card_name" "$ac3_sink"
}

ac3_post_install_test() {
    local card_name="$1" ac3_sink="$2"

    echo ""
    if ! confirm "Would you like to run a quick audio test to verify Dolby Digital is working?"; then
        print_info "Skipping audio test. You can test later by playing any audio."
        print_info "Make sure your receiver is set to the HDMI input and shows Dolby Digital."
        return 0
    fi

    print_step "AC3-TEST" "Running 5.1 surround audio test..."
    print_info "You should hear a tone on each speaker (Left, Right, Center, LFE, Rear Left, Rear Right)."
    print_info "Your receiver should display Dolby Digital / DD during the test."
    echo ""

    # Run speaker-test as the real user (needs PipeWire access)
    local uid
    uid=$(id -u "$REAL_USER")
    local test_output
    test_output=$(sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" bash "$AC3_USER_SCRIPT" test "$ac3_sink" 2>&1 || true)
    echo "$test_output" | tail -5

    echo ""
    if confirm "Did you hear audio from the test?"; then
        print_success "AC-3 Surround Encoding is working correctly!"
        print_info "Your receiver should be showing Dolby Digital."
        return 0
    fi

    # Audio test failed — run auto-diagnosis
    print_error "No audio detected. Running auto-diagnosis..."
    ac3_auto_diagnose "$card_name" "$ac3_sink"
}

ac3_auto_diagnose() {
    local card_name="$1" ac3_sink="$2"
    local issues=()

    echo ""
    print_step "AC3-DIAG" "Auto-diagnosis"

    # Check 1: Is the sink still there?
    if ! ac3_pactl list sinks short 2>/dev/null | grep -q "$ac3_sink"; then
        issues+=("AC-3 sink '$ac3_sink' not found — it may have been removed after WirePlumber restart")
    fi

    # Check 2: Is the profile still active?
    local active_profile
    active_profile=$(ac3_pactl list cards 2>/dev/null | grep -A20 "Name: $card_name" | grep "Active Profile" | awk -F': ' '{print $2}')
    if [[ "$active_profile" != *"ac3"* ]]; then
        issues+=("Active profile is '$active_profile' (expected output:hdmi-ac3-surround)")
    fi

    # Check 3: Is the sink the default?
    local default_sink
    default_sink=$(ac3_pactl get-default-sink 2>/dev/null)
    if [[ "$default_sink" != *"$ac3_sink"* ]]; then
        issues+=("Default sink is '$default_sink' (expected $ac3_sink)")
    fi

    # Check 4: Is the ALSA device actually open?
    local alsa_status
    alsa_status=$(cat /proc/asound/card0/pcm3p/sub0/status 2>/dev/null | head -1 || echo "N/A")
    if [[ "$alsa_status" == "N/A" || "$alsa_status" == "" ]]; then
        issues+=("ALSA HDMI device /proc/asound/card0/pcm3p not accessible")
    fi

    # Check 5: Is the a52 plugin loaded?
    if ! [[ -f /usr/lib/alsa-lib/libasound_module_pcm_a52.so ]]; then
        issues+=("a52 ALSA plugin not found at /usr/lib/alsa-lib/libasound_module_pcm_a52.so")
    fi

    # Check 6: Is WirePlumber running?
    local uid
    uid=$(id -u "$REAL_USER")
    if ! sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user is-active wireplumber 2>/dev/null | grep -q "active"; then
        issues+=("WirePlumber service is not active")
    fi

    # Check 7: Is the udev rule in place?
    if ! [[ -f "$AC3_UDEV_RULE" ]]; then
        issues+=("Udev rule $AC3_UDEV_RULE not found")
    fi

    # Check 8: Is the WirePlumber config in place?
    if ! [[ -f "$AC3_WP_CONF" ]]; then
        issues+=("WirePlumber config $AC3_WP_CONF not found")
    fi

    # Check 9: Is the hdmi-ac3.conf profile set present?
    if ! [[ -f /usr/share/alsa-card-profile/mixer/profile-sets/hdmi-ac3.conf ]]; then
        issues+=("hdmi-ac3.conf profile set not found in /usr/share/alsa-card-profile/mixer/profile-sets/")
    fi

    # Check 10: Check receiver connection
    local display_connected
    display_connected=$(cat /sys/class/drm/card*/status 2>/dev/null | grep -c "connected" || echo "0")
    if [[ "$display_connected" -eq 0 ]]; then
        issues+=("No connected display detected in /sys/class/drm/")
    fi

    # Report findings
    echo ""
    if (( ${#issues[@]} == 0 )); then
        print_info "All checks passed — configuration looks correct."
        print_info "The issue may be on the receiver/TV side:"
        echo ""
        echo -e "    ${DIM}- Verify your receiver is set to the correct HDMI input${RESET}"
        echo -e "    ${DIM}- Check that eARC is enabled in your TV settings${RESET}"
        echo -e "    ${DIM}- Try power-cycling the receiver${RESET}"
        echo -e "    ${DIM}- Some TVs need 'Audio Format' set to 'Auto' or 'Bitstream' in their audio settings${RESET}"
        echo -e "    ${DIM}- Make sure the TV is not forcing PCM output${RESET}"
    else
        print_error "Found ${#issues[@]} issue(s):"
        for issue in "${issues[@]}"; do
            echo -e "    ${RED}- $issue${RESET}"
        done
    fi

    # Generate diagnostic log
    echo ""
    ac3_generate_diagnostic_log "$card_name" "$ac3_sink" "$active_profile" issues[@]

    echo ""
    if confirm "Would you like to revert AC-3 Surround Encoding and restore HDMI stereo?"; then
        run_revert_ac3_surround
    else
        print_info "AC-3 Surround Encoding remains installed."
        print_info "You can revert later from the menu (option 13R) or re-run the test."
    fi
}

ac3_generate_diagnostic_log() {
    local card_name="$1" ac3_sink="$2" active_profile="$3"
    local -n diag_issues="$4"
    local logfile="$LOG_DIR/bc250-ac3-diagnostic-$(date +%Y%m%d-%H%M%S).log"

    {
        echo "BC-250 SteamOS Real Toolkit — AC-3 Surround Diagnostic Report"
        echo "Generated   : $(date)"
        echo "Toolkit     : $TOOLKIT_VERSION"
        echo "Option      : 13 (Install AC-3 Surround Encoding)"
        echo ""
        echo "== Operating System =="
        [[ -f /etc/os-release ]] && cat /etc/os-release || echo "Unknown"
        echo ""
        echo "== Kernel =="
        uname -r
        uname -a
        echo ""
        echo "== Build Info =="
        echo "Kernel build: $(uname -v 2>/dev/null || echo 'N/A')"
        echo "GCC: $(gcc --version 2>/dev/null | head -1 || echo 'N/A')"
        echo ""
        echo "== Installed Toolkit Components =="
        if [[ -f "$PERSIST_STATE_FILE" ]]; then
            cat "$PERSIST_STATE_FILE"
        else
            echo "(none recorded)"
        fi
        echo ""
        echo "== Audio Card / PipeWire / WirePlumber (user session) =="
        local uid
        uid=$(id -u "$REAL_USER")
        sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" bash "$AC3_USER_SCRIPT" diag 2>/dev/null || echo "N/A"
        echo ""
        echo "== Active Profile =="
        echo "Card: $card_name"
        echo "Profile: ${active_profile:-unknown}"
        echo ""
        echo "== ALSA HDMI Device Status =="
        cat /proc/asound/card0/pcm3p/sub0/status 2>/dev/null || echo "Device not accessible"
        echo ""
        cat /proc/asound/card0/pcm3p/sub0/hw_params 2>/dev/null || echo "No hw_params (device not open)"
        echo ""
        echo "== Udev Rule =="
        [[ -f "$AC3_UDEV_RULE" ]] && cat "$AC3_UDEV_RULE" || echo "Not installed"
        echo ""
        echo "== WirePlumber AC-3 Config =="
        [[ -f "$AC3_WP_CONF" ]] && cat "$AC3_WP_CONF" || echo "Not installed"
        echo ""
        echo "== hdmi-ac3.conf Profile Set =="
        [[ -f /usr/share/alsa-card-profile/mixer/profile-sets/hdmi-ac3.conf ]] && \
            head -30 /usr/share/alsa-card-profile/mixer/profile-sets/hdmi-ac3.conf || \
            echo "Not found"
        echo ""
        echo "== a52 Plugin =="
        ls -la /usr/lib/alsa-lib/libasound_module_pcm_a52.so 2>/dev/null || echo "Not found"
        echo ""
        echo "== ffmpeg/libavcodec =="
        ldconfig -p 2>/dev/null | grep libavcodec || echo "libavcodec not found"
        echo ""
        echo "== Display/Connection =="
        for f in /sys/class/drm/card*/status; do
            [[ -f "$f" ]] && echo "$(basename "$(dirname "$f")"): $(cat "$f")"
        done 2>/dev/null || echo "N/A"
        echo ""
        echo "== Diagnosis Issues =="
        if (( ${#diag_issues[@]} > 0 )); then
            for issue in "${diag_issues[@]}"; do
                echo "  - $issue"
            done
        else
            echo "  (no issues detected by auto-diagnosis)"
        fi
        echo ""
        echo "== Recent dmesg (audio/HDMI related, last 30) =="
        dmesg 2>/dev/null | grep -i "hdmi\|audio\|snd\|hda\|drm" | tail -30 || echo "dmesg not accessible"
    } > "$logfile" 2>/dev/null

    chown "$REAL_USER":"$REAL_USER" "$logfile" 2>/dev/null || true

    # Copy to Desktop if available
    local desktop_dir
    desktop_dir="$(sudo -u "$REAL_USER" xdg-user-dir DESKTOP 2>/dev/null || echo "")"
    [[ -n "$desktop_dir" ]] || desktop_dir="${REAL_HOME}/Desktop"
    if [[ -d "$desktop_dir" ]]; then
        local desktop_log="$desktop_dir/$(basename "$logfile")"
        if cp -f "$logfile" "$desktop_log" 2>/dev/null; then
            chown "$REAL_USER":"$REAL_USER" "$desktop_log" 2>/dev/null || true
            print_info "Diagnostic log copied to Desktop: ${BOLD}${desktop_log}${RESET}"
        fi
    fi

    print_info "Diagnostic log saved to: ${BOLD}${logfile}${RESET}"
    echo ""
    print_info "Please share this log when reporting the issue:"
    print_info "  Discord: BC-250 community channel"
    print_info "  GitHub:  ${CYAN}https://github.com/rpf16rj/bc250-steamos-real-toolkit/issues/new${RESET}"
}

run_revert_ac3_surround() {
    print_step "R-AC3" "Revert HDMI AC-3 Surround Encoding"

    if ! ac3_surround_installed && ! ac3_profile_active; then
        print_info "AC-3 Surround Encoding is not installed — nothing to revert."
        return 0
    fi

    if ! ac3_surround_installed && ac3_profile_active; then
        print_info "Config files not found, but AC-3 profile is still active — will revert profile."
    fi

    if ! confirm "This will restore the default HDMI stereo profile. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    # Remove udev rule
    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        steamos-readonly disable || true
    fi
    rm -f "$AC3_UDEV_RULE"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger /sys/class/sound/card0 2>/dev/null || true
    if (( was_steamos )); then
        steamos-readonly enable || true
    fi

    # Remove WirePlumber config, restart WP, restore stereo profile
    # (runs as real user to access PipeWire)
    print_info "Reverting WirePlumber config and restoring HDMI stereo profile..."
    local uid
    uid=$(id -u "$REAL_USER")
    local revert_output
    revert_output=$(sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" bash "$AC3_USER_SCRIPT" revert 2>&1 || true)
    echo "$revert_output" | grep -v "^REVERTED$" || true

    print_success "AC-3 Surround Encoding reverted. HDMI stereo profile restored."
    persist_state_remove "ac3"
}

gfx1013_ensure_mesa_build_deps() {
    # SteamOS's immutable rootfs strips dev headers and .pc files from many
    # packages to save space, even though pacman's local DB still lists the
    # package as fully installed (owning those paths). Building Mesa from
    # source needs those files back. This function force-reinstalls the
    # packages known to hit this (found empirically building Mesa 26.2 with
    # -Dplatforms=x11,wayland -Dllvm=disabled -Dvulkan-drivers=amd — x11 is
    # required so the RADV ICD gets VK_KHR_xcb_surface/xlib_surface; without
    # it, Proton/Wine games that create their Vulkan surface via XWayland
    # fail to launch even though the compositor session itself is Wayland),
    # so a single `pacman -S --overwrite` pass restores everything without
    # guesswork or repeated failed meson runs.
    local pkgs=(meson ninja python-mako python-packaging python-yaml
                glibc linux-api-headers libdrm wayland wayland-protocols
                libffi systemd-libs libelf zlib zstd expat glslang
                libxcb libx11 libxext libxdamage libxfixes libxrandr
                libxshmfence libxxf86vm libxrender libxau libxdmcp xorgproto
                xcb-util xcb-util-wm xcb-util-keysyms xcb-util-renderutil xcb-util-image)
    local need_install=0
    command -v meson >/dev/null 2>&1 || need_install=1
    command -v ninja >/dev/null 2>&1 || need_install=1
    command -v cc >/dev/null 2>&1 || need_install=1
    command -v glslangValidator >/dev/null 2>&1 || need_install=1
    python3 -c "import packaging" 2>/dev/null || need_install=1
    python3 -c "import yaml" 2>/dev/null || need_install=1
    [[ -f /usr/include/stdio.h ]] || need_install=1
    [[ -f /usr/include/linux/errno.h ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/libdrm.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/wayland-client.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/libffi.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/libudev.pc ]] || need_install=1
    [[ -f /usr/include/gelf.h ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/xcb.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/x11.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/xrandr.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/xshmfence.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/zlib.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/libzstd.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/expat.pc ]] || need_install=1
    [[ -f /usr/lib/pkgconfig/wayland-scanner.pc ]] || need_install=1

    [[ "$need_install" = 1 ]] || return 0

    local root_free_mb
    root_free_mb=$(df --output=avail -m / 2>/dev/null | tail -1 | tr -d ' ')
    if [[ -n "$root_free_mb" ]] && (( root_free_mb < 300 )); then
        print_info "${YELLOW}Warning:${RESET} only ${root_free_mb}MB free on / — restoring headers may fail if it runs out."
        print_info "If it fails, free space first (e.g. 'sudo pacman -Rns rust' if installed and unused) and retry."
    fi

    print_info "Restoring dev headers/pkgconfig files SteamOS strips from its image (${pkgs[*]})..."
    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        steamos-readonly disable || { print_info "Could not disable read-only mode."; return 1; }
    fi
    local rc=0
    # Use --overwrite '*' to restore files SteamOS stripped from the image.
    # Drop --needed so pacman reinstalls even when the DB thinks the package
    # is already present (the local DB lists the package as fully installed
    # but the actual .pc files and headers were removed from the image).
    LC_ALL=C sudo pacman -S --noconfirm --overwrite '*' "${pkgs[@]}" || rc=1
    if (( was_steamos )); then
        steamos-readonly enable || true
    fi
    if (( rc != 0 )); then
        return "$rc"
    fi
    # Verify critical .pc files are now present
    local missing_pc=()
    for pc in wayland-client wayland-scanner libudev libdrm libffi zlib libzstd expat; do
        [[ -f "/usr/lib/pkgconfig/${pc}.pc" ]] || missing_pc+=("$pc")
    done
    if (( ${#missing_pc[@]} > 0 )); then
        print_error "Some pkgconfig files are still missing after reinstall: ${missing_pc[*]}"
        print_info "This may happen if the SteamOS image was updated and package versions changed."
        print_info "Try running: sudo pacman -Syu --overwrite '*' ${pkgs[*]}"
        return 1
    fi
    return 0
}

install_gfx1013_fix() {
    print_step "GFX1013" "Installing GFX1013 Compute Queue Fix"

    require_kernel_version || return 1

    echo -e "  ${YELLOW}⚠  This rebuilds and replaces amdgpu.ko with a kernel-specific patched module.${RESET}"
    echo -e "  ${YELLOW}⚠  A bad build can leave the machine with no display at boot.${RESET}"
    echo -e "  ${DIM}Fixes GPU compute queue lifecycle on BC-250 for async compute support.${RESET}"
    echo -e "  ${DIM}Includes kernel patches + Mesa/RADV patches for full async compute functionality.${RESET}"
    echo -e "  ${DIM}Kernel: compute GFXOFF guard, PASID TLB fix, KFD runlist flush, TTM guard,${RESET}"
    echo -e "  ${DIM}  widened SMU SCLK range (350-2230 MHz) for userspace governors.${RESET}"
    echo -e "  ${DIM}Mesa: async compute fix, mesh/task shaders (opt-in via RADV_GFX103=1),${RESET}"
    echo -e "  ${DIM}  FSR4 V3 deferred SDot hybrid (MAD24 chains, dense pre-pass, always active).${RESET}"
    echo -e "  ${DIM}Performance gains of +20-25% in async compute workloads (e.g., Cyberpunk 2077).${RESET}"
    echo ""

    # Mesh shader mode selection
    local mesh_flag=""
    echo -e "  ${CYAN}Mesh Shader Mode:${RESET}"
    echo -e "  ${DIM}  1) MastaG (default): GFX10.3 spoof + mesh/task shaders via RADV_GFX103=1${RESET}"
    echo -e "  ${DIM}     Supports both MESH and TASK shaders. Opt-in per-game with RADV_GFX103=1.${RESET}"
    echo -e "  ${DIM}  2) Native (lonewolf): Native MESH only on GFX10, no GFX10.3 spoof${RESET}"
    echo -e "  ${DIM}     MESH always available, no TASK shader support. No env var needed.${RESET}"
    echo ""
    local mesh_choice
    read -rp "  Select mesh shader mode [1-MastaG/2-Native] (default 1): " mesh_choice
    case "$mesh_choice" in
        2|n|N|native) mesh_flag="--native-mesh"; print_info "Using native mesh shader mode." ;;
        *) mesh_flag="--mastag-mesh"; print_info "Using MastaG mesh shader mode." ;;
    esac
    echo ""

    if ! confirm "Continue with the GFX1013 compute queue fix?"; then
        print_info "Cancelled."
        return 0
    fi

    fixes_repo_sync || return 1

    local fix_dir="$FIXES_REPO_DIR/bc250-audio-fix"
    if [[ ! -d "$fix_dir" ]]; then
        fail_with_log "bc250-audio-fix directory not found in the fixes repository." "GFX1013 Fix — missing directory"
        return 1
    fi

    print_info "Running patch-driver.sh --gfx1013 (fetch-sources.sh && build.sh --gfx1013 && install.sh)..."
    print_info "This clones the matching Valve kernel source tree and can take several minutes."
    
    print_info "Step 1/5: Prefetching kernel headers..."
    audio_fix_prefetch_headers "$fix_dir"
    
    print_info "Step 2/5: Preparing fetch-sources script..."
    audio_fix_patch_fetch_sources "$fix_dir/fetch-sources.sh" || {
        fail_with_log "Could not prepare the GFX1013 fix dependency fetch script." "GFX1013 Fix — fetch-sources compatibility patch"
        return 1
    }
    
    print_info "Step 3/5: Ensuring mkinitcpio preset..."
    audio_fix_ensure_mkinitcpio_preset
    
    print_info "Step 4/5: Setting permissions and resolving kernel commit..."
    chown -R "$REAL_USER":"$REAL_USER" "$fix_dir"
    local fullsha patch_env=""
    fullsha=$(audio_fix_resolve_fullsha || true)
    if [[ -n "$fullsha" ]]; then
        print_info "Resolved kernel commit ${fullsha:0:12}; passing full SHA to patch-driver.sh."
        patch_env="export FULLSHA='$fullsha';"
    else
        print_info "Could not resolve the short kernel commit locally; patch-driver.sh will use its normal source lookup."
    fi
    
    print_info "Step 5/5: Building and installing kernel module (this may take 5-10 minutes)..."
    if ! runuser -u "$REAL_USER" -- bash -c "cd '$fix_dir' && ${patch_env} ./patch-driver.sh --gfx1013"; then
        fail_with_log "GFX1013 compute queue fix build/install failed. The built-in vermagic/ABI guards refuse to install a mismatched module, so your display driver should be unchanged." "GFX1013 Fix — patch-driver.sh"
        return 1
    fi

    print_info "Kernel patches installed. Now building patched Mesa/RADV..."
    local mesa_dir="$FIXES_REPO_DIR/bc250-gfx1013-fix"
    if [[ ! -d "$mesa_dir" ]]; then
        fail_with_log "bc250-gfx1013-fix directory not found in the fixes repository." "GFX1013 Fix — missing Mesa directory"
        return 1
    fi

    # Check for meson, ninja, and the C build toolchain
    print_info "Step 6/7: Checking for meson/ninja build tools and dev headers..."
    if ! gfx1013_ensure_mesa_build_deps; then
        fail_with_log "Failed to prepare Mesa build dependencies. Please check the log above." "GFX1013 Fix — missing build deps"
        return 1
    fi

    print_info "Step 7/7: Building Mesa/RADV (mesh: ${mesh_flag}) (this may take 10-15 minutes)..."
    if ! runuser -u "$REAL_USER" -- bash -c "cd '$mesa_dir' && ./build-mesa.sh ${mesh_flag}"; then
        fail_with_log "Mesa build failed. Kernel patches are installed, but Mesa/RADV patches were not applied. Async compute may not work correctly." "GFX1013 Fix — build-mesa.sh"
        return 1
    fi

    print_success "GFX1013 compute queue fix installed! Reboot required."
    persist_state_add "gfx1013"
    print_info "After reboot, async compute queues are enabled on the BC-250 GPU."
    print_info "Patched Mesa installed to /opt/bc250-gfx1013/"
    print_info "${YELLOW}If anything misbehaves:${RESET} use the Revert option, then reboot."
}

run_revert_gfx1013_fix() {
    print_step "R-GFX1013" "Revert GFX1013 Compute Queue Fix"

    local fix_dir="$FIXES_REPO_DIR/bc250-audio-fix"
    if [[ ! -d "$fix_dir" ]]; then
        print_info "Fixes repository not found locally — nothing to revert."
        return 0
    fi

    if ! confirm "This will restore the stock amdgpu.ko module and remove patched Mesa. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    audio_fix_ensure_mkinitcpio_preset

    if ! (cd "$fix_dir" && ./rollback.sh); then
        fail_with_log "Failed to roll back the GFX1013 compute queue fix." "GFX1013 Fix — rollback.sh"
        return 1
    fi

    # Remove patched Mesa installation
    local mesa_dir="/opt/bc250-gfx1013"
    if [[ -d "$mesa_dir" ]]; then
        print_info "Removing patched Mesa from ${mesa_dir}..."
        sudo rm -rf "$mesa_dir"
    fi

    # Remove VK_DRIVER_FILES from /etc/environment
    local env_file="/etc/environment"
    if [[ -f "$env_file" ]] && grep -q "VK_DRIVER_FILES" "$env_file"; then
        print_info "Removing VK_DRIVER_FILES from ${env_file}..."
        sudo sed -i '/VK_DRIVER_FILES/d' "$env_file"
    fi

    print_success "GFX1013 compute queue fix reverted to stock amdgpu.ko. Reboot to apply."
    persist_state_remove "gfx1013"
}

install_combined_fix() {
    print_step "COMBO" "Installing Combined Fix (selectable components)"

    require_kernel_version || return 1

    echo -e "  ${YELLOW}⚠  This rebuilds and replaces amdgpu.ko with a kernel-specific patched module.${RESET}"
    echo -e "  ${YELLOW}⚠  A bad build can leave the machine with no display at boot.${RESET}"
    echo -e "  ${DIM}Select which components to include in this build:${RESET}"
    echo ""

    local do_audio=0 do_gfx=0 do_vrr=0 do_allm=0
    local patch_flags=()

    # Detect kernel major version for version-specific skip logic
    local kver_major kver_minor kver_rest
    kver_major="$(uname -r | cut -d. -f1)"
    kver_rest="$(uname -r | cut -d. -f2-)"
    kver_minor="${kver_rest%%.*}"

    echo -e "  ${CYAN}1) Audio Fix${RESET} — DP audio/video clock + GPU metrics + DP SS disable + tunable cache"
    if confirm "  Install Audio Fix?"; then do_audio=1; patch_flags+=(--audio); fi
    echo ""
    echo -e "  ${CYAN}2) GFX1013 Compute Fix + Mesa/RADV${RESET} — async compute + FSR4 V3 + mesh/task shaders"
    if confirm "  Install GFX1013 Compute Fix + Mesa?"; then do_gfx=1; patch_flags+=(--gfx1013); fi
    echo ""

    if [[ "$kver_major" -ge 7 ]]; then
        print_info "Kernel 7.x detected — VRR and ALLM patches are not needed (already functional upstream). Skipping."
        echo ""
    else
        echo -e "  ${CYAN}3) VRR PCON FreeSync${RESET} — FreeSync fallback + HDMI VRR (VTEM) + LFC-aware range extending"
        if confirm "  Install VRR PCON FreeSync patch?"; then do_vrr=1; patch_flags+=(--vrr); fi
        echo ""
        echo -e "  ${CYAN}4) ALLM via DP${RESET} — Auto Low Latency Mode for PCON HDMI Game Mode"
        if confirm "  Install ALLM via DP patch?"; then do_allm=1; patch_flags+=(--allm); fi
        echo ""
    fi

    if [[ $do_audio -eq 0 && $do_gfx -eq 0 && $do_vrr -eq 0 && $do_allm -eq 0 ]]; then
        print_info "No patches selected. Nothing to do."
        return 0
    fi

    validate_combined_fix_prerequisites "$do_gfx" || return 1

    echo -e "  ${DIM}Always included: TTM NULL-page guard + SCLK range widening (350-2230 MHz)${RESET}"
    echo ""

    local mesh_flag=""
    if [[ $do_gfx -eq 1 ]]; then
        echo -e "  ${CYAN}Mesh Shader Mode:${RESET}"
        echo -e "  ${DIM}  1) MastaG (default): GFX10.3 spoof + mesh/task shaders via RADV_GFX103=1${RESET}"
        echo -e "  ${DIM}  2) Native (lonewolf): Native MESH only on GFX10, no GFX10.3 spoof${RESET}"
        echo ""
        local mesh_choice
        read -rp "  Select mesh shader mode [1-MastaG/2-Native] (default 1): " mesh_choice
        case "$mesh_choice" in
            2|n|N|native) mesh_flag="--native-mesh"; print_info "Using native mesh shader mode." ;;
            *) mesh_flag="--mastag-mesh"; print_info "Using MastaG mesh shader mode." ;;
        esac
    fi
    echo ""

    local flags_str="${patch_flags[*]}"
    if ! confirm "Continue with selected components: ${flags_str:-none}?"; then
        print_info "Cancelled."
        return 0
    fi

    fixes_repo_sync || return 1

    local fix_dir="$FIXES_REPO_DIR/bc250-audio-fix"
    if [[ ! -d "$fix_dir" ]]; then
        fail_with_log "bc250-audio-fix directory not found in the fixes repository." "Combined Fix — missing directory"
        return 1
    fi

    print_info "Running patch-driver.sh ${flags_str} (single kernel build with selected patch sets)..."
    print_info "This clones the matching Valve kernel source tree and can take several minutes."

    audio_fix_prefetch_headers "$fix_dir"
    audio_fix_patch_fetch_sources "$fix_dir/fetch-sources.sh" || {
        fail_with_log "Could not prepare the combined fix dependency fetch script." "Combined Fix — fetch-sources compatibility patch"
        return 1
    }
    audio_fix_ensure_mkinitcpio_preset

    chown -R "$REAL_USER":"$REAL_USER" "$fix_dir"
    local fullsha patch_env=""
    fullsha=$(audio_fix_resolve_fullsha || true)
    if [[ -n "$fullsha" ]]; then
        print_info "Resolved kernel commit ${fullsha:0:12}; passing full SHA to patch-driver.sh."
        patch_env="export FULLSHA='$fullsha';"
    else
        print_info "Could not resolve the short kernel commit locally; patch-driver.sh will use its normal source lookup."
    fi

    if ! runuser -u "$REAL_USER" -- bash -c "cd '$fix_dir' && ${patch_env} ./patch-driver.sh ${flags_str}"; then
        fail_with_log "Combined fix build/install failed. The built-in vermagic/ABI guards refuse to install a mismatched module, so your display driver should be unchanged." "Combined Fix — patch-driver.sh"
        return 1
    fi

    if [[ $do_gfx -eq 1 ]]; then
        print_info "Kernel patches installed. Now building patched Mesa/RADV..."
        local mesa_dir="$FIXES_REPO_DIR/bc250-gfx1013-fix"
        if [[ ! -d "$mesa_dir" ]]; then
            fail_with_log "bc250-gfx1013-fix directory not found in the fixes repository." "Combined Fix — missing Mesa directory"
            return 1
        fi

        print_info "Checking for meson/ninja build tools and dev headers..."
        if ! gfx1013_ensure_mesa_build_deps; then
            fail_with_log "Failed to prepare Mesa build dependencies. Please check the log above." "Combined Fix — missing build deps"
            return 1
        fi

        print_info "Building Mesa/RADV (mesh: ${mesh_flag}) (this may take 10-15 minutes)..."
        if ! runuser -u "$REAL_USER" -- bash -c "cd '$mesa_dir' && ./build-mesa.sh ${mesh_flag}"; then
            fail_with_log "Mesa build failed. Kernel patches are installed, but Mesa/RADV patches were not applied. Async compute may not work correctly." "Combined Fix — build-mesa.sh"
            return 1
        fi
    fi

    print_success "Combined fix installed! Reboot required."
    [[ $do_audio -eq 1 ]] && persist_state_add "audio"
    [[ $do_gfx -eq 1 ]] && persist_state_add "gfx1013"
    [[ $do_gfx -eq 1 ]] && print_info "Patched Mesa installed to /opt/bc250-gfx1013/"
    print_info "${YELLOW}If anything misbehaves:${RESET} use the Revert options, then reboot."

    if [[ $do_vrr -eq 1 || $do_allm -eq 1 ]]; then
        echo ""
        echo -e "  ${CYAN}The patched amdgpu.ko includes VRR and ALLM support for DP→HDMI PCON adapters.${RESET}"
        echo -e "  ${DIM}VRR: FreeSync fallback + HDMI VRR (VTEM) with improved range extending (LFC-aware).${RESET}"
        echo -e "  ${DIM}ALLM: Auto Low Latency Mode via AVI content_type hint to PCON.${RESET}"
        echo -e "  ${DIM}Requires amdgpu.freesync_pcon_allow_all=1 in the kernel command line for PCON VRR bypass.${RESET}"
        echo ""
        if audio_fix_pcon_grub_installed; then
            print_info "amdgpu.freesync_pcon_allow_all=1 is already in GRUB — VRR/ALLM ready."
        elif confirm "Add amdgpu.freesync_pcon_allow_all=1 to GRUB for VRR over PCON?"; then
            audio_fix_ensure_pcon_grub_param
        else
            print_info "Skipped GRUB param. Add amdgpu.freesync_pcon_allow_all=1 manually for VRR over PCON."
        fi
    fi

    # Kernel 7.x telemetry: 8-core without patched SMU BIOS needs cs_legacy_8core_metrics=1
    if [[ "$do_audio" -eq 1 && "$kver_major" -ge 7 ]]; then
        local core_count
        core_count=$(nproc 2>/dev/null || echo 0)
        if (( core_count >= 16 )); then
            # 8 cores / 16 threads — check if SMU-patched BIOS is in use
            if [[ -f "$GRUB_DEFAULT" ]] && grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=.*amdgpu\.cs_legacy_8core_metrics=1' "$GRUB_DEFAULT" >/dev/null 2>&1; then
                : # already set
            else
                echo ""
                echo -e "  ${YELLOW}8-core detected with kernel 7.x telemetry patch.${RESET}"
                echo -e "  ${DIM}The new telemetry patch defaults to the SMU-patched 8-core layout (136-byte tables).${RESET}"
                echo -e "  ${DIM}If your BIOS does NOT have the SMU telemetry patch (stock BIOS P3.00),${RESET}"
                echo -e "  ${DIM}GPU temperature and some metrics will read as 0 until you add:${RESET}"
                echo -e "  ${CYAN}amdgpu.cs_legacy_8core_metrics=1${RESET} ${DIM}to the kernel command line.${RESET}"
                echo ""
                if confirm "Are you running a stock BIOS (no SMU patch)? Add cs_legacy_8core_metrics=1 to GRUB?"; then
                    steamos_writable "
                        cp \"$GRUB_DEFAULT\" \"$GRUB_DEFAULT.bak\"
                        if ! grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=' \"$GRUB_DEFAULT\" | grep -q 'amdgpu.cs_legacy_8core_metrics=1'; then
                            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\([^\"]*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 amdgpu.cs_legacy_8core_metrics=1\"/' \"$GRUB_DEFAULT\"
                        fi
                        update-grub
                    " || {
                        print_info "Failed to add amdgpu.cs_legacy_8core_metrics=1 to GRUB. Add it manually."
                    }
                    print_info "Added amdgpu.cs_legacy_8core_metrics=1 to GRUB. Reboot to activate correct telemetry."
                else
                    print_info "Skipped. If GPU temperature reads 0, add amdgpu.cs_legacy_8core_metrics=1 to GRUB manually."
                fi
            fi
        fi
    fi
}

# --- AIC8800D80 USB WiFi/BT dongle driver -----------------------------------
aic8800_installed() {
    [[ -d /sys/module/aic8800_fdrv || -f /etc/modprobe.d/aic8800.conf ]]
}

# The vendor Makefile's "steamos-headers" target hardcodes the "jupiter-main"
# repo channel *and* derives pkgver with a single-hyphen-to-dot substitution
# that mishandles flavors like "-drm-exec" (see the shared helpers above for
# details) -- it 404s or fetches the wrong filename on this kernel. Its caller
# (steamdeck-setup.sh) only invokes that target when
# steamos-headers/usr/lib/modules/$KREL/build doesn't already exist, so
# pre-extracting the correct package there makes it skip the broken step
# entirely, with zero changes to the vendor tree.
aic8800_prefetch_headers() {
    local drv="$1" rel hdrpkg tmp
    rel="$(uname -r)"
    [[ -d "$drv/steamos-headers/usr/lib/modules/$rel/build" ]] && return 0
    hdrpkg=$(bc250_headers_pkg_name "$rel") || return 0

    tmp=$(mktemp -d)
    if bc250_fetch_headers_pkg "$hdrpkg" "$tmp/$hdrpkg"; then
        mkdir -p "$drv/steamos-headers"
        tar --zstd -xf "$tmp/$hdrpkg" -C "$drv/steamos-headers"
        chown -R "$REAL_USER":"$REAL_USER" "$drv/steamos-headers" 2>/dev/null || true
        print_info "Headers pre-extracted into $drv/steamos-headers (vendor Makefile's own fetch is unreliable on this kernel flavor)."
    else
        print_info "Could not pre-stage AIC8800 kernel headers from any known repo channel; letting steamdeck-setup.sh try (and report) on its own."
    fi
    rm -rf "$tmp"
}

install_aic8800_wifi() {
    print_step "WIFI" "Installing AIC8800D80 USB WiFi/BT Driver"

    require_kernel_version || return 1

    echo -e "  ${DIM}Only needed for an AIC8800D80-based USB WiFi/BT dongle${RESET}"
    echo -e "  ${DIM}(enumerates as a fake 1111:1111 mass-storage device before setup).${RESET}"
    echo ""

    fixes_repo_sync || return 1

    local aic_dir="$FIXES_REPO_DIR/aic8800"
    local drv="$aic_dir/src/USB/driver_fw/drivers/aic8800"
    local fw_source="$aic_dir/src/USB/driver_fw/fw/aic8800D80"

    if [[ ! -f "$drv/Makefile" || ! -d "$fw_source" ]]; then
        fail_with_log "AIC8800 driver source not found in the fixes repository." "AIC8800 WiFi — missing source"
        return 1
    fi

    aic8800_prefetch_headers "$drv"

    print_info "Installing build tools for AIC8800..."
    steamos_writable 'pacman -Sy --noconfirm --needed base-devel' || {
        fail_with_log "Failed to install AIC8800 build dependencies." "AIC8800 WiFi — build deps"
        return 1
    }

    print_info "Building AIC8800 modules..."
    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$REAL_USER" -- make -C "$drv" clean || true
        runuser -u "$REAL_USER" -- make -C "$drv" || {
            fail_with_log "Failed to build AIC8800 modules." "AIC8800 WiFi — build"
            return 1
        }
    else
        make -C "$drv" clean || true
        make -C "$drv" || {
            fail_with_log "Failed to build AIC8800 modules." "AIC8800 WiFi — build"
            return 1
        }
    fi

    print_info "Installing AIC8800 modules, firmware and configuration..."
    local stage
    stage=$(mktemp -d /tmp/aic8800-wifi-XXXXXX)
    mkdir -p "$stage/firmware/aic8800D80"
    cp -a "$fw_source"/. "$stage/firmware/aic8800D80/"

    cat > "$stage/aic8800.conf" <<EOF
options aic_load_fw aic_fw_path=/usr/lib/firmware/aic8800D80
EOF

    cat > "$stage/40-aic8800-modeswitch.rules" <<'EOF'
# AIC8800D80 WiFi dongle: auto-switch from fake mass-storage to WiFi mode
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="1111", ATTR{idProduct}=="1111", RUN+="/usr/lib/udev/usb_modeswitch '%b/%k'"
EOF

    cat > "$stage/1111:1111" <<'EOF'
# AIC8800D80 WiFi dongle: fake mass-storage -> WiFi mode
MessageContent="555342431234567800000000000010fd0000000000000000000000000000f2"
ResetUSB=1
EOF

    steamos_writable "make -C \"$drv\" install && depmod -a && mkdir -p /usr/lib/firmware/aic8800D80 && cp -a \"$stage/firmware/aic8800D80\"/. /usr/lib/firmware/aic8800D80/ && cp \"$stage/aic8800.conf\" /etc/modprobe.d/aic8800.conf && cp \"$stage/40-aic8800-modeswitch.rules\" /etc/udev/rules.d/ && cp \"$stage/1111:1111\" /etc/usb_modeswitch.d/1111:1111" || {
        fail_with_log "Failed to install AIC8800 driver to /usr and /etc." "AIC8800 WiFi — install"
        rm -rf "$stage"
        return 1
    }
    rm -rf "$stage"

    udevadm control --reload
    systemctl daemon-reload

    print_info "Loading AIC8800 modules..."
    modprobe -r aic8800_fdrv aic_load_fw 2>/dev/null || true
    modprobe aic_load_fw 2>/dev/null || true
    modprobe aic8800_fdrv 2>/dev/null || true

    if grep -q '1111' /sys/bus/usb/devices/*/idVendor 2>/dev/null \
       && grep -q '1111' /sys/bus/usb/devices/*/idProduct 2>/dev/null; then
        print_info "Switching AIC8800D80 dongle to WiFi mode..."
        usb_modeswitch -v 1111 -p 1111 \
            -M "555342431234567800000000000010fd0000000000000000000000000000f2" -R 2>/dev/null || true
    fi

    print_success "AIC8800 WiFi/BT driver installed!"
    persist_state_add "aic8800"
    print_info "Check with: ${CYAN}ip link${RESET} (WiFi) and ${CYAN}bluetoothctl${RESET} (Bluetooth)."
    print_info "${YELLOW}Note:${RESET} rebuild after each SteamOS update — safe to re-run this option any time."
}

run_revert_aic8800_wifi() {
    print_step "R-WIFI" "Revert AIC8800 WiFi/BT Driver"

    if ! aic8800_installed; then
        print_info "AIC8800 driver does not appear to be installed — nothing to revert."
        return 0
    fi

    if ! confirm "This will unload the driver and remove its configuration. Proceed?"; then
        print_info "Cancelled."
        return 0
    fi

    modprobe -r aic8800_fdrv aic_load_fw 2>/dev/null || true

    local was_steamos=0
    if is_steamos; then
        was_steamos=1
        steamos-readonly disable || true
    fi

    rm -f /etc/modprobe.d/aic8800.conf /etc/udev/rules.d/40-aic8800-modeswitch.rules '/etc/usb_modeswitch.d/1111:1111'
    local mod_dir="/usr/lib/modules/$(uname -r)/updates/aic8800"
    if [[ -d "$mod_dir" ]]; then
        rm -rf "$mod_dir"
        depmod
    fi
    udevadm control --reload 2>/dev/null || true

    if (( was_steamos )); then
        steamos-readonly enable || true
    fi

    print_success "AIC8800 driver configuration removed."
    persist_state_remove "aic8800"
}

# --- Intel BE200 Wi-Fi 7 firmware -------------------------------------------
# The BE200 (Gale Peak) PCIe card is supported by the in-tree iwlwifi driver
# since kernel 6.5, and SteamOS 6.18 ships CONFIG_IWLMLD=m + iwlmld.ko.
# However, some BE200 cards ship with firmware that requires ucode >= -100,
# while SteamOS's linux-firmware only goes up to -96.  The driver prints:
#   iwlwifi: no suitable firmware found!
#   iwlwifi: minimum version required: iwlwifi-gl-c0-fm-c0-100
#   iwlwifi: maximum version supported: iwlwifi-gl-c0-fm-c0-c101
# This installs the missing -100/-101 ucode files from Debian's
# firmware-iwlwifi package.  No kernel module build needed — just firmware.
be200_firmware_installed() {
    [[ -f /usr/lib/firmware/iwlwifi-gl-c0-fm-c0-100.ucode ]] \
    || [[ -f /usr/lib/firmware/iwlwifi-gl-c0-fm-c0-100.ucode.zst ]]
}

install_be200_firmware() {
    print_step "WIFI-BE200" "Installing Intel BE200 Wi-Fi 7 Firmware"
    echo -e "  ${DIM}For Intel BE200/BE201 PCIe Wi-Fi 7 cards that fail with 'no suitable firmware found'${RESET}"
    echo -e "  ${DIM}SteamOS ships ucode up to -96; some BE200 cards require -100 or -101.${RESET}"
    echo ""

    if be200_firmware_installed; then
        print_info "BE200 firmware (-100) is already installed."
        if ! confirm "Reinstall/update anyway?"; then
            print_info "Cancelled."
            return 0
        fi
    fi

    if ! command -v curl >/dev/null 2>&1; then
        fail_with_log "curl is required to download the firmware package." "BE200 WiFi — missing curl"
        return 1
    fi

    local workdir deb_url deb_file
    workdir=$(mktemp -d /tmp/be200-fw-XXXXXX)
    trap 'rm -rf "$workdir"' RETURN

    print_info "Finding latest firmware-iwlwifi package from Debian..."
    # Scrape the Debian pool directory for the newest package version.
    # The URL is not hardcoded — we discover it dynamically.
    deb_url=$(curl -fsSL "https://deb.debian.org/debian/pool/non-free-firmware/f/firmware-nonfree/" 2>/dev/null \
        | grep -o 'firmware-iwlwifi_[^"]*_all\.deb' \
        | sort -V | tail -1)

    if [[ -z "$deb_url" ]]; then
        fail_with_log "Could not find a firmware-iwlwifi package URL from Debian." "BE200 WiFi — package discovery"
        return 1
    fi

    deb_url="https://deb.debian.org/debian/pool/non-free-firmware/f/firmware-nonfree/$deb_url"
    deb_file=$(basename "$deb_url")
    print_info "Downloading $deb_file ..."

    if ! curl -fsSL -o "$workdir/$deb_file" "$deb_url"; then
        fail_with_log "Failed to download $deb_url" "BE200 WiFi — download"
        return 1
    fi

    print_info "Extracting firmware from package..."
    (
        cd "$workdir"
        ar x "$deb_file" 2>/dev/null || { echo "ERROR: ar extraction failed" >&2; exit 1; }
        local data_tar
        data_tar=$(ls data.tar.* 2>/dev/null | head -1)
        [[ -n "$data_tar" ]] || { echo "ERROR: no data.tar found" >&2; exit 1; }
        tar -xf "$data_tar" 2>/dev/null || true
    ) || {
        fail_with_log "Failed to extract the Debian package." "BE200 WiFi — extraction"
        return 1
    }

    # The package puts firmware in both ./usr/lib/firmware/ (top-level) and
    # ./usr/lib/firmware/intel/iwlwifi/ (upstream layout).  The kernel loader
    # checks /usr/lib/firmware/ directly, so either path works.
    local fw_src="$workdir/usr/lib/firmware"
    local found=0
    local version
    for version in 100 101; do
        local src="$fw_src/iwlwifi-gl-c0-fm-c0-${version}.ucode"
        if [[ -s "$src" ]]; then
            found=$((found + 1))
        fi
    done

    if [[ $found -eq 0 ]]; then
        fail_with_log "No BE200 firmware files (-100/-101) found in the package." "BE200 WiFi — no firmware in package"
        return 1
    fi

    print_info "Found $found firmware file(s). Installing to /usr/lib/firmware/..."

    local install_cmd="cp -v"
    for version in 100 101; do
        local src="$fw_src/iwlwifi-gl-c0-fm-c0-${version}.ucode"
        [[ -s "$src" ]] && install_cmd="$install_cmd \"$src\" /usr/lib/firmware/"
    done

    steamos_writable "$install_cmd" || {
        fail_with_log "Failed to copy firmware files to /usr/lib/firmware/." "BE200 WiFi — install"
        return 1
    }

    print_info "Reloading iwlwifi module..."
    modprobe -r iwlwifi 2>/dev/null || true
    modprobe iwlwifi 2>/dev/null || true

    print_success "Intel BE200 firmware installed!"
    persist_state_add "be200_fw"
    print_info "Check with: ${CYAN}dmesg | grep iwlwifi${RESET} — should show 'loaded firmware version'"
    print_info "If the card was not detected at boot, a reboot may be needed: ${CYAN}sudo reboot${RESET}"
    print_info "${YELLOW}Note:${RESET} SteamOS updates may overwrite these files — re-run this option if WiFi stops working after an update."
}

run_revert_be200_firmware() {
    print_step "R-WIFI-BE200" "Revert Intel BE200 Wi-Fi 7 Firmware"

    if ! be200_firmware_installed; then
        print_info "BE200 firmware does not appear to be installed — nothing to revert."
        return 0
    fi

    if ! confirm "Remove BE200 firmware files (-100/-101) from /usr/lib/firmware/?"; then
        print_info "Cancelled."
        return 0
    fi

    steamos_writable 'rm -f /usr/lib/firmware/iwlwifi-gl-c0-fm-c0-100.ucode /usr/lib/firmware/iwlwifi-gl-c0-fm-c0-101.ucode /usr/lib/firmware/iwlwifi-gl-c0-fm-c0-100.ucode.zst /usr/lib/firmware/iwlwifi-gl-c0-fm-c0-101.ucode.zst' || {
        fail_with_log "Failed to remove BE200 firmware files." "BE200 WiFi — revert"
        return 1
    }

    modprobe -r iwlwifi 2>/dev/null || true
    modprobe iwlwifi 2>/dev/null || true

    print_success "BE200 firmware files removed."
    persist_state_remove "be200_fw"
}

# --- HDMI-CEC / TV Control (bc250-cec.sh) -----------------------------------
# Self-contained upstream TUI (same pattern as bc250-cu-live-manager.sh): TV
# and AVR/receiver control via cecd + CEC-over-DP-AUX tunneling (wake/standby
# following the console, volume, input switching, multi-device etiquette,
# diagnostics). Opens its own guided menu; every action is also a CLI verb
# ("bc250-cec.sh help" for the full list). It manages its own install state
# under $HOME (toggles, systemd user units) plus one root-owned poweroff unit
# it installs itself with its own sudo prompt, so this is just a launcher.
cec_control_installed() {
    [[ -f "$REAL_HOME/.config/cecd/config.d/50-bc250.toml" ]]
}

run_cec_control() {
    print_step "CEC" "HDMI-CEC / TV Control"
    echo -e "  ${DIM}Wraps the upstream bc250-cec.sh — TV/receiver control via cecd + CEC-over-DP-AUX.${RESET}"
    echo -e "  ${DIM}Opens its own guided menu (setup, tv-on/off, receiver follow, diagnostics, etc).${RESET}"
    echo ""

    fixes_repo_sync || return 1

    local cec_script="$FIXES_REPO_DIR/bc250-cec.sh"
    if [[ ! -f "$cec_script" ]]; then
        fail_with_log "bc250-cec.sh not found in the fixes repository." "HDMI-CEC — missing script"
        return 1
    fi
    chmod +x "$cec_script" 2>/dev/null || true

    # Must run as the real (deck) user, not root: cecd lives on the user
    # D-Bus session, and the script itself refuses to run as root (only its
    # own "shutdown-standby install" step escalates, via its own sudo prompt).
    local user_id
    user_id=$(id -u "$REAL_USER")
    runuser --pty -u "$REAL_USER" -- env \
        XDG_RUNTIME_DIR="/run/user/$user_id" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_id/bus" \
        bash "$cec_script"
}

# ==============================================================================
# OVERCLOCK / PERFORMANCE PROFILES
# ==============================================================================

CPU_DEST="/etc/bc250-smu-oc.conf"
GPU_DEST="/etc/cyan-skillfish-governor-smu/config.toml"
CPU_SERVICE="bc250-smu-oc.service"
GPU_SERVICE="cyan-skillfish-governor-smu.service"

CPU_TMPFILE="$(mktemp /tmp/cpu_profile.XXXXXX)"
GPU_TMPFILE="$(mktemp /tmp/gpu_profile.XXXXXX)"
trap 'rm -f "$CPU_TMPFILE" "$GPU_TMPFILE"' EXIT

write_cpu_undervolt_3_5ghz() { cat > "$CPU_TMPFILE" <<'EOF'
[overclock]
frequency = 3500
scale = -22
max_temperature = 80
EOF
}

write_cpu_overclock_3_85ghz() { cat > "$CPU_TMPFILE" <<'EOF'
[overclock]
frequency = 3850
scale = -30
max_temperature = 90
EOF
}

write_cpu_overclock_4ghz() { cat > "$CPU_TMPFILE" <<'EOF'
[overclock]
frequency = 4000
scale = -37
max_temperature = 90
EOF
}

write_gpu_overclock_1500mhz() { cat > "$GPU_TMPFILE" <<'EOF'
[dbus]
enabled = true
[timing.intervals]
sample = 250
adjust = 100_000
[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10
[gpu]
set-method = "smu"
[frequency-range]
min = 500
max = 1500
[timing.ramp-rates]
normal = 1
burst = 50
[timing]
burst-samples = 60
down-events = 5
[frequency-thresholds]
adjust = 10
[load-target]
upper = 0.65
lower = 0.50
[temperature]
throttling = 80
throttling_recovery = 75
[[safe-points]]
frequency = 500
voltage = 700
[[safe-points]]
frequency = 1000
voltage = 800
[[safe-points]]
frequency = 1175
voltage = 850
[[safe-points]]
frequency = 1500
voltage = 900
EOF
}

write_gpu_overclock_1600mhz() { cat > "$GPU_TMPFILE" <<'EOF'
[dbus]
enabled = true
[timing.intervals]
sample = 250
adjust = 100_000
[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10
[gpu]
set-method = "smu"
[frequency-range]
min = 500
max = 1600
[timing.ramp-rates]
normal = 1
burst = 50
[timing]
burst-samples = 60
down-events = 5
[frequency-thresholds]
adjust = 10
[load-target]
upper = 0.65
lower = 0.50
[temperature]
throttling = 80
throttling_recovery = 75
[[safe-points]]
frequency = 500
voltage = 700
[[safe-points]]
frequency = 1000
voltage = 800
[[safe-points]]
frequency = 1175
voltage = 850
[[safe-points]]
frequency = 1500
voltage = 900
[[safe-points]]
frequency = 1600
voltage = 910
EOF
}

write_gpu_overclock_1600mhz_undervolt() { cat > "$GPU_TMPFILE" <<'EOF'
[dbus]
enabled = true
[timing.intervals]
sample = 250
adjust = 100_000
[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10
[gpu]
set-method = "smu"
[frequency-range]
min = 500
max = 1600
[timing.ramp-rates]
normal = 1
burst = 50
[timing]
burst-samples = 60
down-events = 5
[frequency-thresholds]
adjust = 10
[load-target]
upper = 0.65
lower = 0.50
[temperature]
throttling = 80
throttling_recovery = 75
[[safe-points]]
frequency = 500
voltage = 700
[[safe-points]]
frequency = 1000
voltage = 750
[[safe-points]]
frequency = 1175
voltage = 788
[[safe-points]]
frequency = 1500
voltage = 848
[[safe-points]]
frequency = 1600
voltage = 856
EOF
}

write_gpu_overclock_1750mhz() { cat > "$GPU_TMPFILE" <<'EOF'
[dbus]
enabled = true
[timing.intervals]
sample = 250
adjust = 100_000
[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10
[gpu]
set-method = "smu"
[frequency-range]
min = 500
max = 1750
[timing.ramp-rates]
normal = 1
burst = 50
[timing]
burst-samples = 60
down-events = 5
[frequency-thresholds]
adjust = 10
[load-target]
upper = 0.65
lower = 0.50
[temperature]
throttling = 80
throttling_recovery = 75
[[safe-points]]
frequency = 500
voltage = 700
[[safe-points]]
frequency = 1000
voltage = 800
[[safe-points]]
frequency = 1175
voltage = 850
[[safe-points]]
frequency = 1500
voltage = 900
[[safe-points]]
frequency = 1600
voltage = 910
[[safe-points]]
frequency = 1700
voltage = 920
[[safe-points]]
frequency = 1750
voltage = 925
EOF
}

write_gpu_overclock_1850mhz() { cat > "$GPU_TMPFILE" <<'EOF'
[dbus]
enabled = true
[timing.intervals]
sample = 250
adjust = 100_000
[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10
[gpu]
set-method = "smu"
[frequency-range]
min = 500
max = 1850
[timing.ramp-rates]
normal = 1
burst = 50
[timing]
burst-samples = 60
down-events = 5
[frequency-thresholds]
adjust = 10
[load-target]
upper = 0.65
lower = 0.50
[temperature]
throttling = 80
throttling_recovery = 75
[[safe-points]]
frequency = 500
voltage = 700
[[safe-points]]
frequency = 1000
voltage = 800
[[safe-points]]
frequency = 1175
voltage = 850
[[safe-points]]
frequency = 1500
voltage = 900
[[safe-points]]
frequency = 1600
voltage = 910
[[safe-points]]
frequency = 1700
voltage = 920
[[safe-points]]
frequency = 1850
voltage = 930
EOF
}

write_gpu_overclock_2000mhz() { cat > "$GPU_TMPFILE" <<'EOF'
[dbus]
enabled = true
[timing.intervals]
sample = 250
adjust = 100_000
[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10
[gpu]
set-method = "smu"
[frequency-range]
min = 500
max = 2000
[timing.ramp-rates]
normal = 1
burst = 50
[timing]
burst-samples = 60
down-events = 5
[frequency-thresholds]
adjust = 10
[load-target]
upper = 0.65
lower = 0.50
[temperature]
throttling = 80
throttling_recovery = 75
[[safe-points]]
frequency = 500
voltage = 700
[[safe-points]]
frequency = 1000
voltage = 800
[[safe-points]]
frequency = 1175
voltage = 850
[[safe-points]]
frequency = 1500
voltage = 900
[[safe-points]]
frequency = 1600
voltage = 910
[[safe-points]]
frequency = 1700
voltage = 920
[[safe-points]]
frequency = 1850
voltage = 930
[[safe-points]]
frequency = 2000
voltage = 960
EOF
}

write_gpu_overclock_2100mhz() { cat > "$GPU_TMPFILE" <<'EOF'
[dbus]
enabled = true
[timing.intervals]
sample = 250
adjust = 100_000
[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10
[gpu]
set-method = "smu"
[frequency-range]
min = 500
max = 2100
[timing.ramp-rates]
normal = 1
burst = 50
[timing]
burst-samples = 60
down-events = 5
[frequency-thresholds]
adjust = 10
[load-target]
upper = 0.65
lower = 0.50
[temperature]
throttling = 80
throttling_recovery = 75
[[safe-points]]
frequency = 500
voltage = 700
[[safe-points]]
frequency = 1000
voltage = 800
[[safe-points]]
frequency = 1175
voltage = 850
[[safe-points]]
frequency = 1500
voltage = 900
[[safe-points]]
frequency = 1600
voltage = 910
[[safe-points]]
frequency = 1700
voltage = 920
[[safe-points]]
frequency = 1850
voltage = 930
[[safe-points]]
frequency = 2000
voltage = 960
[[safe-points]]
frequency = 2050
voltage = 980
[[safe-points]]
frequency = 2100
voltage = 1000
EOF
}

write_gpu_overclock_2300mhz() { cat > "$GPU_TMPFILE" <<'EOF'
[dbus]
enabled = true
[timing.intervals]
sample = 250
adjust = 100_000
[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10
[gpu]
set-method = "smu"
[frequency-range]
min = 500
max = 2300
[timing.ramp-rates]
normal = 1
burst = 50
[timing]
burst-samples = 60
down-events = 5
[frequency-thresholds]
adjust = 10
[load-target]
upper = 0.65
lower = 0.50
[temperature]
throttling = 90
throttling_recovery = 85
[[safe-points]]
frequency = 500
voltage = 700
[[safe-points]]
frequency = 1000
voltage = 800
[[safe-points]]
frequency = 1175
voltage = 850
[[safe-points]]
frequency = 1500
voltage = 900
[[safe-points]]
frequency = 1600
voltage = 910
[[safe-points]]
frequency = 1700
voltage = 920
[[safe-points]]
frequency = 1850
voltage = 930
[[safe-points]]
frequency = 2000
voltage = 960
[[safe-points]]
frequency = 2050
voltage = 980
[[safe-points]]
frequency = 2100
voltage = 1000
[[safe-points]]
frequency = 2125
voltage = 1020
[[safe-points]]
frequency = 2150
voltage = 1035
[[safe-points]]
frequency = 2200
voltage = 1050
[[safe-points]]
frequency = 2250
voltage = 1050
[[safe-points]]
frequency = 2300
voltage = 1075
EOF
}

write_gpu_overclock_2350mhz() { cat > "$GPU_TMPFILE" <<'EOF'
[dbus]
enabled = true
[timing.intervals]
sample = 250
adjust = 100_000
[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10
[gpu]
set-method = "smu"
[frequency-range]
min = 500
max = 2350
[timing.ramp-rates]
normal = 1
burst = 50
[timing]
burst-samples = 60
down-events = 5
[frequency-thresholds]
adjust = 10
[load-target]
upper = 0.65
lower = 0.50
[temperature]
throttling = 90
throttling_recovery = 85
[[safe-points]]
frequency = 500
voltage = 700
[[safe-points]]
frequency = 1000
voltage = 800
[[safe-points]]
frequency = 1175
voltage = 850
[[safe-points]]
frequency = 1500
voltage = 900
[[safe-points]]
frequency = 1600
voltage = 910
[[safe-points]]
frequency = 1700
voltage = 920
[[safe-points]]
frequency = 1850
voltage = 930
[[safe-points]]
frequency = 2000
voltage = 960
[[safe-points]]
frequency = 2050
voltage = 980
[[safe-points]]
frequency = 2100
voltage = 1000
[[safe-points]]
frequency = 2125
voltage = 1020
[[safe-points]]
frequency = 2150
voltage = 1035
[[safe-points]]
frequency = 2200
voltage = 1050
[[safe-points]]
frequency = 2250
voltage = 1050
[[safe-points]]
frequency = 2300
voltage = 1075
[[safe-points]]
frequency = 2350
voltage = 1100
EOF
}

install_cpu() {
    cp "$CPU_TMPFILE" "$CPU_DEST"
    systemctl daemon-reload
    systemctl restart "$CPU_SERVICE"
    if systemctl is-active --quiet "$CPU_SERVICE"; then
        print_info "CPU service is running."
    else
        print_error "CPU service failed to start! Check: journalctl -u $CPU_SERVICE"
    fi
}

install_gpu() {
    if [[ -f "${1:-}" ]]; then
        cp "$1" "$GPU_DEST"
    fi
    # Safety net: dbus.enabled must be true for the governor's D-Bus
    # interface to come up (community-reported default was left unset).
    if [[ -f "$GPU_DEST" ]] && ! grep -q '^\[dbus\]' "$GPU_DEST"; then
        printf '[dbus]\nenabled = true\n' | cat - "$GPU_DEST" > "${GPU_DEST}.tmp" && mv "${GPU_DEST}.tmp" "$GPU_DEST"
    fi
    systemctl restart "$GPU_SERVICE"
    if systemctl is-active --quiet "$GPU_SERVICE"; then
        print_info "GPU service is running with current config."
    else
        print_error "GPU service failed to start! Check: journalctl -u $GPU_SERVICE"
    fi
}

oc_edit_cpu_config_nano() {
    print_step "03-E" "Opening CPU Config in nano"
    if [[ ! -f "$CPU_DEST" ]]; then
        print_error "Configuration file not found at $CPU_DEST"
        return 1
    fi
    # nano is a full-screen program; stdout is a pipe (into tee, for the run
    # log) at this point, which breaks ncurses' keypad/cursor addressing and
    # makes arrow keys fail to navigate. Talk to the real terminal directly.
    nano "$CPU_DEST" < /dev/tty > /dev/tty 2>&1 || true
    if confirm "Would you like to restart the CPU service to apply changes?"; then
        systemctl daemon-reload
        systemctl restart "$CPU_SERVICE"
        if systemctl is-active --quiet "$CPU_SERVICE"; then
            print_success "CPU service restarted successfully."
            persist_snapshot_configs "performance" "$CPU_DEST" "$GPU_DEST"
        else
            print_error "CPU service failed to start! Check: journalctl -u $CPU_SERVICE"
        fi
    fi
}

oc_edit_gpu_config_nano() {
    print_step "03-E" "Opening GPU Config in nano"
    if [[ ! -f "$GPU_DEST" ]]; then
        print_error "Configuration file not found at $GPU_DEST"
        return 1
    fi
    # See the comment in oc_edit_cpu_config_nano: force the real TTY so
    # ncurses keypad/cursor addressing (arrow-key navigation) works.
    nano "$GPU_DEST" < /dev/tty > /dev/tty 2>&1 || true
    if confirm "Would you like to restart the GPU service to apply changes?"; then
        systemctl restart "$GPU_SERVICE"
        if systemctl is-active --quiet "$GPU_SERVICE"; then
            print_success "GPU service restarted successfully."
            persist_snapshot_configs "performance" "$CPU_DEST" "$GPU_DEST"
        else
            print_error "GPU service failed to start! Check: journalctl -u $GPU_SERVICE"
        fi
    fi
}

oc_run_bc250_detect() {
    print_step "03-D" "Run bc250-detect (auto-tune CPU undervolt)"
    echo -e "  ${DIM}Stress-tests the CPU at increasing frequency steps to find the lowest stable${RESET}"
    echo -e "  ${DIM}SMU voltage-curve scale ('scale' in overclock.conf) for your target frequency/voltage.${RESET}"
    echo -e "  ${YELLOW}⚠  Re-run this after enabling/disabling CPU Core Unlock (Install Manual 9) — the${RESET}"
    echo -e "  ${YELLOW}⚠  extra 2 cores change the CPU's power/thermal profile, so a scale tuned for 6c/12t${RESET}"
    echo -e "  ${YELLOW}⚠  may no longer be the safest/optimal undervolt for 8c/16t (or vice-versa).${RESET}"
    echo -e "  ${YELLOW}⚠  This runs a real stress test (several minutes) and pushes CPU voltage/frequency${RESET}"
    echo -e "  ${YELLOW}⚠  toward your limits. Monitor temperatures; abort (Ctrl+C) if anything looks wrong.${RESET}"
    echo ""

    export PATH="$PATH:/root/.local/bin:/home/deck/.local/bin"
    command -v pipx &>/dev/null && eval "$(pipx ensurepath --shell 2>/dev/null || true)" || true
    if ! command -v bc250-detect &>/dev/null; then
        fail_with_log "bc250-detect not found in PATH. Install the CPU Governor first (Install Manual 1)." "bc250-detect — missing"
        return 1
    fi
    if ! command -v stress &>/dev/null; then
        fail_with_log "'stress' not found in PATH — bc250-detect needs it to load the CPU. Install the CPU Governor first (Install Manual 1)." "bc250-detect — missing stress"
        return 1
    fi

    local cpu_dir="$EXTERNAL_DIR/bc250_smu_oc"
    if [[ ! -d "$cpu_dir" ]]; then
        fail_with_log "Vendored bc250_smu_oc repository not found at $cpu_dir." "bc250-detect — missing vendored repo"
        return 1
    fi

    local d_freq d_vid d_temp
    read -rp "$(echo -e "  ${BOLD}${WHITE}Target CPU frequency in MHz [3500]:${RESET} ")" d_freq
    d_freq="${d_freq:-3500}"
    read -rp "$(echo -e "  ${BOLD}${WHITE}CPU core voltage limit in mV [1000]:${RESET} ")" d_vid
    d_vid="${d_vid:-1000}"
    read -rp "$(echo -e "  ${BOLD}${WHITE}CPU/GPU temperature limit in °C [90]:${RESET} ")" d_temp
    d_temp="${d_temp:-90}"

    if ! [[ "$d_freq" =~ ^[0-9]+$ && "$d_vid" =~ ^[0-9]+$ && "$d_temp" =~ ^[0-9]+$ ]]; then
        print_error "Frequency, voltage and temperature must all be plain numbers."
        return 1
    fi

    if ! confirm "Run bc250-detect at ${d_freq}MHz / ${d_vid}mV / ${d_temp}°C now?"; then
        print_info "Cancelled."
        return 0
    fi

    cd "$cpu_dir" || return 1
    print_info "Running bc250-detect..."
    bc250-detect --frequency "$d_freq" --vid "$d_vid" --temp "$d_temp" --keep || {
        fail_with_log "bc250-detect failed or was interrupted — see output above." "bc250-detect"
        cd - >/dev/null || true
        return 1
    }
    print_success "bc250-detect finished. New settings saved to $cpu_dir/overclock.conf."

    if confirm "Apply this new profile now and (re)install the CPU governor service?"; then
        bc250-apply --install overclock.conf || {
            fail_with_log "bc250-apply failed." "bc250-detect — apply"
            cd - >/dev/null || true
            return 1
        }
        cd - >/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable --now bc250-smu-oc.service || {
            fail_with_log "Failed to enable/restart the CPU governor service." "bc250-detect — enable service"
            return 1
        }
        persist_snapshot_configs "performance" "$CPU_DEST" "$GPU_DEST"
        print_success "CPU governor updated with the new bc250-detect profile."
    else
        cd - >/dev/null || true
        print_info "Not applied. Edit $cpu_dir/overclock.conf and run 'bc250-apply --install overclock.conf' yourself, or re-run this option (D) later."
    fi
}

oc_active_profile() {
    local cpu_freq="" gpu_freq="" cpu_temp="" label=""
    if [[ -f "$CPU_DEST" ]]; then
        cpu_freq=$(awk -F'= ' '/^frequency/{print $2}' "$CPU_DEST" 2>/dev/null | tr -d ' ')
        cpu_temp=$(awk -F'= ' '/^max_temperature/{print $2}' "$CPU_DEST" 2>/dev/null | tr -d ' ')
    fi
    if [[ -f "$GPU_DEST" ]]; then
        gpu_freq=$(awk -F'= ' '/^frequency/{print $2}' "$GPU_DEST" 2>/dev/null | tr -d ' ' | tail -1)
    fi
    if [[ -n "$cpu_freq" && -n "$gpu_freq" ]]; then
        label="CPU ${cpu_freq}MHz / GPU ${gpu_freq}MHz"
        [[ -n "$cpu_temp" ]] && label+=" / max ${cpu_temp}°C"
        echo "$label"
    else
        echo "Unknown (configs not found)"
    fi
}

oc_match_preset() {
    local cpu_freq gpu_freq gpu_volt
    [[ ! -f "$CPU_DEST" || ! -f "$GPU_DEST" ]] && echo "Unknown" && return
    cpu_freq=$(awk -F'= ' '/^frequency/{print $2}' "$CPU_DEST" 2>/dev/null | tr -d ' ')
    gpu_freq=$(awk -F'= ' '/^frequency/{print $2}' "$GPU_DEST" 2>/dev/null | tr -d ' ' | tail -1)
    gpu_volt=$(awk -F'= ' '/^voltage/{print $2}' "$GPU_DEST" 2>/dev/null | tr -d ' ' | tail -1)

    local preset_cpu_freqs=(3500 3500 3500 3500 3500 3500 3500 3850 4000)
    local preset_gpu_freqs=(1500 1600 1600 1750 1850 2000 2100 2100 2350)
    local preset_gpu_volts=("" 910 856 "" "" "" "" "" "")

    for i in "${!PRESET_NAMES[@]}"; do
        if [[ "$cpu_freq" == "${preset_cpu_freqs[$i]}" && "$gpu_freq" == "${preset_gpu_freqs[$i]}" ]]; then
            if [[ -n "${preset_gpu_volts[$i]}" && "$gpu_volt" != "${preset_gpu_volts[$i]}" ]]; then
                continue
            fi
            echo "${PRESET_NAMES[$i]}"
            return
        fi
    done
    echo "Custom"
}

PRESET_NAMES=("Stock" "Mild" "Mild (undervolt)" "Moderate" "Strong" "Aggressive" "Extreme I ⚠" "Extreme II ⚠" "Extreme III ⚠")
PRESET_DESCS=(
    "CPU 3.5GHz, GPU 1500MHz — 80°C"
    "CPU 3.5GHz, GPU 1600MHz — 80°C"
    "CPU 3.5GHz, GPU 1600MHz undervolt — 80°C"
    "CPU 3.5GHz, GPU 1750MHz — 80°C"
    "CPU 3.5GHz, GPU 1850MHz — 80°C"
    "CPU 3.5GHz, GPU 2000MHz — 80°C"
    "CPU 3.5GHz, GPU 2100MHz — 80°C"
    "CPU 3.85GHz, GPU 2100MHz — 80°C"
    "CPU 4GHz, GPU 2350MHz — 90°C"
)
PRESET_CPU_WRITERS=(write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_overclock_3_85ghz write_cpu_overclock_4ghz)
PRESET_GPU_WRITERS=(write_gpu_overclock_1500mhz write_gpu_overclock_1600mhz write_gpu_overclock_1600mhz_undervolt write_gpu_overclock_1750mhz write_gpu_overclock_1850mhz write_gpu_overclock_2000mhz write_gpu_overclock_2100mhz write_gpu_overclock_2100mhz write_gpu_overclock_2350mhz)
PRESET_HIGH_RISK_THRESHOLD=6

CPU_NAMES=("Undervolt 3.5 GHz (stock)" "Overclock 3.85 GHz" "Overclock 4 GHz")
CPU_DESCS=("3500 MHz, scale -22, max 80°C" "3850 MHz, scale -30, max 90°C" "4000 MHz, scale -37, max 90°C")
CPU_WRITERS=(write_cpu_undervolt_3_5ghz write_cpu_overclock_3_85ghz write_cpu_overclock_4ghz)

GPU_NAMES=("1500 MHz" "1600 MHz" "1750 MHz" "1850 MHz" "2000 MHz" "2100 MHz ⚠" "2300 MHz ⚠" "2350 MHz ⚠")
GPU_DESCS=(
    "throttle 80°C — conservative"
    "throttle 80°C — moderate-low"
    "throttle 80°C — moderate"
    "throttle 80°C — moderate-high"
    "throttle 80°C — standard ceiling"
    "throttle 80°C — HIGH RISK"
    "throttle 90°C — HIGH RISK"
    "throttle 90°C — HIGH RISK"
)
GPU_WRITERS=(write_gpu_overclock_1500mhz write_gpu_overclock_1600mhz write_gpu_overclock_1750mhz write_gpu_overclock_1850mhz write_gpu_overclock_2000mhz write_gpu_overclock_2100mhz write_gpu_overclock_2300mhz write_gpu_overclock_2350mhz)
GPU_HIGH_RISK_THRESHOLD=5

oc_warn_high_risk() {
    echo ""
    echo -e "  ${BOLD}${RED}⚠  WARNING: HIGH-RISK OVERCLOCK PROFILE${RESET}"
    echo ""
    echo -e "  ${WHITE}Unlocking additional compute units (38-40 CU) significantly increases"
    echo -e "  power draw. Combined with high GPU frequencies, this can exceed the"
    echo -e "  safe capacity of your power delivery hardware. The 8-pin connector"
    echo -e "  and its wiring are particularly vulnerable — overloading them can"
    echo -e "  cause the connector to melt or the wires to overheat, resulting in"
    echo -e "  permanent damage or fire risk."
    echo ""
    echo -e "  Only proceed if you have verified your PSU, cabling, and cooling"
    echo -e "  can handle the increased load of your CU configuration.${RESET}"
    echo ""
    echo -e "  ${DIM}Type ${RESET}${BOLD}${YELLOW}OC${RESET}${DIM} to accept full responsibility and proceed, or press Enter to cancel.${RESET}"
    echo ""
    read -rp "  → " ack
    if [[ "$ack" == "OC" ]]; then
        return 0
    else
        print_info "Cancelled."
        return 1
    fi
}

oc_print_summary() {
    local cpu_name="$1" cpu_desc="$2" gpu_name="$3" gpu_desc="$4"
    local custom_temp="${5:-}"
    echo ""
    echo -e "  ${BOLD}${WHITE}Summary:${RESET}"
    echo -e "  ${CYAN}CPU${RESET}  ${cpu_name} — ${cpu_desc}"
    echo -e "  ${CYAN}GPU${RESET}  ${gpu_name} — ${gpu_desc}"
    [[ -n "$custom_temp" ]] && echo -e "  ${CYAN}TMP${RESET}  Temperature override: ${custom_temp}°C (CPU max & GPU throttle)"
    echo ""
}

oc_apply_preset() {
    local idx=$(( $1 - 1 ))
    local name="${PRESET_NAMES[$idx]}"
    local desc="${PRESET_DESCS[$idx]}"

    echo ""
    echo -e "  ${BOLD}${WHITE}Selected:${RESET} ${name} — ${desc}"
    echo ""

    if (( idx >= PRESET_HIGH_RISK_THRESHOLD )); then
        oc_warn_high_risk || return 0
    fi

    if ! confirm "Apply this preset?"; then
        print_info "Cancelled."
        return 0
    fi

    echo ""
    print_info "Writing and installing CPU config..."
    "${PRESET_CPU_WRITERS[$idx]}"
    install_cpu

    print_info "Writing and installing GPU config..."
    "${PRESET_GPU_WRITERS[$idx]}"
    install_gpu "$GPU_TMPFILE"

    echo ""
    print_success "Preset '${name}' applied!"
    persist_snapshot_configs "performance" "$CPU_DEST" "$GPU_DEST"
    echo -e "  ${CYAN}CPU${RESET}  $(awk -F'= ' '/^frequency/{print $2}' "$CPU_DEST" | tr -d ' ')MHz"
    echo -e "  ${CYAN}GPU${RESET}  $(awk -F'= ' '/^frequency/{print $2}' "$GPU_DEST" | tr -d ' ' | tail -1)MHz"
    echo -e "  ${CYAN}TMP${RESET}  $(awk -F'= ' '/^max_temperature/{print $2}' "$CPU_DEST" | tr -d ' ')°C"
    echo ""
}

oc_prompt_temperature() {
    local default="$1"
    while true; do
        read -rp "$(echo -e "  ${WHITE}Max temperature °C (60-100, default ${default}, 0=cancel):${RESET} ")" t
        [[ "$t" =~ ^[0-9]+$ ]] || { echo "  Invalid input."; continue; }
        [[ "$t" -eq 0 ]] && return 1
        (( t >= 60 && t <= 100 )) || { echo "  Out of range (60-100)."; continue; }
        TEMP_RESULT="$t"
        return 0
    done
}

oc_apply_custom() {
    echo ""
    print_section "CPU Profiles"
    for i in "${!CPU_NAMES[@]}"; do
        print_item "$((i+1))" "${CPU_NAMES[$i]}" "${CPU_DESCS[$i]}"
    done
    echo ""
    read -rp "$(echo -e "  ${BOLD}${WHITE}Select CPU profile (0=cancel):${RESET} ")" cpu_choice
    [[ "$cpu_choice" =~ ^[0-9]+$ ]] || { print_error "Invalid input."; return 1; }
    [[ "$cpu_choice" -eq 0 ]] && { print_info "Cancelled."; return 0; }
    (( cpu_choice >= 1 && cpu_choice <= ${#CPU_NAMES[@]} )) || { print_error "Invalid selection."; return 1; }

    echo ""
    print_section "GPU Profiles"
    for i in "${!GPU_NAMES[@]}"; do
        print_item "$((i+1))" "${GPU_NAMES[$i]}" "${GPU_DESCS[$i]}"
    done
    echo ""
    read -rp "$(echo -e "  ${BOLD}${WHITE}Select GPU profile (0=cancel):${RESET} ")" gpu_choice
    [[ "$gpu_choice" =~ ^[0-9]+$ ]] || { print_error "Invalid input."; return 1; }
    [[ "$gpu_choice" -eq 0 ]] && { print_info "Cancelled."; return 0; }
    (( gpu_choice >= 1 && gpu_choice <= ${#GPU_NAMES[@]} )) || { print_error "Invalid selection."; return 1; }

    local cpu_idx=$(( cpu_choice - 1 )) gpu_idx=$(( gpu_choice - 1 ))
    local custom_temp=""

    if (( gpu_idx >= GPU_HIGH_RISK_THRESHOLD )); then
        oc_warn_high_risk || return 0
    fi

    echo ""
    read -rp "$(echo -e "  ${WHITE}Override temperature limit? [y/N]:${RESET} ")" yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        local default_temp=80
        (( gpu_idx >= 2 )) && default_temp=90
        oc_prompt_temperature "$default_temp" || { print_info "Cancelled."; return 0; }
        custom_temp="$TEMP_RESULT"
    fi

    oc_print_summary \
        "${CPU_NAMES[$cpu_idx]}" "${CPU_DESCS[$cpu_idx]}" \
        "${GPU_NAMES[$gpu_idx]}" "${GPU_DESCS[$gpu_idx]}" \
        "$custom_temp"

    if ! confirm "Apply this custom profile?"; then
        print_info "Cancelled."
        return 0
    fi

    echo ""
    print_info "Writing and installing CPU config..."
    "${CPU_WRITERS[$cpu_idx]}"
    [[ -n "$custom_temp" ]] && sed -i "s/^max_temperature = .*/max_temperature = ${custom_temp}/" "$CPU_TMPFILE"
    install_cpu

    print_info "Writing and installing GPU config..."
    "${GPU_WRITERS[$gpu_idx]}"
    if [[ -n "$custom_temp" ]]; then
        local recovery=$(( custom_temp - 5 ))
        sed -i "s/^throttling = .*/throttling = ${custom_temp}/" "$GPU_TMPFILE"
        sed -i "s/^throttling_recovery = .*/throttling_recovery = ${recovery}/" "$GPU_TMPFILE"
    fi
    install_gpu "$GPU_TMPFILE"

    echo ""
    print_success "Custom profile applied!"
    persist_snapshot_configs "performance" "$CPU_DEST" "$GPU_DEST"
    echo -e "  ${CYAN}CPU${RESET}  $(awk -F'= ' '/^frequency/{print $2}' "$CPU_DEST" | tr -d ' ')MHz  /  max $(awk -F'= ' '/^max_temperature/{print $2}' "$CPU_DEST" | tr -d ' ')°C"
    echo -e "  ${CYAN}GPU${RESET}  $(awk -F'= ' '/^frequency/{print $2}' "$GPU_DEST" | tr -d ' ' | tail -1)MHz  /  throttle $(awk -F'= ' '/^throttling /{print $2}' "$GPU_DEST" | tr -d ' ')°C"
    echo ""
}

run_overclock_menu() {
    while true; do
        print_banner
        print_section "Performance Profile Menu"
        echo -e "  ${DIM}Active: $(oc_match_preset) — $(oc_active_profile)${RESET}"
        echo ""
        print_section "Standard Profiles"
        for i in "${!PRESET_NAMES[@]}"; do
            (( i >= PRESET_HIGH_RISK_THRESHOLD )) && continue
            print_item "$((i+1))" "${PRESET_NAMES[$i]}" "${PRESET_DESCS[$i]}"
        done
        echo ""
        print_section "High-Risk Profiles  ⚠  Requires OC acknowledgement"
        for i in "${!PRESET_NAMES[@]}"; do
            (( i < PRESET_HIGH_RISK_THRESHOLD )) && continue
            print_item "$((i+1))" "${PRESET_NAMES[$i]}" "${PRESET_DESCS[$i]}"
        done
        echo ""
        print_section "Advanced"
        print_item "C" "Custom"          "Mix & match CPU and GPU profiles"
        print_item "E" "Edit GPU Config" "Manually edit GPU config with nano"
        print_item "F" "Edit CPU Config" "Manually edit CPU config with nano"
        print_item "D" "Run bc250-detect" "Auto-tune CPU undervolt (re-run after CPU Core Unlock)"
        print_item "0" "Back"            ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" oc_choice

        case "${oc_choice^^}" in
            C) oc_apply_custom;         press_enter ;;
            E) oc_edit_gpu_config_nano; press_enter ;;
            F) oc_edit_cpu_config_nano; press_enter ;;
            D) oc_run_bc250_detect;     press_enter ;;
            0) return 0 ;;
            *)
                if [[ "$oc_choice" =~ ^[0-9]+$ ]] && (( oc_choice >= 1 && oc_choice <= ${#PRESET_NAMES[@]} )); then
                    oc_apply_preset "$oc_choice"
                    press_enter
                else
                    print_error "Invalid selection: '$oc_choice'"
                    sleep 1
                fi
                ;;
        esac
    done
}

# ==============================================================================
# STATUS
# ==============================================================================

run_status() {
    print_banner
    print_section "System Status"

    local CPU_CONF="/etc/bc250-smu-oc.conf"
    local GPU_CONF="/etc/cyan-skillfish-governor-smu/config.toml"

    echo -e "  ${BOLD}${YELLOW}Kernel${RESET}            $(uname -r)"
    echo ""

    print_section "Overclock"
    echo -e "  ${DIM}Active: $(oc_match_preset) — $(oc_active_profile)${RESET}"
    echo ""

    if [[ -f "$CPU_CONF" ]]; then
        local cpu_freq cpu_scale cpu_temp
        cpu_freq=$(awk -F'= ' '/^frequency/{print $2}' "$CPU_CONF" | tr -d ' ')
        cpu_scale=$(awk -F'= ' '/^scale/{print $2}' "$CPU_CONF" | tr -d ' ')
        cpu_temp=$(awk -F'= ' '/^max_temperature/{print $2}' "$CPU_CONF" | tr -d ' ')
        echo -e "  ${CYAN}CPU Profile${RESET}       ${cpu_freq}MHz  scale ${cpu_scale}  max ${cpu_temp}°C"
    else
        echo -e "  ${CYAN}CPU Profile${RESET}       ${DIM}config not found${RESET}"
    fi

    if [[ -f "$GPU_CONF" ]]; then
        local gpu_freq gpu_throttle
        gpu_freq=$(awk -F'= ' '/^frequency/{print $2}' "$GPU_CONF" | tr -d ' ' | tail -1)
        gpu_throttle=$(awk -F'= ' '/^throttling /{print $2}' "$GPU_CONF" | tr -d ' ')
        echo -e "  ${CYAN}GPU Profile${RESET}       ${gpu_freq}MHz  throttle ${gpu_throttle}°C"
    else
        echo -e "  ${CYAN}GPU Profile${RESET}       ${DIM}config not found${RESET}"
    fi

    local cpu_svc_enabled cpu_svc_result gpu_svc_state
    cpu_svc_enabled=$(systemctl is-enabled bc250-smu-oc.service 2>/dev/null || echo "disabled")
    cpu_svc_result=$(systemctl show bc250-smu-oc.service --property=ExecMainStatus --value 2>/dev/null || echo "unknown")
    gpu_svc_state=$(systemctl is-active cyan-skillfish-governor-smu.service 2>/dev/null || echo "unknown")

    local cpu_icon gpu_icon cpu_label
    if [[ "$cpu_svc_enabled" == "enabled" && "$cpu_svc_result" == "0" ]]; then
        cpu_icon="$ICON_OK"; cpu_label="${GREEN}enabled (applied successfully)${RESET}"
    elif [[ "$cpu_svc_enabled" == "enabled" ]]; then
        cpu_icon="$ICON_WARN"; cpu_label="${YELLOW}enabled (exit code: ${cpu_svc_result})${RESET}"
    else
        cpu_icon="$ICON_WARN"; cpu_label="${YELLOW}disabled${RESET}"
    fi
    if [[ "$gpu_svc_state" == "active" ]]; then gpu_icon="$ICON_OK"; else gpu_icon="$ICON_WARN"; fi
    echo -e "  ${CYAN}CPU Service${RESET}       ${cpu_icon} ${cpu_label}"
    echo -e "  ${CYAN}GPU Service${RESET}       ${gpu_icon} $([[ "$gpu_svc_state" == "active" ]] && echo -e "${GREEN}${gpu_svc_state}${RESET}" || echo -e "${YELLOW}${gpu_svc_state}${RESET}")"

    if mitigations_currently_off; then
        echo -e "  ${CYAN}CPU Mitigations${RESET}   ${ICON_OK} ${GREEN}disabled${RESET} (mitigations=off set in GRUB)"
    else
        echo -e "  ${CYAN}CPU Mitigations${RESET}   ${ICON_WARN} ${YELLOW}enabled${RESET} (default — disable for max performance)"
    fi

    if core_unlock_persist_installed; then
        if core_unlock_cores_active; then
            echo -e "  ${CYAN}CPU Core Unlock${RESET}   ${ICON_OK} ${GREEN}8c/16t active${RESET} ($(nproc --all) threads, boot service enabled)"
        else
            local core_unlock_auto_hint="reboot to pick up all 8 cores"
            [[ -f "$CORE_UNLOCK_CONF" ]] && grep -q '^AUTO_REBOOT=yes' "$CORE_UNLOCK_CONF" 2>/dev/null \
                && core_unlock_auto_hint="auto-reboot enabled, should self-correct shortly"
            echo -e "  ${CYAN}CPU Core Unlock${RESET}   ${ICON_WARN} ${YELLOW}boot service enabled, still 6c/12t${RESET} ($core_unlock_auto_hint)"
        fi
    else
        if core_unlock_cores_active; then
            echo -e "  ${CYAN}CPU Core Unlock${RESET}   ${YELLOW}boot service removed, but 8c/16t still active${RESET} ($(nproc --all) threads — mask persists until a real cold power-off)"
        else
            echo -e "  ${CYAN}CPU Core Unlock${RESET}   ${DIM}not installed (6c/12t, SteamOS default)${RESET}"
        fi
    fi

    if ram_split_installed; then
        local uma_now
        uma_now=$(ram_split_current_uma 2>/dev/null)
        echo -e "  ${CYAN}RAM/VRAM Split${RESET}    ${ICON_OK} ${GREEN}UMA_SIZE=${uma_now:-?}MB${RESET}, ttm.pages_limit ceiling active"
    else
        echo -e "  ${CYAN}RAM/VRAM Split${RESET}    ${DIM}not installed (stock ${RAM_SPLIT_STOCK_UMA_MB}MB split, SteamOS default)${RESET}"
    fi

    echo ""
    print_section "Swap & ZRAM/ZSWAP"

    local swap_mb; swap_mb=$(swapfile_size_mb)
    if (( swap_mb > SWAPFILE_STOCK_SIZE_MB )); then
        echo -e "  ${CYAN}Swapfile${RESET}          ${ICON_OK} ${GREEN}$(( swap_mb / 1024 ))G${RESET} at $SWAPFILE_PATH"
    else
        echo -e "  ${CYAN}Swapfile${RESET}          ${DIM}${swap_mb}M (SteamOS default) at $SWAPFILE_PATH${RESET}"
    fi

    if zram_currently_disabled && zswap_currently_on; then
        echo -e "  ${CYAN}ZRAM/ZSWAP${RESET}        ${ICON_OK} ${GREEN}ZRAM off / ZSWAP on${RESET} (lz4)"
    elif zram_currently_disabled; then
        echo -e "  ${CYAN}ZRAM/ZSWAP${RESET}        ${ICON_WARN} ${YELLOW}ZRAM off / ZSWAP configured but inactive${RESET}"
    else
        echo -e "  ${CYAN}ZRAM/ZSWAP${RESET}        ${DIM}ZRAM on / ZSWAP off (SteamOS default)${RESET}"
    fi

    echo ""
    print_section "Sensors & Fan Control"

    local sens_driver sens_icon sens_color
    sens_driver="$(sensors_active_driver)"
    case "$sens_driver" in
        nct6687) sens_icon="$ICON_OK";   sens_color="$GREEN";  sens_driver="nct6687 (loaded — full PWM control)" ;;
        nct6683) sens_icon="$ICON_WARN"; sens_color="$YELLOW"; sens_driver="nct6683 (loaded — read-only)" ;;
        *)       sens_icon="$ICON_WARN"; sens_color="$YELLOW"; sens_driver="not loaded" ;;
    esac
    echo -e "  ${CYAN}Sensor Driver${RESET}     ${sens_icon} ${sens_color}${sens_driver}${RESET}"

    local cc_svc_state cc_icon cc_color
    cc_svc_state=$(systemctl is-active coolercontrold.service 2>/dev/null || echo "not installed")
    if [[ "$cc_svc_state" == "active" ]]; then cc_icon="$ICON_OK"; cc_color="$GREEN"; else cc_icon="$ICON_WARN"; cc_color="$YELLOW"; fi
    echo -e "  ${CYAN}CoolerControl${RESET}     ${cc_icon} ${cc_color}${cc_svc_state}${RESET}"

    local xbox_icon xbox_color xbox_label
    xbox_label="$(xbox_adapter_status_label)"
    case "$xbox_label" in
        loaded) xbox_icon="$ICON_OK"; xbox_color="$GREEN" ;;
        "installed (not loaded)") xbox_icon="$ICON_WARN"; xbox_color="$YELLOW" ;;
        *) xbox_icon="$DIM"; xbox_color="$DIM" ;;
    esac
    echo -e "  ${CYAN}Xbox Wireless Adapter${RESET} ${xbox_icon} ${xbox_color}${xbox_label}${RESET}"

    echo ""
    print_section "Community Fixes"

    local acpi_icon acpi_color acpi_label
    if acpi_fix_installed; then
        if compgen -G /sys/devices/system/cpu/cpu0/cpufreq >/dev/null; then
            acpi_icon="$ICON_OK"; acpi_color="$GREEN"; acpi_label="active (C/P-states present)"
        else
            acpi_icon="$ICON_WARN"; acpi_color="$YELLOW"; acpi_label="installed — reboot pending"
        fi
    else
        acpi_icon="$DIM"; acpi_color="$DIM"; acpi_label="not installed"
    fi
    echo -e "  ${CYAN}ACPI Fix${RESET}          ${acpi_icon} ${acpi_color}${acpi_label}${RESET}"

    local audio_icon audio_color audio_label resolved_amdgpu
    resolved_amdgpu=$(modinfo -F filename amdgpu 2>/dev/null || echo "")
    if [[ "$resolved_amdgpu" == *"/updates/"* ]]; then
        audio_icon="$ICON_OK"; audio_color="$GREEN"; audio_label="patched module active"
    else
        audio_icon="$DIM"; audio_color="$DIM"; audio_label="stock amdgpu.ko"
    fi
    echo -e "  ${CYAN}DP Audio/Video Fix${RESET} ${audio_icon} ${audio_color}${audio_label}${RESET}"

    # The kernel side has no runtime marker to check (unlike the upstream
    # Fedora installer, our direct module-replace approach doesn't add a
    # /proc/cmdline flag or /sys/module note), so kernel status relies on
    # persist_state (set by install_gfx1013_fix / detected retroactively by
    # persist_detect_and_record_installed). Mesa status is verified directly
    # from disk since the ICD json is a reliable on-disk signal.
    local gfx1013_icon gfx1013_color gfx1013_label gfx1013_mesa_ok=0
    compgen -G "/opt/bc250-gfx1013/*/share/vulkan/icd.d/radeon_icd.x86_64.json" >/dev/null 2>&1 && gfx1013_mesa_ok=1
    if persist_state_has "gfx1013" && (( gfx1013_mesa_ok )); then
        if [[ "$resolved_amdgpu" == *"/updates/"* ]]; then
            gfx1013_icon="$ICON_OK"; gfx1013_color="$GREEN"; gfx1013_label="kernel + Mesa/RADV active"
        else
            gfx1013_icon="$ICON_WARN"; gfx1013_color="$YELLOW"; gfx1013_label="installed — reboot pending"
        fi
    elif persist_state_has "gfx1013" || (( gfx1013_mesa_ok )); then
        gfx1013_icon="$ICON_WARN"; gfx1013_color="$YELLOW"; gfx1013_label="incomplete (kernel or Mesa half missing)"
    else
        gfx1013_icon="$DIM"; gfx1013_color="$DIM"; gfx1013_label="not installed"
    fi
    echo -e "  ${CYAN}GFX1013 Compute Fix${RESET} ${gfx1013_icon} ${gfx1013_color}${gfx1013_label}${RESET}"

    local wifi_icon wifi_color wifi_label
    if aic8800_installed; then
        wifi_icon="$ICON_OK"; wifi_color="$GREEN"; wifi_label="installed"
    else
        wifi_icon="$DIM"; wifi_color="$DIM"; wifi_label="not installed"
    fi
    echo -e "  ${CYAN}AIC8800 WiFi Driver${RESET} ${wifi_icon} ${wifi_color}${wifi_label}${RESET}"

    local ds5_icon ds5_color ds5_label resolved_hp
    resolved_hp=$(modinfo -F filename hid_playstation 2>/dev/null || echo "")
    if ds5_bridge_fix_installed; then
        if [[ "$resolved_hp" == *"/updates/"* ]]; then
            ds5_icon="$ICON_OK"; ds5_color="$GREEN"; ds5_label="patched module active"
        else
            ds5_icon="$ICON_WARN"; ds5_color="$YELLOW"; ds5_label="installed — reboot pending"
        fi
    else
        ds5_icon="$DIM"; ds5_color="$DIM"; ds5_label="not installed"
    fi
    echo -e "  ${CYAN}DS5 Bridge Fix${RESET}     ${ds5_icon} ${ds5_color}${ds5_label}${RESET}"

    local chord_icon chord_color chord_label
    if ds5_chord_vdf_patched 2>/dev/null; then
        chord_icon="$ICON_OK"; chord_color="$GREEN"; chord_label="patched (QAM enabled)"
    else
        chord_icon="$DIM"; chord_color="$DIM"; chord_label="not patched"
    fi
    echo -e "  ${CYAN}DS5 Chord Config${RESET}  ${chord_icon} ${chord_color}${chord_label}${RESET}"

    local cec_icon cec_color cec_label
    if cec_control_installed; then
        cec_icon="$ICON_OK"; cec_color="$GREEN"; cec_label="configured"
    else
        cec_icon="$DIM"; cec_color="$DIM"; cec_label="not configured"
    fi
    echo -e "  ${CYAN}HDMI-CEC / TV Control${RESET} ${cec_icon} ${cec_color}${cec_label}${RESET}"

    echo ""
    print_section "Audio"

    local ac3_icon ac3_color ac3_label
    if ac3_surround_installed; then
        local uid ac3_active
        uid=$(id -u "$REAL_USER")
        ac3_active=$(sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" bash "$AC3_USER_SCRIPT" detect 2>/dev/null | grep "^AC3_ACTIVE=" | cut -d= -f2)
        if [[ "$ac3_active" == "yes" ]]; then
            ac3_icon="$ICON_OK"; ac3_color="$GREEN"; ac3_label="installed — AC-3 profile active"
        else
            ac3_icon="$ICON_WARN"; ac3_color="$YELLOW"; ac3_label="installed — profile not active (stereo)"
        fi
    else
        ac3_icon="$DIM"; ac3_color="$DIM"; ac3_label="not installed"
    fi
    echo -e "  ${CYAN}AC-3 Surround${RESET}      ${ac3_icon} ${ac3_color}${ac3_label}${RESET}"

    echo ""
    echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

install_all_progress_init() { : > "$INSTALL_ALL_PROGRESS"; }
install_all_progress_done() { echo "$1" >> "$INSTALL_ALL_PROGRESS"; }
install_all_progress_is_done() { [[ -f "$INSTALL_ALL_PROGRESS" ]] && grep -Fxq "$1" "$INSTALL_ALL_PROGRESS"; }
install_all_progress_clear() { rm -f "$INSTALL_ALL_PROGRESS"; }

run_install_all_step() {
    local step_num="$1"; shift
    local total_steps="$1"; shift
    local description="$1"; shift
    local step_function="$1"; shift

    if install_all_progress_is_done "$step_function"; then
        print_info "Skipping already completed step: $step_function"
        return 0
    fi

    print_step "$(printf "%02d" $step_num)" "[$step_num/$total_steps] $description"
    "$step_function" "$@" || { print_error "Step $step_function failed — saved progress so you can resume later."; return 1; }
    install_all_progress_done "$step_function"
    echo ""
}

run_install_all() {
    print_step "00" "Install All — Swap/ZSWAP + Mitigations + ACPI + RAM/VRAM + Sensor PWM + CoolerControl + Core Unlock + Validation + CPU/GPU Governor + CU Live Manager + Combined Fix + AC-3 Surround"
    if [[ -f "$INSTALL_ALL_PROGRESS" ]]; then
        if confirm "A previous Install All did not finish. Continue from where it stopped?"; then
            print_info "Resuming previous Install All..."
        else
            print_info "Starting a fresh Install All."
            install_all_progress_init
        fi
    else
        install_all_progress_init
    fi

    run_install_all_step 1 14 "Configuring Swap" run_configure_swap auto || return 1
    run_install_all_step 2 14 "Enabling ZSWAP/Disabling ZRAM" run_zram_zswap_toggle auto || return 1
    run_install_all_step 3 14 "Disabling CPU Mitigations" run_disable_mitigations auto || return 1
    run_install_all_step 4 14 "Installing ACPI Fix" install_acpi_fix || return 1
    run_install_all_step 5 14 "Installing RAM/VRAM Split" install_ram_split auto || return 1
    run_install_all_step 6 14 "Ensuring Sensor PWM Driver" ensure_sensors_pwm_installed || return 1
    run_install_all_step 7 14 "Ensuring CoolerControl Installation" ensure_coolercontrol_installed || return 1
    run_install_all_step 8 14 "Installing Core Unlock" install_core_unlock auto || return 1
    run_install_all_step 9 14 "Validating Core Unlock" validate_core_unlock || return 1
    run_install_all_step 10 14 "Installing CPU Governor" run_cpu_governor || return 1
    run_install_all_step 11 14 "Installing GPU Governor" run_gpu_governor || return 1
    run_install_all_step 12 14 "Installing CU Live Manager" run_cu_live_manager || return 1
    run_install_all_step 13 14 "Installing Combined Fix" install_combined_fix || return 1
    run_install_all_step 14 14 "Installing AC-3 Surround" install_ac3_surround auto || return 1

    install_all_progress_clear
    print_success "Install All completed!"
}

run_revert_all() {
    print_step "00-U" "Revert All — CPU/GPU Governor + Mitigations + Swap/ZSWAP + ACPI + Combined Fix + AC-3 + Core Unlock + RAM/VRAM"
    run_revert_cpu_governor
    echo ""
    run_revert_gpu_governor
    echo ""
    run_revert_mitigations auto
    echo ""
    run_revert_swap auto
    echo ""
    run_revert_zram_zswap auto
    echo ""
    run_revert_acpi_fix
    echo ""
    run_revert_ac3_surround
    echo ""
    run_revert_ds5_bridge_fix
    echo ""
    run_revert_ds5_chord_vdf
    echo ""
    run_revert_core_unlock
    echo ""
    run_revert_ram_split
    echo ""
    run_revert_gfx1013_fix
    echo ""
    run_revert_aic8800_wifi
}

run_install_manual() {
    while true; do
        print_banner
        print_section "Install / Revert Manual"
        echo -e "  ${DIM}Same components as Install All / Revert All — pick them one at a time.${RESET}"
        echo ""
        print_item "1"  "Install CPU Governor"          "bc250-smu-oc CPU overclock service"
        print_item "1R" "Revert CPU Governor"           "Remove bc250-smu-oc"
        print_item "2"  "Install GPU Governor"          "cyan-skillfish GPU governor service"
        print_item "2R" "Revert GPU Governor"           "Remove cyan-skillfish-governor-smu"
        print_item "3"  "Disable CPU Mitigations"        "Add mitigations=off to GRUB"
        print_item "3R" "Re-enable CPU Mitigations"      "Remove mitigations=off from GRUB"
        print_item "4"  "Configure Swap"                "Resize swapfile, set vm.swappiness"
        print_item "4R" "Revert Swap to Default"         "Back to stock ${SWAPFILE_STOCK_SIZE_MB}M / swappiness=60"
        print_item "5"  "Disable ZRAM & Enable ZSWAP"    "lz4, 25% pool — needs reboot"
        print_item "5R" "Revert ZRAM/ZSWAP to Default"   "Back to stock ZRAM — needs reboot"
        print_item "6"  "Install ACPI Fix"               "CPU C-/P-states"
        print_item "6R" "Revert ACPI Fix"                 "Remove ACPI fix"
        print_item "7"  "CU Unlock Live"                 "Open bc250-cu-live-manager.sh (WGP/CU live manager)"
        print_item "8"  "CPU Core Unlock"                "⚠  EXPERIMENTAL: 6c/12t -> 8c/16t, needs reboot"
        print_item "8R" "Revert CPU Core Unlock"          "Remove boot-time re-apply service"
        print_item "9"  "Install RAM/VRAM Split"        "UMA_SIZE=512 + ttm.pages_limit dynamic ceiling"
        print_item "9R" "Revert RAM/VRAM Split"         "Restore stock ${RAM_SPLIT_STOCK_UMA_MB}MB split"
        print_item "10"  "Install Combined Audio+GFX1013" "⚠  Single kernel build (recommended): DP audio + async compute + Mesa/RADV + FSR4 + mesh/task"
        print_item "10R" "Revert Combined Fix"           "Restore stock amdgpu.ko + remove patched Mesa"
        print_item "11"  "Install AC-3 Surround Encoding"  "HDMI/DP Dolby Digital 5.1 via eARC — zero latency, native a52 encoding"
        print_item "11R" "Revert AC-3 Surround Encoding"   "Restore HDMI stereo profile"
        print_item "0"  "Back" ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" manual_choice

        case "${manual_choice^^}" in
            1)  run_cpu_governor;        press_enter ;;
            1R) run_revert_cpu_governor; press_enter ;;
            2)  run_gpu_governor;        press_enter ;;
            2R) run_revert_gpu_governor; press_enter ;;
            3)  run_disable_mitigations; press_enter ;;
            3R) run_revert_mitigations;  press_enter ;;
            4)  run_configure_swap;      press_enter ;;
            4R) run_revert_swap;         press_enter ;;
            5)  run_zram_zswap_toggle;   press_enter ;;
            5R) run_revert_zram_zswap;   press_enter ;;
            6)  install_acpi_fix;        press_enter ;;
            6R) run_revert_acpi_fix;     press_enter ;;
            7)  run_cu_live_manager;     press_enter ;;
            8)  install_core_unlock;     press_enter ;;
            8R) run_revert_core_unlock;  press_enter ;;
            9)  install_ram_split;       press_enter ;;
            9R) run_revert_ram_split;   press_enter ;;
            10) install_combined_fix;    press_enter ;;
            10R) run_revert_gfx1013_fix; press_enter ;;
            11) install_ac3_surround;      press_enter ;;
            11R) run_revert_ac3_surround;  press_enter ;;
            0)  return 0 ;;
            *)
                print_error "Invalid selection: '$manual_choice'"
                sleep 1
                ;;
        esac
    done
}

run_swap_menu() {
    while true; do
        print_banner
        print_section "Swap & ZRAM/ZSWAP"
        echo -e "  ${DIM}Adapted from redbeard1083/bc250-toolkit — swapfile size/swappiness, ZRAM -> ZSWAP${RESET}"
        echo ""
        echo -e "  ${CYAN}Swapfile${RESET}   $SWAPFILE_PATH — $(( $(swapfile_size_mb) )) MB"
        echo -e "  ${CYAN}ZRAM${RESET}       $(zram_currently_disabled && echo "disabled (systemd.zram=0 in GRUB)" || echo "enabled (SteamOS default)")"
        echo -e "  ${CYAN}ZSWAP${RESET}      $(zswap_currently_on && echo "enabled in GRUB" || echo "disabled (SteamOS default)")"
        echo ""
        print_item "1" "Configure Swap"            "Resize $SWAPFILE_PATH and set vm.swappiness"
        print_item "2" "Disable ZRAM & Enable ZSWAP" "lz4, 25% pool — needs reboot"
        echo ""
        print_item "3" "Revert Swap to Default"     "Back to stock ${SWAPFILE_STOCK_SIZE_MB}M / swappiness=60"
        print_item "4" "Revert ZRAM/ZSWAP to Default" "Back to stock ZRAM — needs reboot"
        print_item "0" "Back" ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" swap_choice

        case "$swap_choice" in
            1) run_configure_swap;      press_enter ;;
            2) run_zram_zswap_toggle;   press_enter ;;
            3) run_revert_swap;         press_enter ;;
            4) run_revert_zram_zswap;   press_enter ;;
            0) return 0 ;;
            *)
                print_error "Invalid selection: '$swap_choice'"
                sleep 1
                ;;
        esac
    done
}

run_cu_live_manager() {
    print_step "CU" "Launching BC-250 CU/WGP Live Manager"
    if [[ ! -f "$CU_LIVE_MANAGER" ]]; then
        print_error "bc250-cu-live-manager.sh not found at $CU_LIVE_MANAGER"
        return 1
    fi
    ( bash "$CU_LIVE_MANAGER" )
    return 0
}

run_aic8800_menu() {
    while true; do
        print_banner
        print_section "AIC8800 WiFi/BT Driver"
        echo ""
        print_item "I" "Install AIC8800 WiFi/BT Driver" "For AIC8800D80 USB WiFi/BT dongles"
        print_item "R" "Revert AIC8800 WiFi/BT Driver"  "Remove AIC8800 driver"
        print_item "0" "Back"                           ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" aic_choice

        case "${aic_choice^^}" in
            I) install_aic8800_wifi;     press_enter ;;
            R) run_revert_aic8800_wifi;  press_enter ;;
            0) return 0 ;;
            *)
                print_error "Invalid selection: '$aic_choice'"
                sleep 1
                ;;
        esac
    done
}

run_be200_menu() {
    while true; do
        print_banner
        print_section "BE200 Wi-Fi 7 Firmware"
        echo ""
        print_item "I" "Install BE200 Firmware" "For Intel BE200/BE201 PCIe Wi-Fi 7 cards missing -100/-101 ucode"
        print_item "R" "Revert BE200 Firmware"  "Remove BE200 firmware files"
        print_item "0" "Back"                   ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" be200_choice

        case "${be200_choice^^}" in
            I) install_be200_firmware;    press_enter ;;
            R) run_revert_be200_firmware; press_enter ;;
            0) return 0 ;;
            *)
                print_error "Invalid selection: '$be200_choice'"
                sleep 1
                ;;
        esac
    done
}

install_toolkit_steamos_control_plugin() {
    print_step "DSC" "Toolkit SteamOS Control Decky Plugin"

    local plugin_dir="$SCRIPT_DIR/extras/toolkit-steamos-control"
    if [[ ! -f "$plugin_dir/install.sh" ]]; then
        fail_with_log "Toolkit SteamOS Control plugin files are missing." "Decky Plugin Install"
        return 1
    fi
    print_info "Installing prebuilt Toolkit SteamOS Control for Decky..."
    sudo -u "$REAL_USER" -H bash "$plugin_dir/install.sh" || {
        fail_with_log "Decky plugin installation failed." "Decky Plugin Install"
        return 1
    }
    print_success "Toolkit SteamOS Control installed. Open Decky's Quick Access Menu to use it."
}

run_extras_menu() {
    while true; do
        print_banner
        print_section "Extras"
        echo ""
        print_item "A" "AIC8800 WiFi/BT Driver"      "Install/revert AIC8800D80 USB WiFi/BT dongles"
        print_item "E" "BE200 Wi-Fi 7 Firmware"      "Install/revert Intel BE200 PCIe firmware (-100/-101 ucode)"
        print_item "F" "Sensors & Fan Control"        "NCT6686D sensors / NCT6687 PWM fan control"
        print_item "H" "HDMI-CEC / TV Control"        "Open bc250-cec.sh (TV/receiver control via cecd)"
        print_item "K" "CoolerControl"                "Install/revert CoolerControl fan-curve daemon + GUI"
        print_item "P" "Enable SteamOS Update Persistence" "Re-apply toolkit settings after SteamOS updates"
        print_item "D" "DS5 Bridge PS Button Fix"    "Install/revert patched hid-playstation.ko — DualSense PS button chord combos"
        print_item "X" "Xbox Wireless Adapter"        "Install/revert xone driver for Xbox One/Series controllers"
        print_item "Z" "Toolkit SteamOS Control"      "Install Decky fan profiles and LED bar controls"
        print_item "0" "Back" ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" extras_choice

        case "${extras_choice^^}" in
            A) run_aic8800_menu ;;
            E) run_be200_menu ;;
            F) run_sensors_menu ;;
            H) run_cec_control;           press_enter ;;
            K) run_coolercontrol_menu ;;
            P) install_persistence;       press_enter ;;
            D) run_ds5_bridge_menu ;;
            X) run_xbox_adapter_menu ;;
            Z) install_toolkit_steamos_control_plugin; press_enter ;;
            0) return 0 ;;
            *)
                print_error "Invalid selection: '$extras_choice'"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# STEAMOS UPDATE PERSISTENCE
# ==============================================================================
# Track which components have been installed and automatically re-apply them
# after a SteamOS atomic update wipes /etc and /usr/lib/modules.

reapply_installed_components() {
    print_step "RAP" "Re-applying toolkit settings after SteamOS update"
    local component
    if [[ ! -f "$PERSIST_STATE_FILE" ]]; then
        print_info "No persisted toolkit state to re-apply."
        return 0
    fi
    while IFS= read -r component; do
        [[ -n "$component" ]] || continue
        print_info "Re-applying component: $component"
        case "$component" in
            cpu)        run_cpu_governor || print_error "CPU governor reapply failed" ;;
            gpu)        run_gpu_governor || print_error "GPU governor reapply failed" ;;
            mitigations) run_disable_mitigations auto || print_error "Mitigations reapply failed" ;;
            swap)       run_configure_swap auto || print_error "Swap reapply failed" ;;
            zswap)      run_zram_zswap_toggle auto || print_error "ZSWAP reapply failed" ;;
            acpi)       install_acpi_fix || print_error "ACPI fix reapply failed" ;;
            audio)      install_audio_fix || print_error "DP audio fix reapply failed" ;;
            ac3)        install_ac3_surround || print_error "AC-3 surround reapply failed" ;;
            ds5_bridge) install_ds5_bridge_fix || print_error "DS5 Bridge fix reapply failed" ;;
            ds5_chord_vdf) run_install_ds5_chord_vdf || print_error "DS5 Chord VDF reapply failed" ;;
            cu)         print_info "CU Live Manager skipped in unattended re-apply." ;;
            core_unlock) print_info "CPU Core Unlock boot service persists via the atomic-update keep list — skipped in unattended re-apply." ;;
            ram_split)  print_info "RAM/VRAM split persists on its own (CMOS is hardware state; GRUB config is in the atomic-update keep list) — skipped in unattended re-apply." ;;
            aic8800)    install_aic8800_wifi || print_error "AIC8800 WiFi reapply failed" ;;
            sensors)    install_sensors_pwm || print_error "Sensors PWM reapply failed" ;;
            coolercontrol) install_coolercontrol || print_error "CoolerControl reapply failed" ;;
            xbox)       install_xbox_adapter || print_error "Xbox adapter reapply failed" ;;
            persistence) install_persistence || print_error "Persistence reapply failed" ;;
            *)          print_info "Unknown persisted component: $component" ;;
        esac
        echo ""
    done < "$PERSIST_STATE_FILE"
    persist_restore_all_configs
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart bc250-smu-oc.service cyan-skillfish-governor-smu.service coolercontrold.service 2>/dev/null || true
    install_all_progress_clear 2>/dev/null || true
    print_success "Toolkit re-apply completed."
}

install_persistence() {
    print_step "PST" "Enable SteamOS update persistence"

    if ! is_steamos; then
        print_info "Persistence is only meaningful on SteamOS; nothing to do."
        return 0
    fi

    mkdir -p "$PERSIST_STATE_DIR"
    persist_detect_and_record_installed

    local reapply_script="$PERSIST_STATE_DIR/bc250-toolkit-reattach.sh"
    cat > "$reapply_script" <<EOF
#!/usr/bin/env bash
# Auto-generated by bc250-steamos-real-toolkit
set -euo pipefail
export AUTO=1
exec "$SCRIPT_PATH" --reapply-all
EOF
    chmod +x "$reapply_script"
    chown "$REAL_USER":"$REAL_USER" "$reapply_script" 2>/dev/null || true

    local tmp_unit="$PERSIST_STATE_DIR/bc250-toolkit-persist.service"
    cat > "$tmp_unit" <<EOF
[Unit]
Description=Re-apply BC-250 SteamOS Real Toolkit settings after updates
After=network-online.target multi-user.target
Wants=network-online.target
ConditionKernelCommandLine=!steamos-recovery

[Service]
Type=oneshot
ExecStart=$reapply_script
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    chown "$REAL_USER":"$REAL_USER" "$tmp_unit" 2>/dev/null || true

    cat > "$PERSIST_KEEP_FILE" <<'EOF'
# Toolkit state preserved across SteamOS atomic updates
# generated by bc250-steamos-real-toolkit
/etc/default/grub
/etc/modprobe.d/aic8800.conf
/etc/modprobe.d/sensors.conf
/etc/modules-load.d/99-sensors.conf
/etc/sysctl.d/99-swappiness.conf
/etc/udev/rules.d/40-aic8800-modeswitch.rules
/etc/usb_modeswitch.d/1111:1111
/etc/bc250-smu-oc.conf
/etc/cyan-skillfish-governor-smu
/etc/cyan-skillfish-governor-smu/config.toml
/etc/dbus-1/system.d/com.cyan.SkillFishGovernor.conf
/etc/bc250-cu-live-manager.conf
/etc/bc250-control
/etc/coolercontrol
/etc/coolercontrold
/var/lib/toolkit-steamos-control
/etc/systemd/system/toolkit-steamos-fan.service
/etc/systemd/system/steamos-led.service.d/toolkit-steamos-control.conf
/etc/systemd/system/bc250-smu-oc.service
/etc/systemd/system/cyan-skillfish-governor-smu.service
/etc/systemd/system/bc250-acpi-heal.service
/etc/systemd/system/bc250-cpufreq.service
/etc/systemd/system/bc250-gpu-freq-restore.service
/etc/systemd/system/bc250-cu-live-manager.service
/etc/systemd/system/bc250-core-unlock.service
/etc/bc250-core-unlock.conf
/etc/systemd/system/aic8800-modules.service
/etc/systemd/system/bc250-toolkit-persist.service
/etc/systemd/system/multi-user.target.wants/bc250-smu-oc.service
/etc/systemd/system/multi-user.target.wants/cyan-skillfish-governor-smu.service
/etc/systemd/system/multi-user.target.wants/bc250-acpi-heal.service
/etc/systemd/system/multi-user.target.wants/bc250-cpufreq.service
/etc/systemd/system/multi-user.target.wants/bc250-gpu-freq-restore.service
/etc/systemd/system/multi-user.target.wants/bc250-cu-live-manager.service
/etc/systemd/system/multi-user.target.wants/bc250-core-unlock.service
/etc/systemd/system/multi-user.target.wants/aic8800-modules.service
/etc/systemd/system/multi-user.target.wants/bc250-toolkit-persist.service
/etc/systemd/system-sleep/bc250-cec-amp.sh
/etc/systemd/system/bc250-cec-poweroff-standby.service
/etc/systemd/system/multi-user.target.wants/bc250-cec-poweroff-standby.service
/etc/atomic-update.conf.d/bc250-toolkit.conf
EOF
    chown "$REAL_USER":"$REAL_USER" "$PERSIST_KEEP_FILE" 2>/dev/null || true

    local keep=/etc/atomic-update.conf.d/bc250-toolkit.conf
    steamos_writable "install -D -m 644 -o root -g root '$PERSIST_KEEP_FILE' '$keep' && install -D -m 644 -o root -g root '$tmp_unit' '/etc/systemd/system/bc250-toolkit-persist.service' && install -D -m 755 -o root -g root '$reapply_script' '/usr/local/bin/bc250-toolkit-reattach.sh' && systemctl daemon-reload && systemctl enable bc250-toolkit-persist.service" || {
        fail_with_log "Failed to install SteamOS update persistence files." "Persistence Install"
        return 1
    }

    if [[ "$AUTO" != "1" ]]; then
        persist_snapshot_configs "global" \
            /etc/bc250-smu-oc.conf \
            /etc/cyan-skillfish-governor-smu/config.toml \
            /etc/cyan-skillfish-governor-smu/freq-state \
            /etc/coolercontrol \
            /etc/coolercontrold \
            /etc/modprobe.d/aic8800.conf \
            /etc/modprobe.d/sensors.conf \
            /etc/modules-load.d/99-sensors.conf \
            /etc/sysctl.d/99-swappiness.conf \
            /etc/udev/rules.d/40-aic8800-modeswitch.rules \
            /etc/usb_modeswitch.d/1111:1111
    fi
    persist_state_add "persistence"
    print_success "SteamOS update persistence enabled. Toolkit settings will be re-applied after system updates."
}

run_show_persistence_list() {
    print_banner
    print_section "Persistence List"
    persist_detect_and_record_installed
    if [[ ! -f "$PERSIST_STATE_FILE" ]]; then
        print_info "No persisted components recorded yet."
        echo ""
        return 0
    fi
    echo -e "  ${DIM}Components recorded in $PERSIST_STATE_FILE:${RESET}"
    while IFS= read -r component; do
        [[ -n "$component" ]] && echo -e "    - ${CYAN}${component}${RESET}"
    done < "$PERSIST_STATE_FILE"
    echo ""
    if [[ -d "$PERSIST_STATE_DIR/config-snapshots" ]]; then
        echo -e "  ${DIM}Saved config snapshots:${RESET}"
        for snapshot in "$PERSIST_STATE_DIR/config-snapshots"/*; do
            [[ -e "$snapshot" ]] || continue
            echo -e "    - $(basename "$snapshot")"
        done
    else
        echo -e "  ${DIM}No saved config snapshots yet.${RESET}"
    fi
    echo ""
}

run_persistence_menu() {
    while true; do
        print_banner
        print_section "SteamOS Update Persistence"
        echo ""
        print_item "E" "Enable / Update Persistence" "Track & re-apply toolkit settings after SteamOS updates"
        print_item "V" "View Persistence List"       "Show installed components and saved config snapshots"
        print_item "0" "Back"                      ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" persist_choice

        case "${persist_choice^^}" in
            E) install_persistence;       press_enter ;;
            V) run_show_persistence_list; press_enter ;;
            0) return 0 ;;
            *)
                print_error "Invalid selection: '$persist_choice'"
                sleep 1
                ;;
        esac
    done
}

show_menu() {
    print_banner
    print_section "Quick Start"
    print_item  "1"  "Install All"           "Install all necessary optimizations: CPU/GPU governor, Mitigations, Swap/ZSWAP, Fixes, CU Unlock"
    print_item  "2"  "Install / Revert Manual" "Same as Install All, one component at a time"
    print_item  "3"  "Performance Profiles"  "CPU & GPU performance profiles"
    print_item  "4"  "Revert / Uninstall All" "Undo everything back to SteamOS defaults"
    print_item  "5"  "Extras"                "Sensors & fans, CoolerControl, HDMI-CEC, AIC8800 WiFi, persistence"
    echo ""
    print_section "System"
    print_item  "V"  "Verify My Setup"       "Current system summary"
    print_item  "G"  "Changelog"             "Open the README changelog on GitHub"
    print_item  "I"  "Help"                  "Open the repository (usage & troubleshooting)"
    print_item  "P"  "SteamOS Update Persistence" "Track, view and re-apply after any SteamOS update (recommended)"
    print_item  "0"  "Exit"                  ""
    echo ""
    echo -e "  ${DIM}${TOOLKIT_VERSION} — ${REPO_URL}${RESET}"
    echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
}

ensure_desktop_shortcut || true

# Non-interactive re-apply mode used by the persistence service after SteamOS updates.
if [[ "${1:-}" == "--reapply-all" ]]; then
    AUTO=1
    reapply_installed_components
    exit 0
fi

# Validate prerequisites for Combined Fix installation
validate_combined_fix_prerequisites() {
    local check_mesa="${1:-1}"
    print_step "VALIDATE" "Validating Combined Fix prerequisites"

    # Check disk space (>5GB free)
    local required_space_gb=5
    local free_space_gb
    free_space_gb=$(df --output=avail -BG /home | tail -1 | tr -dc '0-9')

    if [[ -z "$free_space_gb" ]] || (( free_space_gb < required_space_gb )); then
        print_error "Insufficient disk space: ${free_space_gb:-0}GB free, ${required_space_gb}GB required"
        print_info "Please free up at least ${required_space_gb}GB of space on /home"
        return 1
    fi

    # Check build tools (meson/ninja are auto-installed later by gfx1013_ensure_mesa_build_deps)
    local build_tools=("git" "make" "gcc" "patch")
    local missing_tools=()
    local missing_mesa_tools=()

    for tool in "${build_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing build tools: ${missing_tools[*]}"
        print_info "Please install the missing tools and try again"
        return 1
    fi

    if [[ "$check_mesa" == "1" ]]; then
        for tool in meson ninja; do
            command -v "$tool" >/dev/null 2>&1 || missing_mesa_tools+=("$tool")
        done
        if [[ ${#missing_mesa_tools[@]} -gt 0 ]]; then
            print_info "Note: meson/ninja not found — will be auto-installed during Mesa build."
        fi
    fi

    # Check basic connectivity (try to reach a known host)
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        print_warning "Unable to reach external network (8.8.8.8)"
        print_warning "The Combined Fix requires internet access to download source code"
        print_warning "Continuing anyway, but installation may fail if network is unavailable"
        # Don't return 1 here - just warn, as the user might be in a restricted environment
    fi

    print_success "All Combined Fix prerequisites met"
    return 0
}

while true; do
    show_menu
    read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" choice

    case "${choice^^}" in
        1) run_install_all;       press_enter ;;
        2) run_install_manual ;;
        3) run_overclock_menu ;;
        4) run_revert_all;        press_enter ;;
        5) run_extras_menu ;;
        V) run_status;            press_enter ;;
        G) run_changelog;         press_enter ;;
        I) run_help;              press_enter ;;
        P) run_persistence_menu;  press_enter ;;
        0)
            echo -e "\n  ${DIM}Goodbye.${RESET}\n"
            echo -e "  ${DIM}Press Enter to close...${RESET}"
            read -r
            exit 0
            ;;
        *)
            print_error "Invalid selection: '$choice'"
            sleep 1
            ;;
    esac
done
