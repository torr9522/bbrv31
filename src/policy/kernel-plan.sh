#!/usr/bin/env bash
set -euo pipefail
kernel_policy() {
    local os=${1:-debian} version=${2:-12} arch=${3:-amd64} cpu=${4:-unknown} secure=${5:-unknown} virt=${6:-unknown}
    [[ $os == debian && $version == 12 && $arch == amd64 ]] || { printf 'kernel.decision=BLOCKED\nkernel.reason=SUPPORTED_PLATFORM_REQUIRED\n'; return; }
    [[ $secure == enabled ]] && { printf 'kernel.decision=BLOCKED\nkernel.reason=SECURE_BOOT_ENABLED\n'; return; }
    [[ $virt == CONTAINER || $virt == LXC || $virt == OPENVZ ]] && { printf 'kernel.decision=BLOCKED\nkernel.reason=CONTAINER_KERNEL_SHARED\n'; return; }
    if [[ $cpu == x86-64-v3 ]]; then printf 'kernel.decision=CANDIDATE\nkernel.catalog=6.18.54-x64v3-xanmod1\nkernel.reason=FORMAL_BASELINE\n'; else printf 'kernel.decision=ALTERNATE_BASELINE_REQUIRED\nkernel.catalog=6.18.54-x64v3-xanmod1\nkernel.reason=CPU_BELOW_X64V3\n'; fi
}
