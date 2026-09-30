#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
policy_system() {
    local thp=${1:-UNAVAILABLE} services=${2:-} secure=${3:-unknown} arch=${4:-unknown} os=${5:-unknown} version=${6:-unknown} cpu_level=${7:-unknown}
    if [[ $arch == amd64 && $os == debian && $version == 12 ]]; then platform_support=SUPPORTED; else platform_support=SUPPORTED_WITH_LIMITS; fi
    [[ $arch != amd64 ]] && platform_support=UNSUPPORTED
    [[ $os != debian || $version != 12 ]] && platform_support=SUPPORTED_WITH_LIMITS
    if [[ $cpu_level == x86-64-v3 || $cpu_level == x86-64-v4 ]]; then kernel_compatibility=PASS; else kernel_compatibility=NO; fi
    if [[ $secure == enabled ]]; then kernel_install_policy=BLOCKED; kernel_block_reason=SECURE_BOOT_ENABLED; else kernel_install_policy=UNDECIDED; kernel_block_reason=NONE; fi
    if [[ $thp == UNAVAILABLE ]]; then thp_policy=SKIP; else thp_policy=DEFER_RUNTIME_VALIDATION; fi
    if [[ -n $services ]]; then nofile_policy=SERVICE_AWARE_CANDIDATE; else nofile_policy=COMPATIBILITY_TARGET_524288; fi
    policy_kv platform_support "$platform_support"; policy_kv kernel_compatibility "$kernel_compatibility"; policy_kv kernel_install_policy "$kernel_install_policy"; policy_kv kernel_block_reason "$kernel_block_reason"; policy_kv thp_policy "$thp_policy"; policy_kv thp_compat_target never; policy_kv nofile_policy "$nofile_policy"; policy_kv nofile_compat_target 524288
}
