#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/system-resource.sh"
system_resource_plan() {
    local thp=${1:-always} services=${2:-} swap=${3:-NO} memory=${4:-4096} recommended
    printf 'thp.decision=CANDIDATE\nthp.target=never\nthp.reason=COMPAT_ORIGINAL\n'
    if [[ -n $services ]]; then printf 'nofile.decision=CANDIDATE\nnofile.target=524288\nnofile.services=%s\nnofile.reason=SERVICE_AWARE\n' "$services"; else printf 'nofile.decision=COMPAT_CANDIDATE\nnofile.target=524288\nnofile.services=\nnofile.reason=LIMITS_COMPATIBILITY\n'; fi
    if [[ $swap == YES ]]; then
        printf 'swap.decision=RESPECT\nswap.reason=EXISTING_SWAP_NOT_OWNED\nswap.recommended_mb=0\n'
    else
        if (( memory < 512 )); then recommended=1024
        elif (( memory < 1024 )); then recommended=$((memory * 2))
        elif (( memory < 2048 )); then recommended=$((memory * 3 / 2))
        elif (( memory < 4096 )); then recommended=$memory
        else recommended=0
        fi
        if (( recommended > 0 )); then printf 'swap.decision=CANDIDATE\nswap.reason=ORIGINAL_MEMORY_RECOMMENDATION\nswap.recommended_mb=%s\n' "$recommended"
        else printf 'swap.decision=SKIP\nswap.reason=MEMORY_GE_4G\nswap.recommended_mb=0\n'; fi
    fi
    printf 'vm.decision=DEFER_TO_SYSCTL_PLAN\nvm.reason=PHASE3_OWNED_VALUES\n'
}
