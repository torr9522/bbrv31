#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
source "$BBRV3_ROOT/src/policy/region.sh" 2>/dev/null || true
source "$BBRV3_ROOT/src/policy/bandwidth.sh"
source "$BBRV3_ROOT/src/policy/buffer.sh"
source "$BBRV3_ROOT/src/policy/low-memory.sh"
source "$BBRV3_ROOT/src/policy/rps-rfs.sh"
source "$BBRV3_ROOT/src/policy/network.sh"
source "$BBRV3_ROOT/src/policy/system.sh"

policy_decision() {
    local ram cpu queues rss profile bw region_result bandwidth_result
    ram=$(policy_get memory.total_mib); cpu=$(policy_get cpu.count); queues=$(policy_get network.rx_queue_count); rss=$(policy_get network.rss)
    region_result=$(policy_region); printf '%s\n' "$region_result"
    bandwidth_result=$(policy_bandwidth); printf '%s\n' "$bandwidth_result"
    profile=$(awk -F= '$1=="profile"{print $2; exit}' <<<"$region_result")
    bw=$(awk -F= '$1=="bandwidth_mbps"{print $2; exit}' <<<"$bandwidth_result")
    policy_buffer "$profile" "$bw" "$ram"; policy_low_memory "$ram"
    policy_rps_rfs "$cpu" "$queues" "$rss"
    policy_network "$(policy_get capability.ip_forward)" "$(policy_get capability.iptables)" "$(policy_get qdisc.root)" "$(policy_get qdisc.cake_present)" "$(policy_get qdisc.htb_present)" "$(policy_get qdisc.tbf_present)" "$(policy_get qdisc.filters)" "$(policy_get qdisc.classes)" "$(policy_get qdisc.mq_root)" "$(policy_get qdisc.fq_present)"
    policy_system "$(policy_get thp.state)" "$(policy_get nofile.known_services)" "$(policy_get boot.secure_boot)" "$(policy_get platform.arch)" "$(policy_get platform.os)" "$(policy_get platform.version)" "$(policy_get cpu.level)"
    policy_kv swap_state "$(policy_get swap.kind)"; policy_kv qdisc_current "$(policy_get qdisc.root)"; policy_kv policy_version "$POLICY_VERSION"; [[ $profile == SYSTEM_DEFAULT ]] && policy_kv sysctl_count 27 || policy_kv sysctl_count 31; policy_kv fatal_reasons NONE; policy_kv blocking_reasons NONE; policy_kv degraded_reasons "$( [[ $(policy_get bandwidth_confidence) == LOW ]] && printf BANDWIDTH_EVIDENCE || printf NONE )"; policy_kv warnings NONE; policy_kv system_mutation NO
}

if [[ ${1:-} == --input ]]; then POLICY_INPUT=$2; fi
policy_decision
