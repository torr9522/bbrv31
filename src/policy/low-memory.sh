#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

policy_low_memory() {
    local ram=$1 class branch swap dirty free
    if (( ram < 512 )); then class=LT_512M; elif (( ram < 1024 )); then class=512M_TO_LT_1G; elif (( ram < 2048 )); then class=1G_TO_LT_2G; elif (( ram < 4096 )); then class=2G_TO_LT_4G; else class=GE_4G; fi
    if (( ram < 2048 )); then branch=LT_2G; swap=20; dirty=20; free=32768; else branch=GE_2G; swap=5; dirty=15; free=65536; fi
    policy_kv memory_mode "$class"; policy_kv memory_original_branch "$branch"; policy_kv vm_swappiness "$swap"; policy_kv vm_dirty_ratio "$dirty"; policy_kv vm_min_free_kbytes "$free"
}
