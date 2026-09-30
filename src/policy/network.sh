#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
policy_network() {
    local forward=${1:-0} iptables=${2:-NO} qroot=${3:-unknown} cake=${4:-NO} htb=${5:-NO} tbf=${6:-NO} filters=${7:-NO} classes=${8:-NO} mq=${9:-NO} fq=${10:-NO}
    if [[ $cake == YES || $htb == YES || $tbf == YES || $filters == YES || $classes == YES ]]; then qpolicy=BLOCK_AUTO; qreason=EXISTING_QDISC_OWNER_OR_COMPLEX_TREE
    elif [[ $mq == YES && $fq == YES ]]; then qpolicy=KEEP_MQ_AND_MANAGE_LEAF; qreason=MQ_ROOT_WITH_FQ_LEAF
    elif [[ $qroot == fq ]]; then qpolicy=ALREADY_COMPATIBLE; qreason=ACTIVE_FQ
    else qpolicy=FQ_CANDIDATE; qreason=NON_FQ_SIMPLE_ROOT; fi
    [[ $forward == 1 ]] && mss=CANDIDATE && mssreason=FORWARDING_ENABLED || mss=SKIP && mssreason=NOT_FORWARDING_HOST
    [[ $iptables == YES ]] || mssreason=${mssreason},BACKEND_REVIEW
    policy_kv qdisc_policy "$qpolicy"; policy_kv qdisc_reason "$qreason"; policy_kv mss_policy "$mss"; policy_kv mss_reason "$mssreason"
    policy_kv route_iw_original_target 32/32; policy_kv route_iw_policy UNDECIDED; policy_kv route_iw_reason PHASE2_NO_APPLY
}
