#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/kernel.sh"
kernel_preflight() {
    local os version arch secure; os=$(. /etc/os-release; printf '%s' "$ID"); version=$(. /etc/os-release; printf '%s' "$VERSION_ID"); arch=$(uname -m); secure=unknown
    command -v mokutil >/dev/null 2>&1 && secure=$(mokutil --sb-state 2>/dev/null | awk '{print tolower($NF)}') || true
    [[ $os == debian && $version == 12 && $arch == x86_64 ]] || return 2; [[ $secure != enabled ]] || return 3; [[ $(kernel_cpu_level) == x86-64-v3 ]] || return 4; command -v dpkg >/dev/null && command -v update-initramfs >/dev/null && command -v update-grub >/dev/null || return 5
}
kernel_capture_fallback() { local d=${1:-$BBRV3_KERNEL_STATE_ROOT}; mkdir -p "$d"; dpkg-query -W -f='${Package}\t${Version}\n' 'linux-image-*' 2>/dev/null | grep -v xanmod >"$d/fallback-kernels.tsv" || true; [[ -s "$d/fallback-kernels.tsv" ]]; }
kernel_set_one_shot() { local entry=$1 d=${2:-$BBRV3_KERNEL_STATE_ROOT}; command -v grub-reboot >/dev/null 2>&1 || return 1; grub-reboot "$entry"; grub-editenv /boot/grub/grubenv list >"$d/grubenv.after"; printf ONE_SHOT_READY >"$d/boot-state"; }
kernel_set_persistent_default() {
    local entry=$1 d=${2:-$BBRV3_KERNEL_STATE_ROOT}
    local defaults=${BBRV3_GRUB_DEFAULT_FILE:-/etc/default/grub}
    local grubenv=${BBRV3_GRUB_ENV_FILE:-/boot/grub/grubenv}
    local formal=${BBRV3_FORMAL_KERNEL:-6.18.54-x64v3-xanmod1}
    local current_default saved_entry current_defaults current_grubenv candidate
    [[ -r $defaults && -r $grubenv ]] || return 1
    mkdir -p "$d"
    current_default=$(sed -n 's/^GRUB_DEFAULT=//p' "$defaults" | head -1)
    if [[ $current_default == *"$formal"* ]]; then
        printf '%s\n' "$entry" >"$d/persistent-boot-entry"
        printf PERSISTENT_READY >"$d/boot-state"
        return 0
    fi
    if [[ $current_default == saved ]]; then
        command -v grub-editenv >/dev/null 2>&1 || return 1
        saved_entry=$(grub-editenv "$grubenv" list 2>/dev/null | sed -n 's/^saved_entry=//p' | head -1)
        if [[ $saved_entry == "$entry" ]]; then
            printf '%s\n' "$entry" >"$d/persistent-boot-entry"
            printf PERSISTENT_READY >"$d/boot-state"
            return 0
        fi
    fi
    command -v update-grub >/dev/null 2>&1 || return 1
    command -v grub-set-default >/dev/null 2>&1 || return 1
    command -v grub-editenv >/dev/null 2>&1 || return 1
    current_defaults=$(mktemp)
    current_grubenv=$(mktemp)
    candidate=$(mktemp)
    cp -a "$defaults" "$current_defaults"
    cp -a "$grubenv" "$current_grubenv"
    [[ -e $d/grub.default.before ]] || cp -a "$defaults" "$d/grub.default.before"
    [[ -e $d/grubenv.before-persistent ]] || cp -a "$grubenv" "$d/grubenv.before-persistent"
    awk 'BEGIN { found=0 } /^GRUB_DEFAULT=/ { print "GRUB_DEFAULT=saved"; found=1; next } { print } END { if (!found) print "GRUB_DEFAULT=saved" }' "$defaults" >"$candidate"
    cat "$candidate" >"$defaults"
    if ! update-grub >/dev/null || ! grub-set-default "$entry"; then
        cat "$current_defaults" >"$defaults"
        cp -a "$current_grubenv" "$grubenv"
        update-grub >/dev/null 2>&1 || true
        rm -f "$current_defaults" "$current_grubenv" "$candidate"
        return 1
    fi
    grub-editenv "$grubenv" list >"$d/grubenv.persistent"
    if ! grep -Fqx "saved_entry=$entry" "$d/grubenv.persistent"; then
        cat "$current_defaults" >"$defaults"
        cp -a "$current_grubenv" "$grubenv"
        update-grub >/dev/null 2>&1 || true
        rm -f "$current_defaults" "$current_grubenv" "$candidate"
        return 1
    fi
    printf '%s\n' "$entry" >"$d/persistent-boot-entry"
    printf PERSISTENT_READY >"$d/boot-state"
    rm -f "$current_defaults" "$current_grubenv" "$candidate"
}
kernel_find_xanmod_entry() { local cfg=${BBRV3_GRUB_CFG:-/boot/grub/grub.cfg}; sed -n "s/^[[:space:]]*menuentry .*'\\([^']*xanmod[^']*\\)'.*/\\1/p" "$cfg" 2>/dev/null | head -1; }
kernel_protect_fallback() { local d=${1:-$BBRV3_KERNEL_STATE_ROOT}; [[ -s "$d/fallback-kernels.tsv" ]] || kernel_capture_fallback "$d"; }
kernel_install_package() { local pkg=$1 d=${2:-$BBRV3_KERNEL_STATE_ROOT} entry; kernel_preflight; mkdir -p "$d"; kernel_capture_fallback "$d" || return 6; dpkg-deb --info "$pkg" >"$d/package.info"; sha256sum "$pkg" >"$d/package.sha256"; dpkg -i "$pkg"; update-initramfs -u -k all; update-grub; kernel_protect_fallback "$d"; entry=$(kernel_find_xanmod_entry || true); [[ -n $entry ]] || return 7; kernel_set_one_shot "$entry" "$d"; printf '%s\n' "$entry" >"$d/boot-entry"; printf INSTALLED >"$d/state"; }
kernel_update_package() { kernel_install_package "$@"; }
kernel_uninstall_package() { local package=$1; [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) == 'install ok installed' ]] || return 1; [[ $(uname -r) != *xanmod* ]] || return 2; local fallback; fallback=$(dpkg-query -W -f='${Package}\n' 'linux-image-*' 2>/dev/null | grep -v xanmod | head -1); [[ -n $fallback ]] || return 3; DEBIAN_FRONTEND=noninteractive apt-get remove -y "$package"; }
