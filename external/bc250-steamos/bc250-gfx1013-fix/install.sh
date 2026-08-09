#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

release_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
release_version=$(<"${release_root}/VERSION")

# The build targets the RUNNING kernel; this is the version everything was
# validated on. Other Fedora kernels get a warning, and a loud failure at the
# patch step if the amdgpu source has drifted too far.
tested_kernel=7.1.5-101.fc43.x86_64
kernel_release=$(uname -r)
kernel_version=${kernel_release%%-*}
kernel_rel=${kernel_release#*-}
kernel_rel=${kernel_rel%.*}
kernel_srpm_url="https://kojipkgs.fedoraproject.org/packages/kernel/${kernel_version}/${kernel_rel}/src/kernel-${kernel_version}-${kernel_rel}.src.rpm"
mesa_version=26.2.0-rc3
mesa_tarball_url=https://archive.mesa3d.org/mesa-${mesa_version}.tar.xz
mesa_tarball_sha256=f733c005660d342a51c6727d1ad481f43d05b4c601ac72247fa641e1d73a8ad1

build_root="${release_root}/build"
artifact_root="${build_root}/artifacts"
module_artifact="${artifact_root}/amdgpu.ko.xz"
mesa_stage_root="${artifact_root}/mesa-root"
mesa_prefix="/opt/bc250-gfx1013/${release_version}"

cu_mode=24
state_root=/var/lib/bc250-gfx1013
config_root=/etc/bc250-gfx1013
generator=/usr/lib/systemd/user-environment-generators/60-bc250-gfx1013-v33
stock_module="/usr/lib/modules/${kernel_release}/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.xz"
stock_initramfs="/boot/initramfs-${kernel_release}.img"

usage() {
    cat >&2 <<EOF
usage:
  sudo $0 deps        install build dependencies (dnf)
  $0 build [--40cu]   build the kernel module and Mesa from patches/
  sudo $0 install [--40cu]   install the built artifacts; patched boot is one-shot
  sudo $0 activate    make the patched entry the default (run from a patched boot)
  sudo $0 boot-patched   select the patched entry for the next boot only
  sudo $0 boot-stock     select the stock entry for the next boot only
  sudo $0 uninstall
  $0 status

Optional Mesa features (mesh/task shaders, taskmesh queries) are controlled by
patches/mesa/series: comment a line out with '#' before running build to skip
that patch. The kernel v33 patches are all required. --40cu additionally applies
the duggasco 40-CU unlock patch and boot parameter (see README).
EOF
    exit 64
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ ${EUID} -eq 0 ]] || die 'this operation requires root'
}

verify_target() {
    local device_dir match=0

    [[ ${kernel_release} == "${tested_kernel}" ]] ||
        printf 'warning: running kernel %s; validated on %s only\n' \
            "${kernel_release}" "${tested_kernel}" >&2
    [[ -r /etc/os-release ]] || die '/etc/os-release is missing'
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ ${ID:-} == fedora ]] ||
        die 'install.sh supports only Fedora; see README Option 2 for other distros'
    [[ ${VERSION_ID:-} == 43 ]] ||
        printf 'warning: Fedora %s; validated on Fedora 43 only\n' "${VERSION_ID:-?}" >&2
    command -v rpm-ostree >/dev/null 2>&1 &&
        die 'Fedora Atomic/Bazzite is not supported by this direct installer'

    for device_dir in /sys/bus/pci/devices/*; do
        [[ -r ${device_dir}/vendor && -r ${device_dir}/device ]] || continue
        [[ $(<"${device_dir}/vendor") == 0x1002 ]] || continue
        [[ $(<"${device_dir}/device") == 0x13fe ]] || continue
        match=1
        break
    done
    [[ ${match} -eq 1 ]] || die 'AMD BC-250 PCI device 1002:13fe was not found'

    if grep -rqs 'bc250_cc_write_mode' /etc/modprobe.d/; then
        printf 'note: a 40-CU unlock modprobe config was detected. It affects the stock\n' >&2
        printf 'module only; the patched boot builds its own. To keep 40 CU on the patched\n' >&2
        printf 'boot, use: ./install.sh build --40cu && sudo ./install.sh install --40cu\n' >&2
    fi

    for command_name in dracut lsinitrd grub2-editenv modinfo depmod sha256sum; do
        command -v "${command_name}" >/dev/null 2>&1 ||
            die "required command is missing: ${command_name}"
    done
    [[ -f ${stock_module} ]] || die "stock module is missing: ${stock_module}"
    [[ -f ${stock_initramfs} ]] || die "stock initramfs is missing: ${stock_initramfs}"
}

install_deps() {
    require_root
    dnf install -y --setopt=install_weak_deps=False \
        curl xz tar cpio patch gcc gcc-c++ make elfutils-libelf-devel openssl \
        "kernel-devel-${kernel_release%.*}" \
        meson ninja-build bison flex python3-mako python3-pyyaml glslang \
        libdrm-devel libxcb-devel libX11-devel libxshmfence-devel \
        libXrandr-devel wayland-devel wayland-protocols-devel \
        expat-devel zlib-devel libzstd-devel spirv-tools-devel
}

fetch() {
    local url=$1 destination=$2
    [[ -f ${destination} ]] && return 0
    curl -fL --retry 3 -o "${destination}.part" "${url}"
    mv "${destination}.part" "${destination}"
}

build_kernel_module() {
    local source_root="${build_root}/kernel"
    local srpm
    srpm="${build_root}/$(basename "${kernel_srpm_url}")"
    local kernel_tree="/usr/src/kernels/${kernel_release}"
    local tarball_name patch_file module

    [[ -d ${kernel_tree} ]] ||
        die "kernel-devel for ${kernel_release} is missing; run: sudo $0 deps"

    printf '== kernel module: fetching source\n'
    fetch "${kernel_srpm_url}" "${srpm}"
    rm -rf "${source_root}"
    mkdir -p "${source_root}"
    (cd "${source_root}" &&
        rpm2cpio "${srpm}" | cpio -id --quiet 'linux-*.tar.xz')
    tarball_name=$(find "${source_root}" -maxdepth 1 -name 'linux-*.tar.xz' | head -1)
    [[ -n ${tarball_name} ]] || die 'kernel source tarball not found in the src.rpm'

    printf '== kernel module: extracting drivers/gpu/drm/amd\n'
    tar -C "${source_root}" -xf "${tarball_name}" --wildcards 'linux-*/drivers/gpu/drm/amd'
    local linux_root
    linux_root=$(find "${source_root}" -maxdepth 1 -type d -name 'linux-*' | head -1)

    printf '== kernel module: applying patches\n'
    for patch_file in "${release_root}"/patches/kernel/v33/*.patch; do
        printf '   %s\n' "$(basename "${patch_file}")"
        patch -p1 -s -d "${linux_root}" <"${patch_file}"
    done
    if [[ ${cu_mode} == 40 ]]; then
        printf '   40cu-bc250-unlock.patch\n'
        patch -p1 -d "${linux_root}" <"${release_root}/patches/kernel/40cu-bc250-unlock.patch"
    fi

    printf '== kernel module: building\n'
    make -C "${kernel_tree}" "M=${linux_root}/drivers/gpu/drm/amd/amdgpu" \
        modules "-j$(nproc)" >"${build_root}/kernel-build.log" 2>&1 ||
        die "kernel module build failed; see ${build_root}/kernel-build.log"

    module="${linux_root}/drivers/gpu/drm/amd/amdgpu/amdgpu.ko"
    [[ -f ${module} ]] || die 'amdgpu.ko was not produced'
    [[ $(modinfo -F vermagic "${module}") == "${kernel_release} "* ]] ||
        die 'built module vermagic does not match the running kernel'

    mkdir -p "${artifact_root}"
    xz -9 -c "${module}" >"${module_artifact}"
    printf '%s\n' "${cu_mode}" >"${artifact_root}/cu-mode"
    printf '== kernel module: done (%s)\n' "${module_artifact}"
}

build_mesa() {
    local source_root="${build_root}/mesa"
    local tarball="${build_root}/mesa-${mesa_version}.tar.xz"
    local series="${release_root}/patches/mesa/series"
    local mesa_src="${source_root}/mesa-${mesa_version}"
    local patch_name

    [[ -f ${series} ]] || die "patch series is missing: ${series}"

    printf '== mesa: fetching source\n'
    fetch "${mesa_tarball_url}" "${tarball}"
    printf '%s  %s\n' "${mesa_tarball_sha256}" "${tarball}" | sha256sum --quiet -c ||
        die 'mesa tarball failed checksum verification'
    rm -rf "${source_root}"
    mkdir -p "${source_root}"
    tar -C "${source_root}" -xf "${tarball}"

    printf '== mesa: applying patches from series\n'
    while IFS= read -r patch_name; do
        [[ -z ${patch_name} || ${patch_name} == \#* ]] && continue
        printf '   %s\n' "${patch_name}"
        patch -p1 -s -d "${mesa_src}" <"${release_root}/patches/mesa/${patch_name}"
    done <"${series}"

    printf '== mesa: building\n'
    meson setup "${source_root}/build" "${mesa_src}" \
        -Dvulkan-drivers=amd -Dgallium-drivers= -Dplatforms=x11,wayland \
        -Dglx=disabled -Dllvm=disabled -Dvideo-codecs= \
        -Dprefix="${mesa_prefix}" -Dlibdir=lib64 -Dbuildtype=release \
        >"${build_root}/mesa-setup.log" 2>&1 ||
        die "meson setup failed; see ${build_root}/mesa-setup.log"
    ninja -C "${source_root}/build" >"${build_root}/mesa-build.log" 2>&1 ||
        die "mesa build failed; see ${build_root}/mesa-build.log"

    rm -rf "${mesa_stage_root}"
    DESTDIR="${mesa_stage_root}" ninja -C "${source_root}/build" install \
        >>"${build_root}/mesa-build.log" 2>&1
    [[ -f "${mesa_stage_root}${mesa_prefix}/lib64/libvulkan_radeon.so" ]] ||
        die 'mesa install staging is missing libvulkan_radeon.so'
    printf '== mesa: done (%s)\n' "${mesa_stage_root}${mesa_prefix}"
}

build_release() {
    mkdir -p "${build_root}"
    build_kernel_module
    build_mesa
    printf 'build complete (%s CU); next: sudo %s install\n' "${cu_mode}" "$0"
}

capture_state() {
    local destination=$1
    install -d -m 0700 "${destination}"
    uname -a >"${destination}/uname.txt"
    cp -a /proc/cmdline "${destination}/cmdline.txt"
    cp -a /etc/os-release "${destination}/os-release"
    cp --preserve=all "${stock_module}" "${destination}/stock-amdgpu.ko.xz"
    cp --preserve=all "${stock_initramfs}" "${destination}/stock-initramfs.img"
    grub2-editenv list >"${destination}/grubenv-before.txt"
    sed -n 's/^saved_entry=//p' "${destination}/grubenv-before.txt" \
        >"${destination}/saved-entry-before.txt"
    find /boot/loader/entries -maxdepth 1 -type f -print0 2>/dev/null |
        sort -z | xargs -0 -r sha256sum >"${destination}/bls-sha256.txt"
    sha256sum "${destination}/stock-amdgpu.ko.xz" \
        "${destination}/stock-initramfs.img" >"${destination}/SHA256SUMS"
}

stage_boot_entry() {
    local backup=$1 module_payload=$2
    local machine_id stock_entry variant test_entry test_entry_id test_initramfs
    local staging_entry verify_root embedded_module stock_hash payload_hash
    local restore_needed=0

    machine_id=$(< /etc/machine-id)
    stock_entry="/boot/loader/entries/${machine_id}-${kernel_release}.conf"
    variant="bc250-gfx1013-v33"
    test_entry="/boot/loader/entries/${machine_id}-${kernel_release}-${variant}.conf"
    test_entry_id="${machine_id}-${kernel_release}-${variant}"
    test_initramfs="/boot/initramfs-${kernel_release}-${variant}.img"
    staging_entry=$(mktemp)
    verify_root=$(mktemp -d)

    [[ -f ${stock_entry} ]] || die "stock BLS entry is missing: ${stock_entry}"
    [[ ! -e ${test_entry} && ! -e ${test_initramfs} ]] ||
        die 'a BC-250 patched boot entry already exists; uninstall it first'
    [[ $(modinfo -F vermagic "${module_payload}") == "${kernel_release} "* ]] ||
        die 'patched module vermagic does not match the running kernel'

    stock_hash=$(sha256sum "${stock_module}" | awk '{print $1}')
    payload_hash=$(sha256sum "${module_payload}" | awk '{print $1}')

    restore_stock_module() {
        if [[ ${restore_needed} -eq 1 ]]; then
            install -m 0644 "${backup}/stock-amdgpu.ko.xz" "${stock_module}"
            command -v restorecon >/dev/null 2>&1 && restorecon "${stock_module}"
            depmod -a "${kernel_release}"
            restore_needed=0
        fi
    }
    trap restore_stock_module EXIT
    restore_needed=1
    install -m 0644 "${module_payload}" "${stock_module}"
    command -v restorecon >/dev/null 2>&1 && restorecon "${stock_module}"
    depmod -a "${kernel_release}"
    dracut -f "${test_initramfs}" "${kernel_release}"
    restore_stock_module
    trap - EXIT

    [[ $(sha256sum "${stock_module}" | awk '{print $1}') == "${stock_hash}" ]] ||
        die 'stock module was not restored byte-for-byte'
    [[ $(sha256sum "${stock_initramfs}" | awk '{print $1}') == \
       $(sha256sum "${backup}/stock-initramfs.img" | awk '{print $1}') ]] ||
        die 'stock initramfs changed unexpectedly'

    (cd "${verify_root}" && lsinitrd --unpack "${test_initramfs}")
    embedded_module="${verify_root}${stock_module}"
    [[ -f ${embedded_module} ]] || die 'patched initramfs does not contain amdgpu.ko.xz'
    [[ $(sha256sum "${embedded_module}" | awk '{print $1}') == "${payload_hash}" ]] ||
        die 'patched initramfs contains the wrong amdgpu module'

    awk -v kernel_release="${kernel_release}" -v variant="${variant}" \
        -v image="$(basename "${test_initramfs}")" -v extra_kargs="${BC250_KARGS:-}" '
        /^title / { print "title Fedora Linux (" kernel_release ", BC-250 GFX1013 V33) 43"; next }
        /^version / { print "version " kernel_release "-" variant; next }
        /^initrd / { print "initrd /" image " $tuned_initrd"; next }
        /^options / {
            line=$0
            if (line !~ /amdgpu\.sched_policy=/) line=line " amdgpu.sched_policy=2"
            line=line " bc250.gfx1013_v33=1"
            if (extra_kargs != "") line=line " " extra_kargs
            print line
            next
        }
        { print }
    ' "${stock_entry}" >"${staging_entry}"

    grep -q 'bc250.gfx1013_v33=1' "${staging_entry}" || die 'boot marker generation failed'
    install -m 0644 "${staging_entry}" "${test_entry}"
    command -v restorecon >/dev/null 2>&1 && restorecon "${test_entry}" "${test_initramfs}"
    printf '%s\n' "${test_entry}" >"${state_root}/boot-entry"
    printf '%s\n' "${test_initramfs}" >"${state_root}/initramfs"
    printf '%s\n' "${test_entry_id}" >"${state_root}/entry-id"
    grub2-editenv - set "next_entry=${test_entry_id}"
    rm -f -- "${staging_entry}"
    rm -rf -- "${verify_root}"
}

install_release() {
    local stamp backup

    require_root
    verify_target
    [[ -f ${module_artifact} ]] ||
        die "kernel module artifact is missing; run: $0 build"
    [[ -f "${mesa_stage_root}${mesa_prefix}/lib64/libvulkan_radeon.so" ]] ||
        die "mesa artifact is missing; run: $0 build"
    [[ ! -e ${state_root}/active.env ]] || die 'a release is already installed; uninstall it first'

    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    backup="${state_root}/backups/${stamp}"
    capture_state "${backup}"
    install -d -m 0755 "${state_root}" "${config_root}" "$(dirname "${generator}")"
    printf '%s\n' "${backup}" >"${state_root}/active-backup"

    rm -rf "${mesa_prefix}"
    install -d -m 0755 "$(dirname "${mesa_prefix}")"
    cp -a "${mesa_stage_root}${mesa_prefix}" "${mesa_prefix}"
    install -m 0755 "${release_root}/config/60-bc250-gfx1013-v33" "${generator}"
    cat >"${config_root}/active.env" <<EOF
BC250_RELEASE_VERSION=${release_version}
EOF
    cp -a "${config_root}/active.env" "${state_root}/active.env"

    if [[ $(cat "${artifact_root}/cu-mode" 2>/dev/null) == 40 || ${cu_mode} == 40 ]]; then
        BC250_KARGS="amdgpu.bc250_cc_write_mode=3${BC250_KARGS:+ ${BC250_KARGS}}"
    fi
    stage_boot_entry "${backup}" "${module_artifact}"
    printf 'install complete\n'
    printf 'the patched entry is selected for the next boot only; stock remains the default\n'
    printf 'reboot when ready, then run: %s status\n' "$0"
}

require_active_install() {
    [[ -r ${state_root}/active.env && -r ${state_root}/entry-id ]] ||
        die 'no active BC-250 release installation was found'
}

activate_release() {
    local entry_id
    require_root
    require_active_install
    grep -qw 'bc250.gfx1013_v33=1' /proc/cmdline ||
        die 'boot the patched entry successfully before making it the default'
    entry_id=$(<"${state_root}/entry-id")
    grub2-set-default "${entry_id}"
    printf 'the patched entry is now the saved default\n'
}

boot_patched_once() {
    local entry_id
    require_root
    require_active_install
    entry_id=$(<"${state_root}/entry-id")
    grub2-editenv - set "next_entry=${entry_id}"
    printf 'the patched entry is selected for the next boot only\n'
}

boot_stock_once() {
    local stock_entry_id
    require_root
    require_active_install
    stock_entry_id="$(< /etc/machine-id)-${kernel_release}"
    [[ -f /boot/loader/entries/${stock_entry_id}.conf ]] ||
        die 'the stock BLS entry is missing'
    grub2-editenv - set "next_entry=${stock_entry_id}"
    printf 'the stock entry is selected for the next boot only\n'
}

uninstall_release() {
    local boot_entry initramfs entry_id active_version
    local next_entry saved_entry backup original_saved_entry

    require_root
    [[ -r ${state_root}/active.env ]] || die 'no active BC-250 release installation was found'
    # shellcheck disable=SC1091
    . "${state_root}/active.env"
    active_version=${BC250_RELEASE_VERSION:?}
    # Tolerate a partially-completed install: any state file may be absent.
    boot_entry=$(cat "${state_root}/boot-entry" 2>/dev/null || true)
    initramfs=$(cat "${state_root}/initramfs" 2>/dev/null || true)
    entry_id=$(cat "${state_root}/entry-id" 2>/dev/null || true)
    backup=$(cat "${state_root}/active-backup" 2>/dev/null || true)

    if [[ -n ${entry_id} ]]; then
        next_entry=$(grub2-editenv list | sed -n 's/^next_entry=//p')
        [[ ${next_entry} != "${entry_id}" ]] || grub2-editenv - unset next_entry
        saved_entry=$(grub2-editenv list | sed -n 's/^saved_entry=//p')
        if [[ ${saved_entry} == "${entry_id}" ]]; then
            original_saved_entry=$(cat "${backup}/saved-entry-before.txt" 2>/dev/null || true)
            [[ -n ${original_saved_entry} ]] ||
                original_saved_entry="$(< /etc/machine-id)-${kernel_release}"
            grub2-set-default "${original_saved_entry}"
        fi
    fi
    [[ -n ${boot_entry} ]] && rm -f -- "${boot_entry}"
    [[ -n ${initramfs} ]] && rm -f -- "${initramfs}"
    rm -f -- "${generator}" "${config_root}/active.env"
    rm -rf -- "/opt/bc250-gfx1013/${active_version:?}"
    rmdir --ignore-fail-on-non-empty /opt/bc250-gfx1013 "${config_root}" 2>/dev/null || true
    mv "${state_root}/active.env" "${state_root}/last-uninstalled.env"
    printf 'uninstall complete; the stock kernel module and boot entry were never replaced\n'
}

case ${1:-} in
    deps)
        [[ $# -eq 1 ]] || usage
        install_deps
        ;;
    build)
        [[ $# -eq 1 || ( $# -eq 2 && ${2} == --40cu ) ]] || usage
        [[ ${2:-} == --40cu ]] && cu_mode=40
        build_release
        ;;
    install)
        [[ $# -eq 1 || ( $# -eq 2 && ${2} == --40cu ) ]] || usage
        [[ ${2:-} == --40cu ]] && cu_mode=40
        install_release
        ;;
    uninstall)
        [[ $# -eq 1 ]] || usage
        uninstall_release
        ;;
    activate)
        [[ $# -eq 1 ]] || usage
        activate_release
        ;;
    boot-patched)
        [[ $# -eq 1 ]] || usage
        boot_patched_once
        ;;
    boot-stock)
        [[ $# -eq 1 ]] || usage
        boot_stock_once
        ;;
    status)
        [[ $# -eq 1 ]] || usage
        exec "${release_root}/scripts/status.sh"
        ;;
    *) usage ;;
esac
