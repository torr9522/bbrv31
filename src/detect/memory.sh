#!/usr/bin/env bash

memory_class() {
    local mib=$1
    if (( mib < 512 )); then printf LT_512M
    elif (( mib < 1024 )); then printf 512M_TO_LT_1G
    elif (( mib < 2048 )); then printf 1G_TO_LT_2G
    elif (( mib < 4096 )); then printf 2G_TO_LT_4G
    else printf GE_4G; fi
}

detect_memory() {
    local total_kib available_kib swap_total_kib swap_free_kib total_mib available_mib
    total_kib=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    available_kib=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
    swap_total_kib=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
    swap_free_kib=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)
    total_mib=$((total_kib / 1024)); available_mib=$((available_kib / 1024))
    kv memory.total_mib "$total_mib"
    kv memory.available_mib "$available_mib"
    kv memory.class "$(memory_class "$total_mib")"
    (( total_mib < 2048 )) && kv memory.original_branch LT_2G || kv memory.original_branch GE_2G
    kv memory.swap_total_mib "$((swap_total_kib / 1024))"
    kv memory.swap_free_mib "$((swap_free_kib / 1024))"
}
