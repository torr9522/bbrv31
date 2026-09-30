#!/usr/bin/env bash

detect_hardware() {
    local ifaces='' dev queues=0 rx=0 driver rss=UNAVAILABLE rps=NO
    if available ip; then ifaces=$(ip -o link show | awk -F': ' '$2!="lo" {print $2}' | cut -d@ -f1); fi
    while read -r dev; do
        [[ -n $dev ]] || continue
        rx=$(find "/sys/class/net/$dev/queues" -maxdepth 1 -type d -name 'rx-*' 2>/dev/null | wc -l)
        queues=$((queues + rx))
        driver=$(basename "$(readlink "/sys/class/net/$dev/device/driver" 2>/dev/null || printf unknown)")
        [[ -r "/sys/class/net/$dev/queues/rx-0/rps_cpus" ]] && rps=YES
        if available ethtool && ethtool -k "$dev" >/dev/null 2>&1; then rss=PRESENT; fi
        kv "network.iface.${dev}.rx_queues" "$rx"
        kv "network.iface.${dev}.driver" "${driver:-unknown}"
    done <<<"$ifaces"
    kv network.rx_queue_count "$queues"
    kv network.rss "$rss"
    kv network.ethtool_channels "$(available ethtool && printf READ_ONLY || printf UNAVAILABLE)"
    kv network.rss_indirection "$rss"
    kv network.rps_files "$rps"
}
