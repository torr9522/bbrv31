#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/network.sh"

network_verify() {
    local d=$1 qdec rdec qroot route result=0
    qdec=$(awk -F= '$1=="qdisc.decision"{print $2}' "$d/desired.env")
    rdec=$(awk -F= '$1=="route.decision"{print $2}' "$d/desired.env")
    qroot=$(network_qdisc_text)
    if [[ $qdec == CANDIDATE ]]; then
        local mq queues fq_count
        mq=$(awk -F= '$1=="qdisc.mq"{print $2}' "$d/desired.env")
        queues=$(awk -F= '$1=="qdisc.queue_count"{print $2}' "$d/desired.env")
        fq_count=$({ grep -oE '(^|[[:space:]])fq([[:space:]]|$)|"kind"[[:space:]]*:[[:space:]]*"fq"' <<<"$qroot" || true; } | wc -l)
        if [[ $mq == YES ]]; then
            grep -Eq '(^|[[:space:]])mq([[:space:]]|$)|"kind"[[:space:]]*:[[:space:]]*"mq"' <<<"$qroot" && (( fq_count >= queues )) || { printf 'qdisc\tMISMATCH\n'; result=1; }
        elif (( fq_count < 1 )); then printf 'qdisc\tMISMATCH\n'; result=1
        fi
    fi
    if (( result == 0 )); then printf 'qdisc\t%s\n' "$( [[ $qdec == SKIP || $qdec == NOOP || $qdec == BLOCKED ]] && printf "$qdec" || printf MATCH )"; fi
    route=$(network_route_text)
    if [[ $rdec == CANDIDATE ]] && ! grep -q 'initcwnd 32' <<<"$route"; then printf 'route\tMISMATCH\n'; result=1; else printf 'route\t%s\n' "$( [[ $rdec == SKIP || $rdec == NOOP || $rdec == BLOCKED ]] && printf "$rdec" || printf MATCH )"; fi
    for res in rps mss; do dec=$(awk -F= -v r="$res" '$1==r ".decision"{print $2}' "$d/desired.env"); if [[ $res == mss && $dec == CANDIDATE && ! -f $d/mss.marker ]]; then printf 'mss\tMISMATCH\n'; result=1; elif [[ $res == rps && $dec == CANDIDATE ]]; then local ifname sysroot; ifname=$(<"$d/interface"); sysroot=${BBRV3_NETWORK_SYSFS_ROOT:-/sys}; if find "$sysroot/class/net/$ifname/queues" -maxdepth 2 -type f -name rps_cpus -exec grep -Eq '^[0,]*0*$' {} \; -print | grep -q .; then printf 'rps\tMISMATCH\n'; result=1; else printf 'rps\tMATCH\n'; fi; else printf '%s\t%s\n' "$res" "${dec:-SKIP}"; fi; done
    return $result
}
