#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/network.sh"

network_rollback_transaction() {
    local d=$1 state; state=$(<"$d/state"); [[ $state == VERIFIED || $state == APPLY_FAILED || $state == VERIFY_FAILED || $state == DRIFTED ]] || return 1; printf ROLLING_BACK >"$d/state"
    local current desired dev; desired=$(awk -F= '$1=="qdisc.decision"{print $2}' "$d/desired.env"); dev=$(<"$d/interface")
    if [[ $desired == CANDIDATE ]]; then current=$(network_qdisc_text); grep -Eq '(^|[[:space:]])fq([[:space:]]|$)|"kind"[[:space:]]*:[[:space:]]*"fq"' <<<"$current" || { printf QDISC_DRIFT >&2; printf DRIFTED >"$d/state"; return 1; }; fi
    desired=$(awk -F= '$1=="route.decision"{print $2}' "$d/desired.env")
    if [[ $desired == CANDIDATE ]]; then current=$(network_route_text); grep -q 'initcwnd 32' <<<"$current" || { printf ROUTE_DRIFT >&2; printf DRIFTED >"$d/state"; return 1; }; fi
    if [[ $(awk -F= '$1=="qdisc.decision"{print $2}' "$d/desired.env") == CANDIDATE ]]; then
        local base; base=$(awk 'NF{print;exit}' "$d/qdisc.baseline"); [[ $base == *pfifo_fast* || $base == *pfifo* ]] && network_tc_mutation qdisc replace dev "$dev" root pfifo_fast
    fi
    if [[ $(awk -F= '$1=="route.decision"{print $2}' "$d/desired.env") == CANDIDATE ]]; then
        local route; route=$(<"$d/route.baseline"); read -r -a args <<<"$route"; network_ip_mutation route replace "${args[@]}"
    fi
    if [[ $(awk -F= '$1=="rps.decision"{print $2}' "$d/desired.env") == CANDIDATE && -s $d/rps.cpus ]]; then
        while IFS=$'\t' read -r q cpus flow; do [[ -d $q ]] || continue; printf '%s\n' "$cpus" >"$q/rps_cpus"; printf '%s\n' "$flow" >"$q/rps_flow_cnt"; done <"$d/rps.cpus"
    fi
    if [[ -f $d/mss.marker ]]; then network_iptables_mutation -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -m comment --comment "$(<"$d/mss.marker")" -j TCPMSS --clamp-mss-to-pmtu || true; fi
    printf ROLLED_BACK >"$d/state"; printf 'PASS network rollback\n'
}
