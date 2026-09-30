#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
policy_rps_rfs() {
    local cpu=${1:-1} queues=${2:-0} rss=${3:-UNAVAILABLE} recommendation confidence reason
    if (( cpu == 1 )); then recommendation=SKIP; confidence=HIGH; reason=SINGLE_CPU
    elif (( queues <= 1 )) && [[ $rss != PRESENT ]]; then recommendation=CANDIDATE; confidence=MEDIUM; reason=SINGLE_RX_QUEUE_WITHOUT_RSS
    else recommendation=DEFAULT_SKIP; confidence=MEDIUM; reason=RSS_OR_MULTIPLE_RX_QUEUES_PRESENT; fi
    policy_kv rps_rfs_policy "$recommendation"; policy_kv rps_rfs_confidence "$confidence"; policy_kv rps_rfs_reason "$reason"
}
