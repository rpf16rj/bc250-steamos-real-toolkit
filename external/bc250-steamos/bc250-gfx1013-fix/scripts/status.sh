#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Report the installation and boot state for bug reports. Read-only.

set -euo pipefail

kernel_release=7.1.5-101.fc43.x86_64
state_root=/var/lib/bc250-gfx1013
config_root=/etc/bc250-gfx1013
generator=/usr/lib/systemd/user-environment-generators/60-bc250-gfx1013-v33

section() { printf '\n== %s\n' "$1"; }

section system
uname -r
[[ -r /etc/os-release ]] && sed -n 's/^PRETTY_NAME=//p' /etc/os-release
if [[ $(uname -r) == "${kernel_release}" ]]; then
    printf 'kernel=supported\n'
else
    printf 'kernel=UNSUPPORTED (expected %s)\n' "${kernel_release}"
fi

section installation
if [[ -r ${state_root}/active.env ]]; then
    cat "${state_root}/active.env"
    printf 'entry_id=%s\n' "$(cat "${state_root}/entry-id" 2>/dev/null || echo missing)"
else
    printf 'no active installation\n'
fi
printf 'generator=%s\n' "$([[ -x ${generator} ]] && echo installed || echo missing)"
if [[ -r ${config_root}/active.env ]]; then
    # shellcheck disable=SC1091
    . "${config_root}/active.env"
    icd="/opt/bc250-gfx1013/${BC250_RELEASE_VERSION:-}/share/vulkan/icd.d/radeon_icd.x86_64.json"
    printf 'icd=%s (%s)\n' "${icd}" "$([[ -r ${icd} ]] && echo present || echo missing)"
fi

section boot
printf 'patched_boot_marker=%s\n' \
    "$(grep -qw 'bc250.gfx1013_v33=1' /proc/cmdline && echo yes || echo no)"
grub2-editenv list 2>/dev/null | grep -E '^(saved_entry|next_entry)=' || true

section environment
for name in VK_DRIVER_FILES VK_ICD_FILENAMES; do
    printf '%s=%s\n' "${name}" "${!name:-<unset>}"
done

section vulkan
if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary 2>/dev/null |
        grep -E 'deviceName|driverInfo|apiVersion' | sed 's/^[[:space:]]*//' | sort -u
else
    printf 'vulkaninfo is not installed (dnf install vulkan-tools)\n'
fi

section gpu
for device_dir in /sys/bus/pci/devices/*; do
    [[ -r ${device_dir}/vendor && -r ${device_dir}/device ]] || continue
    [[ $(<"${device_dir}/vendor") == 0x1002 ]] || continue
    [[ $(<"${device_dir}/device") == 0x13fe ]] || continue
    printf 'bc250=%s\n' "${device_dir##*/}"
done
lsmod | grep -q '^amdgpu' && printf 'amdgpu=loaded\n' || printf 'amdgpu=not loaded\n'

section kernel_log
# Recent GPU-related kernel messages (hangs, resets, page faults). Needs root
# or a readable journal; silently shortens otherwise.
{ journalctl -k -b --no-pager 2>/dev/null || dmesg 2>/dev/null; } |
    grep -iE 'amdgpu|drm.*(gfx|ring|reset)|gpu (hang|reset)|page fault' |
    tail -n 40 || printf 'kernel log not readable (run with sudo for this section)\n'
