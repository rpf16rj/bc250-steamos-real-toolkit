#!/usr/bin/env bash
# Put privileged BC-250 assets on SteamOS's large shared partition while
# retaining the conventional /var/lib/bc250-control path.
set -euo pipefail

ROOT_DIR=/var/lib/bc250-control
BACKING_DIR=/home/.steamos/offload/var/lib/bc250-control
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEGACY_UMR_DIR=/etc/bc250-control/umr
LEGACY_ROOT_DIR=/var/lib/bc250-40cu
UNIT_NAME='var-lib-bc250\x2dcontrol.mount'
UNIT_PATH="/etc/systemd/system/$UNIT_NAME"
KEEP_PATH=/etc/atomic-update.conf.d/bc250-storage.conf
MIGRATION_OLD=""

log() { echo "[bc250-storage] $*"; }
die() { echo "[bc250-storage] $*" >&2; exit 1; }
require_root() { [[ $EUID -eq 0 ]] || die "Run with sudo."; }

restore_failed_migration() {
    local rc=$?
    if [[ $rc -ne 0 && -n "$MIGRATION_OLD" && -d "$MIGRATION_OLD" ]] \
        && ! mountpoint -q "$ROOT_DIR"; then
        rm -rf "$ROOT_DIR"
        mv "$MIGRATION_OLD" "$ROOT_DIR"
    fi
    exit "$rc"
}
trap restore_failed_migration EXIT

secure_directory() {
    local current="$1" metadata owner mode
    while :; do
        [[ -d "$current" && ! -L "$current" ]] \
            || die "Unsafe storage path (not a real directory): $current"
        metadata=$(stat -Lc '%u %a' "$current")
        read -r owner mode <<< "$metadata"
        [[ "$owner" == 0 && $((8#$mode & 8#022)) -eq 0 ]] \
            || die "Unsafe storage path (must be root-owned and not group/world-writable): $current"
        [[ "$current" == / ]] && break
        current=${current%/*}
        [[ -n "$current" ]] || current=/
    done
}

migrate_helper() {
    local source="$1" target="$2" unit="$3"
    [[ -f "$source" && ! -L "$source" ]] || return 0
    if [[ ! -e "$target" ]]; then
        install -D -o root -g root -m 0755 "$source" "$target"
    fi
    if [[ -f "$unit" && ! -L "$unit" ]]; then
        sed -i "s|$source|$target|g" "$unit"
    fi
    rm -f "$source"
    log "Migrated legacy helper $source."
}

migrate_aic_helper() {
    local old=/etc/aic8800-ensure-modules.sh
    local source="$SCRIPT_DIR/aic8800/src/USB/driver_fw/drivers/aic8800"
    local firmware="$SCRIPT_DIR/aic8800/src/USB/driver_fw/fw/aic8800D80"
    local helper="$SCRIPT_DIR/aic8800/aic8800-ensure-modules.sh"
    local unit=/etc/systemd/system/aic8800-modules.service
    local stage repo_line repo
    [[ -f "$old" && ! -L "$old" ]] || return 0
    if [[ ! -f "$source/Makefile" && -f /etc/aic8800-paths.conf \
        && ! -L /etc/aic8800-paths.conf ]]; then
        repo_line=$(grep -m1 '^AIC8800_REPO=' /etc/aic8800-paths.conf || true)
        repo=${repo_line#AIC8800_REPO=}
        if [[ "$repo" =~ ^/[A-Za-z0-9_./-]+$ ]]; then
            source="$repo/src/USB/driver_fw/drivers/aic8800"
            firmware="$repo/src/USB/driver_fw/fw/aic8800D80"
            helper="$repo/aic8800-ensure-modules.sh"
        fi
    fi
    if [[ ! -f "$source/Makefile" || ! -d "$firmware" || ! -f "$helper" ]]; then
        systemctl disable --now aic8800-modules.service >/dev/null 2>&1 || true
        rm -f "$old" /etc/aic8800-paths.conf "$unit"
        log "Disabled unsafe legacy AIC8800 boot helper; rerun aic8800/steamdeck-setup.sh."
        return 0
    fi
    if find "$source" "$firmware" -type l -print -quit | grep -q .; then
        die "Refusing to snapshot AIC8800 source containing symlinks."
    fi
    install -d -o root -g root -m 0755 "$ROOT_DIR/aic8800"
    stage=$(mktemp -d "$ROOT_DIR/aic8800/.source-migrate.XXXXXX")
    cp -a "$source"/. "$stage"/
    chown -R root:root "$stage"
    chmod -R go-w "$stage"
    rm -rf "$ROOT_DIR/aic8800/source"
    mv "$stage" "$ROOT_DIR/aic8800/source"
    rm -rf "$ROOT_DIR/aic8800/firmware/aic8800D80"
    install -d -o root -g root -m 0755 "$ROOT_DIR/aic8800/firmware/aic8800D80"
    cp -a "$firmware"/. "$ROOT_DIR/aic8800/firmware/aic8800D80"/
    chown -R root:root "$ROOT_DIR/aic8800"
    chmod -R go-w "$ROOT_DIR/aic8800"
    install -D -o root -g root -m 0755 "$helper" \
        "$ROOT_DIR/helper/aic8800-ensure-modules"
    if [[ -f "$unit" && ! -L "$unit" ]]; then
        sed -i "s|$old|$ROOT_DIR/helper/aic8800-ensure-modules|g" "$unit"
        if grep -q '^ConditionPathExists=' "$unit"; then
            sed -i "s|^ConditionPathExists=.*|ConditionPathExists=$ROOT_DIR/aic8800/source/Makefile|" "$unit"
        fi
    fi
    rm -f "$old" /etc/aic8800-paths.conf
    log "Migrated legacy AIC8800 helper and trusted source snapshot."
}

install_storage() {
    require_root
    local parent old="" tmp

    for parent in /home/.steamos /home/.steamos/offload \
        /home/.steamos/offload/var /home/.steamos/offload/var/lib; do
        if [[ ! -e "$parent" ]]; then
            install -d -o root -g root -m 0755 "$parent"
        fi
        secure_directory "$parent"
    done
    if [[ ! -e "$BACKING_DIR" ]]; then
        install -d -o root -g root -m 0755 "$BACKING_DIR"
    fi
    secure_directory "$BACKING_DIR"

    # The legacy UMR payload can fill the /etc overlay so completely that the
    # mount unit cannot be written. Move it directly into the secure backing
    # tree first, then update the existing environment file in place.
    if [[ -d "$LEGACY_UMR_DIR" && ! -L "$LEGACY_UMR_DIR" ]]; then
        local umr_stage
        umr_stage=$(mktemp -d "$BACKING_DIR/.umr-migrate.XXXXXX")
        cp -a "$LEGACY_UMR_DIR"/. "$umr_stage"/
        [[ -x "$umr_stage/bin/umr" \
            && -f "$umr_stage/share/umr/database/cyan_skillfish.asic" \
            && -f "$umr_stage/share/umr/database/cyan_skillfish.soc15" ]] \
            || die "Refusing to remove incomplete legacy UMR data."
        chown -R root:root "$umr_stage"
        chmod -R go-w "$umr_stage"
        rm -rf "$BACKING_DIR/umr"
        mv "$umr_stage" "$BACKING_DIR/umr"
        rm -rf "$LEGACY_UMR_DIR"
        rmdir /etc/bc250-control 2>/dev/null || true
        if [[ -f /etc/bc250-cu-live-manager.conf \
            && ! -L /etc/bc250-cu-live-manager.conf ]]; then
            sed -i "s|^UMR=.*|UMR=$ROOT_DIR/umr/bin/umr|" \
                /etc/bc250-cu-live-manager.conf
            sed -i "s|^UMR_DATABASE_PATH=.*|UMR_DATABASE_PATH=$ROOT_DIR/umr/share/umr/database|" \
                /etc/bc250-cu-live-manager.conf
        fi
        log "Migrated legacy UMR out of the /etc overlay."
    fi

    if mountpoint -q "$ROOT_DIR"; then
        [[ "$(findmnt -rn -M "$ROOT_DIR" -o FSROOT)" == "/.steamos/offload/var/lib/bc250-control" ]] \
            || die "$ROOT_DIR is already an unexpected mount point."
    else
        if [[ -e "$ROOT_DIR" ]]; then
            [[ -d "$ROOT_DIR" && ! -L "$ROOT_DIR" ]] \
                || die "Refusing to replace unsafe path: $ROOT_DIR"
            secure_directory "$ROOT_DIR"
            old="/var/lib/.bc250-control.migrate.$$"
            MIGRATION_OLD="$old"
            mv "$ROOT_DIR" "$old"
        fi
        install -d -o root -g root -m 0755 "$ROOT_DIR"
        if [[ -n "$old" ]]; then
            cp -a "$old"/. "$BACKING_DIR"/
        fi
    fi

    tmp=$(mktemp /etc/systemd/system/.bc250-storage.XXXXXX)
    cat > "$tmp" << EOF
[Unit]
Description=BC-250 persistent privileged storage
After=home.mount
RequiresMountsFor=/home
Before=local-fs.target

[Mount]
What=$BACKING_DIR
Where=$ROOT_DIR
Type=none
Options=bind

[Install]
WantedBy=local-fs.target
EOF
    chmod 0644 "$tmp"
    chown root:root "$tmp"
    mv -f "$tmp" "$UNIT_PATH"

    systemctl daemon-reload
    systemctl enable --now "$UNIT_NAME" >/dev/null
    mountpoint -q "$ROOT_DIR" || die "Failed to mount $ROOT_DIR"
    secure_directory "$ROOT_DIR"
    if [[ -n "$old" ]]; then
        rm -rf "$old"
        MIGRATION_OLD=""
        old=""
    fi

    # Preserve old service paths without retaining 100+ MB on the tiny /var
    # partition. This compatibility link stays entirely inside root-owned
    # /var/lib and is removed after component units have been rewritten.
    if [[ -d "$LEGACY_ROOT_DIR" && ! -L "$LEGACY_ROOT_DIR" ]]; then
        rm -rf "$ROOT_DIR/legacy-bc250-40cu"
        cp -a "$LEGACY_ROOT_DIR" "$ROOT_DIR/legacy-bc250-40cu"
        chown -R root:root "$ROOT_DIR/legacy-bc250-40cu"
        chmod -R go-w "$ROOT_DIR/legacy-bc250-40cu"
        rm -rf "$LEGACY_ROOT_DIR"
        ln -s "$ROOT_DIR/legacy-bc250-40cu" "$LEGACY_ROOT_DIR"
        log "Offloaded legacy $LEGACY_ROOT_DIR data."
    fi

    migrate_helper /etc/bc250-acpi-heal.sh \
        "$ROOT_DIR/helper/bc250-acpi-heal" \
        /etc/systemd/system/bc250-acpi-heal.service
    migrate_helper /etc/bc250-cec-poweroff-standby.sh \
        "$ROOT_DIR/helper/bc250-cec-poweroff-standby" \
        /etc/systemd/system/bc250-cec-poweroff-standby.service
    migrate_aic_helper
    if [[ -f /etc/cyan-skillfish-governor-smu/freq-state \
        && ! -L /etc/cyan-skillfish-governor-smu/freq-state ]]; then
        if [[ ! -e "$ROOT_DIR/governor/freq-state" ]]; then
            install -D -o root -g root -m 0644 \
                /etc/cyan-skillfish-governor-smu/freq-state \
                "$ROOT_DIR/governor/freq-state"
        fi
        rm -f /etc/cyan-skillfish-governor-smu/freq-state
        log "Migrated legacy GPU frequency state."
    fi
    install -d -o root -g root -m 0755 "$(dirname "$KEEP_PATH")"
    tmp=$(mktemp "$(dirname "$KEEP_PATH")/.bc250-storage.XXXXXX")
    cat > "$tmp" << EOF
# BC-250 offloaded storage retained across SteamOS atomic updates.
$UNIT_PATH
/etc/systemd/system/local-fs.target.wants/$UNIT_NAME
EOF
    chmod 0644 "$tmp"
    chown root:root "$tmp"
    mv -f "$tmp" "$KEEP_PATH"
    systemctl daemon-reload
    log "$ROOT_DIR is backed by $BACKING_DIR"
}

show_status() {
    local state=missing source=-
    if mountpoint -q "$ROOT_DIR"; then
        state=mounted
        source=$(findmnt -rn -M "$ROOT_DIR" -o SOURCE)
    elif [[ -f "$UNIT_PATH" ]]; then
        state=unmounted
    fi
    log "storage: $state"
    log "path: $ROOT_DIR"
    log "source: $source"
    log "unit: $UNIT_PATH"
    log "atomic-update list: $KEEP_PATH"
}

case "${1:-install}" in
    install|repair) install_storage ;;
    status) show_status ;;
    *) die "Usage: $0 {install|repair|status}" ;;
esac
