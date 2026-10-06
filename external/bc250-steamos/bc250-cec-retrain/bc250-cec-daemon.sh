#!/usr/bin/env bash
# BC-250 CEC daemon: announces this board to the HDMI CEC bus as "SteamOS"
# and relinks the DisplayPort link (a link retrain by default, or a full
# DRM hotplug replug) when the display reports powering on, or when another
# CEC device points the active source at us.
#
# Why: a CH7218 DP-to-HDMI converter does not restart its HDMI output when
# the display or AVR behind it comes back, and does not tell the board
# either. Reproduced live twice on 2026-10-03: the board kept streaming 4K60
# over a healthy, trained link the whole time; switching the AVR's input to
# the board produced no hotplug at all, only CEC traffic; and the board's
# own re-detect at TV power-on came minutes before the AVR was routing this
# input, so it did not help. Waking the converter's DP input (DPCD 0x600
# D3 -> D0) alone did nothing; a full link retrain brought the picture back
# every time. CEC is the only signal that the path to the display is live
# again, from two independent sources:
#   1. the display's own power state (off -> on), polled periodically;
#   2. another device (TV/AVR) naming our physical address as the new
#      active source -- e.g. switching TV input back to SteamOS while the
#      display never actually powered off. The power-state poll alone
#      cannot see this, since the display was "on" throughout.
#
# Retrain is the default because it is all the converter needs and nothing
# above the link notices it: no disconnect, no EDID re-read, no compositor
# reconfiguration. It goes through the connector's debugfs link_settings
# file: writing an invalid setting ("0 0") clears any forced link settings
# and retrains at the ones the driver decides itself (amdgpu logs "Invalid
# Input value No HW will be programmed" and then retrains anyway -- the
# message is misleading). A valid "<lanes> <rate>" would also retrain but
# pin those settings until reboot. With the stream blanked (DPMS off) the
# write retrains nothing, which is fine: unblanking trains the link anyway.
# RELINK_METHOD=hotplug restores the old full replug via trigger_hotplug,
# and is also what runs if link_settings is missing.
#
# Never sends <Standby> or <Image View On> -- detection only, per the
# feature request this shipped for. Verified on a real CEC bus trace that
# claiming a logical address never transmits anything beyond the mandatory
# address-claim broadcasts and our own power-status queries. Separately,
# after the replug settles, it injects one synthetic keypress via uinput
# -- not a CEC command at all, just a workaround for Steam/gamescope's own
# UI being left on a black screen instead of its usual screensaver after a
# hotplug replug. The one opt-in exception, off by default
# (SWITCH_INPUT_ON_POWER_ON), broadcasts <Active Source> after a power-on
# so the TV switches to this board's input on its own. Separately, two
# more opt-in hooks (ON_POWER_ON_COMMAND/ON_POWER_OFF_COMMAND) can run an
# arbitrary user script on a genuine power transition -- the command
# always comes from the config file, never from anything received over
# CEC, so nothing on the bus can influence what gets executed.
#
# The debugfs link_settings/trigger_hotplug writes need root; the CEC calls do not
# (/dev/cecN is group `video`), but the whole service runs as root anyway
# to keep this one small rather than split across a privilege boundary for
# a single write.
#
# All tunables below read from the environment, which is how
# /etc/bc250-cec.conf reaches this script: it is wired up as
# EnvironmentFile=-/etc/bc250-cec.conf in the unit, parsed by systemd
# itself as plain KEY=value (not sourced as shell), so an edited config
# file can never inject shell code here.

set -Eeuo pipefail

readonly OSD_NAME="${BC250_CEC_DISPLAY_NAME:-SteamOS}"
readonly POLL_INTERVAL_S="${BC250_CEC_POLL_INTERVAL_S:-5}"
readonly TRIGGER_COOLDOWN_S="${BC250_CEC_TRIGGER_COOLDOWN_S:-30}"
readonly TV_LOGICAL_ADDRESS=0
readonly AUDIO_SYSTEM_LOGICAL_ADDRESS=5
# Independently toggle the replug and the wake keypress per trigger
# source, so e.g. one source's detection can be disabled without losing
# the other, or the keypress can be disabled while keeping the replug.
readonly HOTPLUG_ON_POWER_ON="${BC250_CEC_HOTPLUG_ON_POWER_ON:-1}"
readonly HOTPLUG_ON_ACTIVE_SOURCE="${BC250_CEC_HOTPLUG_ON_ACTIVE_SOURCE:-1}"
# How the two settings above relink: "retrain" (default) or "hotplug" (the
# full replug this daemon used before 2026-10-04). The HOTPLUG_ON_* names
# predate the retrain and are kept so existing configs keep working.
readonly RELINK_METHOD="${BC250_CEC_RELINK_METHOD:-retrain}"
# The wake keypress below is off by default since the retrain became the
# default relink: it worked around Steam's black screen after a full
# replug, and a retrain never disconnects anything Steam could react to.
# Set both to 1 again alongside RELINK_METHOD=hotplug.
readonly WAKE_KEY_ON_POWER_ON="${BC250_CEC_WAKE_KEY_ON_POWER_ON:-0}"
readonly WAKE_KEY_ON_ACTIVE_SOURCE="${BC250_CEC_WAKE_KEY_ON_ACTIVE_SOURCE:-0}"
# Steam/gamescope can be left showing a black screen instead of its usual
# screensaver after a hotplug replug -- confirmed on hardware 2026-09-28,
# fixed by one synthetic keypress. F15 is the user's explicit choice of
# default: not present on physical keyboards at all (unlike F13, which
# some extended keyboards do have) and essentially never bound to
# anything in a game or in Steam's own UI, unlike a real key that could
# double as an in-game action if a game happens to be running when this
# fires. Empty disables the wake keypress entirely.
readonly WAKE_KEY="${BC250_CEC_WAKE_KEY:-KEY_F15}"
readonly WAKE_DELAY_S="${BC250_CEC_WAKE_DELAY_S:-1}"
# Opt-in and off by default: this is the one thing the rest of this daemon
# deliberately never does on its own (see the top-of-file note on why) --
# broadcast ACTIVE_SOURCE so the TV switches its input to us, and request
# the AVR route its audio from us too. Only wired to the power-on trigger
# (an active-source trigger means the TV already switched to us, so
# sending it again would be pointless). The delay lets the replug and the
# display's own post-power-on settling happen first rather than racing a
# CEC broadcast against them.
readonly SWITCH_INPUT_ON_POWER_ON="${BC250_CEC_SWITCH_INPUT_ON_POWER_ON:-0}"
readonly SWITCH_INPUT_DELAY_S="${BC250_CEC_SWITCH_INPUT_DELAY_S:-3}"
# Run an arbitrary user-provided script on a genuine power transition --
# e.g. smart-home integration, muting/pausing something, anything else
# scriptable. Empty (the default) disables each independently. The
# command always comes from this trusted, root-owned config file, never
# from anything received over CEC -- CEC only ever supplies the trigger
# (a boolean "the display just turned on/off"), never the payload, so
# there is no path for a CEC message from any device on the bus to
# influence what gets executed. The script itself still runs as root,
# same as the rest of this daemon; write it carefully.
readonly ON_POWER_ON_COMMAND="${BC250_CEC_ON_POWER_ON_COMMAND:-}"
readonly ON_POWER_OFF_COMMAND="${BC250_CEC_ON_POWER_OFF_COMMAND:-}"
# Shared between the poll loop and the active-source monitor loop, which
# run as two concurrent background jobs -- a plain shell variable is not
# visible across them, but a file is. RuntimeDirectory=bc250-cec in the
# unit creates this, root-owned, cleaned up on stop.
readonly TRIGGER_STATE_FILE="${BC250_CEC_TRIGGER_STATE_FILE:-/run/bc250-cec/last-trigger}"

log() { printf 'bc250-cec: %s\n' "$1"; }

# Discover the CEC device node and the DRM connector it belongs to.
# `cec-ctl --list-devices` prints e.g.:
#   amdgpu (DP-1):
#       /dev/cec0
# Both are resolved fresh on every start rather than hardcoded: the
# connector is fixed on this board today, but nothing here needs it to
# stay that way, and re-discovery costs nothing.
discover_cec() {
    local list connector dev
    list="$(cec-ctl --list-devices 2>/dev/null)" || return 1
    connector="$(sed -nE 's/^[A-Za-z0-9_]+ \(([^)]+)\):$/\1/p' <<<"$list" | head -1)"
    dev="$(grep -oE '/dev/cec[0-9]+' <<<"$list" | head -1)"
    [[ -n "$connector" && -n "$dev" ]] || return 1
    printf '%s\n%s\n' "$dev" "$connector"
}

# This connector's debugfs file for the configured relink method:
# link_settings for a retrain, trigger_hotplug for a replug. A retrain falls
# back to the replug when link_settings is missing. The PCI address segment
# of the path is not hardcoded -- a glob costs nothing and does not assume
# the GPU stays at the same PCI address.
find_debugfs_file() {
    local connector="$1" name="$2" path
    for path in /sys/kernel/debug/dri/*/"$connector"/"$name"; do
        [[ -e "$path" ]] && { printf '%s\n' "$path"; return 0; }
    done
    return 1
}

find_relink_path() {
    local connector="$1"
    if [[ "$RELINK_METHOD" == retrain ]]; then
        find_debugfs_file "$connector" link_settings && return 0
    fi
    find_debugfs_file "$connector" trigger_hotplug
}

# Retrain or replug, depending on which file find_relink_path() returned.
relink() {
    local trigger_path="$1" connector="$2"
    case "$trigger_path" in
        */link_settings)
            log "retraining the link on $connector"
            echo '0 0' > "$trigger_path" || log "failed to write $trigger_path" ;;
        *)
            log "triggering hotplug replug on $connector"
            echo 1 > "$trigger_path" || log "failed to write $trigger_path" ;;
    esac
}

# Re-assert our logical address claim. A real display power cycle can reset
# more of the CEC/AUX link state than just "is the display on" -- observed
# on hardware: a TV off for as little as 5s left the adapter fully
# unconfigured (logical address mask 0x0000, OSD name cleared), which
# silently blinds every later poll forever since nothing else re-claims it.
claim_logical_address() {
    local dev="$1"
    cec-ctl -d "$dev" --playback --osd-name "$OSD_NAME" >/dev/null 2>&1
}

# This adapter's own physical address (e.g. "2.3.0.0"), used to recognize
# ourselves in another device's SET_STREAM_PATH/ACTIVE_SOURCE broadcasts.
own_physical_address() {
    local dev="$1"
    cec-ctl -d "$dev" -S 2>/dev/null | sed -nE 's/^\s*Physical Address\s*:\s*([0-9a-fA-F.]+)\s*$/\1/p' | head -1
}

# "on" if the display answered GIVE_DEVICE_POWER_STATUS with pwr-state: on;
# "off" only for a confirmed pwr-state: standby reply; "unknown" for
# anything else (no reply, a communication error, the in-transition
# states) -- display fully powered off, or unreachable through a
# currently-off AVR in the chain, are indistinguishable from a transient
# hiccup without a real reply, so neither can safely be called "off".
# CEC's logical address 0 is always the TV by the spec's own convention,
# regardless of how many CEC repeaters (an AVR, for instance) sit between
# this board and it, so this needs no topology-specific logic.
#
# If our own adapter has lost its logical address claim (cec-ctl reports
# "unconfigured"), that is not a display power state at all -- re-claim and
# retry once immediately, so a lost claim costs at most one extra query
# rather than blinding every poll until the service is restarted.
#
# The on/off/unknown distinction matters beyond that retry: confirmed on
# hardware 2026-09-28 that this board's own replug and active-source
# broadcasts transiently disrupt CEC communication for a few seconds
# afterward, which previously read back as a plain "off" -- indistinguishable
# from the display actually reporting standby. That is a safe default for
# power-ON detection (worst case, a delayed "on" reading), but it let a
# self-inflicted comms hiccup fire the power-OFF custom command
# (ON_POWER_OFF_COMMAND) during the settling window right after a real
# power-ON, which is a much worse false positive for that feature.
query_power_state() {
    local dev="$1" out
    out="$(cec-ctl -d "$dev" --to "$TV_LOGICAL_ADDRESS" --give-device-power-status 2>&1)" || true
    if grep -qE 'unconfigured' <<<"$out"; then
        log "adapter lost its logical address claim; re-claiming"
        claim_logical_address "$dev"
        out="$(cec-ctl -d "$dev" --to "$TV_LOGICAL_ADDRESS" --give-device-power-status 2>&1)" || true
    fi
    if grep -qE 'pwr-state: on\b' <<<"$out"; then
        printf 'on\n'
    elif grep -qE 'pwr-state: standby\b' <<<"$out"; then
        printf 'off\n'
    else
        printf 'unknown\n'
    fi
}

# One synthetic keypress via a throwaway uinput virtual keyboard --
# python-evdev is already present on this system (confirmed 2026-09-28),
# so this needs no new input-injection tool like ydotool. A fresh
# UInput() per call is deliberately simple/stateless, matching how the
# rest of this daemon shells out to cec-ctl fresh each time rather than
# holding a persistent handle; this only runs after an actual trigger,
# gated by the same cooldown, so it is not a hot path.
inject_wake_key() {
    [[ -n "$WAKE_KEY" ]] || return 0
    python3 - "$WAKE_KEY" <<'PYEOF' 2>/dev/null || log "failed to inject the wake keypress"
import sys, time
from evdev import UInput, ecodes as e

key = getattr(e, sys.argv[1])
with UInput({e.EV_KEY: [key]}, name="bc250-cec-wake") as ui:
    time.sleep(0.1)  # let udev/libinput enumerate the new virtual device
    ui.write(e.EV_KEY, key, 1)
    ui.syn()
    time.sleep(0.05)
    ui.write(e.EV_KEY, key, 0)
    ui.syn()
PYEOF
}

# Broadcast ACTIVE_SOURCE naming our own physical address, so the TV
# switches its input to us, then separately ask the AVR (always logical
# address 5 by the CEC spec, like the TV always being 0) to route its
# audio from us too. Confirmed on hardware 2026-09-28: Active Source alone
# only switches the picture -- this AVR's own audio-source selection is
# independent and falls back to "TV Audio (ARC)" otherwise, the same as
# it does for a native TV app, until SYSTEM_AUDIO_MODE_REQUEST tells it
# which HDMI input should actually be feeding its speakers. The one
# command pair in this whole daemon that can change what the display
# shows or plays -- opt-in only, see SWITCH_INPUT_ON_POWER_ON above.
switch_input_to_us() {
    local dev="$1" own_addr="$2"
    cec-ctl -d "$dev" --active-source "phys-addr=$own_addr" >/dev/null 2>&1 \
        || log "failed to send active-source"
    cec-ctl -d "$dev" --to "$AUDIO_SYSTEM_LOGICAL_ADDRESS" \
        --system-audio-mode-request "phys-addr=$own_addr" >/dev/null 2>&1 \
        || log "failed to send system-audio-mode-request"
}

# Fire the relink (retrain or replug), the wake keypress, the active-source switch,
# and/or (power-on only) the custom power-on command, for one trigger
# source ("power_on" or "active_source") -- each independently
# switchable. Shares one cooldown across both sources via
# TRIGGER_STATE_FILE so a power-on and an active-source switch landing
# close together cannot double-trigger. The custom command is folded in
# here (rather than called separately from the poll loop) specifically
# so it shares this same protection: hardware-observed 2026-09-28, this
# board's own replug/active-source broadcasts transiently disrupt CEC
# communication for a few seconds afterward, which the poll loop could
# briefly misread as an off->on blip and fire the custom command a
# second time even though the replug itself was correctly cooldown-
# suppressed.
fire_trigger() {
    local trigger_path="$1" connector="$2" cec_dev="$3" own_addr="$4" source="$5" reason="$6"
    local do_hotplug do_wake do_switch_input do_custom_command now last state_file

    case "$source" in
        power_on) do_hotplug="$HOTPLUG_ON_POWER_ON"; do_wake="$WAKE_KEY_ON_POWER_ON"
                  do_switch_input="$SWITCH_INPUT_ON_POWER_ON"
                  [[ -n "$ON_POWER_ON_COMMAND" ]] && do_custom_command=1 || do_custom_command=0 ;;
        active_source) do_hotplug="$HOTPLUG_ON_ACTIVE_SOURCE"; do_wake="$WAKE_KEY_ON_ACTIVE_SOURCE"
                  do_switch_input=0
                  do_custom_command=0 ;;
    esac

    # A retrain is cheap and does not disturb CEC, so each source gets its
    # own cooldown: a power-on followed within seconds by an AVR input switch
    # to us must still relink on the switch -- the power-on relink can come
    # before the AVR routes this input, which is exactly the failure seen on
    # 2026-10-03. A full replug keeps the old shared cooldown, which exists
    # because a replug disrupts CEC for a few seconds and could otherwise
    # read back as a second trigger.
    if [[ "$trigger_path" == */link_settings ]]; then
        state_file="$TRIGGER_STATE_FILE.$source"
    else
        state_file="$TRIGGER_STATE_FILE"
    fi

    if [[ "$do_hotplug" != 1 && "$do_wake" != 1 && "$do_switch_input" != 1 && "$do_custom_command" != 1 ]]; then
        log "$reason, but everything is disabled for this trigger; skipping"
        return 0
    fi

    now="$(date +%s)"
    last="$(cat "$state_file" 2>/dev/null || printf '0')"
    if (( now - last >= TRIGGER_COOLDOWN_S )); then
        log "$reason"
        if [[ "$do_hotplug" == 1 ]]; then
            relink "$trigger_path" "$connector"
        fi
        printf '%s\n' "$now" > "$state_file"
        if [[ "$do_wake" == 1 ]]; then
            sleep "$WAKE_DELAY_S"
            inject_wake_key
        fi
        if [[ "$do_switch_input" == 1 ]]; then
            sleep "$SWITCH_INPUT_DELAY_S"
            log "switching TV input and AVR audio to us ($own_addr)"
            switch_input_to_us "$cec_dev" "$own_addr"
        fi
        if [[ "$do_custom_command" == 1 ]]; then
            run_custom_command "$ON_POWER_ON_COMMAND" "power-on"
        fi
    else
        log "$reason, but within the ${TRIGGER_COOLDOWN_S}s cooldown; skipping"
    fi
}

# Run a user-configured script (ON_POWER_ON_COMMAND/ON_POWER_OFF_COMMAND)
# in the background -- fire-and-forget, so an arbitrarily slow script
# (a home-automation API call, etc.) never blocks the poll loop's own
# detection. Its stdout/stderr are left connected to this service's own
# (i.e. land in `journalctl -u bc250-cec` alongside our own log lines),
# deliberately not silenced, so a broken script is visible for debugging
# rather than failing invisibly.
run_custom_command() {
    local cmd="$1" event="$2"
    [[ -n "$cmd" ]] || return 0
    log "running configured $event command: $cmd"
    "$cmd" &
    disown
}

# Loop 1: poll the display's power state, trigger on a genuine off -> on
# or on -> off transition. Baseline-only on the first reading, so a
# display already on (or off) when this service (re)starts does not
# glitch the picture or spuriously fire a power-off command.
poll_power_loop() {
    local cec_dev="$1" trigger_path="$2" connector="$3" own_addr="$4"
    local state prev_state="" baseline_set=0

    while :; do
        state="$(query_power_state "$cec_dev")"

        if (( baseline_set )); then
            if [[ "$prev_state" != on && "$state" == on ]]; then
                # The custom power-on command runs from inside
                # fire_trigger() itself, not here -- see its own comment
                # for why.
                fire_trigger "$trigger_path" "$connector" "$cec_dev" "$own_addr" power_on "display powered on ($prev_state -> on)"
            elif [[ "$prev_state" == on && "$state" == off ]]; then
                # Strictly "off" (a confirmed pwr-state: standby reply),
                # not just "not on" -- a transient comms hiccup reads as
                # "unknown", never "off", so it can no longer masquerade
                # as a genuine power-off here. See query_power_state().
                run_custom_command "$ON_POWER_OFF_COMMAND" "power-off"
            fi
        else
            log "baseline display power state: $state"
        fi

        baseline_set=1
        prev_state="$state"
        sleep "$POLL_INTERVAL_S"
    done
}

# Loop 2: passively watch the bus for SET_STREAM_PATH/ACTIVE_SOURCE naming
# our own physical address -- the signal that a TV/AVR just switched its
# active input to us while the display itself never went to standby, which
# the power-state poll alone cannot see. Read-only: never replies on the
# bus, so this cannot itself cause an input switch.
#
# Our own trigger_hotplug writes invalidate `cec-ctl -m`'s open handle --
# confirmed on hardware, it exits a few seconds after we fire a replug
# (presumably the DRM connector disconnect/reconnect cycling the CEC
# adapter underneath it). The device path itself stays stable (still
# /dev/cec0 every time), so just reattach in place rather than treating
# this as fatal -- the first design killed and restarted the whole
# service on every such hiccup, which briefly blinds the power-poll loop
# too (a fresh instance's first reading is always baseline-only, so a
# transition landing in that gap would be silently missed).
monitor_active_source_loop() {
    local cec_dev="$1" trigger_path="$2" connector="$3" own_addr="$4"
    local pending line

    if [[ -z "$own_addr" ]]; then
        log "could not determine our own physical address; active-source watch disabled"
        return 1
    fi
    log "watching for active-source switches to $own_addr"

    while :; do
        pending=0
        # cec-ctl -m prints each message opcode on one line and its fields
        # (e.g. "phys-addr: 2.3.0.0") on the following indented lines --
        # track whether the last opcode line was one we care about, then
        # check the next phys-addr line against our own address.
        #
        # Only "Received from" lines: confirmed on hardware 2026-09-28
        # that our own SWITCH_INPUT_ON_POWER_ON broadcast shows up here
        # as "Transmitted by Playback Device 1 to all (...): ACTIVE_SOURCE"
        # -- without this filter the monitor detects its own broadcast as
        # if the TV had switched to us and re-fires (the 30s cooldown
        # happened to still be active when this was first caught, but
        # reacting to our own transmissions is wrong regardless of timing).
        while IFS= read -r line; do
            if grep -qE '^Received from.*(SET_STREAM_PATH|ACTIVE_SOURCE)' <<<"$line"; then
                pending=1
                continue
            fi
            if (( pending )) && grep -qE 'phys-addr:' <<<"$line"; then
                if grep -qF "$own_addr" <<<"$line"; then
                    fire_trigger "$trigger_path" "$connector" "$cec_dev" "$own_addr" active_source "active source switched to us ($own_addr)"
                fi
                pending=0
            fi
        done < <(cec-ctl -d "$cec_dev" -m 2>/dev/null)

        log "active-source monitor's cec-ctl exited; reattaching"
        sleep 1
    done
}

main() {
    local cec_info cec_dev connector trigger_path own_addr waiting=""

    # The adapter only exists once amdgpu has brought up a CEC-capable
    # display, which can be much later than boot (TV off, adapter unplugged)
    # or never (a display without CEC). Wait for it here, quietly: exiting
    # for a systemd restart logged the same failure every 10 seconds.
    # Logged once on entering the wait and once when it ends.
    while :; do
        if cec_info="$(discover_cec)"; then
            cec_dev="$(sed -n 1p <<<"$cec_info")"
            connector="$(sed -n 2p <<<"$cec_info")"
            trigger_path="$(find_relink_path "$connector")" && break
            if [[ "$waiting" != hotplug ]]; then
                log "found $cec_dev on connector $connector, but no link_settings/trigger_hotplug debugfs entry yet; waiting"
                waiting=hotplug
            fi
        elif [[ "$waiting" != adapter ]]; then
            log "no CEC adapter yet (no /dev/cecN); waiting for one to appear"
            waiting=adapter
        fi
        sleep "$POLL_INTERVAL_S"
    done
    log "found $cec_dev on connector $connector; relinking via $(basename "$trigger_path")"

    cec-ctl -d "$cec_dev" --playback --osd-name "$OSD_NAME" >/dev/null || {
        log "failed to claim a CEC logical address on $cec_dev; exiting for a restart"
        exit 1
    }
    log "claimed a Playback logical address on $cec_dev as '$OSD_NAME'"
    own_addr="$(own_physical_address "$cec_dev")"

    mkdir -p "$(dirname "$TRIGGER_STATE_FILE")"

    poll_power_loop "$cec_dev" "$trigger_path" "$connector" "$own_addr" &
    local poll_pid=$!
    monitor_active_source_loop "$cec_dev" "$trigger_path" "$connector" "$own_addr" &
    local monitor_pid=$!

    # Either loop exiting is unexpected (both are infinite by design) --
    # tear down the other and exit so systemd restarts the whole service
    # cleanly rather than leaving an orphaned background loop running
    # under the old PID while systemd starts a fresh instance. `|| true`
    # keeps `set -e` from skipping the cleanup below on a nonzero exit.
    wait -n "$poll_pid" "$monitor_pid" || true
    kill "$poll_pid" "$monitor_pid" 2>/dev/null || true
    log "a monitoring loop exited unexpectedly; exiting for a restart"
    exit 1
}

main "$@"
