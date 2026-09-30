#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

policy_bandwidth() {
    local source=${REQUESTED_BANDWIDTH_SOURCE:-MANUAL_PRESET} value=${REQUESTED_BANDWIDTH:-1000} confidence=HIGH fallback=NO cpu_limited=NO
    if [[ $source == AUTO_PROBE || $source == UNAVAILABLE ]]; then source=${REQUESTED_BANDWIDTH_SOURCE:-UNAVAILABLE}; confidence=LOW; fallback=YES; value=${REQUESTED_BANDWIDTH:-1000}; fi
    [[ $value =~ ^[0-9]+$ && $value -gt 0 ]] || { value=1000; source=FALLBACK; confidence=LOW; fallback=YES; }
    policy_kv bandwidth_source "$source"; policy_kv bandwidth_mbps "$value"; policy_kv bandwidth_confidence "$confidence"; policy_kv bandwidth_cpu_limited "$cpu_limited"; policy_kv bandwidth_probe_count 0; policy_kv bandwidth_fallback_used "$fallback"
}
