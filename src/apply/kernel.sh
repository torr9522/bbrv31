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
kernel_find_xanmod_entry() { sed -n "s/^[[:space:]]*menuentry .*'\\([^']*xanmod[^']*\\)'.*/\\1/p" /boot/grub/grub.cfg 2>/dev/null | head -1; }
kernel_protect_fallback() { local d=${1:-$BBRV3_KERNEL_STATE_ROOT}; [[ -s "$d/fallback-kernels.tsv" ]] || kernel_capture_fallback "$d"; }
kernel_install_package() { local pkg=$1 d=${2:-$BBRV3_KERNEL_STATE_ROOT} entry; kernel_preflight; mkdir -p "$d"; kernel_capture_fallback "$d" || return 6; dpkg-deb --info "$pkg" >"$d/package.info"; sha256sum "$pkg" >"$d/package.sha256"; dpkg -i "$pkg"; update-initramfs -u -k all; update-grub; kernel_protect_fallback "$d"; entry=$(kernel_find_xanmod_entry || true); [[ -n $entry ]] || return 7; kernel_set_one_shot "$entry" "$d"; printf '%s\n' "$entry" >"$d/boot-entry"; printf INSTALLED >"$d/state"; }
kernel_update_package() { kernel_install_package "$@"; }
kernel_uninstall_package() { local package=$1; [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) == 'install ok installed' ]] || return 1; [[ $(uname -r) != *xanmod* ]] || return 2; local fallback; fallback=$(dpkg-query -W -f='${Package}\n' 'linux-image-*' 2>/dev/null | grep -v xanmod | head -1); [[ -n $fallback ]] || return 3; apt-get remove "$package"; }
