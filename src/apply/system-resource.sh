#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/system-resource.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/swap.sh"
system_resource_apply() {
    local d=$1; printf APPLYING >"$d/state"
    if [[ $(awk -F= '$1=="thp.decision"{print $2}' "$d/desired.env") == CANDIDATE ]]; then
        local p=${BBRV3_THP_PATH:-/sys/kernel/mm/transparent_hugepage/enabled}; [[ -w $p ]] || { printf THP_UNAVAILABLE >"$d/thp.result"; } && { printf never >"$p"; printf APPLIED >"$d/thp.result"; }
    else printf SKIP >"$d/thp.result"; fi
    local services; services=$(awk -F= '$1=="nofile.services"{print $2}' "$d/desired.env")
    if [[ -n $services ]]; then
        local svc dir; IFS=, read -ra svcs <<<"$services"; for svc in "${svcs[@]}"; do dir="/etc/systemd/system/$svc.service.d"; install -d -m 755 "$dir"; printf '[Service]\nLimitNOFILE=524288\n' >"$dir/90-bbrv3-universal-nofile.conf"; done
        systemctl daemon-reload 2>/dev/null || true
    fi
    if [[ ${BBRV3_CREATE_SWAP:-NO} == YES && $(awk -F= '$1=="swap.decision"{print $2}' "$d/desired.env") == CANDIDATE ]]; then swap_create_owned "$d"; fi
    printf VERIFIED >"$d/state"
}
