#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/network.sh"

network_capture_baseline() {
    local d=$1 ifname=${2:-$(network_default_if)}
    printf '%s\n' "$(network_qdisc_text)" >"$d/qdisc.baseline"
    printf '%s\n' "$(network_route_text)" >"$d/route.baseline"
    printf '%s\n' "${ifname:-UNKNOWN}" >"$d/interface"
    if [[ -n ${BBRV3_NETWORK_FACTS:-} ]]; then
        for k in rps.cpus rps.flow_cnt rps.sock_flow_entries mss.rules ip_forward ipv6_forward; do printf '%s\n' "$(network_fact "$k")" >"$d/$k"; done
    else
        printf '%s\n' "$(cat "${BBRV3_NETWORK_PROC_ROOT:-/proc}/sys/net/core/rps_sock_flow_entries" 2>/dev/null || true)" >"$d/rps.sock_flow_entries"
        printf '%s\n' "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || true)" >"$d/ip_forward"
        printf '%s\n' "$(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || true)" >"$d/ipv6_forward"
        printf '%s\n' "$("$BBRV3_NETWORK_IPTABLES_BIN" -t mangle -S FORWARD 2>/dev/null || true)" >"$d/mss.rules"
        : >"$d/rps.cpus"; : >"$d/rps.flow_cnt"
        local sysroot=${BBRV3_NETWORK_SYSFS_ROOT:-/sys}; if [[ -n $ifname && -d $sysroot/class/net/$ifname/queues ]]; then
            while read -r q; do printf '%s\t%s\t%s\n' "$q" "$(cat "$q/rps_cpus" 2>/dev/null || true)" "$(cat "$q/rps_flow_cnt" 2>/dev/null || true)" >>"$d/rps.cpus"; done < <(find "$sysroot/class/net/$ifname/queues" -maxdepth 1 -type d -name 'rx-*' | sort)
        fi
    fi
    sha256sum "$d/qdisc.baseline" "$d/route.baseline" "$d/rps.cpus" "$d/rps.flow_cnt" "$d/mss.rules" >"$d/baseline.sha256"
}
