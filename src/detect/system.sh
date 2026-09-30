#!/usr/bin/env bash

detect_system() {
    local thp=UNAVAILABLE nofile=UNKNOWN filemax=UNKNOWN nr_open=UNKNOWN default_limit=UNKNOWN services=''
    [[ -r /sys/kernel/mm/transparent_hugepage/enabled ]] && thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled)
    nofile=$(ulimit -n 2>/dev/null || printf UNKNOWN)
    [[ -r /proc/sys/fs/file-max ]] && filemax=$(cat /proc/sys/fs/file-max)
    [[ -r /proc/sys/fs/nr_open ]] && nr_open=$(cat /proc/sys/fs/nr_open)
    if available systemctl; then
        default_limit=$(systemctl show --property=DefaultLimitNOFILE --value 2>/dev/null || printf UNKNOWN)
        for service in xray sing-box hysteria tuic nginx caddy; do
            systemctl list-unit-files "${service}.service" --no-legend 2>/dev/null | grep -q "${service}.service" && services+="${services:+,}${service}.service"
        done
    fi
    kv thp.available "$( [[ $thp == UNAVAILABLE ]] && printf NO || printf YES )"
    kv thp.state "$thp"
    kv nofile.shell "$nofile"
    kv nofile.file_max "$filemax"
    kv nofile.nr_open "$nr_open"
    kv nofile.systemd_default "$default_limit"
    kv nofile.known_services "$services"
    [[ -n $services ]] && kv nofile.service_aware_candidate YES || kv nofile.service_aware_candidate NO
}
