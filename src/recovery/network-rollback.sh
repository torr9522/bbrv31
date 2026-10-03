#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/network.sh"

network_rollback_transaction() {
    local d=$1 state; state=$(<"$d/state"); [[ $state == VERIFIED || $state == APPLY_FAILED || $state == VERIFY_FAILED || $state == DRIFTED ]] || return 1; printf ROLLING_BACK >"$d/state"
    local current desired dev; desired=$(awk -F= '$1=="qdisc.decision"{print $2}' "$d/desired.env"); dev=$(<"$d/interface")
    if [[ $desired == CANDIDATE && ${NETWORK_FORCE_RECOVERY:-NO} != YES ]]; then current=$(network_qdisc_text); grep -Eq '(^|[[:space:]])fq([[:space:]]|$)|"kind"[[:space:]]*:[[:space:]]*"fq"' <<<"$current" || { printf QDISC_DRIFT >&2; printf DRIFTED >"$d/state"; return 1; }; fi
    desired=$(awk -F= '$1=="route.decision"{print $2}' "$d/desired.env")
    if [[ $desired == CANDIDATE ]]; then current=$(network_route_text); if [[ ${NETWORK_FORCE_RECOVERY:-NO} == YES ]]; then local base_id current_id; base_id=$(sed -E 's/[[:space:]]+initcwnd[[:space:]]+[0-9]+//g; s/[[:space:]]+initrwnd[[:space:]]+[0-9]+//g' "$d/route.baseline" | awk '{$1=$1; print}'); current_id=$(sed -E 's/[[:space:]]+initcwnd[[:space:]]+[0-9]+//g; s/[[:space:]]+initrwnd[[:space:]]+[0-9]+//g' <<<"$current" | awk '{$1=$1; print}'); [[ $base_id == "$current_id" ]] || { printf HARD_CONFLICT >&2; printf DRIFTED >"$d/state"; return 1; }; else grep -q 'initcwnd 32' <<<"$current" || { printf ROUTE_DRIFT >&2; printf DRIFTED >"$d/state"; return 1; }; fi; fi
    if [[ $(awk -F= '$1=="qdisc.decision"{print $2}' "$d/desired.env") == CANDIDATE ]]; then
        local base queues i; base=$(awk 'NF{print;exit}' "$d/qdisc.baseline")
        if [[ $base == *fq_codel* ]]; then network_tc_mutation qdisc replace dev "$dev" root fq_codel
        elif [[ $base == *pfifo_fast* || $base == *pfifo* ]]; then network_tc_mutation qdisc replace dev "$dev" root pfifo_fast
        elif [[ $base == *' mq '* || $base == 'qdisc mq '* ]]; then
            queues=$(awk -F= '$1=="qdisc.queue_count"{print $2}' "$d/desired.env")
            for ((i=1; i<=queues; i++)); do network_tc_mutation qdisc del dev "$dev" parent ":$i" 2>/dev/null || true; done
        fi
    fi
    if [[ $(awk -F= '$1=="route.decision"{print $2}' "$d/desired.env") == CANDIDATE ]]; then
        local route; route=$(<"$d/route.baseline"); read -r -a args <<<"$route"; network_ip_mutation route replace "${args[@]}"
    fi
    if [[ $(awk -F= '$1=="rps.decision"{print $2}' "$d/desired.env") == CANDIDATE && -s $d/rps.cpus ]]; then
        while IFS=$'\t' read -r q cpus flow; do [[ -d $q ]] || continue; printf '%s\n' "$cpus" >"$q/rps_cpus"; printf '%s\n' "$flow" >"$q/rps_flow_cnt"; done <"$d/rps.cpus"
    fi
    if [[ -f $d/mss.marker ]]; then local marker; marker=$(<"$d/mss.marker"); if [[ $marker == nft:* && $marker != nft:existing ]]; then network_nft_mutation delete table inet bbrv3_universal || true; elif [[ $marker == iptables:* ]]; then marker=${marker#iptables:}; network_iptables_mutation -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -m comment --comment "$marker" -j TCPMSS --clamp-mss-to-pmtu || true; fi; fi
    printf ROLLED_BACK >"$d/state"; printf 'PASS network rollback\n'
}
