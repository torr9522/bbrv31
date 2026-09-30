#!/usr/bin/env bash

detect_capabilities() {
    local iptables=NO backend=NONE nft=NO forward=0 ip6forward=0
    available iptables && iptables=YES && backend=$(iptables -V 2>/dev/null | sed -n 's/.*(\([^)]*\)).*/\1/p')
    available nft && nft=YES
    [[ -r /proc/sys/net/ipv4/ip_forward ]] && forward=$(cat /proc/sys/net/ipv4/ip_forward)
    [[ -r /proc/sys/net/ipv6/conf/all/forwarding ]] && ip6forward=$(cat /proc/sys/net/ipv6/conf/all/forwarding)
    kv capability.iptables "$iptables"
    kv capability.iptables_backend "${backend:-UNKNOWN}"
    kv capability.nft "$nft"
    kv capability.ip_forward "$forward"
    kv capability.ipv6_forward "$ip6forward"
    kv capability.tc "$(available tc && printf YES || printf NO)"
    kv capability.ethtool "$(available ethtool && printf YES || printf NO)"
}
