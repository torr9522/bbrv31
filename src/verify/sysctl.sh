#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/paths.sh"
verify_plan() {
    local plan=$1 out=${2:-/dev/stdout} key desired actual result
    printf 'key\tdesired	actual	result\n' >"$out"
    while IFS=$'\t' read -r key desired category source start end; do
        [[ $key == key || -z $key ]] && continue
        actual=$(sysctl_read "$key" || true)
        if [[ -z $actual ]]; then result=UNSUPPORTED; elif [[ $actual == "$desired" ]]; then result=MATCH; else result=MISMATCH; fi
        printf '%s\t%s\t%s\t%s\n' "$key" "$desired" "${actual:-UNAVAILABLE}" "$result" >>"$out"
    done <"$plan"
    if awk -F '\t' 'NR>1 && $4 != "MATCH" {bad=1} END{exit bad}' "$out"; then return 0; else return 1; fi
}
