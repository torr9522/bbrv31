#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/paths.sh"
capture_baseline() {
    local dir=$1 plan=$2
    printf 'key\tvalue\n' >"$dir/baseline.tsv"
    while IFS=$'\t' read -r key desired category source start end; do
        [[ $key == key || -z $key ]] && continue
        local value; value=$(sysctl_read "$key" || true)
        printf '%s\t%s\n' "$key" "${value:-UNAVAILABLE}" >>"$dir/baseline.tsv"
    done <"$plan"
    capture_ownership "$dir"
    [[ "$plan" == "$dir/desired.tsv" ]] || cp -a "$plan" "$dir/desired.tsv"
}
