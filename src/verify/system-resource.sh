#!/usr/bin/env bash
set -euo pipefail
system_resource_verify() {
    local d=$1 p=${BBRV3_THP_PATH:-/sys/kernel/mm/transparent_hugepage/enabled} services svc pid limit path fstab
    [[ $(awk -F= '$1=="thp.decision"{print $2}' "$d/desired.env") != CANDIDATE ]] || { [[ -r $p ]] && grep -Eq '\[never\]|^never$' "$p" || return 1; }
    services=$(awk -F= '$1=="nofile.services"{print $2}' "$d/desired.env")
    if [[ -z $services ]]; then grep -q 'managed-by=bbrv3-universal' "${BBRV3_LIMITS_DIR:-/etc/security/limits.d}/90-bbrv3-universal.conf" || return 1
    else IFS=, read -ra svcs <<<"$services"; for svc in "${svcs[@]}"; do pid=$(systemctl show -p MainPID --value "$svc.service" 2>/dev/null || printf 0); if [[ $pid =~ ^[1-9][0-9]*$ && -r /proc/$pid/limits ]]; then limit=$(awk '/Max open files/{print $4; exit}' "/proc/$pid/limits"); [[ $limit == unlimited || ${limit:-0} -ge 524288 ]] || return 1; fi; done; fi
    if [[ -s $d/owned-swap.path ]]; then path=$(<"$d/owned-swap.path"); swapon --show=NAME --noheadings | awk '{$1=$1;print}' | grep -Fqx "$path" || return 1; fstab=${BBRV3_FSTAB_PATH:-/etc/fstab}; grep -Fq "$path none swap sw 0 0 # bbrv3-universal" "$fstab" || return 1; fi
}
