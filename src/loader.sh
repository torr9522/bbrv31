#!/usr/bin/env bash
set -euo pipefail

ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
SYSCTL_DATA=$ROOT/data/original-sysctl.tsv
BUFFER_DATA=$ROOT/data/original-buffer-tables.tsv
PROFILE_DATA=$ROOT/metadata/profile-metadata.tsv

fail() { printf 'FAIL %s\n' "$*" >&2; return 1; }

load_validate() {
    [[ -s $SYSCTL_DATA ]] || fail "missing sysctl data"
    [[ -s $BUFFER_DATA ]] || fail "missing buffer data"
    [[ -s $PROFILE_DATA ]] || fail "missing profile metadata"
    local count duplicates missing
    count=$(tail -n +2 "$SYSCTL_DATA" | awk -F '\t' 'NF >= 8 {print}' | wc -l)
    [[ $count -eq 31 ]] || fail "sysctl count=$count"
    duplicates=$(tail -n +2 "$SYSCTL_DATA" | cut -f1 | sort | uniq -d)
    [[ -z $duplicates ]] || fail "duplicate sysctl ids: $duplicates"
    missing=$(tail -n +2 "$SYSCTL_DATA" | awk -F '\t' '$1=="" || $2=="" || $3=="" || $4=="" || $5=="" || $6=="" {print $1}' )
    [[ -z $missing ]] || fail "incomplete sysctl rows: $missing"
    awk -F '\t' 'NR>1 && ($1=="" || $2=="" || $3=="" || $4=="") {bad=1} END {exit bad}' "$BUFFER_DATA" || fail "incomplete buffer row"
    awk -F '\t' 'NR>1 && ($1=="" || $2=="" || $3=="" || $4=="") {bad=1} END {exit bad}' "$PROFILE_DATA" || fail "incomplete profile row"
    printf 'PASS loader sysctl_count=%s profiles=%s buffer_rows=%s\n' "$count" "$(($(wc -l < "$PROFILE_DATA") - 1))" "$(($(wc -l < "$BUFFER_DATA") - 1))"
}

if [[ ${1:-} == --check ]]; then
    load_validate
fi
