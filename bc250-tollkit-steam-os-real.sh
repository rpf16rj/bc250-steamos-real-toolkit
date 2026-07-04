#!/usr/bin/env bash
# ==============================================================================
#  BC-250 SteamOS Real Toolkit
#  SteamOS-focused helper for BC-250 CPU/GPU governors and performance profiles.
# ==============================================================================

set -euo pipefail

# Re-launch with sudo if not already root
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"

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

print_banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═════════════════════════════════════════════════════════════════════╗"
    echo "  ║                                                                     ║"
    echo "  ║                 BC-250 SteamOS Real Toolkit                         ║"
    echo "  ║           CPU/GPU Governors & Performance Profiles                  ║"
    echo "  ║                                                                     ║"
    echo "  ╚═════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
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
    echo -e "\n  ${DIM}Press Enter to return to the menu...${RESET}"
    read -r
}

confirm() {
    local prompt="${1:-Are you sure?}"
    echo -e "\n  ${YELLOW}${prompt}${RESET} ${DIM}[y/N]${RESET} "
    read -rp "  → " ans
    [[ "$ans" =~ ^[Yy]$ ]]
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

steamos_writable() {
    local cmd="$1"
    if is_steamos; then
        print_info "SteamOS detected: disabling read-only mode..."
        if ! steamos-readonly disable; then
            print_error "Failed to disable SteamOS read-only mode."
            return 1
        fi
        eval "$cmd"
        local rc=$?
        print_info "Re-enabling SteamOS read-only mode..."
        steamos-readonly enable || true
        return $rc
    else
        eval "$cmd"
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
        print_error "Failed to install build dependencies."
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
        shelly) sudo -u "$REAL_USER" shelly aur install "$package" ;;
        paru)   sudo -u "$REAL_USER" paru -S --noconfirm "$package" ;;
        yay)    sudo -u "$REAL_USER" yay -S --noconfirm "$package" ;;
    esac
}

aur_remove() {
    local package="$1" helper
    if ! helper="$(aur_helper)"; then
        print_error "No AUR helper found (shelly, paru, or yay). Please install one first."
        return 1
    fi
    print_info "Removing $package via $helper..."
    case "$helper" in
        shelly) shelly remove "$package" ;;
        paru)   paru -Rns --noconfirm "$package" 2>/dev/null || true ;;
        yay)    yay -Rns --noconfirm "$package" 2>/dev/null || true ;;
    esac
}

# ==============================================================================
# GOVERNORS
# ==============================================================================

run_cpu_governor() {
    print_step "01" "Installing CPU Governor"

    if systemctl is-enabled bc250-smu-oc.service &>/dev/null || \
       pipx list 2>/dev/null | grep -q 'bc250-smu-oc'; then
        print_info "CPU governor already installed — skipping."
        return 0
    fi

    print_info "Installing dependencies: python-pipx, stress"
    steamos_writable 'pacman -Syu python-pipx stress --noconfirm' || {
        print_error "Failed to install dependencies."
        return 1
    }

    print_info "Cloning bc250_smu_oc repository..."
    if [[ -d "bc250_smu_oc" ]]; then
        print_info "Directory already exists — pulling latest changes..."
        git -C bc250_smu_oc pull || { print_error "Failed to pull repository."; return 1; }
    else
        git clone https://github.com/bc250-collective/bc250_smu_oc.git || { print_error "Failed to clone repository."; return 1; }
    fi
    cd bc250_smu_oc
    print_info "Installing via pipx..."
    pipx install . || { print_error "Failed to install via pipx."; cd ..; return 1; }
    pipx ensurepath || true
    export PATH="$PATH:/root/.local/bin"
    print_info "Running bc250-detect..."
    bc250-detect --frequency 3500 --vid 1000 --keep || { print_error "bc250-detect failed."; cd ..; return 1; }
    print_info "Applying overclock config..."
    bc250-apply --install overclock.conf || { print_error "bc250-apply failed."; cd ..; return 1; }
    print_info "Enabling systemd service..."
    systemctl enable bc250-smu-oc || { print_error "Failed to enable service."; cd ..; return 1; }
    cd ..
    print_success "CPU Governor installed successfully!"
}

run_gpu_governor() {
    print_step "02" "Installing GPU Governor"

    if systemctl is-enabled cyan-skillfish-governor-smu.service &>/dev/null || \
       pacman -Qq cyan-skillfish-governor-smu &>/dev/null; then
        print_info "GPU governor already installed — skipping."
        return 0
    fi

    print_info "Installing cyan-skillfish-governor-smu via AUR helper..."
    ensure_build_deps || return 1
    steamos_writable 'aur_install cyan-skillfish-governor-smu' || {
        print_error "Failed to install GPU governor."
        return 1
    }

    print_info "Enabling and starting systemd service..."
    systemctl enable --now cyan-skillfish-governor-smu.service || {
        print_error "Failed to enable GPU governor service."
        return 1
    }

    print_success "GPU Governor installed and started successfully!"
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

write_gpu_overclock_1750mhz() { cat > "$GPU_TMPFILE" <<'EOF'
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
    nano "$CPU_DEST" || true
    if confirm "Would you like to restart the CPU service to apply changes?"; then
        systemctl daemon-reload
        systemctl restart "$CPU_SERVICE"
        if systemctl is-active --quiet "$CPU_SERVICE"; then
            print_success "CPU service restarted successfully."
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
    nano "$GPU_DEST" || true
    if confirm "Would you like to restart the GPU service to apply changes?"; then
        systemctl restart "$GPU_SERVICE"
        if systemctl is-active --quiet "$GPU_SERVICE"; then
            print_success "GPU service restarted successfully."
        else
            print_error "GPU service failed to start! Check: journalctl -u $GPU_SERVICE"
        fi
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
    local cpu_freq gpu_freq
    [[ ! -f "$CPU_DEST" || ! -f "$GPU_DEST" ]] && echo "Unknown" && return
    cpu_freq=$(awk -F'= ' '/^frequency/{print $2}' "$CPU_DEST" 2>/dev/null | tr -d ' ')
    gpu_freq=$(awk -F'= ' '/^frequency/{print $2}' "$GPU_DEST" 2>/dev/null | tr -d ' ' | tail -1)

    local preset_cpu_freqs=(3500 3500 3500 3500 3500 3500 3850 4000)
    local preset_gpu_freqs=(1500 1600 1750 1850 2000 2100 2100 2350)

    for i in "${!PRESET_NAMES[@]}"; do
        if [[ "$cpu_freq" == "${preset_cpu_freqs[$i]}" && "$gpu_freq" == "${preset_gpu_freqs[$i]}" ]]; then
            echo "${PRESET_NAMES[$i]}"
            return
        fi
    done
    echo "Custom"
}

PRESET_NAMES=("Stock" "Mild" "Moderate" "Strong" "Aggressive" "Extreme I ⚠" "Extreme II ⚠" "Extreme III ⚠")
PRESET_DESCS=(
    "CPU 3.5GHz, GPU 1500MHz — 80°C"
    "CPU 3.5GHz, GPU 1600MHz — 80°C"
    "CPU 3.5GHz, GPU 1750MHz — 80°C"
    "CPU 3.5GHz, GPU 1850MHz — 80°C"
    "CPU 3.5GHz, GPU 2000MHz — 80°C"
    "CPU 3.5GHz, GPU 2100MHz — 80°C"
    "CPU 3.85GHz, GPU 2100MHz — 80°C"
    "CPU 4GHz, GPU 2350MHz — 90°C"
)
PRESET_CPU_WRITERS=(write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_undervolt_3_5ghz write_cpu_overclock_3_85ghz write_cpu_overclock_4ghz)
PRESET_GPU_WRITERS=(write_gpu_overclock_1500mhz write_gpu_overclock_1600mhz write_gpu_overclock_1750mhz write_gpu_overclock_1850mhz write_gpu_overclock_2000mhz write_gpu_overclock_2100mhz write_gpu_overclock_2100mhz write_gpu_overclock_2350mhz)
PRESET_HIGH_RISK_THRESHOLD=5

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
        print_item "0" "Back"            ""
        echo ""
        echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
        read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" oc_choice

        case "${oc_choice^^}" in
            C) oc_apply_custom;         press_enter ;;
            E) oc_edit_gpu_config_nano; press_enter ;;
            F) oc_edit_cpu_config_nano; press_enter ;;
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

    local cpu_color gpu_color cpu_label
    if [[ "$cpu_svc_enabled" == "enabled" && "$cpu_svc_result" == "0" ]]; then
        cpu_color="$GREEN"; cpu_label="enabled (applied successfully)"
    elif [[ "$cpu_svc_enabled" == "enabled" ]]; then
        cpu_color="$YELLOW"; cpu_label="enabled (exit code: ${cpu_svc_result})"
    else
        cpu_color="$RED"; cpu_label="disabled"
    fi
    [[ "$gpu_svc_state" == "active" ]] && gpu_color="$GREEN" || gpu_color="$RED"
    echo -e "  ${CYAN}CPU Service${RESET}       ${cpu_color}${cpu_label}${RESET}"
    echo -e "  ${CYAN}GPU Service${RESET}       ${gpu_color}${gpu_svc_state}${RESET}"
    echo ""

    echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

show_menu() {
    print_banner
    print_section "Performance"
    print_item  "1"  "Performance Profiles"  "CPU & GPU performance profiles"
    echo ""
    print_section "Governors"
    print_item  "2"  "Install CPU Governor"  "bc250-smu-oc CPU overclock service"
    print_item  "3"  "Install GPU Governor"  "cyan-skillfish GPU governor service"
    echo ""
    print_section "Revert"
    print_item  "4"  "Revert CPU Governor"     "Remove bc250-smu-oc service"
    print_item  "5"  "Revert GPU Governor"     "Remove cyan-skillfish-governor-smu"
    echo ""
    print_section "System"
    print_item  "S"  "Status"                "Current system summary"
    print_item  "0"  "Exit"                  ""
    echo ""
    echo -e "  ${BOLD}${CYAN}═════════════════════════════════════════════════════════════════════${RESET}"
}

while true; do
    show_menu
    read -rp "$(echo -e "  ${BOLD}${WHITE}Enter selection:${RESET} ")" choice

    case "${choice^^}" in
        1) run_overclock_menu ;;
        2) run_cpu_governor;       press_enter ;;
        3) run_gpu_governor;       press_enter ;;
        4) run_revert_cpu_governor; press_enter ;;
        5) run_revert_gpu_governor; press_enter ;;
        S) run_status;             press_enter ;;
        0)
            echo -e "\n  ${DIM}Goodbye.${RESET}\n"
            exit 0
            ;;
        *)
            print_error "Invalid selection: '$choice'"
            sleep 1
            ;;
    esac
done
