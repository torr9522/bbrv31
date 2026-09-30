#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/network.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../recovery" && pwd)/network-baseline.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../recovery" && pwd)/network-ownership.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../verify" && pwd)/network.sh"

network_apply_qdisc() { local d=$1; [[ $(awk -F= '$1=="qdisc.decision"{print $2}' "$d/desired.env") == CANDIDATE ]] || return 0; local dev; dev=$(<"$d/interface"); [[ $dev != UNKNOWN && -n $dev ]] || return 1; network_tc_mutation qdisc replace dev "$dev" root fq; }
network_apply_route() {
    local d=$1 dec route clean; dec=$(awk -F= '$1=="route.decision"{print $2}' "$d/desired.env"); [[ $dec == CANDIDATE ]] || return 0
    route=$(<"$d/route.baseline"); clean=$(sed -E 's/[[:space:]]+initcwnd[[:space:]]+[0-9]+//g; s/[[:space:]]+initrwnd[[:space:]]+[0-9]+//g' <<<"$route"); [[ -n $clean ]] || return 1
    # The original route attributes are retained; only IW attributes are added.
    read -r -a args <<<"$clean"; network_ip_mutation route replace "${args[@]}" initcwnd 32 initrwnd 32
}
network_apply_rps() {
    local d=$1 dec; dec=$(awk -F= '$1=="rps.decision"{print $2}' "$d/desired.env"); [[ $dec == CANDIDATE ]] || return 0
    local cpu ifname sysroot mask; cpu=$(awk -F= '$1=="cpu"{print $2}' "$d/facts.env"); ifname=$(<"$d/interface"); sysroot=${BBRV3_NETWORK_SYSFS_ROOT:-/sys}; mask=f
    [[ -n $ifname && -d $sysroot/class/net/$ifname/queues ]] || return 1
    printf 4096 >"$sysroot/class/net/$ifname/queues/rx-0/rps_flow_cnt" 2>/dev/null || return 1
    while read -r q; do printf '%s\n' "$mask" >"$q/rps_cpus"; printf 4096 >"$q/rps_flow_cnt"; done < <(find "$sysroot/class/net/$ifname/queues" -maxdepth 1 -type d -name 'rx-*' | sort)
    printf '%s\n' "$((4096 * cpu))" >"${BBRV3_NETWORK_PROC_ROOT:-/proc}/sys/net/core/rps_sock_flow_entries" 2>/dev/null || true
}
network_apply_mss() { local d=$1 dec; dec=$(awk -F= '$1=="mss.decision"{print $2}' "$d/desired.env"); [[ $dec == CANDIDATE ]] || return 0; local marker="bbrv3-universal:$(basename "$d")"; network_iptables_mutation -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -m comment --comment "$marker" -j TCPMSS --clamp-mss-to-pmtu; printf '%s\n' "$marker" >"$d/mss.marker"; }

network_apply_transaction() {
    local d=$1; printf PREPARED >"$d/state"; network_capture_baseline "$d" "$(<"$d/interface")"; network_capture_ownership "$d"; printf APPLYING >"$d/state"
    network_apply_qdisc "$d" || { printf APPLY_FAILED >"$d/state"; return 1; }
    network_apply_rps "$d" || { [[ $(awk -F= '$1=="rps.decision"{print $2}' "$d/desired.env") == CANDIDATE ]] && { printf APPLY_FAILED >"$d/state"; return 1; } || true; }
    network_apply_mss "$d" || { [[ $(awk -F= '$1=="mss.decision"{print $2}' "$d/desired.env") == CANDIDATE ]] && { printf APPLY_FAILED >"$d/state"; return 1; } || true; }
    network_apply_route "$d" || { printf APPLY_FAILED >"$d/state"; return 1; }
    if ! network_verify "$d" >"$d/verify.tsv"; then printf VERIFY_FAILED >"$d/state"; return 1; fi
    printf VERIFIED >"$d/state"; printf 'PASS network transaction=%s\n' "$(basename "$d")"
}
