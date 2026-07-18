#!/usr/bin/env bash
# bc250-cec.sh
#
# HDMI-CEC / TV control for the BC-250 on SteamOS, through a DP->HDMI
# adapter that tunnels CEC over the DisplayPort AUX channel.
#
# Discovery notes (July 2026, SteamOS 3.8 / kernel 6.16.12-valve24.2):
#   - The kernel side already works: CONFIG_DRM_DISPLAY_DP_AUX_CEC=y (the
#     modern name of CONFIG_DRM_DP_CEC), so amdgpu exposes /dev/cec0 on the
#     DP-1 AUX channel whenever a CEC-tunneling adapter is attached.
#   - Valve ships a full CEC daemon in the OS image: cecd (user service,
#     D-Bus name com.steampowered.CecDaemon1, config fragments merged from
#     ~/.config/cecd/config.d/*.toml). Out of the box it wakes the TV on
#     resume, suspends the console when the TV turns off, and relays the
#     TV remote as a uinput input device.
#   - Steam's own UI writes 99-steamos-manager.toml in that config dir and
#     rewrites it regularly -- never edit that file. Our overrides go in
#     99-zz-bc250.toml, which sorts after it and therefore wins.
#
# What this script adds on top of cecd:
#   - status/test/scan/monitor tooling for the whole CEC stack
#   - OSD name ("BC-250" instead of "steamdeck" in the TV's device list)
#   - behavior toggles that outrank the Steam UI fragment
#   - TV + receiver standby on POWEROFF (cecd only covers suspend)
#   - wake TV + grab input at cold boot (cecd only covers resume)
#   - receiver power (amp-on/amp-off) via <System Audio Mode Request>
#   - receiver follows the console: amp-follow toggles for boot / poweroff
#     / suspend / resume, stored in ~/.config/bc250-cec.conf and read by
#     the generated helpers at runtime (flip = instant, no reinstall)
#   - multi-device etiquette: 'active' (who holds the input), 'handoff'
#     (route the TV/receiver to another device), 'release' (<Inactive
#     Source>), and both installed units are POLITE -- they never steal
#     the input or power off the TV while another device is the active
#     source. Sharing a receiver with an Apple TV etc. stops being a
#     tug-of-war.
#
# cecd raw-message discovery (verified live): SendReceiveRawMessage
# matches the reply by OPCODE even when the reply is a broadcast --
# <Report Physical Address>, <Device Vendor ID> and <Active Source> all
# come back fine. A broadcast *request* (dest 15) also works; it times
# out iff nobody answers. cecd does NOT loop back its own replies, so
# <Request Active Source> timing out while our Active property is true
# just means "we hold it ourselves".
#
# Root handling deviates from bc250-power.sh on purpose: everything here
# talks to cecd on the *user* D-Bus session, so the script must run as
# deck, NOT root. The one exception -- installing the poweroff standby
# system unit -- shells out to sudo for just that action.
#
# User config and units live in $HOME. System integration lives in /etc and is
# registered in SteamOS's atomic-update keep list during installation.
set -euo pipefail

REAL_USER=$(id -un)
REAL_HOME="${REAL_HOME:-$(getent passwd "$REAL_USER" | cut -d: -f6)}"
[[ "$REAL_HOME" == /* ]] || { echo "Could not resolve home for $REAL_USER" >&2; exit 1; }
HOME=$REAL_HOME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CEC_DEV="/dev/cec0"
TV_LA=0                                      # CEC logical address of the TV

DBUS_NAME="com.steampowered.CecDaemon1"
DAEMON_PATH="/com/steampowered/CecDaemon1/Daemon"
DEV_PATH="/com/steampowered/CecDaemon1/Devices/Cec0"
IF_CONFIG="$DBUS_NAME.Config1"
IF_DEV="$DBUS_NAME.CecDevice1"
CECD_SVC="cecd.service"                      # Valve's daemon (user scope)

CONF_DIR="$HOME/.config/cecd/config.d"
NAME_CONF="$CONF_DIR/50-bc250.toml"          # our osd_name fragment
OVR_CONF="$CONF_DIR/99-zz-bc250.toml"        # toggle overrides (sorts last)

USER_UNIT_DIR="$HOME/.config/systemd/user"
WAKE_UNIT="$USER_UNIT_DIR/bc250-cec-boot-wake.service"
WAKE_SVC="bc250-cec-boot-wake.service"
WAKE_HELPER="$HOME/.local/bin/bc250-cec-boot-wake"
STANDBY_UNIT="/etc/systemd/system/bc250-cec-poweroff-standby.service"
STANDBY_SVC="bc250-cec-poweroff-standby.service"
STANDBY_HELPER="/var/lib/bc250-control/helper/bc250-cec-poweroff-standby"

# Receiver-follow toggles live in our own flat key=value file, read by the
# generated helpers AT RUNTIME -- flipping a toggle never needs a unit
# reinstall. Root helpers get the absolute path baked in at install.
AMP_CONF="$HOME/.config/bc250-cec.conf"
SLEEP_HOOK="/etc/systemd/system-sleep/bc250-cec-amp.sh"
UPDATE_PERSIST_SH="$SCRIPT_DIR/bc250-update-persistence.sh"
STORAGE_SH="$SCRIPT_DIR/bc250-storage.sh"

OSD_DEFAULT="BC-250"                         # CEC OSD name limit: 14 bytes

log()  { echo -e "\033[1;32m[cec]\033[0m $*"; }
warn() { echo -e "\033[1;33m[cec]\033[0m $*"; }
die()  { echo -e "\033[1;31m[cec]\033[0m $*" >&2; exit 1; }
install_update_persistence() {
    [[ -f "$UPDATE_PERSIST_SH" ]] \
        || die "Update persistence helper missing: $UPDATE_PERSIST_SH"
    sudo bash "$UPDATE_PERSIST_SH" install cec
}

require_user() {
    [[ $EUID -ne 0 ]] || die "Run as deck, not root -- cecd lives on deck's user D-Bus session.
      Only 'shutdown-standby install' needs sudo, and it asks by itself."
    [[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]] \
        || die "No user D-Bus session (\$XDG_RUNTIME_DIR/bus missing) -- run from a logged-in deck session."
}

# cecd is D-Bus activatable, so a Ping starts it if the unit isn't up yet.
require_daemon() {
    systemctl --user is-active -q "$CECD_SVC" 2>/dev/null && return 0
    busctl --user --timeout=5 call "$DBUS_NAME" "$DAEMON_PATH" \
        org.freedesktop.DBus.Peer Ping >/dev/null 2>&1 && return 0
    die "cecd is not running and could not be started -- try: systemctl --user start cecd"
}

cleanup() { tui_show_cursor; }
trap cleanup EXIT

# ========================= pure-bash TUI menu =============================
# Same skin as bc250-power.sh: zero dependencies, every menu action calls
# the same cmd_* function as the CLI, nothing is menu-only.
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
# action drops back to the menu instead of killing it
run_action() {
    local rc=0
    ( trap cleanup EXIT; "$@" ) || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo -e "${CR}${CB}[cec]${C0} action failed (exit $rc) -- see message above."
    fi
    pause_key
}

b_ok()   { printf '%s' "${CG}[$1]${C0}"; }
b_mid()  { printf '%s' "${CY}[$1]${C0}"; }
b_off()  { printf '%s' "${CD}[$1]${C0}"; }

c_state() {   # colorize systemctl is-enabled / is-active words
    case "$1" in
        enabled|active|running)          printf '%s' "${CG}$1${C0}" ;;
        failed|masked)                   printf '%s' "${CR}$1${C0}" ;;
        disabled|inactive|not-found|-)   printf '%s' "${CD}$1${C0}" ;;
        *)                               printf '%s' "${CY}$1${C0}" ;;
    esac
}

unit_state() {   # systemctl wrapper that never emits two lines / fails
    local out
    out=$(systemctl "$@" 2>/dev/null | head -1) || true
    echo "${out:--}"
}

# ========================= D-Bus / cecd plumbing ==========================

cecd_up() { systemctl --user is-active -q "$CECD_SVC" 2>/dev/null; }

dev_call() {   # dev_call METHOD [SIG ARGS...]
    local m="$1"; shift
    busctl --user --timeout=5 call "$DBUS_NAME" "$DEV_PATH" "$IF_DEV" "$m" "$@"
}

_prop() {   # _prop PATH IFACE NAME -> value with type letter and quotes stripped
    local out
    out=$(busctl --user --timeout=2 get-property "$DBUS_NAME" "$1" "$2" "$3" 2>/dev/null) \
        || { echo "?"; return 0; }
    out=${out#* }                       # strip the type letter
    out=${out%\"}; out=${out#\"}        # strip quotes on strings
    printf '%s\n' "$out"
}
cfg_prop() { _prop "$DAEMON_PATH" "$IF_CONFIG" "$1"; }
dev_prop() { _prop "$DEV_PATH" "$IF_DEV" "$1"; }

daemon_reload_config() {
    busctl --user --timeout=5 call "$DBUS_NAME" "$DAEMON_PATH" "$IF_CONFIG" Reload \
        || warn "Config1.Reload failed -- try: systemctl --user restart cecd"
}

pa_pretty() {   # decimal physical address -> a.b.c.d (13312 -> 3.4.0.0)
    local d="$1"
    [[ "$d" =~ ^[0-9]+$ ]] || { echo "?"; return 0; }
    printf '%x.%x.%x.%x' $(( (d>>12)&15 )) $(( (d>>8)&15 )) $(( (d>>4)&15 )) $(( d&15 ))
}

la_name() {
    case "$1" in
        0)  echo "TV" ;;
        4)  echo "Playback Device 1" ;;
        5)  echo "Audio System" ;;
        8)  echo "Playback Device 2" ;;
        11) echo "Playback Device 3" ;;
        1|2|9)    echo "Recording Device" ;;
        3|6|7|10) echo "Tuner" ;;
        *)  echo "LA $1" ;;
    esac
}

ala_valid() { [[ "$1" =~ ^[0-9]+$ && "$1" -ge 1 && "$1" -le 14 ]]; }

audio_la() {
    # cecd reports 255 for "no audio system announced" -- and 0 (the TV's
    # address, impossible for an amp) as its unset default, seen live when
    # system audio mode is off. Either way fall back to 5: the CEC spec
    # fixes the audio system there, and a receiver in standby often isn't
    # announced even though it still listens.
    local v; v=$(dev_prop AudioLogicalAddress)
    if ala_valid "$v"; then echo "$v"; else echo 5; fi
}

# Ask a device for its power state: <Give Device Power Status> (0x8f = 143),
# expect <Report Power Status> (0x90 = 144). Reply includes the opcode, so
# the status byte is the LAST field (verified live: "ay 2 144 0").
power_status() {   # power_status LA
    local out
    out=$(busctl --user --timeout=3 call "$DBUS_NAME" "$DEV_PATH" "$IF_DEV" \
          SendReceiveRawMessage ayyyq 1 143 "$1" 144 1500 2>/dev/null) || { echo "no-reply"; return 0; }
    case "${out##* }" in
        0) echo "on" ;;
        1) echo "standby" ;;
        2) echo "standby->on" ;;
        3) echo "on->standby" ;;
        *) echo "unknown" ;;
    esac
}
tv_power_status() { power_status "$TV_LA"; }

# raw_req LA REQ_OPCODE REPLY_OPCODE [TIMEOUT_MS]
# -> reply payload bytes AFTER the opcode ("hi lo ..."), fails on timeout.
# LA 15 broadcasts the request; broadcast replies still match (see header).
raw_req() {
    local out
    out=$(busctl --user --timeout=5 call "$DBUS_NAME" "$DEV_PATH" "$IF_DEV" \
          SendReceiveRawMessage ayyyq 1 "$2" "$1" "$3" "${4:-1500}" 2>/dev/null) || return 1
    echo "$out" | cut -d' ' -f4-
}

raw_send() {   # raw_send LA BYTE... -- fire-and-forget (LA 15 = broadcast)
    local la="$1"; shift
    busctl --user --timeout=5 call "$DBUS_NAME" "$DEV_PATH" "$IF_DEV" \
        SendRawMessage ayy $# "$@" "$la" >/dev/null
}

dev_pa() {   # LA -> decimal physical address, via <Give Physical Address>
    local r bytes; r=$(raw_req "$1" 131 132) || return 1
    read -ra bytes <<< "$r"
    echo $(( ${bytes[0]:-0} * 256 + ${bytes[1]:-0} ))
}

pa_depth() {   # decimal PA -> nesting depth in the HDMI tree (TV = 0)
    local d="$1" n=0
    if (( d & 15 ));         then n=4
    elif (( (d>>4) & 15 ));  then n=3
    elif (( (d>>8) & 15 ));  then n=2
    elif (( (d>>12) & 15 )); then n=1
    fi
    echo "$n"
}

osd_of() {   # LA -> OSD name via <Give OSD Name>, "?" if no reply
    local r b hex char name=""
    r=$(raw_req "$1" 70 71) || { echo "?"; return 0; }
    for b in $r; do
        printf -v hex '%02x' "$b"
        printf -v char '%b' "\\x$hex"
        name+="$char"
    done
    echo "${name:-?}"
}

vendor_of() {   # LA -> brand via <Give Device Vendor ID>, IEEE OUI mapped
    local r bytes id; r=$(raw_req "$1" 140 135) || { echo "-"; return 0; }
    read -ra bytes <<< "$r"
    id=$(printf '%02X%02X%02X' "${bytes[0]:-0}" "${bytes[1]:-0}" "${bytes[2]:-0}")
    case "$id" in
        0010FA) echo "Apple" ;;      00A0DE) echo "Yamaha" ;;
        0000F0) echo "Samsung" ;;    00E091) echo "LG" ;;
        080046) echo "Sony" ;;       008045) echo "Panasonic" ;;
        00903E) echo "Philips" ;;    000039) echo "Toshiba" ;;
        08001F) echo "Sharp" ;;      0009B0) echo "Onkyo" ;;
        0005CD) echo "Denon" ;;      000678) echo "Marantz" ;;
        00E036) echo "Pioneer" ;;    001A11) echo "Google" ;;
        6B746D) echo "Vizio" ;;      000CE7) echo "Amazon" ;;
        *)      echo "$id" ;;
    esac
}

# Decimal PA of the bus's current active source, or fail if nobody claims.
# Instant when it's us (Active property); otherwise <Request Active Source>
# (0x85=133) broadcast, reply <Active Source> (0x82=130) carries the PA.
# Caveat (verified live): "no reply" is NOT proof the input isn't ours.
# cecd flips Active=true only when the TV confirms routing on the bus, and
# TVs stay silent when a claim doesn't change the current path -- so after
# a release + re-claim the property can read false while the TV still
# shows us. The polite gates are unaffected: they only back off when a
# DIFFERENT device answers, and that reply path is verified.
active_source_pa() {
    if [[ "$(dev_prop Active)" == true ]]; then dev_prop PhysicalAddress; return 0; fi
    local r bytes; r=$(raw_req 15 133 130 2000) || return 1
    read -ra bytes <<< "$r"
    echo $(( ${bytes[0]:-0} * 256 + ${bytes[1]:-0} ))
}

# toml_set KEY VALUE FILE -- flat-key TOML edit, no /tmp round-trips
# (temp file lives next to the target, repo rule: fs.protected_regular)
toml_set() {
    local key="$1" val="$2" file="$3" tmp
    mkdir -p "$(dirname "$file")"
    tmp=$(mktemp "$(dirname "$file")/.bc250-cec.XXXXXX")
    if [[ -f "$file" ]]; then
        grep -v "^${key}[[:space:]]*=" "$file" > "$tmp" || true
    fi
    printf '%s = %s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$file"
}

# amp_conf_get KEY DEFAULT / amp_conf_set KEY 0|1 -- receiver-follow flags.
# Same no-/tmp temp-file pattern as toml_set (fs.protected_regular).
amp_conf_get() {
    local v
    v=$(sed -n "s/^${1}=//p" "$AMP_CONF" 2>/dev/null | head -1)
    echo "${v:-$2}"
}

amp_conf_set() {
    local tmp
    mkdir -p "$(dirname "$AMP_CONF")"
    tmp=$(mktemp "$(dirname "$AMP_CONF")/.bc250-cec.XXXXXX")
    if [[ -f "$AMP_CONF" ]]; then
        grep -v "^${1}=" "$AMP_CONF" > "$tmp" || true
    else
        printf '# Written by bc250-cec.sh -- receiver (amp) follow toggles.\n# Read at runtime by the boot-wake/poweroff/sleep helpers.\n' > "$tmp"
    fi
    echo "${1}=${2}" >> "$tmp"
    mv "$tmp" "$AMP_CONF"
}

# key -> default: poweroff standby was always on before it became a toggle
amp_follow_def() { if [[ "$1" == poweroff ]]; then echo 1; else echo 0; fi }

ovr_has() { grep -q "^${1}[[:space:]]*=" "$OVR_CONF" 2>/dev/null; }

ovr_count() {
    grep -cE '^(wake_tv|suspend_tv|allow_standby|uinput)[[:space:]]*=' "$OVR_CONF" 2>/dev/null \
        || echo 0
}

prop_for() {   # toml key -> Config1 property name
    case "$1" in
        wake_tv)       echo WakeTv ;;
        suspend_tv)    echo SuspendTv ;;
        allow_standby) echo AllowStandby ;;
        uinput)        echo Uinput ;;
    esac
}

remote_dev_present() { grep -q 'Name="cecd' /proc/bus/input/devices 2>/dev/null; }

# ============================== badges ====================================

badge_osd() {
    cecd_up || { b_off "cecd not running"; return 0; }
    local name; name=$(cfg_prop OsdName)
    case "$name" in
        "?")        b_off "cecd not answering" ;;
        steamdeck)  b_off "steamdeck (default)" ;;
        *)          b_ok "$name" ;;
    esac
    return 0
}

badge_toggle() {   # badge_toggle <toml-key>
    cecd_up || { b_off "cecd not running"; return 0; }
    local val mark=""
    val=$(cfg_prop "$(prop_for "$1")")
    ovr_has "$1" && mark=" *override"
    case "$val" in
        true)  b_ok "on${mark}" ;;
        false) b_off "off${mark}" ;;
        *)     b_off "?" ;;
    esac
    return 0
}

badge_overrides() {
    local n; n=$(ovr_count)
    if [[ "$n" -gt 0 ]]; then b_mid "$n key(s) overridden"
    else b_off "Steam UI in control"; fi
    return 0
}

badge_standby() {
    if [[ "$(systemctl is-enabled "$STANDBY_SVC" 2>/dev/null)" == enabled ]]; then b_ok "installed"
    elif [[ -f "$STANDBY_UNIT" ]]; then b_mid "present - not enabled"
    else b_off "not installed"; fi
    return 0
}

wake_mode() {   # installed boot-wake helper's mode (polite|grab), or ""
    sed -n 's/^MODE=//p' "$WAKE_HELPER" 2>/dev/null
}

badge_wake() {
    local m; m=$(wake_mode)
    if [[ "$(systemctl --user is-enabled "$WAKE_SVC" 2>/dev/null)" == enabled ]]; then b_ok "installed${m:+ - $m}"
    elif [[ -f "$WAKE_UNIT" ]]; then b_mid "present - not enabled"
    else b_off "not installed"; fi
    return 0
}

badge_wake_mode() {
    case "$(wake_mode)" in
        polite) b_ok "polite - won't steal the input" ;;
        grab)   b_mid "grab - always takes the input" ;;
        *)      b_off "not installed" ;;
    esac
    return 0
}

badge_amp_follow() {   # badge_amp_follow KEY -- one receiver-follow flag
    if [[ "$(amp_conf_get "amp_$1" "$(amp_follow_def "$1")")" == 1 ]]; then b_ok "on"
    else b_off "off"; fi
    return 0
}

badge_amp_power() {   # colorize a power_status word passed in
    case "$1" in
        on|"standby->on") b_ok "$1" ;;
        standby|"on->standby") b_mid "$1" ;;
        *) b_off "$1" ;;
    esac
    return 0
}

badge_amp_summary() {
    local n=0 k
    for k in boot poweroff suspend resume; do
        [[ "$(amp_conf_get "amp_$k" "$(amp_follow_def "$k")")" == 1 ]] && n=$((n+1))
    done
    if (( n > 0 )); then b_ok "$n follow(s) on"; else b_off "no follows"; fi
    return 0
}

badge_sleep_hook() {
    if [[ -f "$SLEEP_HOOK" ]]; then b_ok "installed"; else b_off "not installed"; fi
    return 0
}

badge_active() {   # cheap: Active property only, no bus traffic
    cecd_up || { b_off "cecd not running"; return 0; }
    if [[ "$(dev_prop Active)" == true ]]; then b_ok "input is ours"
    else b_mid "not ours"; fi
    return 0
}

badge_remote() {
    cecd_up || { b_off "cecd not running"; return 0; }
    local val; val=$(cfg_prop Uinput)
    if [[ "$val" == true ]] && remote_dev_present; then b_ok "active"
    elif [[ "$val" == true ]]; then b_mid "enabled - no device"
    else b_off "off"; fi
    return 0
}

# ============================== status ====================================

cmd_status() {
    require_user
    echo -e "${CB}== CEC device ==${C0}"
    if [[ -e "$CEC_DEV" ]]; then
        echo "  $CEC_DEV: present ($(stat -c '%A %U:%G' "$CEC_DEV" 2>/dev/null || echo '?'))"
    else
        echo -e "  $CEC_DEV: ${CR}MISSING${C0} -- adapter unplugged, or it doesn't tunnel CEC over DP"
    fi

    echo -e "${CB}== cecd daemon (Valve, user service) ==${C0}"
    local act; act=$(systemctl --user is-active "$CECD_SVC" 2>/dev/null || true)
    echo "  cecd.service: $(c_state "${act:--}")  ${CD}(statically enabled via graphical-session.target)${C0}"
    if ! cecd_up; then
        warn "cecd is down -- the sections below will be empty. Try: systemctl --user start cecd"
    fi

    echo -e "${CB}== identity on the CEC bus ==${C0}"
    local osd la pa active ala
    osd=$(cfg_prop OsdName); pa=$(dev_prop PhysicalAddress); active=$(dev_prop Active)
    la=$(dev_prop LogicalAddresses)     # "count v1 v2..."
    ala=$(dev_prop AudioLogicalAddress)
    local la_disp="?"
    if [[ "$la" =~ ^[0-9]+[[:space:]] ]]; then
        la_disp=""
        local v
        for v in ${la#* }; do la_disp+="${la_disp:+, }$v ($(la_name "$v"))"; done
    fi
    echo "  OSD name:         $osd"
    echo "  logical address:  $la_disp"
    echo "  physical address: $(pa_pretty "$pa")"
    if [[ "$active" == true ]]; then
        echo "  active source:    yes -- the TV/receiver input is ours"
    else
        echo "  active source:    no -- another device (or nobody) holds it; see '$0 active'"
    fi
    if ala_valid "$ala"; then
        echo "  audio system:     LA $ala ($(la_name "$ala")) -- vol-up/vol-down/mute target"
    else
        echo "  audio system:     none announced (amp + volume verbs assume LA 5)"
    fi

    echo -e "${CB}== behavior (effective cecd config) ==${C0}"
    local key
    for key in wake_tv suspend_tv allow_standby uinput; do
        local src="steam-ui"; ovr_has "$key" && src="override"
        printf '  %-15s %-6s (%s)\n' "$key" "$(cfg_prop "$(prop_for "$key")")" "$src"
    done

    echo -e "${CB}== TV ==${C0}"
    echo "  power status: $(tv_power_status)"

    echo -e "${CB}== installed extras ==${C0}"
    echo "  poweroff standby unit: $(c_state "$(unit_state is-enabled "$STANDBY_SVC")")"
    echo "  boot wake unit (user): $(c_state "$(unit_state --user is-enabled "$WAKE_SVC")")"
    echo "  amp suspend/resume hook: $([[ -f "$SLEEP_HOOK" ]] && echo present || echo absent)"
    local k follows=""
    for k in boot poweroff suspend resume; do
        follows+="${follows:+ }$k=$(amp_conf_get "amp_$k" "$(amp_follow_def "$k")")"
    done
    echo "  receiver follows: $follows"
    [[ -f "$NAME_CONF" ]] && echo "  $NAME_CONF: present" || echo "  $NAME_CONF: not written"
    [[ -f "$OVR_CONF"  ]] && echo "  $OVR_CONF: present ($(ovr_count) key(s))" || echo "  $OVR_CONF: not written"

    echo -e "${CB}== TV remote ==${C0}"
    if remote_dev_present; then
        echo "  cecd uinput device present -- TV remote keys reach the system"
    else
        echo "  no cecd input device (uinput off, or no remote traffic yet)"
    fi
}

# ============================ OSD name ====================================

cmd_osd_name() {
    require_user; require_daemon
    local name="${1:-}"
    if [[ "$name" == "--reset" ]]; then
        rm -f "$NAME_CONF"
        daemon_reload_config >/dev/null
        log "OSD name fragment removed -- back to cecd's default after next restart."
        return 0
    fi
    if [[ -z "$name" ]]; then
        ask "TV OSD name (max 14 bytes)" "$OSD_DEFAULT"; name="$REPLY"
    fi
    local bytes; bytes=$(printf %s "$name" | wc -c)
    (( bytes >= 1 && bytes <= 14 )) || die "OSD name must be 1-14 bytes (got $bytes)."
    if [[ ! -f "$NAME_CONF" ]]; then
        mkdir -p "$CONF_DIR"
        printf '# Written by bc250-cec.sh -- OSD name shown in the TV device list.\n' > "$NAME_CONF"
    fi
    toml_set osd_name "\"$name\"" "$NAME_CONF"
    daemon_reload_config >/dev/null
    dev_call SetOsdName s "$name" >/dev/null 2>&1 \
        || warn "SetOsdName bus call failed (config still saved; takes effect on cecd restart)"
    local eff; eff=$(cfg_prop OsdName)
    if [[ "$eff" == "$name" ]]; then
        log "OSD name: $name (saved to $NAME_CONF, live on the bus)"
    else
        warn "Saved, but cecd still reports '$eff' -- config merge order may differ; check 'status'."
    fi
}

# ============================ toggles =====================================

cmd_toggle() {
    local arg="${1:-}" want="${2:-}" toml
    case "$arg" in
        wake-tv)       toml=wake_tv ;;
        suspend-tv)    toml=suspend_tv ;;
        allow-standby) toml=allow_standby ;;
        uinput)        toml=uinput ;;
        *) die "usage: $0 toggle {wake-tv|suspend-tv|allow-standby|uinput} [on|off]" ;;
    esac
    require_user; require_daemon
    local prop cur new
    prop=$(prop_for "$toml")
    cur=$(cfg_prop "$prop")
    case "$want" in
        on)  new=true ;;
        off) new=false ;;
        "")  if [[ "$cur" == true ]]; then new=false; else new=true; fi ;;
        *)   die "usage: $0 toggle $arg [on|off]" ;;
    esac
    if [[ ! -f "$OVR_CONF" ]]; then
        mkdir -p "$CONF_DIR"
        cat > "$OVR_CONF" << 'EOF'
# Written by bc250-cec.sh -- overrides Steam UI CEC toggles.
# Sorts after 99-steamos-manager.toml so these values win.
# Delete this file (or run 'bc250-cec.sh clear-overrides') to give
# control back to Steam's Settings UI.
EOF
        warn "First override: Steam UI toggles stop having effect for keys set here."
        warn "Undo any time with: $0 clear-overrides"
    fi
    toml_set "$toml" "$new" "$OVR_CONF"
    daemon_reload_config >/dev/null
    local eff; eff=$(cfg_prop "$prop")
    log "$arg: $cur -> $eff"
    if [[ "$eff" != "$new" ]]; then
        warn "Effective value did not follow the override -- cecd's config merge order"
        warn "may differ from expected. Reverting is safe: $0 clear-overrides"
        return 1
    fi
    # Reload updates the property, but uinput device plumbing may need a
    # real restart to appear/disappear.
    if [[ "$toml" == uinput ]]; then
        sleep 2
        local have=0; remote_dev_present && have=1
        if { [[ "$new" == true && $have -eq 0 ]] || [[ "$new" == false && $have -eq 1 ]]; } && [[ -t 0 ]]; then
            ask "uinput device state didn't change yet -- restart cecd now? [Y/n]" "Y"
            [[ "$REPLY" =~ ^[Yy] ]] && systemctl --user restart "$CECD_SVC" && log "cecd restarted."
        fi
    fi
}

cmd_clear_overrides() {
    require_user
    if [[ ! -f "$OVR_CONF" ]]; then
        log "No overrides file -- Steam UI already in control."
        return 0
    fi
    rm -f "$OVR_CONF"
    cecd_up && daemon_reload_config >/dev/null
    log "Overrides cleared. Effective toggles now:"
    local key
    for key in wake_tv suspend_tv allow_standby uinput; do
        printf '  %-15s %s\n' "$key" "$(cfg_prop "$(prop_for "$key")")"
    done
}

# ================= TV + receiver standby on poweroff ======================
# cecd's suspend_tv covers suspend only. This system unit covers poweroff:
# it is inert at boot (ExecStart=true, RemainAfterExit) and does its work in
# ExecStop, which systemd runs early in shutdown while /dev/cec0, journald
# and systemctl are all still alive. The gate on the queued goal target
# excludes reboot; suspend never stops the unit at all. cec-ctl (v4l-utils)
# is used instead of cecd/D-Bus because the user session may already be
# tearing down -- and a second fd transmitting alongside cecd is verified
# to work.
#
# Also POLITE: before sending standby it asks the bus who the active source
# is (cec-ctl --request-active-source). If another device answers -- someone
# is watching the Apple TV through the same receiver -- the TV and receiver
# stay on. When WE hold the input there is no reply (cecd never answers a
# request sent from its own logical address, and it's dead by now anyway),
# so the standby proceeds. Verified live: an active Apple TV replies with
# "phys-addr: 3.2.0.0"-style output; the sed below extracts exactly that.

cmd_shutdown_standby() {
    local action="${1:-status}"
    case "$action" in
        install)
            require_user
            [[ -f "$STORAGE_SH" ]] || die "Storage helper missing: $STORAGE_SH"
            sudo bash "$STORAGE_SH" install
            install_update_persistence
            log "Installing $STANDBY_SVC + helper (sudo)..."
            { printf '#!/bin/bash\nconf=%q\n' "$AMP_CONF"; cat << 'EOF'
# Written by bc250-cec.sh -- CEC standby to TV + receiver on poweroff.
# Runs from the unit's ExecStop; regenerate via "bc250-cec.sh
# shutdown-standby install"; do not edit.
# Gate 1: real poweroff/halt only -- reboot and suspend leave the TV alone.
systemctl list-jobs | grep -qE '(poweroff|halt)\.target.*start' || exit 0
dev=/dev/cec0
[ -e "$dev" ] || exit 0
# Gate 2 (polite): if another device is the active source, someone is
# still watching -- leave the TV and receiver on.
own=$(cec-ctl -d "$dev" 2>/dev/null | sed -n 's/.*Physical Address *: *//p' | head -1)
act=$(cec-ctl -s -d "$dev" --request-active-source 2>/dev/null \
      | sed -n 's/.*phys-addr: *\([0-9a-f.]*\).*/\1/p' | head -1)
if [ -n "$act" ] && [ "$act" != "$own" ]; then
    exit 0
fi
# LA 0 = TV, LA 5 = audio system; a missing receiver just never ACKs.
cec-ctl -s -d "$dev" --to 0 --standby || true
# receiver standby is a toggle (default on): bc250-cec.sh amp-follow poweroff
grep -qx 'amp_poweroff=0' "$conf" 2>/dev/null \
    || cec-ctl -s -d "$dev" --to 5 --standby || true
EOF
            } | sudo tee "$STANDBY_HELPER" >/dev/null
            sudo chmod +x "$STANDBY_HELPER"
            sudo rm -f /etc/bc250-cec-poweroff-standby.sh
            sudo tee "$STANDBY_UNIT" >/dev/null << EOF
[Unit]
Description=BC-250: CEC standby to TV + receiver on poweroff (polite)
# Inert at boot; the work happens in ExecStop during shutdown.
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/true
ExecStop=$STANDBY_HELPER
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
            sudo systemctl daemon-reload
            sudo systemctl enable "$STANDBY_SVC" >/dev/null 2>&1
            sudo systemctl start "$STANDBY_SVC"
            log "Installed. TV + receiver stand by on poweroff (not reboot/suspend) --"
            log "unless another device holds the input; then they stay on for it."
            ;;
        remove)
            require_user
            log "Removing $STANDBY_SVC (sudo)..."
            sudo systemctl disable --now "$STANDBY_SVC" >/dev/null 2>&1 || true
            sudo rm -f "$STANDBY_UNIT" "$STANDBY_HELPER" \
                /etc/bc250-cec-poweroff-standby.sh
            sudo systemctl daemon-reload
            log "Removed."
            ;;
        status)
            echo "  unit file: $STANDBY_UNIT $([[ -f "$STANDBY_UNIT" ]] && echo present || echo absent)"
            echo "  helper:    $STANDBY_HELPER $([[ -f "$STANDBY_HELPER" ]] && echo present || echo absent)"
            echo "  enabled:   $(systemctl is-enabled "$STANDBY_SVC" 2>/dev/null || echo -)"
            echo "  active:    $(systemctl is-active "$STANDBY_SVC" 2>/dev/null || echo -)"
            ;;
        *) die "usage: $0 shutdown-standby {install|remove|status}" ;;
    esac
}

shutdown_standby_toggle() {   # menu helper: flip install state
    if [[ "$(systemctl is-enabled "$STANDBY_SVC" 2>/dev/null)" == enabled ]]; then
        cmd_shutdown_standby remove
    else
        cmd_shutdown_standby install
    fi
}

# ========================= wake TV at boot ================================
# cecd wakes the TV on resume-from-suspend (wake_tv) but does nothing at
# cold boot. This user unit runs a generated helper once per session start;
# Wake() powers the TV on AND switches its input to us. cecd is D-Bus
# activatable, so the calls also cover "cecd not started yet"; the retry
# loop covers the adapter still negotiating HPD right after boot.
#
# Order matters when the console is plugged THROUGH the receiver: the amp
# wake (amp-follow boot) runs first, and TV wake + <Active Source> wait for
# the amp to report on -- a receiver in standby misses broadcasts, and a TV
# woken early just shows a dead input.
#
# Default mode is POLITE: if the TV is already on and another device is the
# active source (someone's watching the Apple TV), the helper backs off
# instead of yanking the input. 'install grab' restores the old behavior.
# The polite probe stays FIRST (before the amp wake): it's read-only, and
# <System Audio Mode Request> would steal the audio path from an active
# device if we sent it before looking.
# The active-source probe can't misfire on ourselves: cecd never answers
# <Request Active Source> sent from its own logical address, and at session
# start we haven't claimed anything yet anyway.

write_wake_helper() {   # write_wake_helper polite|grab
    mkdir -p "$(dirname "$WAKE_HELPER")"
    {
        printf '#!/bin/bash\n'
        printf '# Written by bc250-cec.sh -- TV wake at session start. Regenerate with\n'
        printf '# "bc250-cec.sh boot-wake install [polite|grab]"; do not edit.\n'
        printf 'MODE=%q\n' "$1"
        printf 'CONF=%q\n' "$AMP_CONF"
        cat << 'EOF'
D=(busctl --user --timeout=5 call com.steampowered.CecDaemon1
   /com/steampowered/CecDaemon1/Devices/Cec0
   com.steampowered.CecDaemon1.CecDevice1)
# TV power status (0x8f -> 0x90), retried while the adapter settles
st=""
for i in 1 2 3 4 5; do
    out=$("${D[@]}" SendReceiveRawMessage ayyyq 1 143 0 144 1500 2>/dev/null) \
        && { st=${out##* }; break; }
    sleep 2
done
if [[ -z "$st" ]]; then
    echo "bc250-cec: TV power probe got no reply after retries -- adapter/cecd may not be up; attempting wake anyway" \
        | systemd-cat -t bc250-cec-boot-wake -p warning
fi
if [[ "$MODE" == polite && ( "$st" == 0 || "$st" == 2 ) ]]; then
    # TV is on (or waking): if any device answers <Request Active Source>,
    # someone else is watching -- leave the input alone.
    if "${D[@]}" SendReceiveRawMessage ayyyq 1 133 15 130 2000 >/dev/null 2>&1; then
        exit 0
    fi
fi
# Receiver wake FIRST (toggle: bc250-cec.sh amp-follow boot): with the
# console plugged THROUGH the receiver, the amp must be up for the TV to
# have a picture to route to -- and a receiver in standby misses routing
# broadcasts (same behavior 'handoff' works around), so the <Active
# Source> claim below has to wait for it. <System Audio Mode Request>
# with our PA = "amp on + take the audio"; LA 5 is fixed by spec. The PA
# read retries: the adapter can register late at boot (65535 = f.f.f.f).
amp_sent=0
if grep -qx 'amp_boot=1' "$CONF" 2>/dev/null; then
    pa=""
    for i in 1 2 3 4; do
        pa=$(busctl --user --timeout=5 get-property com.steampowered.CecDaemon1 \
             /com/steampowered/CecDaemon1/Devices/Cec0 \
             com.steampowered.CecDaemon1.CecDevice1 PhysicalAddress 2>/dev/null \
             | awk '{print $2}')
        [[ "$pa" =~ ^[0-9]+$ ]] && (( pa != 65535 )) && break
        sleep 2
    done
    if [[ "$pa" =~ ^[0-9]+$ ]] && (( pa != 65535 )); then
        "${D[@]}" SendRawMessage ayy 3 112 $(( (pa>>8)&255 )) $(( pa&255 )) 5 >/dev/null || true
        amp_sent=1
    else
        echo "bc250-cec: own physical address never registered -- receiver boot wake skipped" \
            | systemd-cat -t bc250-cec-boot-wake -p warning
    fi
fi
# Hold ALL TV commands until the amp reports on (0x8f -> 0x90, status 0):
# a receiver mid-wake misses broadcasts, and waking the TV first just
# routes it to a dead input. Give up after ~20 s and proceed anyway --
# better a late picture than none.
if [[ $amp_sent == 1 ]]; then
    for i in 1 2 3 4 5 6; do
        out=$("${D[@]}" SendReceiveRawMessage ayyyq 1 143 5 144 1500 2>/dev/null) \
            && [[ "${out##* }" == 0 ]] && break
        sleep 2
    done
fi
# Wake = TV power on + input to us; the explicit claim after it is needed
# because Wake alone doesn't broadcast <Active Source> (verified live).
"${D[@]}" Wake || true
"${D[@]}" SetActiveSource i -- -1 || true
exit 0
EOF
    } > "$WAKE_HELPER"
    chmod +x "$WAKE_HELPER"
}

cmd_boot_wake() {
    local action="${1:-status}" mode="${2:-polite}"
    case "$action" in
        install)
            require_user
            [[ "$mode" == polite || "$mode" == grab ]] \
                || die "usage: $0 boot-wake install [polite|grab]"
            write_wake_helper "$mode"
            mkdir -p "$USER_UNIT_DIR"
            cat > "$WAKE_UNIT" << EOF
[Unit]
Description=BC-250: wake the TV at session start (mode: $mode)
After=cecd.service
Wants=cecd.service

[Service]
Type=oneshot
ExecStart=$WAKE_HELPER

[Install]
WantedBy=graphical-session.target
EOF
            systemctl --user daemon-reload
            systemctl --user enable "$WAKE_SVC" >/dev/null 2>&1
            if [[ "$mode" == polite ]]; then
                log "Installed (polite). TV wakes at session start -- but if another device"
                log "is already the active source on a TV that's on, we don't steal the input."
            else
                log "Installed (grab). TV wakes + switches to the BC-250 at every session start."
            fi
            ;;
        remove)
            require_user
            systemctl --user disable "$WAKE_SVC" >/dev/null 2>&1 || true
            rm -f "$WAKE_UNIT" "$WAKE_HELPER"
            systemctl --user daemon-reload
            log "Removed."
            ;;
        status)
            echo "  unit file: $WAKE_UNIT $([[ -f "$WAKE_UNIT" ]] && echo present || echo absent)"
            echo "  helper:    $WAKE_HELPER $([[ -x "$WAKE_HELPER" ]] && echo "present (mode: $(wake_mode))" || echo absent)"
            echo "  enabled:   $(systemctl --user is-enabled "$WAKE_SVC" 2>/dev/null || echo -)"
            ;;
        *) die "usage: $0 boot-wake {install [polite|grab]|remove|status}" ;;
    esac
}

boot_wake_toggle() {
    if [[ "$(systemctl --user is-enabled "$WAKE_SVC" 2>/dev/null)" == enabled ]]; then
        cmd_boot_wake remove
    else
        cmd_boot_wake install
    fi
}

boot_wake_mode_toggle() {   # menu helper: polite <-> grab (reinstall keeps the unit)
    local m; m=$(wake_mode)
    [[ -n "$m" ]] || die "Boot-wake is not installed -- install it first; the mode is part of the install."
    if [[ "$m" == polite ]]; then cmd_boot_wake install grab; else cmd_boot_wake install polite; fi
}

# ==================== receiver follows the console ========================
# Four toggles that make the receiver's power track the console: boot,
# poweroff, suspend, resume. Flags live in $AMP_CONF and are read by the
# helpers at runtime, so flipping one is instant -- but each needs its
# carrier installed: boot -> boot-wake unit, poweroff -> shutdown-standby
# unit, suspend/resume -> the amp-sleep hook below. Standby paths keep the
# polite gate: a receiver someone else is playing through stays on.

cmd_amp_follow() {
    local key="${1:-}" want="${2:-}"
    case "$key" in
        boot|poweroff|suspend|resume) ;;
        *) die "usage: $0 amp-follow {boot|poweroff|suspend|resume} [on|off]" ;;
    esac
    require_user
    local ck="amp_$key" cur new
    cur=$(amp_conf_get "$ck" "$(amp_follow_def "$key")")
    [[ "$cur" == 1 ]] || cur=0   # tolerate a hand-edited conf
    case "$want" in
        on)  new=1 ;;
        off) new=0 ;;
        "")  if [[ "$cur" == 1 ]]; then new=0; else new=1; fi ;;
        *)   die "usage: $0 amp-follow $key [on|off]" ;;
    esac
    amp_conf_set "$ck" "$new"
    local words=(off on)
    log "receiver follow '$key': ${words[$cur]} -> ${words[$new]}"
    case "$key" in
        boot)
            # regenerate the helper in case it predates amp support; a
            # pre-MODE helper reads back empty -- default that to polite
            # rather than silently behaving as grab
            if [[ -x "$WAKE_HELPER" ]]; then
                local m; m=$(wake_mode)
                write_wake_helper "${m:-polite}"
            fi
            [[ "$(systemctl --user is-enabled "$WAKE_SVC" 2>/dev/null)" == enabled ]] \
                || warn "Needs the boot-wake unit to act: $0 boot-wake install"
            ;;
        poweroff)
            # helper must exist AND know about the toggle (older installs don't)
            grep -q amp_poweroff "$STANDBY_HELPER" 2>/dev/null \
                || warn "Poweroff unit missing or predates this toggle -- refresh: $0 shutdown-standby install"
            ;;
        suspend|resume)
            [[ -f "$SLEEP_HOOK" ]] \
                || warn "Needs the sleep hook to act: $0 amp-sleep install"
            ;;
    esac
    return 0
}

cmd_amp_sleep() {
    local action="${1:-status}"
    case "$action" in
        install)
            require_user
            install_update_persistence
            log "Installing $SLEEP_HOOK (sudo)..."
            sudo mkdir -p "$(dirname "$SLEEP_HOOK")"
            { printf '#!/bin/bash\nconf=%q\n' "$AMP_CONF"; cat << 'EOF'
# Written by bc250-cec.sh -- receiver (CEC audio system, LA 5) follows
# console suspend/resume. Runs as root from systemd-sleep; the TV side is
# cecd's job (wake_tv/suspend_tv). Toggles: bc250-cec.sh amp-follow
# suspend|resume -- this hook is inert while both are off.
dev=/dev/cec0
flag() { grep -qx "$1=1" "$conf" 2>/dev/null; }
case "$1" in
pre)
    flag amp_suspend || exit 0
    [ -e "$dev" ] || exit 0
    # polite: if another device is playing through the receiver, leave it on
    own=$(cec-ctl -d "$dev" 2>/dev/null | sed -n 's/.*Physical Address *: *//p' | head -1)
    act=$(cec-ctl -s -d "$dev" --request-active-source 2>/dev/null \
          | sed -n 's/.*phys-addr: *\([0-9a-f.]*\).*/\1/p' | head -1)
    if [ -n "$act" ] && [ "$act" != "$own" ]; then exit 0; fi
    cec-ctl -s -d "$dev" --to 5 --standby || true
    ;;
post)
    flag amp_resume || exit 0
    # Backgrounded: the DP link (and /dev/cec0 behind a receiver's standby
    # passthrough) can take seconds to renegotiate after resume, and a
    # sleep hook must not block resume while we retry.
    (
        for i in 1 2 3 4 5; do
            if [ -e "$dev" ]; then
                pa=$(cec-ctl -d "$dev" 2>/dev/null | sed -n 's/.*Physical Address *: *//p' | head -1)
                # f.f.f.f = registration not back yet -- keep retrying
                [ -n "$pa" ] && [ "$pa" != "f.f.f.f" ] \
                    && cec-ctl -s -d "$dev" --to 5 --system-audio-mode-request phys-addr="$pa" \
                    && exit 0
            fi
            sleep 2
        done
    ) >/dev/null 2>&1 &
    ;;
esac
exit 0
EOF
            } | sudo tee "$SLEEP_HOOK" >/dev/null
            sudo chmod +x "$SLEEP_HOOK"
            log "Installed. Acts on the 'suspend' / 'resume' follows (both currently:"
            log "suspend=$(amp_conf_get amp_suspend 0) resume=$(amp_conf_get amp_resume 0) -- flip with: $0 amp-follow suspend|resume)"
            ;;
        remove)
            require_user
            log "Removing $SLEEP_HOOK (sudo)..."
            sudo rm -f "$SLEEP_HOOK"
            log "Removed."
            ;;
        status)
            echo "  hook file: $SLEEP_HOOK $([[ -f "$SLEEP_HOOK" ]] && echo present || echo absent)"
            ;;
        *) die "usage: $0 amp-sleep {install|remove|status}" ;;
    esac
}

amp_sleep_toggle() {   # menu helper
    if [[ -f "$SLEEP_HOOK" ]]; then cmd_amp_sleep remove; else cmd_amp_sleep install; fi
}

# ======================== recommended setup ===============================

cmd_setup() {
    require_user; require_daemon
    log "Recommended setup: OSD name, TV standby on suspend + poweroff, wake at boot."
    echo
    log "[1/4] OSD name -> $OSD_DEFAULT"
    cmd_osd_name "$OSD_DEFAULT" || warn "OSD name step failed -- continuing."
    echo
    log "[2/4] Standby TV when the console suspends"
    cmd_toggle suspend-tv on || warn "suspend-tv toggle failed -- continuing."
    echo
    log "[3/4] Standby TV on poweroff (needs sudo)"
    cmd_shutdown_standby install || warn "poweroff unit install failed -- continuing."
    echo
    log "[4/4] Wake TV at boot"
    cmd_boot_wake install || warn "boot wake install failed -- continuing."
    if [[ -t 0 ]]; then
        echo
        ask "Also wake the receiver (amp) at boot? [y/N]" "N"
        if [[ "$REPLY" =~ ^[Yy] ]]; then
            cmd_amp_follow boot on || warn "amp boot follow failed -- continuing."
        else
            log "Skipped -- flip later with: $0 amp-follow boot on"
        fi
    fi
    echo
    log "Done. Already on out of the box: wake TV on resume, suspend console"
    log "when the TV turns off, TV remote as input. Check with: $0 status"
}

# ============================== tests =====================================

t_pass() { echo -e "  ${CG}${CB}PASS${C0} $*"; }
t_fail() { echo -e "  ${CR}${CB}FAIL${C0} $*"; }
t_skip() { echo -e "  ${CD}skip${C0} $*"; }

cmd_test() {
    require_user; require_daemon
    log "Guided TV-control test. Steps never abort the sequence."
    echo

    if dev_call Poll y "$TV_LA" >/dev/null 2>&1; then
        t_pass "TV answers polls at logical address $TV_LA"
    else
        t_fail "TV did not ACK a poll -- is it on this HDMI input / CEC enabled in its menu?"
    fi

    local st; st=$(tv_power_status)
    if [[ "$st" == no-reply ]]; then
        t_fail "TV power status: no reply"
    else
        t_pass "TV power status: $st"
    fi

    log "Waking the TV (Wake = power on + switch input to us)..."
    if dev_call Wake >/dev/null 2>&1; then
        sleep 3
        st=$(tv_power_status)
        case "$st" in
            on|"standby->on") t_pass "TV reports '$st' after Wake" ;;
            *)                t_fail "TV reports '$st' after Wake (some TVs are slow -- re-run status)" ;;
        esac
    else
        t_fail "Wake call failed"
    fi

    log "Claiming active source..."
    if dev_call SetActiveSource i -- -1 >/dev/null 2>&1; then
        sleep 2
        if [[ "$(dev_prop Active)" == true ]]; then
            t_pass "BC-250 is the active source"
        else
            t_fail "SetActiveSource sent but Active still false"
        fi
    else
        t_fail "SetActiveSource call failed"
    fi

    local ala; ala=$(dev_prop AudioLogicalAddress)
    if ala_valid "$ala"; then
        local astat
        if astat=$(dev_call GetAudioStatus y "$ala" 2>/dev/null); then
            t_pass "audio system LA $ala: volume $(echo "$astat" | awk '{print $2}')%, mute $(echo "$astat" | awk '{print $3}')"
            log "Volume blip (up, then back down)..."
            dev_call VolumeUp y "$ala" >/dev/null 2>&1 || true
            sleep 1
            dev_call VolumeDown y "$ala" >/dev/null 2>&1 || true
        else
            t_skip "audio system present (LA $ala) but no audio status reply -- soundbar off?"
        fi
    else
        t_skip "no audio system on the bus"
    fi

    if [[ -t 0 ]]; then
        echo
        ask "Send TV standby to test power-off? [y/N]" "N"
        if [[ "$REPLY" =~ ^[Yy] ]]; then
            dev_call Standby y "$TV_LA" >/dev/null 2>&1 || true
            sleep 3
            st=$(tv_power_status)
            case "$st" in
                standby|"on->standby"|no-reply) t_pass "TV standing by ('$st')" ;;
                *)                              t_fail "TV still reports '$st'" ;;
            esac
            # auto-wake: the terminal is usually ON the TV we just put to
            # sleep, so a prompt here would never be seen
            log "Waking the TV back up..."
            dev_call Wake >/dev/null 2>&1 || true
            sleep 3
            st=$(tv_power_status)
            case "$st" in
                on|"standby->on") t_pass "TV back on ('$st')" ;;
                *)                t_fail "TV reports '$st' after wake-back -- manual recovery: $0 tv-on" ;;
            esac
        fi
    fi
}

# =============================== scan =====================================

cmd_scan() {
    require_user; require_daemon
    # Poll is a bus-level ACK probe (fast NACK for empty addresses), so
    # sweeping all 15 addresses is cheap; details are only fetched from
    # devices that ACK. Rows sort by physical address, which nests the
    # HDMI tree naturally (3.0.0.0 receiver, 3.4.0.0 = its input 4).
    local ours
    ours=" $(dev_prop LogicalAddresses | cut -d' ' -f2- ) "
    log "Scanning the CEC bus (logical addresses 0-14)..."
    local act; act=$(active_source_pa) || act=""
    local rows=() la pa
    for la in {0..14}; do
        if [[ "$ours" == *" $la "* ]]; then
            pa=$(dev_prop PhysicalAddress)
            rows+=("$pa|$la|$(cfg_prop OsdName)|-|(this device)")
            continue
        fi
        dev_call Poll y "$la" >/dev/null 2>&1 || continue
        pa=$(dev_pa "$la") || pa=65535
        rows+=("$pa|$la|$(osd_of "$la")|$(vendor_of "$la")|$(power_status "$la")")
    done
    printf '  %-13s %-3s %-20s %-16s %-10s %s\n' "physical" "LA" "role" "OSD name" "vendor" "power"
    local name vend st indent mark padisp
    while IFS='|' read -r pa la name vend st; do
        indent=$(printf '%*s' $(( $(pa_depth "$pa") * 2 )) "")
        padisp=$(pa_pretty "$pa"); [[ "$pa" == 65535 ]] && padisp="?"
        mark=""
        [[ -n "$act" && "$pa" == "$act" ]] && mark=" ${CG}<- active source${C0}"
        printf '  %-13s %-3s %-20s %-16s %-10s %s%s\n' \
            "${indent}${padisp}" "$la" "$(la_name "$la")" "$name" "$vend" "$st" "$mark"
    done < <(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1n)
    [[ -n "$act" ]] || echo "  ${CD}(no active source -- nobody currently claims the input)${C0}"
}

# ===================== playing nice with other devices ====================
# The classic multi-CEC-device fight: two sources behind one receiver both
# fire <Active Source> / One Touch Play and yank the input around. These
# verbs (plus the polite install units) are the ceasefire: look first, ask
# for the input politely, give it back when done.

cmd_active() {
    require_user; require_daemon
    if [[ "$(dev_prop Active)" == true ]]; then
        log "We are the active source ($(pa_pretty "$(dev_prop PhysicalAddress)")) -- the TV/receiver input is ours."
        return 0
    fi
    local pa
    if ! pa=$(active_source_pa); then
        log "No active source claimed on the bus."
        echo "  TV off / on a non-CEC input -- or it's silently showing us: TVs don't"
        echo "  re-announce routing that didn't change. 'switch' claims it cleanly."
        return 0
    fi
    # Name the holder: find the logical address reporting that physical
    # address (the <Active Source> broadcast doesn't carry identity).
    local ours la hold=""
    ours=" $(dev_prop LogicalAddresses | cut -d' ' -f2- ) "
    for la in {0..14}; do
        [[ "$ours" == *" $la "* ]] && continue
        dev_call Poll y "$la" >/dev/null 2>&1 || continue
        [[ "$(dev_pa "$la" || echo -1)" == "$pa" ]] || continue
        hold="LA $la, $(la_name "$la"), \"$(osd_of "$la")\""
        break
    done
    log "Active source: $(pa_pretty "$pa")${hold:+ ($hold)} -- another device holds the input."
    echo "  Take it over: '$0 switch' -- or leave them alone; that's the point."
}

cmd_handoff() {
    require_user; require_daemon
    local target="${1:-}"
    if [[ -z "$target" && -t 0 ]]; then
        cmd_scan
        echo
        ask "Hand the input to (LA number or physical address a.b.c.d)"
        target="$REPLY"
    fi
    [[ -n "$target" ]] || die "usage: $0 handoff <LA | a.b.c.d>   ('scan' lists both)"
    local pa la="" a b c d
    if [[ "$target" =~ ^[0-9a-fA-F]\.[0-9a-fA-F]\.[0-9a-fA-F]\.[0-9a-fA-F]$ ]]; then
        IFS=. read -r a b c d <<< "$target"
        pa=$(( 16#$a<<12 | 16#$b<<8 | 16#$c<<4 | 16#$d ))
        # find the LA behind that PA -- needed for the wake step below
        local ours cand
        ours=" $(dev_prop LogicalAddresses | cut -d' ' -f2- ) "
        for cand in {0..14}; do
            [[ "$ours" == *" $cand "* ]] && continue
            dev_call Poll y "$cand" >/dev/null 2>&1 || continue
            [[ "$(dev_pa "$cand" || echo -1)" == "$pa" ]] && { la=$cand; break; }
        done
    elif [[ "$target" =~ ^[0-9]+$ ]] && (( target <= 14 )); then
        la=$target
        dev_call Poll y "$la" >/dev/null 2>&1 || die "Nothing answers at LA $la -- try 'scan'."
        pa=$(dev_pa "$la") || die "Device at LA $la did not report a physical address."
    else
        die "usage: $0 handoff <LA | a.b.c.d>   ('scan' lists both)"
    fi
    (( pa != 0 )) || die "0.0.0.0 is the TV itself -- handoff routes TO a source device."
    # Verified live (Apple TV): a device in standby IGNORES <Set Stream
    # Path> -- wake-on-routing is optional in the spec -- but honors it
    # once awake. So wake it first and wait until it reports on.
    if [[ -n "$la" && "$(power_status "$la")" != on ]]; then
        log "Target is asleep -- waking it (<User Control Pressed>[Power On])..."
        dev_call PressOnceUserControl ayy 1 109 "$la" >/dev/null 2>&1 || true
        local i
        for i in {1..6}; do
            sleep 2
            [[ "$(power_status "$la")" == on ]] && break
        done
    fi
    # <Set Stream Path> (0x86): TV + receiver route to that path, and the
    # device there answers with an <Active Source> claim.
    log "Routing the input to $(pa_pretty "$pa") via <Set Stream Path>..."
    raw_send 15 134 $(( (pa>>8)&255 )) $(( pa&255 ))
    # the claim can trail the routing by a few seconds (verified live)
    local act="" i
    for i in {1..4}; do
        sleep 2
        act=$(active_source_pa) || act=""
        [[ "$act" == "$pa" ]] && break
    done
    if [[ "$act" == "$pa" ]]; then
        log "Done -- $(pa_pretty "$pa") claimed the input."
    else
        warn "No <Active Source> claim from $(pa_pretty "$pa") yet -- some devices"
        warn "take a while after waking. Check with 'active'."
    fi
}

cmd_release() {
    require_user; require_daemon
    local pa; pa=$(dev_prop PhysicalAddress)
    if [[ ! "$pa" =~ ^[0-9]+$ ]] || (( pa == 65535 )); then
        die "Own physical address unknown -- adapter detached? If it stays broken: $0 repair"
    fi
    # <Inactive Source> (0x9d), directed to the TV with our PA: "we're done,
    # you pick". The TV falls back to its previous input / home screen
    # instead of us force-routing anywhere. The politest exit there is.
    raw_send "$TV_LA" 157 $(( (pa>>8)&255 )) $(( pa&255 ))
    log "<Inactive Source> sent -- we gave up the input; the TV decides what's next."
}

# =============================== repair ===================================
# "CEC stopped responding" -- usually after suspend. Two known causes:
# some adapters silently lose their CEC registration across sleep (symptom:
# works once, then every command times out -- reported in the field on a
# TCL Roku + DP adapter setup), and behind a receiver the standby-
# passthrough drops /dev/cec0 for ~20 s while the link renegotiates.
# Restarting cecd makes it re-claim its logical address -- the rootless
# equivalent of the cec-ctl --clear + --playback dance. Raw re-registration
# is only safe when cecd is NOT running: --clear on a live cecd would yank
# its claimed address out from under it.

reg_info() {   # adapter registration as cec-ctl sees it -> "PA MASK"
    local out pa mask
    out=$(cec-ctl -d "$CEC_DEV" 2>/dev/null) || true
    pa=$(sed -n 's/.*Physical Address *: *//p' <<< "$out" | head -1)
    mask=$(sed -n 's/.*Logical Address Mask *: *//p' <<< "$out" | head -1)
    echo "${pa:-?} ${mask:-?}"
}

reg_ok() {   # reg_ok PA MASK -- registered = valid PA and a nonzero LA mask
    [[ "$1" != "?" && "$1" != "f.f.f.f" && "$2" =~ ^0x0*[1-9a-fA-F] ]]
}

tv_acks() {   # can we reach the TV -- via cecd if up, else raw cec-ctl
    if cecd_up; then
        dev_call Poll y "$TV_LA" >/dev/null 2>&1
    else
        cec-ctl -s -d "$CEC_DEV" --to "$TV_LA" --give-device-power-status 2>/dev/null \
            | grep -q 'pwr-state'
    fi
}

repair_checks() {   # print the three health lines; sets OK_REG OK_BUS OK_TV
    local pa mask dpa
    read -r pa mask <<< "$(reg_info)"
    OK_REG=0; OK_BUS=0; OK_TV=0
    reg_ok "$pa" "$mask" && OK_REG=1
    if cecd_up; then
        dpa=$(dev_prop PhysicalAddress)
        [[ "$dpa" =~ ^[0-9]+$ ]] && (( dpa != 65535 )) && OK_BUS=1
    fi
    tv_acks && OK_TV=1
    echo "  adapter registration: $( ((OK_REG)) && echo ok || echo BAD ) (PA $pa, LA mask $mask)"
    echo "  cecd on the bus:      $( ((OK_BUS)) && echo ok || echo "not answering / no address" )"
    echo "  TV ACKs us:           $( ((OK_TV)) && echo ok || echo NO )"
    return 0
}

cmd_repair() {
    require_user
    [[ -e "$CEC_DEV" ]] || die "$CEC_DEV is missing -- software can't repair that.
      Behind a receiver it vanishes for ~20 s after amp standby while the
      passthrough renegotiates (wait, then retry); otherwise re-seat the
      adapter (it must tunnel CEC over the DP AUX channel)."
    log "CEC health check..."
    repair_checks
    if (( OK_REG && OK_BUS && OK_TV )); then
        log "Healthy -- nothing to repair."
        return 0
    fi
    echo
    # cecd ships with the OS and is pulled in by dependency, so is-enabled
    # says "disabled" even on a stock install -- presence of the unit file
    # is the real signal. Only a MASKED unit means "user turned it off on
    # purpose"; then (or with no cecd at all) we re-register raw instead.
    local pa mask i want_cecd=0
    if [[ "$(systemctl --user is-enabled "$CECD_SVC" 2>/dev/null)" != masked ]] \
       && systemctl --user cat "$CECD_SVC" >/dev/null 2>&1; then
        want_cecd=1
        log "Restarting cecd -- it re-claims its logical address on startup..."
        systemctl --user restart "$CECD_SVC"
        for i in {1..8}; do
            sleep 2
            read -r pa mask <<< "$(reg_info)"
            reg_ok "$pa" "$mask" && cecd_up && break
        done
    else
        log "cecd is masked or absent -- raw re-registration (--clear + --playback)..."
        cec-ctl -d "$CEC_DEV" --clear >/dev/null 2>&1 || true
        cec-ctl -d "$CEC_DEV" --playback >/dev/null 2>&1 || true
        sleep 2
    fi
    log "After repair:"
    repair_checks
    if (( OK_REG && OK_TV )) && { (( ! want_cecd )) || (( OK_BUS )); }; then
        log "Repaired."
        return 0
    fi
    warn "Still unhealthy. Next: replug the adapter / power-cycle the receiver."
    warn "If only the TV poll fails, check the TV's CEC setting (brand names:"
    warn "SimpLink, Anynet+, Bravia Sync, 1-Touch Play, HDMI Control) -- TV"
    warn "firmware updates are known to flip it off."
    return 1
}

# ======================== monitor / remote ================================

cmd_monitor() {
    echo "Raw CEC bus traffic -- Ctrl-C to exit."
    echo -e "${CD}(rootless alternative: busctl --user monitor $DBUS_NAME)${C0}"
    if [[ $EUID -eq 0 ]]; then exec cectool monitor; fi
    # kernel CEC monitor mode needs CAP_NET_ADMIN (EPERM as plain user)
    exec sudo cectool monitor
}

cmd_remote() {
    require_user
    local val; val=$(cfg_prop Uinput)
    echo "  uinput relay (cecd config): $val"
    echo
    if remote_dev_present; then
        echo "  cecd input devices:"
        awk -v RS= '/Name="cecd/ { print "    " $0 "\n" }' /proc/bus/input/devices \
            | grep -E 'Name=|Handlers=' | sed 's/^[NH]: /    /'
        echo
        echo "  TV remote arrows / OK / back should drive gamescope directly."
    else
        echo "  No cecd input device found."
        [[ "$val" == true ]] && echo "  Toggle is on -- try: systemctl --user restart cecd"
        [[ "$val" == true ]] || echo "  Enable with: $0 toggle uinput on"
    fi
}

# ========================= one-shot CLI verbs =============================

cmd_tv_on()    { require_user; require_daemon; dev_call Wake >/dev/null; log "Wake sent (power on + switch input)."; }

cmd_tv_off() {
    require_user; require_daemon
    if [[ "${1:-}" == hard ]]; then
        # <User Control Pressed>[Power Off Function] (0x6c): the remote's
        # DISCRETE off key. For TVs that bounce back out of <Standby> when
        # more CEC traffic arrives during suspend (TCL Roku class). Unlike
        # ui-cmd=power (0x40) it is not a toggle, so no state-gating needed.
        dev_call PressOnceUserControl ayy 1 108 "$TV_LA" >/dev/null
        log "Discrete power-off keypress sent to the TV."
    elif [[ -n "${1:-}" ]]; then
        die "usage: $0 tv-off [hard]"
    else
        dev_call Standby y "$TV_LA" >/dev/null
        log "Standby sent to the TV."
    fi
}

# <System Audio Mode Request> (0x70) with our physical address as operand:
# the spec requires an amp in standby to power on, take over audio, and
# reply <Set System Audio Mode> (0x72). Verified live against a Yamaha
# RX-V381. Fallback for amps that skip the reply: <User Control Pressed>
# [Power On Function] (0x6d).
cmd_amp_on() {
    require_user; require_daemon
    local la pa out
    la=$(audio_la)
    pa=$(dev_prop PhysicalAddress)
    if [[ ! "$pa" =~ ^[0-9]+$ ]] || (( pa == 65535 )); then
        die "Own physical address unknown -- adapter detached, or the receiver's
      standby-passthrough is still renegotiating the link (takes ~20 s; retry).
      If it stays broken: $0 repair"
    fi
    if out=$(dev_call SendReceiveRawMessage ayyyq 3 112 $(( (pa>>8)&255 )) $(( pa&255 )) "$la" 114 2000 2>/dev/null); then
        local sam=off; [[ "${out##* }" == 1 ]] && sam=on
        log "Receiver (LA $la) awake -- system audio mode: $sam."
    else
        warn "No <Set System Audio Mode> reply -- trying <User Control Pressed>[Power On]..."
        dev_call PressOnceUserControl ayy 1 109 "$la" >/dev/null 2>&1 || true
        sleep 2
        log "Receiver power status: $(power_status "$la")"
    fi
}

cmd_amp_off() {
    require_user; require_daemon
    local la; la=$(audio_la)
    dev_call Standby y "$la" >/dev/null
    log "Standby sent to the receiver (LA $la)."
    # Verified live (RX-V381): with the console plugged THROUGH the
    # receiver, its HDMI passthrough drops on standby, taking /dev/cec0
    # and cecd's device object with it until Standby Through renegotiates
    # the link (~20 s). CEC verbs just fail during that window.
    warn "If the console is routed through the receiver, CEC drops for ~20 s"
    warn "while its standby-passthrough takes over -- verbs fail until then."
}
cmd_switch()   { require_user; require_daemon; dev_call SetActiveSource i -- -1 >/dev/null; log "Active-source claim sent."; }
cmd_vol_up()   { require_user; require_daemon; dev_call VolumeUp   y "$(audio_la)" >/dev/null; }
cmd_vol_down() { require_user; require_daemon; dev_call VolumeDown y "$(audio_la)" >/dev/null; }
cmd_mute()     { require_user; require_daemon; dev_call Mute       y "$(audio_la)" >/dev/null; }

# ============================== menus =====================================

menu_toggles() {
    while true; do
        local items=(
            "Wake TV on resume|$(badge_toggle wake_tv)|cecd wakes the TV when the console resumes from sleep. On by default."
            "Standby TV on suspend|$(badge_toggle suspend_tv)|TV turns off when the console goes to sleep."
            "Suspend when TV turns off|$(badge_toggle allow_standby)|TV standby puts the console to sleep too. On by default."
            "TV remote as input|$(badge_toggle uinput)|Relay remote keys as an input device -- drives gamescope."
            "Clear overrides|$(badge_overrides)|Delete our override file; Steam UI regains control of all four."
        )
        menu_select "CEC behavior toggles  ${CD}(override Steam UI)${C0}" "${items[@]}" || { echo; break; }
        case $MENU_CHOICE in
            0) run_action cmd_toggle wake-tv ;;
            1) run_action cmd_toggle suspend-tv ;;
            2) run_action cmd_toggle allow-standby ;;
            3) run_action cmd_toggle uinput ;;
            4) run_action cmd_clear_overrides ;;
        esac
    done
}

menu_amp() {
    while true; do
        local la ast
        la=$(audio_la); ast=$(power_status "$la")
        local items=(
            "Receiver power|$(badge_amp_power "$ast")|amp-on / amp-off via <System Audio Mode Request> -- flips based on the state shown."
            "Wake receiver at boot|$(badge_amp_follow boot)|Boot-wake also powers the receiver + hands it the audio. Needs boot-wake installed."
            "Standby receiver at poweroff|$(badge_amp_follow poweroff)|Poweroff unit sends the receiver to standby too. On by default; needs the unit."
            "Standby receiver on suspend|$(badge_amp_follow suspend)|Receiver off when the console sleeps -- unless another device plays through it. Needs the hook."
            "Wake receiver on resume|$(badge_amp_follow resume)|Receiver on + takes the audio when the console wakes. Needs the hook."
            "Suspend/resume hook|$(badge_sleep_hook)|Root helper in /etc/systemd/system-sleep driving the two follows above. Uses sudo."
        )
        menu_select "Receiver / amp  ${CD}(CEC audio system, LA $la)${C0}" "${items[@]}" || { echo; break; }
        case $MENU_CHOICE in
            0) if [[ "$ast" == on ]]; then run_action cmd_amp_off; else run_action cmd_amp_on; fi ;;
            1) run_action cmd_amp_follow boot ;;
            2) run_action cmd_amp_follow poweroff ;;
            3) run_action cmd_amp_follow suspend ;;
            4) run_action cmd_amp_follow resume ;;
            5) run_action amp_sleep_toggle ;;
        esac
    done
}

menu_boot_wake() {
    while true; do
        local items=(
            "Boot wake unit|$(badge_wake)|Wake the TV at every session start. Toggles install/remove (installs polite)."
            "Mode: polite / grab|$(badge_wake_mode)|polite: back off if another device holds the input. grab: always switch the TV to us."
        )
        menu_select "Wake TV at boot  ${CD}(session-start unit)${C0}" "${items[@]}" || { echo; break; }
        case $MENU_CHOICE in
            0) run_action boot_wake_toggle ;;
            1) run_action boot_wake_mode_toggle ;;
        esac
    done
}

cmd_menu() {
    [[ -t 0 && -t 1 ]] || die "The menu needs an interactive terminal. See '$0 help' for CLI commands."
    # Opposite of bc250-power.sh: this script must NOT run as root, because
    # cecd only exists on deck's user D-Bus session.
    [[ $EUID -ne 0 ]] || die "Run as deck, not root. Only the poweroff unit asks for sudo itself."
    while true; do
        local items=(
            "Status overview||Full health dump: device, daemon, TV power, config. Always safe."
            "Recommended setup||One shot: OSD name + TV off on suspend/poweroff + TV (and optionally receiver) wake at boot."
            "Set TV name (OSD)|$(badge_osd)|Name in the TV's device list. Default: $OSD_DEFAULT."
            "Behavior toggles|$(badge_overrides)|Wake/standby/remote toggles -- overrides Steam UI settings."
            "TV standby on power-off|$(badge_standby)|CEC standby on poweroff only -- skipped if another device holds the input. Uses sudo."
            "Wake TV at boot|$(badge_wake)|Wake the TV at session start -- install/remove, and polite vs grab mode."
            "Receiver / amp|$(badge_amp_summary)|Receiver power now, plus follow-the-console toggles: boot, poweroff, suspend, resume."
            "Who has the input|$(badge_active)|Ask the bus for the active source -- the device the TV/receiver is showing."
            "Take the input|$(badge_active)|Claim active source now -- switch the TV/receiver to the BC-250 ('switch')."
            "Hand off the input|$(badge_active)|Route the TV/receiver to another device (it wakes + claims the input)."
            "Release the input||We give up the input, the TV picks what's next. The polite exit."
            "Test TV control|$(tv_badge_menu)|Guided sequence: poll, wake, switch input, audio, standby."
            "Scan CEC bus|$(tv_badge_menu)|HDMI tree of every device: address, name, vendor, power, active source."
            "Repair CEC|$(tv_badge_menu)|Dead after suspend? Health check + re-register the adapter on the bus."
            "TV-remote input|$(badge_remote)|uinput relay state and the input devices cecd created."
            "Live CEC monitor||Raw bus traffic via cectool (needs sudo; Ctrl-C exits)."
            "Full help||The complete manual for every CLI command."
        )
        menu_select "BC-250 CEC / TV control  ${CD}(SteamOS cecd)${C0}" "${items[@]}" || { echo; break; }
        case $MENU_CHOICE in
            0) run_action cmd_status ;;
            1) run_action cmd_setup ;;
            2) run_action cmd_osd_name ;;
            3) menu_toggles ;;
            4) run_action shutdown_standby_toggle ;;
            5) menu_boot_wake ;;
            6) menu_amp ;;
            7) run_action cmd_active ;;
            8) run_action cmd_switch ;;
            9) run_action cmd_handoff ;;
            10) run_action cmd_release ;;
            11) run_action cmd_test ;;
            12) run_action cmd_scan ;;
            13) run_action cmd_repair ;;
            14) run_action cmd_remote ;;
            15) cmd_monitor ;;
            16) cmd_help; pause_key ;;
        esac
    done
}

tv_badge_menu() {   # tiny live badge for the test row: is the TV reachable?
    cecd_up || { b_off "cecd not running"; return 0; }
    [[ -e "$CEC_DEV" ]] || { b_off "no /dev/cec0"; return 0; }
    b_ok "ready"
    return 0
}

cmd_help() {
    cat << 'EOF'
bc250-cec.sh -- HDMI-CEC / TV control for the BC-250 on SteamOS
================================================================
The kernel and Valve's cecd daemon already do the heavy lifting: CEC is
tunneled over the DP->HDMI adapter's AUX channel to /dev/cec0, and cecd
(user service, D-Bus com.steampowered.CecDaemon1) wakes the TV on resume,
suspends the console when the TV turns off, and relays the TV remote as
an input device. This script configures cecd and fills its gaps.

Run as deck (NOT root/sudo) -- cecd lives on the user D-Bus session.
Only 'shutdown-standby install' escalates, by itself, for one unit file.

GUIDED MENU
  Run with no arguments in a terminal: arrow keys / j k, Enter, q.
  Every menu action is one of the CLI commands below.

SETUP
  setup            Recommended one-shot: osd-name BC-250, TV standby on
                   suspend + poweroff, wake TV at boot, and (optional
                   prompt) wake the receiver at boot too.
  osd-name [NAME]  Name shown in the TV's device/input list (max 14
                   bytes, default BC-250). 'osd-name --reset' removes it.
  toggle KEY [on|off]
                   KEY: wake-tv | suspend-tv | allow-standby | uinput
                     wake-tv        wake TV when console resumes  (default on)
                     suspend-tv     TV standby when console sleeps (default off)
                     allow-standby  console sleeps when TV turns off (default on)
                     uinput         TV remote -> input events      (default on)
                   Written to ~/.config/cecd/config.d/99-zz-bc250.toml,
                   which outranks Steam UI's fragment. No arg = flip.
  clear-overrides  Delete the override file; Steam UI back in control.
  shutdown-standby install|remove|status
                   System unit: CEC standby to the TV + receiver on
                   POWEROFF only (reboot and suspend excluded) -- and only
                   if no OTHER device holds the input. The one sudo action.
  boot-wake install [polite|grab] | remove | status
                   User unit: wake the TV at every session start.
                   polite (default): if the TV is on and another device is
                   the active source, don't touch the input. grab: old
                   behavior, always switch input to the BC-250.

EVERYDAY VERBS
  tv-on            Wake the TV and switch input to the BC-250.
  tv-off [hard]    Put the TV into standby. 'hard' sends the remote's
                   discrete power-off key instead (<User Control Pressed>
                   [Power Off Function]) -- for TVs that bounce back out
                   of <Standby> when other CEC traffic follows it.
  amp-on           Power on the receiver/soundbar via <System Audio Mode
                   Request> -- it also takes over volume handling.
  amp-off          Put the receiver/soundbar into standby.
  switch           Claim active source (switch TV input to us).
  vol-up|vol-down|mute
                   Volume on the CEC audio system (soundbar/AVR).

RECEIVER FOLLOWS THE CONSOLE
  amp-follow {boot|poweroff|suspend|resume} [on|off]
                   Make the receiver's power track the console. No arg =
                   flip. Stored in ~/.config/bc250-cec.conf, read by the
                   helpers at runtime -- flipping is instant. Each needs
                   its carrier: boot -> 'boot-wake install', poweroff ->
                   'shutdown-standby install' (poweroff is ON by default),
                   suspend/resume -> 'amp-sleep install'.
  amp-sleep install|remove|status
                   Root hook in /etc/systemd/system-sleep driving the
                   suspend/resume follows (sudo). Standby paths stay
                   polite: a receiver another device is playing through
                   is left on.

PLAYING NICE (shared receiver / multiple CEC sources)
  active           Who holds the input right now: us, another device (says
                   which), or nobody. Look before you switch.
  handoff [LA|a.b.c.d]
                   Route the TV/receiver to another device via <Set Stream
                   Path>; it wakes and claims the input. No arg: pick from
                   a scan. The counterpart of 'switch'.
  release          <Inactive Source>: we give up the input and the TV
                   picks what's next. Politer than tv-off when others
                   share the screen.
  Both installed units are polite by default -- boot-wake won't steal the
  input from an active device, shutdown-standby won't power off a TV that
  another device is using.

DIAGNOSTICS
  status           Full health dump -- device, daemon, bus identity,
                   effective config + source, TV power, installed units.
  test             Guided pass/fail sequence: poll TV, power status,
                   wake, input switch, audio, optional standby.
  scan             HDMI tree of all devices: physical address, role, OSD
                   name, vendor, power, and who is the active source.
  repair           Health check + fix for "CEC stopped responding":
                   restarts cecd so it re-claims its logical address (raw
                   cec-ctl --clear/--playback only if cecd is off).
  monitor          Raw CEC traffic (sudo cectool monitor; Ctrl-C exits).
                   Rootless: busctl --user monitor com.steampowered.CecDaemon1
  remote           TV-remote relay state + the input devices cecd made.

TROUBLESHOOTING
  CEC dead after suspend/resume:  run 'repair'. Some DP->HDMI adapters
    silently lose their CEC registration across sleep (works once, then
    every command times out); behind a receiver, its standby-passthrough
    also drops /dev/cec0 for ~20 s while the link renegotiates.
  TV turns back on (or lands on its home screen) instead of staying off
    when the console suspends:  some TVs (TCL Roku notably) abort
    <Standby> when more CEC traffic arrives -- use 'tv-off hard'.
  Why build on cecd instead of raw cec-ctl units: keeping cecd gives us
    the TV remote as input, Steam UI integration and resume handling for
    free; raw cec-ctl scripts are the fallback when cecd itself is off.

FILE MAP (user files live in home; system files use the atomic-update keep list)
  ~/.config/cecd/config.d/50-bc250.toml       osd_name
  ~/.config/cecd/config.d/99-zz-bc250.toml    toggle overrides (outranks
                                              Steam UI's 99-steamos-manager.toml)
  ~/.config/bc250-cec.conf                    receiver-follow toggles
  ~/.config/systemd/user/bc250-cec-boot-wake.service
  ~/.local/bin/bc250-cec-boot-wake            its helper (polite/grab + amp)
  /etc/systemd/system/bc250-cec-poweroff-standby.service
  /var/lib/bc250-control/helper/bc250-cec-poweroff-standby
                                                 root-owned helper (polite gate)
  /etc/systemd/system-sleep/bc250-cec-amp.sh  amp suspend/resume hook
  (nothing in /usr or /boot; cecd itself is part of the OS image)
EOF
}

# ============================ dispatch ====================================

if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    cmd_menu
    exit 0
fi
case "${1:-}" in
    status)            cmd_status ;;
    setup)             cmd_setup ;;
    osd-name)          shift; cmd_osd_name "$@" ;;
    toggle)            shift; cmd_toggle "$@" ;;
    clear-overrides)   cmd_clear_overrides ;;
    shutdown-standby)  shift; cmd_shutdown_standby "${1:-status}" ;;
    boot-wake)         shift; cmd_boot_wake "${1:-status}" "${2:-polite}" ;;
    active)            cmd_active ;;
    handoff)           shift; cmd_handoff "${1:-}" ;;
    release)           cmd_release ;;
    amp-follow)        shift; cmd_amp_follow "$@" ;;
    amp-sleep)         shift; cmd_amp_sleep "${1:-status}" ;;
    test)              cmd_test ;;
    scan)              cmd_scan ;;
    monitor)           cmd_monitor ;;
    remote)            cmd_remote ;;
    tv-on)             cmd_tv_on ;;
    tv-off)            shift; cmd_tv_off "${1:-}" ;;
    repair)            cmd_repair ;;
    amp-on)            cmd_amp_on ;;
    amp-off)           cmd_amp_off ;;
    switch)            cmd_switch ;;
    vol-up)            cmd_vol_up ;;
    vol-down)          cmd_vol_down ;;
    mute)              cmd_mute ;;
    menu)              cmd_menu ;;
    help|-h|--help)    cmd_help ;;
    *) echo "Usage: $0 {status|setup|osd-name|toggle|clear-overrides|shutdown-standby|boot-wake|"
       echo "           active|handoff|release|amp-follow|amp-sleep|test|scan|repair|monitor|"
       echo "           remote|tv-on|tv-off|amp-on|amp-off|switch|vol-up|vol-down|mute|menu|help}"
       echo "  (no arguments on a terminal opens the guided menu)"
       echo
       echo "Run '$0 help' for the full explanation of every command."
       exit 1 ;;
esac
