#!/usr/bin/env bash
set -euo pipefail
ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$ROOT/src/core/kernel.sh"
source "$ROOT/src/apply/kernel.sh"
source "$ROOT/src/policy/kernel-plan.sh"
kernel_plan_command() { local os version; . /etc/os-release; os=$ID; version=$VERSION_ID; kernel_policy "$os" "$version" "$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" "$(kernel_cpu_level)" unknown "$(systemd-detect-virt 2>/dev/null || printf unknown)"; }
kernel_status_command() { printf 'kernel.current=%s\nkernel.cpu_level=%s\nkernel.boot_mode=%s\nkernel.catalog=6.18.54-x64v3-xanmod1\n' "$(uname -r)" "$(kernel_cpu_level)" "$(kernel_boot_mode)"; }
cmd=${1:-status}; shift || true
case $cmd in kernel-plan) kernel_plan_command;; kernel-status) kernel_status_command;; kernel-install|kernel-update|kernel-uninstall) [[ $EUID -eq 0 ]] || exit 1; kernel_lock || exit 1; case $cmd in kernel-install) kernel_install_package "$1";; kernel-update) kernel_update_package "$1";; kernel-uninstall) kernel_uninstall_package "$1";; esac;; *) exit 2;; esac
