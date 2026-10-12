#!/bin/bash
# Called by udev (71-bc250-cec-keys.rules) when an rc input device appears, and
# by the package scripts for devices that already exist. $1 is the rc device
# name, e.g. rc0. Does nothing for non-CEC remotes.
#
# The kernel's rc-cec keymap turns the TV remote's OK into KEY_OK and its Back
# into KEY_BACK/KEY_EXIT, which Steam's UI ignores. Remap them to Enter and
# Esc, which it understands.
set -u

rc="${1:-}"
[[ "$rc" =~ ^rc[0-9]+$ ]] || exit 0
[[ "$(sed -n 's/^DRV_NAME=//p' "/sys/class/rc/$rc/uevent" 2>/dev/null)" == cec ]] || exit 0

# CEC user-control codes: 0x00 Select (OK), 0x0d Exit, 0x4c Back. LG remotes
# send Exit for their Back button, so both go to Esc.
keymap='0x00=KEY_ENTER,0x0d=KEY_ESC,0x4c=KEY_ESC'
enabled=1

# /etc/bc250-cec.conf is plain KEY=value for systemd, so read it as text.
conf=/etc/bc250-cec.conf
if [[ -r "$conf" ]]; then
    while IFS='=' read -r key value; do
        value="${value%\"}"; value="${value#\"}"
        case "$key" in
            BC250_CEC_REMOTE_KEYS) enabled="$value" ;;
            BC250_CEC_REMOTE_KEYMAP) [[ -n "$value" ]] && keymap="$value" ;;
        esac
    done < <(grep -E '^[[:space:]]*BC250_CEC_REMOTE_KEY(S|MAP)=' "$conf")
fi

[[ "$enabled" == 1 ]] || exit 0
# scancode=KEY_NAME pairs only: this goes to ir-keytable, nothing else.
if [[ ! "$keymap" =~ ^0x[0-9a-fA-F]+=KEY_[A-Z0-9_]+(,0x[0-9a-fA-F]+=KEY_[A-Z0-9_]+)*$ ]]; then
    echo "bc250-cec: ignoring malformed BC250_CEC_REMOTE_KEYMAP: $keymap" >&2
    exit 0
fi

exec ir-keytable -s "$rc" -k "$keymap" >/dev/null
