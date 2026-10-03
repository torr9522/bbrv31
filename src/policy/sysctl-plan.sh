#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/paths.sh"

make_sysctl_plan() {
    local input=$1 output=$2 profile=${REQUESTED_PROFILE:-auto} bw=${REQUESTED_BANDWIDTH:-1000} ram=${REQUESTED_RAM_MB:-} requested_buffer=${REQUESTED_BUFFER_MB:-}
    local detect=$BBRV3_PROJECT_ROOT/.phase3-detect.$$
    "$BBRV3_PROJECT_ROOT/src/detect/all.sh" >"$detect"
    [[ -n $ram ]] && sed -i "s/^memory.total_mib=.*/memory.total_mib=$ram/" "$detect"
    local decision; decision=$(POLICY_INPUT="$detect" REQUESTED_PROFILE="$profile" REQUESTED_BANDWIDTH="$bw" REQUESTED_BANDWIDTH_SOURCE=MANUAL_VALUE "$BBRV3_PROJECT_ROOT/src/policy/decision.sh")
    local selected buffer swappiness dirty minfree buffer_bytes= sysctl_count=31
    selected=$(awk -F= '$1=="profile"{print $2; exit}' <<<"$decision")
    buffer=$(awk -F= '$1=="buffer_original_mb"{print $2; exit}' <<<"$decision")
    if [[ $selected == SYSTEM_DEFAULT ]]; then
        buffer=N/A; sysctl_count=27
    elif [[ -n $requested_buffer ]]; then [[ $requested_buffer =~ ^[0-9]+$ && $requested_buffer -gt 0 ]] || return 2; buffer=$requested_buffer; fi
    swappiness=$(awk -F= '$1=="vm_swappiness"{print $2; exit}' <<<"$decision")
    dirty=$(awk -F= '$1=="vm_dirty_ratio"{print $2; exit}' <<<"$decision")
    minfree=$(awk -F= '$1=="vm_min_free_kbytes"{print $2; exit}' <<<"$decision")
    [[ $buffer == N/A ]] || buffer_bytes=$((buffer * 1024 * 1024))
    printf 'key\tvalue\tcategory\tsource_function\tsource_line_start\tsource_line_end\n' >"$output"
    while IFS=$'\t' read -r id key value function start end category notes; do
        [[ $id == id || -z $id ]] && continue
        if [[ $selected == SYSTEM_DEFAULT ]]; then
            case $key in net.core.rmem_max|net.core.wmem_max|net.ipv4.tcp_rmem|net.ipv4.tcp_wmem) continue;; esac
        fi
        value=${value//buffer_bytes/$buffer_bytes}; value=${value//20<2GB\;5>=2GB/$swappiness}; value=${value//20<2GB\;15>=2GB/$dirty}; value=${value//32768<2GB\;65536>=2GB/$minfree}
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$value" "$category" "$function" "$start" "$end" >>"$output"
    done <"$BBRV3_PROJECT_ROOT/data/original-sysctl.tsv"
    rm -f "$detect"
    printf 'profile=%s\nbandwidth_mbps=%s\nbuffer_mb=%s\nbuffer_policy=%s\nmemory_branch=%s\nsysctl_count=%s\n' "$selected" "$bw" "$buffer" "$([[ $selected == SYSTEM_DEFAULT ]] && printf system || printf managed)" "$(awk -F= '$1=="memory_original_branch"{print $2}' <<<"$decision")" "$sysctl_count" >"${output}.meta"
}

if [[ ${1:-} == --output ]]; then make_sysctl_plan "" "$2"; fi
