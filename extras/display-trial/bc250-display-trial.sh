#!/bin/bash
# BC-250 Display Trial — Forced EDID + DP-1 enable + session-switch fix
# Auto-reverts on 2nd reboot if user doesn't confirm.
set -euo pipefail

TRIAL_DIR="/var/lib/bc250-display-trial"
STATE_FILE="$TRIAL_DIR/state"
LOG_FILE="/var/log/bc250-display-trial.log"
BACKUP_DIR="$TRIAL_DIR/backup"
SCRIPT_PATH="$(readlink -f "$0")"
GRUB_DEFAULT="/etc/default/grub"
MKINITCPIO_CONF="/etc/mkinitcpio.conf"
REAL_USER="${SUDO_USER:-$(id -un 2>/dev/null || echo deck)}"
REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || echo "/home/deck")
EDID_SOURCE="$REAL_HOME/.config/gamescope/edid.bin"
EDID_DEST="/lib/firmware/edid/edid.bin"
REVERT_SERVICE="/etc/systemd/system/bc250-display-trial-revert.service"
SESSION_DROPIN_DIR="$REAL_HOME/.config/systemd/user/plasma-kwin_wayland.service.d"
SESSION_DROPIN="$SESSION_DROPIN_DIR/dp1-reprobe.conf"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
DIM='\033[2m'; RESET='\033[0m'; BOLD='\033[1m'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" 2>/dev/null || true; }
log_info() { echo -e "  ${CYAN}ℹ${RESET} $*"; log "INFO: $*"; }
log_ok() { echo -e "  ${GREEN}✓${RESET} $*"; log "OK: $*"; }
log_warn() { echo -e "  ${YELLOW}⚠${RESET} $*"; log "WARN: $*"; }
log_err() { echo -e "  ${RED}✗${RESET} $*"; log "ERROR: $*"; }

steamos_rw() { command -v steamos-readonly >/dev/null 2>&1 && steamos-readonly disable 2>/dev/null || true; }
steamos_ro() { command -v steamos-readonly >/dev/null 2>&1 && steamos-readonly enable 2>/dev/null || true; }

read_state() {
    if [[ -f "$STATE_FILE" ]]; then source "$STATE_FILE"; else STATUS="NONE"; BOOT_COUNT=0; fi
}

write_state() {
    mkdir -p "$TRIAL_DIR"
    cat > "$STATE_FILE" << EOF
STATUS="${1:-$STATUS}"
BOOT_COUNT=${2:-$BOOT_COUNT}
APPLIED_AT="${APPLIED_AT:-$(date '+%Y-%m-%d %H:%M:%S')}"
EOF
}

# ==============================================================================
apply() {
    echo -e "${BOLD}BC-250 Display Trial — Applying changes${RESET}"
    echo ""

    read_state

    if [[ "$STATUS" == "PENDING" ]]; then
        log_warn "Trial already applied (boot_count=$BOOT_COUNT). Run 'revert' first if you want to re-apply."
        return 1
    fi

    if [[ ! -f "$EDID_SOURCE" ]]; then
        log_err "EDID source not found: $EDID_SOURCE"
        return 1
    fi

    mkdir -p "$TRIAL_DIR" "$BACKUP_DIR"
    APPLIED_AT="$(date '+%Y-%m-%d %H:%M:%S')"

    steamos_rw

    # 1. Back up originals
    log_info "Backing up original configs..."
    cp -f "$GRUB_DEFAULT" "$BACKUP_DIR/grub"
    cp -f "$MKINITCPIO_CONF" "$BACKUP_DIR/mkinitcpio.conf"
    [[ -f "$EDID_DEST" ]] && cp -f "$EDID_DEST" "$BACKUP_DIR/edid.bin" || true
    log_ok "Backups saved to $BACKUP_DIR"

    # 2. Copy EDID to firmware
    log_info "Installing EDID to /lib/firmware/edid/edid.bin..."
    mkdir -p /lib/firmware/edid
    cp -f "$EDID_SOURCE" "$EDID_DEST"
    log_ok "EDID installed ($(wc -c < "$EDID_DEST") bytes)"

    # 3. Add EDID to mkinitcpio FILES
    log_info "Adding EDID to mkinitcpio FILES..."
    if grep -q '^FILES=()' "$MKINITCPIO_CONF"; then
        sed -i 's|^FILES=()|FILES=(/lib/firmware/edid/edid.bin)|' "$MKINITCPIO_CONF"
    elif grep -q 'edid/edid.bin' "$MKINITCPIO_CONF"; then
        log_info "EDID already in FILES"
    else
        sed -i 's|^FILES=(\(.*\))|FILES=(\1 /lib/firmware/edid/edid.bin)|' "$MKINITCPIO_CONF"
    fi
    log_ok "mkinitcpio.conf updated: $(grep '^FILES=' "$MKINITCPIO_CONF")"

    # 4. Rebuild initramfs
    log_info "Rebuilding initramfs..."
    local preset
    preset=$(ls /etc/mkinitcpio.d/linux-neptune-61*.preset 2>/dev/null | sort -V | tail -1)
    preset=$(basename "$preset" .preset)
    if mkinitcpio -p "$preset" 2>&1 | tail -5; then
        log_ok "Initramfs rebuilt (preset: $preset)"
    else
        log_err "Initramfs rebuild failed!"
        steamos_ro
        return 1
    fi

    # 5. Add kernel params to GRUB
    log_info "Adding kernel parameters to GRUB..."
    local cmdline_add="drm.edid_firmware=DP-1:edid/edid.bin video=DP-1:e"
    if grep -q 'drm.edid_firmware' "$GRUB_DEFAULT"; then
        log_info "Kernel params already present in GRUB"
    else
        sed -i "s|\\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\\)\"|\\1 $cmdline_add\"|" "$GRUB_DEFAULT"
        log_ok "Added: $cmdline_add"
    fi

    # 6. Update GRUB
    log_info "Updating GRUB..."
    if update-grub 2>&1 | tail -3; then
        log_ok "GRUB updated"
    else
        log_err "GRUB update failed!"
        steamos_ro
        return 1
    fi

    # 7. Create auto-revert systemd service
    log_info "Creating auto-revert service..."
    cat > "$REVERT_SERVICE" << EOF
[Unit]
Description=BC-250 Display Trial Auto-Revert (reverts on 2nd boot if unconfirmed)
Before=display-manager.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH auto-revert
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable bc250-display-trial-revert.service 2>/dev/null
    log_ok "Auto-revert service enabled"

    # 8. Create session-fix drop-in for Plasma's kwin
    log_info "Creating session-fix drop-in for plasma-kwin_wayland..."
    mkdir -p "$SESSION_DROPIN_DIR"
    cat > "$SESSION_DROPIN" << EOF
[Service]
ExecStartPre=$SCRIPT_PATH session-fix
EOF
    log_ok "Session-fix drop-in installed"

    steamos_ro

    # 9. Write state
    write_state "PENDING" 0
    log_ok "Trial state: PENDING (boot_count=0)"

    echo ""
    echo -e "  ${GREEN}${BOLD}Trial applied successfully!${RESET}"
    echo ""
    echo -e "  ${DIM}Changes:${RESET}"
    echo -e "  ${DIM}- EDID firmware: /lib/firmware/edid/edid.bin${RESET}"
    echo -e "  ${DIM}- Kernel params: drm.edid_firmware=DP-1:edid/edid.bin video=DP-1:e${RESET}"
    echo -e "  ${DIM}- Initramfs rebuilt with EDID file${RESET}"
    echo -e "  ${DIM}- Session-fix: DP-1 re-probe before kwin starts${RESET}"
    echo -e "  ${DIM}- Auto-revert: enabled (reverts on 2nd reboot if unconfirmed)${RESET}"
    echo ""
    echo -e "  ${BOLD}Reboot now to test.${RESET}"
    echo -e "  ${DIM}If it works: run '$0 confirm' to make it permanent.${RESET}"
    echo -e "  ${DIM}If it doesn't: just reboot again — auto-revert will restore everything.${RESET}"
    echo ""
    log "APPLY: Trial applied successfully"
}

# ==============================================================================
confirm() {
    echo -e "${BOLD}Confirming display trial as successful...${RESET}"
    read_state

    if [[ "$STATUS" != "PENDING" ]]; then
        log_warn "No pending trial to confirm (status=$STATUS)."
        return 1
    fi

    steamos_rw

    # Disable and remove auto-revert service
    systemctl disable bc250-display-trial-revert.service 2>/dev/null || true
    rm -f "$REVERT_SERVICE"
    systemctl daemon-reload
    log_ok "Auto-revert service removed"

    steamos_ro

    write_state "CONFIRMED" "$BOOT_COUNT"
    log_ok "Trial confirmed! Changes are now permanent."
    log "CONFIRM: User confirmed trial works (boot_count=$BOOT_COUNT)"

    echo ""
    echo -e "  ${GREEN}${BOLD}Trial confirmed!${RESET}"
    echo -e "  ${DIM}Auto-revert disabled. Changes will persist across reboots.${RESET}"
    echo -e "  ${DIM}To revert later: run '$0 revert'${RESET}"
    echo ""
}

# ==============================================================================
revert() {
    echo -e "${BOLD}Reverting display trial changes...${RESET}"
    read_state

    if [[ "$STATUS" == "NONE" || "$STATUS" == "REVERTED" ]]; then
        log_warn "Nothing to revert (status=$STATUS)."
        return 0
    fi

    steamos_rw

    # 1. Restore GRUB
    if [[ -f "$BACKUP_DIR/grub" ]]; then
        log_info "Restoring GRUB config..."
        cp -f "$BACKUP_DIR/grub" "$GRUB_DEFAULT"
        update-grub 2>&1 | tail -3
        log_ok "GRUB restored"
    fi

    # 2. Restore mkinitcpio.conf
    if [[ -f "$BACKUP_DIR/mkinitcpio.conf" ]]; then
        log_info "Restoring mkinitcpio.conf..."
        cp -f "$BACKUP_DIR/mkinitcpio.conf" "$MKINITCPIO_CONF"
        local preset
        preset=$(ls /etc/mkinitcpio.d/linux-neptune-61*.preset 2>/dev/null | sort -V | tail -1)
        preset=$(basename "$preset" .preset)
        mkinitcpio -p "$preset" 2>&1 | tail -5
        log_ok "Initramfs rebuilt with original config"
    fi

    # 3. Remove EDID firmware
    if [[ -f "$EDID_DEST" ]]; then
        log_info "Removing EDID firmware..."
        rm -f "$EDID_DEST"
        rmdir /lib/firmware/edid 2>/dev/null || true
        log_ok "EDID firmware removed"
    fi

    # 4. Remove auto-revert service
    systemctl disable bc250-display-trial-revert.service 2>/dev/null || true
    rm -f "$REVERT_SERVICE"
    systemctl daemon-reload

    # 5. Remove session-fix drop-in
    rm -rf "$SESSION_DROPIN_DIR"
    log_ok "Session-fix drop-in removed"

    steamos_ro

    write_state "REVERTED" "$BOOT_COUNT"
    log_ok "All changes reverted."
    log "REVERT: All changes reverted (was status=$STATUS, boot_count=$BOOT_COUNT)"

    echo ""
    echo -e "  ${GREEN}${BOLD}All changes reverted!${RESET}"
    echo -e "  ${DIM}Reboot to apply the restoration.${RESET}"
    echo ""
}

# ==============================================================================
auto_revert() {
    # Called by systemd service at boot. No terminal output — just logging.
    read_state

    if [[ "$STATUS" != "PENDING" ]]; then
        log "AUTO-REVERT: Status=$STATUS, nothing to do."
        exit 0
    fi

    local new_count=$((BOOT_COUNT + 1))
    log "AUTO-REVERT: Boot count $BOOT_COUNT -> $new_count"

    if (( new_count >= 2 )); then
        log "AUTO-REVERT: Boot count >= 2, reverting trial (user did not confirm)."
        # Perform silent revert
        steamos_rw

        if [[ -f "$BACKUP_DIR/grub" ]]; then
            cp -f "$BACKUP_DIR/grub" "$GRUB_DEFAULT"
            update-grub >/dev/null 2>&1
            log "AUTO-REVERT: GRUB restored"
        fi

        if [[ -f "$BACKUP_DIR/mkinitcpio.conf" ]]; then
            cp -f "$BACKUP_DIR/mkinitcpio.conf" "$MKINITCPIO_CONF"
            local preset
            preset=$(ls /etc/mkinitcpio.d/linux-neptune-61*.preset 2>/dev/null | sort -V | tail -1)
            preset=$(basename "$preset" .preset)
            mkinitcpio -p "$preset" >/dev/null 2>&1
            log "AUTO-REVERT: Initramfs rebuilt with original config"
        fi

        rm -f "$EDID_DEST"
        rmdir /lib/firmware/edid 2>/dev/null || true
        log "AUTO-REVERT: EDID firmware removed"

        systemctl disable bc250-display-trial-revert.service 2>/dev/null || true
        rm -f "$REVERT_SERVICE"
        systemctl daemon-reload

        rm -rf "$SESSION_DROPIN_DIR"
        log "AUTO-REVERT: Session-fix drop-in removed"

        steamos_ro

        write_state "REVERTED" "$new_count"
        log "AUTO-REVERT: Revert complete. System will use original display config on next boot."
    else
        write_state "PENDING" "$new_count"
        log "AUTO-REVERT: First boot after apply (count=$new_count). Waiting for user confirmation."
    fi
}

# ==============================================================================
session_fix() {
    # Called by ExecStartPre of plasma-kwin_wayland. Minimal output, just logging.
    log "SESSION-FIX: Plasma session starting, forcing DP-1 re-probe..."

    # Force connector re-probe by reading status (triggers HPD re-check on amdgpu)
    local status
    status=$(cat /sys/class/drm/card0-DP-1/status 2>/dev/null || echo "N/A")
    log "SESSION-FIX: Initial DP-1 status: $status"

    if [[ "$status" == "connected" ]]; then
        log "SESSION-FIX: DP-1 already connected, nothing to do."
        exit 0
    fi

    # Try forcing DPMS on
    echo on > /sys/class/drm/card0-DP-1/dpms 2>/dev/null || true
    sleep 1

    # Wait up to 10 seconds for connector to appear
    for i in $(seq 1 10); do
        status=$(cat /sys/class/drm/card0-DP-1/status 2>/dev/null || echo "N/A")
        if [[ "$status" == "connected" ]]; then
            log "SESSION-FIX: DP-1 connected after ${i}s."
            exit 0
        fi
        sleep 1
    done

    log "SESSION-FIX: DP-1 still not connected after 10s + DPMS toggle."
    log "SESSION-FIX: kwin will start with placeholder output. Display may appear later."
    exit 0
}

# ==============================================================================
show_status() {
    read_state
    echo -e "${BOLD}BC-250 Display Trial Status${RESET}"
    echo ""
    echo -e "  Status:      ${BOLD}${STATUS}${RESET}"
    echo -e "  Boot count:  ${BOOT_COUNT}"
    echo -e "  Applied at:  ${APPLIED_AT:-N/A}"
    echo ""
    echo -e "  ${DIM}Backups:  $BACKUP_DIR${RESET}"
    echo -e "  ${DIM}State:    $STATE_FILE${RESET}"
    echo -e "  ${DIM}Log:      $LOG_FILE${RESET}"
    echo ""

    case "$STATUS" in
        PENDING)
            if (( BOOT_COUNT == 0 )); then
                echo -e "  ${YELLOW}Trial applied but not yet rebooted.${RESET}"
                echo -e "  ${DIM}Reboot to test. Run 'confirm' if it works.${RESET}"
            elif (( BOOT_COUNT == 1 )); then
                echo -e "  ${GREEN}First boot completed — trial is active.${RESET}"
                echo -e "  ${DIM}Run 'confirm' if it works, or reboot again to auto-revert.${RESET}"
            else
                echo -e "  ${RED}Boot count >= 2 — should have been auto-reverted.${RESET}"
            fi
            ;;
        CONFIRMED)
            echo -e "  ${GREEN}Trial confirmed — changes are permanent.${RESET}"
            ;;
        REVERTED)
            echo -e "  ${DIM}Trial reverted — original config restored.${RESET}"
            ;;
        NONE)
            echo -e "  ${DIM}No trial active.${RESET}"
            ;;
    esac
    echo ""
}

# ==============================================================================
show_log() {
    if [[ -f "$LOG_FILE" ]]; then
        cat "$LOG_FILE"
    else
        echo "No log file found at $LOG_FILE"
    fi
}

# ==============================================================================
usage() {
    echo "BC-250 Display Trial — Forced EDID + DP-1 enable"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  apply        Apply trial changes (EDID firmware + kernel params + session fix)"
    echo "  confirm      Mark trial as successful (disables auto-revert, makes permanent)"
    echo "  revert       Revert all changes manually"
    echo "  auto-revert  Called by systemd at boot (do not run manually)"
    echo "  session-fix  Called by kwin ExecStartPre (do not run manually)"
    echo "  status       Show current trial status"
    echo "  log          Show trial log"
    echo ""
}

# ==============================================================================
main() {
    local cmd="${1:-}"
    case "$cmd" in
        apply)        apply ;;
        confirm)      confirm ;;
        revert)       revert ;;
        auto-revert)  auto_revert ;;
        session-fix)  session_fix ;;
        status)       show_status ;;
        log)          show_log ;;
        *)            usage; exit 1 ;;
    esac
}

main "$@"
