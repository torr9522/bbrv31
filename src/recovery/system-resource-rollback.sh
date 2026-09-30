#!/usr/bin/env bash
set -euo pipefail
system_resource_rollback() {
    local d=$1 p=${BBRV3_THP_PATH:-/sys/kernel/mm/transparent_hugepage/enabled} old; old=$(cat "$d/thp.baseline" 2>/dev/null || true)
    [[ -n $old && -w $p ]] && { local selected; selected=$(sed -nE 's/.*\[([^]]+)\].*/\1/p' <<<"$old"); [[ -n $selected ]] && printf '%s' "$selected" >"$p" || true; }
    local services; services=$(awk -F= '$1=="nofile.services"{print $2}' "$d/desired.env"); if [[ -n $services ]]; then local svc; IFS=, read -ra svcs <<<"$services"; for svc in "${svcs[@]}"; do rm -f "/etc/systemd/system/$svc.service.d/90-bbrv3-universal-nofile.conf"; done; systemctl daemon-reload 2>/dev/null || true; fi
    printf ROLLED_BACK >"$d/state"
}
