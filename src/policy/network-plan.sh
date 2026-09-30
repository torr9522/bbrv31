#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/network.sh"

network_plan() {
    local cpu=${1:-1} qroot=${2:-unknown} mq=${3:-NO} fq=${4:-NO} cake=${5:-NO} htb=${6:-NO} tbf=${7:-NO} filters=${8:-NO} classes=${9:-NO} queues=${10:-0} rss=${11:-UNAVAILABLE} forward=${12:-0} backend=${13:-NONE} route_count=${14:-0} route=${15:-}
    local qdecision qreason rdecision rreason rpsdecision rpsreason mdecision mreason ifname
    if [[ $cake == YES || $htb == YES || $tbf == YES || $filters == YES || $classes == YES ]]; then qdecision=BLOCKED; qreason=EXISTING_QDISC_OWNER_OR_COMPLEX_TREE
    elif [[ $mq == YES ]]; then [[ $fq == YES ]] && qdecision=NOOP || qdecision=BLOCKED; qreason=MQ_ROOT_PRESERVED_LEAF_REVIEW
    elif [[ $qroot == fq ]]; then qdecision=NOOP; qreason=ALREADY_FQ
    elif [[ $qroot == fq_codel ]]; then qdecision=CANDIDATE; qreason=FQ_CODEL_TO_FQ_SIMPLE_ROOT
    elif [[ $qroot == pfifo_fast || $qroot == pfifo ]]; then qdecision=CANDIDATE; qreason=SIMPLE_SINGLE_QUEUE
    else qdecision=BLOCKED; qreason=UNKNOWN_QDISC_TOPOLOGY; fi
    if (( cpu == 1 )); then rpsdecision=SKIP; rpsreason=SINGLE_CPU
    elif (( queues == 1 )) && [[ $rss != PRESENT ]]; then rpsdecision=CANDIDATE; rpsreason=SINGLE_RX_QUEUE_WITHOUT_RSS
    elif (( queues > 1 )) && [[ $rss == PRESENT ]]; then rpsdecision=SKIP; rpsreason=RSS_OR_MULTIPLE_RX_QUEUES_PRESENT
    else rpsdecision=REVIEW; rpsreason=RPS_FACTS_INCOMPLETE; fi
    if (( forward == 1 )) && [[ $backend == nft-only ]]; then mdecision=CANDIDATE; mreason=NFT_TCPMSS_CLAMP
    elif (( forward == 1 )) && [[ $backend == NONE ]]; then mdecision=REVIEW; mreason=BACKEND_REVIEW
    elif (( forward == 1 )) && [[ $backend != NONE ]]; then mdecision=CANDIDATE; mreason=FORWARDING_ENABLED
    else mdecision=SKIP; mreason=NOT_FORWARDING_HOST; fi
    if (( route_count == 1 )); then
        if [[ $route == *multipath* ]]; then rdecision=BLOCKED; rreason=MULTIPATH_ROUTE
        elif [[ $route == *initcwnd\ 32* && $route == *initrwnd\ 32* ]]; then rdecision=NOOP; rreason=ALREADY_32_32
        else rdecision=CANDIDATE; rreason=SINGLE_DEFAULT_ROUTE; fi
    elif (( route_count > 1 )); then rdecision=BLOCKED; rreason=MULTIPLE_DEFAULT_ROUTES
    else rdecision=SKIP; rreason=NO_IPV4_DEFAULT
    fi
    ifname=$(awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$route")
    printf 'qdisc.decision=%s\nqdisc.reason=%s\nqdisc.interface=%s\n' "$qdecision" "$qreason" "${ifname:-UNKNOWN}"
    printf 'rps.decision=%s\nrps.reason=%s\n' "$rpsdecision" "$rpsreason"
    printf 'mss.decision=%s\nmss.reason=%s\nmss.backend=%s\n' "$mdecision" "$mreason" "$backend"
    printf 'route.decision=%s\nroute.reason=%s\nroute.target=32/32\n' "$rdecision" "$rreason"
}
