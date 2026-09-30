#!/usr/bin/env bash
set -euo pipefail
ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$ROOT/src/common.sh"
source "$ROOT/src/core/network.sh"
source "$ROOT/src/policy/network-plan.sh"
source "$ROOT/src/apply/network.sh"
source "$ROOT/src/recovery/network-rollback.sh"

usage() { printf '%s\n' 'Usage:' '  bbrv3-universal.sh plan-network [--fixture DIR] [--detail]' '  bbrv3-universal.sh apply-network [--fixture DIR] [--only RESOURCE]' '  bbrv3-universal.sh verify-network [--transaction ID]' '  bbrv3-universal.sh rollback-network [--transaction ID]' '  bbrv3-universal.sh recover-network'; }
parse_network_args() { NETWORK_FIXTURE= NETWORK_ONLY= NETWORK_DETAIL=NO NETWORK_TRANSACTION= NETWORK_FORCE_RECOVERY=NO; while (($#)); do case $1 in --fixture) NETWORK_FIXTURE=$2; shift 2;; --only) NETWORK_ONLY=$2; shift 2;; --detail) NETWORK_DETAIL=YES; shift;; --transaction) NETWORK_TRANSACTION=$2; shift 2;; --force-owned) NETWORK_FORCE_RECOVERY=YES; shift;; *) return 2;; esac; done; export NETWORK_FORCE_RECOVERY; }
collect_network_facts() {
    local out=$1 fixture=${NETWORK_FIXTURE:-} route qroot mq fq cake htb tbf filters classes cpu queues rss forward backend count
    if [[ -n $fixture ]]; then
        BBRV3_NETWORK_FACTS="$fixture/facts.env"; export BBRV3_NETWORK_FACTS
        route=$(network_fact route.current); qroot=$(network_fact qdisc.root); mq=$(network_fact qdisc.mq_root); fq=$(network_fact qdisc.fq_present); cake=$(network_fact qdisc.cake_present); htb=$(network_fact qdisc.htb_present); tbf=$(network_fact qdisc.tbf_present); filters=$(network_fact qdisc.filters); classes=$(network_fact qdisc.classes); cpu=$(network_fact cpu.count); queues=$(network_fact network.rx_queue_count); rss=$(network_fact network.rss); forward=$(network_fact capability.ip_forward); backend=$(network_fact capability.iptables_backend); [[ $backend == nft ]] && backend=iptables-nft; [[ -z $backend ]] && backend=NONE
    else
        unset BBRV3_NETWORK_FACTS
        local d; d=$(mktemp -d); "$ROOT/src/detect/all.sh" >"$d/detect"
        route=$("$BBRV3_NETWORK_IP_BIN" -4 route show default 2>/dev/null || true); qroot=$(awk -F= '$1=="qdisc.root"{print $2}' "$d/detect"); mq=$(awk -F= '$1=="qdisc.mq_root"{print $2}' "$d/detect"); fq=$(awk -F= '$1=="qdisc.fq_present"{print $2}' "$d/detect"); cake=$(awk -F= '$1=="qdisc.cake_present"{print $2}' "$d/detect"); htb=$(awk -F= '$1=="qdisc.htb_present"{print $2}' "$d/detect"); tbf=$(awk -F= '$1=="qdisc.tbf_present"{print $2}' "$d/detect"); filters=$(awk -F= '$1=="qdisc.filters"{print $2}' "$d/detect"); classes=$(awk -F= '$1=="qdisc.classes"{print $2}' "$d/detect"); cpu=$(awk -F= '$1=="cpu.count"{print $2}' "$d/detect"); queues=$(awk -F= '$1=="network.rx_queue_count"{print $2}' "$d/detect"); rss=$(awk -F= '$1=="network.rss"{print $2}' "$d/detect"); forward=$(awk -F= '$1=="capability.ip_forward"{print $2}' "$d/detect"); backend=$(awk -F= '$1=="capability.iptables_backend"{print $2}' "$d/detect"); rm -rf "$d"
    fi
    route=${route:-}; count=$(grep -c '^default' <<<"$route" || true)
    network_plan "${cpu:-1}" "${qroot:-unknown}" "${mq:-NO}" "${fq:-NO}" "${cake:-NO}" "${htb:-NO}" "${tbf:-NO}" "${filters:-NO}" "${classes:-NO}" "${queues:-0}" "${rss:-UNAVAILABLE}" "${forward:-0}" "${backend:-NONE}" "$count" "$route" >"$out/desired.env"
    printf 'qdisc.root=%s\nroute.current=%s\n' "${qroot:-unknown}" "$route" >"$out/facts.env"
    printf 'cpu=%s\nrx_queues=%s\nrss=%s\n' "${cpu:-1}" "${queues:-0}" "${rss:-UNAVAILABLE}" >>"$out/facts.env"
    printf 'network_plan_version=4A\nqdisc=%s\nrps=%s\nmss=%s\nroute=%s\n' "$(awk -F= '$1=="qdisc.decision"{print $2}' "$out/desired.env")" "$(awk -F= '$1=="rps.decision"{print $2}' "$out/desired.env")" "$(awk -F= '$1=="mss.decision"{print $2}' "$out/desired.env")" "$(awk -F= '$1=="route.decision"{print $2}' "$out/desired.env")" >"$out/desired.meta"
    network_default_if >"$out/interface" 2>/dev/null || true
}
make_network_plan() { local d=$1; collect_network_facts "$d"; }
plan_network_command() { local d; d=$(mktemp -d); make_network_plan "$d"; cat "$d/desired.meta" "$d/desired.env"; printf 'system_mutation=NO\n'; rm -rf "$d"; }
apply_network_command() {
    network_lock || { printf OPERATION_IN_PROGRESS >&2; return 1; }
    local d; d=$(network_new_transaction); make_network_plan "$d"; printf PREPARED >"$d/state"; printf '%s\n' "${NETWORK_ONLY:-ALL}" >"$d/resource-scope"
    NETWORK_AUDIT_FILE=$d/mutations.log export NETWORK_AUDIT_FILE
    network_apply_transaction "$d"
}
find_network_transaction() { [[ -n ${NETWORK_TRANSACTION:-} ]] && printf '%s/transactions/%s\n' "$BBRV3_NETWORK_STATE_ROOT" "$NETWORK_TRANSACTION" || network_latest; }
verify_network_command() { local d; d=$(find_network_transaction); [[ -n $d && -f $d/desired.env ]] || { printf NO_TRANSACTION; return 1; }; printf 'transaction=%s\nstate=%s\n' "$(basename "$d")" "$(<"$d/state")"; network_verify "$d"; }
rollback_network_command() { network_lock || return 1; local d; d=$(find_network_transaction); [[ -n $d ]] || { printf NO_TRANSACTION; return 1; }; network_rollback_transaction "$d"; }
recover_network_command() { network_lock || return 1; local d; d=$(find_network_transaction); [[ -n $d ]] || { printf NO_TRANSACTION; return 1; }; network_rollback_transaction "$d"; }

command_name=${1:-}; shift || true; parse_network_args "$@" || { usage >&2; exit 2; }
case $command_name in
  plan-network) plan_network_command;; apply-network) [[ $EUID -eq 0 || ${BBRV3_MOCK:-0} == 1 ]] || { printf ROOT_REQUIRED >&2; exit 1; }; apply_network_command;; verify-network) verify_network_command;; rollback-network|recover-network) [[ $EUID -eq 0 || ${BBRV3_MOCK:-0} == 1 ]] || { printf ROOT_REQUIRED >&2; exit 1; }; [[ $command_name == recover-network ]] && recover_network_command || rollback_network_command;; *) usage >&2; exit 2;;
esac
