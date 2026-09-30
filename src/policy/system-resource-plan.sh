#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/system-resource.sh"
system_resource_plan() {
    local thp=${1:-always} services=${2:-} swap=${3:-NO} memory=${4:-GE_4G}
    printf 'thp.decision=CANDIDATE\nthp.target=never\nthp.reason=COMPAT_ORIGINAL\n'
    if [[ -n $services ]]; then printf 'nofile.decision=CANDIDATE\nnofile.target=524288\nnofile.services=%s\nnofile.reason=SERVICE_AWARE\n' "$services"; else printf 'nofile.decision=COMPAT_CANDIDATE\nnofile.target=524288\nnofile.services=\nnofile.reason=LIMITS_COMPATIBILITY\n'; fi
    if [[ $swap == YES ]]; then printf 'swap.decision=RESPECT\nswap.reason=EXISTING_SWAP_NOT_OWNED\n'; else printf 'swap.decision=CANDIDATE\nswap.reason=NO_EXISTING_SWAP\n'; fi
    printf 'vm.decision=DEFER_TO_SYSCTL_PLAN\nvm.reason=PHASE3_OWNED_VALUES\n'
}
