#!/usr/bin/env bash
set -euo pipefail
BBRV3_KERNEL_STATE_ROOT=${BBRV3_KERNEL_STATE_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/kernel}
kernel_ensure_root() { [[ ! -L $BBRV3_KERNEL_STATE_ROOT ]] || return 1; install -d -m 700 "$BBRV3_KERNEL_STATE_ROOT"; }
kernel_lock() { kernel_ensure_root; exec 6>"$BBRV3_KERNEL_STATE_ROOT/lock"; flock -n 6; }
kernel_cpu_level() { local flags; flags=$(awk -F: '/^(flags|Features)/{print $2;exit}' /proc/cpuinfo); if [[ $(uname -m) != x86_64 ]]; then printf arm64; elif grep -qw avx2 <<<"$flags" && grep -qw fma <<<"$flags"; then printf x86-64-v3; elif grep -qw sse4_2 <<<"$flags"; then printf x86-64-v2; else printf x86-64-v1; fi; }
kernel_boot_mode() { [[ -d /sys/firmware/efi ]] && printf UEFI || printf BIOS; }
