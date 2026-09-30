#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/kernel.sh"
kernel_preflight() {
    local os version arch secure; os=$(. /etc/os-release; printf '%s' "$ID"); version=$(. /etc/os-release; printf '%s' "$VERSION_ID"); arch=$(uname -m); secure=unknown
    command -v mokutil >/dev/null 2>&1 && secure=$(mokutil --sb-state 2>/dev/null | awk '{print tolower($NF)}') || true
    [[ $os == debian && $version == 12 && $arch == x86_64 ]] || return 2; [[ $secure != enabled ]] || return 3; [[ $(kernel_cpu_level) == x86-64-v3 ]] || return 4; command -v dpkg >/dev/null && command -v update-initramfs >/dev/null && command -v update-grub >/dev/null || return 5
}
kernel_install_package() { local pkg=$1 d=${2:-$BBRV3_KERNEL_STATE_ROOT}; kernel_preflight; mkdir -p "$d"; dpkg-deb --info "$pkg" >"$d/package.info"; sha256sum "$pkg" >"$d/package.sha256"; dpkg -i "$pkg"; update-initramfs -c -k all; update-grub; printf INSTALLED >"$d/state"; }
kernel_update_package() { kernel_install_package "$@"; }
kernel_uninstall_package() { local package=$1; [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) == 'install ok installed' ]] || return 1; [[ $(uname -r) != *xanmod* ]] || return 2; dpkg -s linux-image-* >/dev/null 2>&1 || return 3; apt-get remove "$package"; }
