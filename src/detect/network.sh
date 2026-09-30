#!/usr/bin/env bash

route_field() { awk -v key="$1" '{for(i=1;i<=NF;i++) if($i==key && i<NF){print $(i+1); exit}}'; }

detect_network() {
    local r4 r6 if4 gw4 metric4 if6 gw6 metric6 v4=NO v6=NO stack=NONE
    if ! available ip; then
        kv network.ip_command MISSING
        kv network.default_if_v4 UNKNOWN
        kv network.default_if_v6 UNKNOWN
        kv network.ip_stack UNKNOWN
        return
    fi
    r4=$(ip -4 route show default 2>/dev/null | head -n1 || true)
    r6=$(ip -6 route show default 2>/dev/null | head -n1 || true)
    if4=$(route_field dev <<<"$r4"); gw4=$(route_field via <<<"$r4"); metric4=$(route_field metric <<<"$r4")
    if6=$(route_field dev <<<"$r6"); gw6=$(route_field via <<<"$r6"); metric6=$(route_field metric <<<"$r6")
    if [[ -n "$r4" || -n $(ip -4 -o addr show scope global 2>/dev/null) ]]; then v4=YES; fi
    if [[ -n "$r6" || -n $(ip -6 -o addr show scope global 2>/dev/null) ]]; then v6=YES; fi
    if [[ $v4 == YES && $v6 == YES ]]; then stack=DUAL_STACK; elif [[ $v4 == YES ]]; then stack=IPV4_ONLY; elif [[ $v6 == YES ]]; then stack=IPV6_ONLY; fi
    kv network.ip_command PRESENT
    kv network.default_if_v4 "${if4:-NONE}"
    kv network.default_gw_v4 "${gw4:-NONE}"
    kv network.default_metric_v4 "${metric4:-NONE}"
    kv network.default_if_v6 "${if6:-NONE}"
    kv network.default_gw_v6 "${gw6:-NONE}"
    kv network.default_metric_v6 "${metric6:-NONE}"
    kv network.ip_stack "$stack"
}
