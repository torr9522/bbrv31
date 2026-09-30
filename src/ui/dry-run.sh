#!/usr/bin/env bash
set -euo pipefail
UI_ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
summary() {
    local input=$1 get
    get() { awk -F= -v key="$1" '$1==key {sub(/^[^=]*=/, ""); print; exit}' "$input"; }
    printf 'System: %s %s %s\n' "$(get platform.os)" "$(get platform.version)" "$(get platform.arch)"
    printf 'CPU: %s vCPU / %s\n' "$(get cpu.count)" "$(get cpu.level)"
    printf 'Memory: %s MiB / %s\n' "$(get memory.total_mib)" "$(get memory_mode)"
    printf 'Swap: %s (%s MiB)\n' "$(get swap.kind)" "$(get swap.total_mib)"
    printf 'Virtualization: %s\n' "$(get virtualization.class)"
    printf 'Platform: %s / kernel baseline: %s\n' "$(get platform_support)" "$(get kernel_compatibility)"
    printf 'Profile: %s (%s)\n' "$(get profile)" "$(get profile_confidence)"
    printf 'Bandwidth: %s Mbps (%s)\n' "$(get bandwidth_mbps)" "$(get bandwidth_source)"
    printf 'Buffer: Original %s MB / guard %s\n' "$(get buffer_original_mb)" "$(get buffer_guard)"
    printf 'Qdisc: %s / policy %s\n' "$(get qdisc.root)" "$(get qdisc_policy)"
    printf 'RPS/RFS: %s (%s)\n' "$(get rps_rfs_policy)" "$(get rps_rfs_reason)"
    printf 'MSS: %s (%s)\n' "$(get mss_policy)" "$(get mss_reason)"
    printf 'Route IW: %s\n' "$(get route_iw_policy)"
    printf 'THP: %s / nofile: %s\n' "$(get thp_policy)" "$(get nofile_policy)"
    printf 'Sysctl: %s original keys\n' "$(get sysctl_count)"
    printf 'System mutation: %s\n' "$(get system_mutation)"
}
detail() { cat "$1"; }

case ${1:-} in
  summary) summary "$2";;
  detail) detail "$2";;
esac
