#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/paths.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../recovery" && pwd)/ownership.sh"

rollback_transaction() {
    local dir=$1 key value path expected actual state
    [[ -f $dir/state && $(<"$dir/state") =~ ^(VERIFIED|APPLY_FAILED|VERIFY_FAILED|ROLLING_BACK)$ ]] || { printf 'ROLLBACK_BLOCKED_STATE\n' >&2; return 1; }
    state=$(<"$dir/state")
    path=$(owned_path)
    expected=$(awk -F '\t' 'NR==2{print $3}' "$dir/ownership.tsv" 2>/dev/null || true)
    if [[ -e $path ]]; then
        actual=$(hash_file "$path")
        if [[ ${FORCE_RECOVERY:-NO} != YES ]] || ! owned_marker "$path"; then
            [[ $actual == $(<"$dir/applied.sha256") ]] || { printf 'FILE_DRIFT\n' >&2; printf 'FILE_DRIFT\n' >"$dir/rollback-error"; return 1; }
        fi
    else
        printf 'FILE_DRIFT\n' >&2; printf 'FILE_DRIFT\n' >"$dir/rollback-error"; return 1
    fi
    if [[ $state == VERIFIED ]]; then
        while IFS=$'\t' read -r key value; do
            [[ $key == key || -z $key ]] && continue
            [[ ${FORCE_RECOVERY:-NO} == YES || $(sysctl_read "$key" || true) == "$(awk -F '\t' -v k="$key" '$1==k{print $2; exit}' "$dir/desired.tsv")" ]] || { printf 'RUNTIME_DRIFT %s\n' "$key" >&2; printf 'RUNTIME_DRIFT\n' >"$dir/rollback-error"; return 1; }
        done <"$dir/baseline.tsv"
    fi
    while IFS=$'\t' read -r key value; do
        [[ $key == key || -z $key || $value == UNAVAILABLE ]] && continue
        sysctl_write "$key" "$value" >/dev/null 2>"$dir/rollback-$key.err" || { printf 'RUNTIME_ROLLBACK_FAILED %s\n' "$key" >&2; return 1; }
    done <"$dir/baseline.tsv"
    if [[ -f $dir/owned-before.conf ]]; then
        install -d -m 755 "$(dirname "$path")"; cp -a "$dir/owned-before.conf" "$path"
    else
        rm -f "$path"
    fi
    while IFS=$'\t' read -r key value; do
        [[ $key == key || -z $key || $value == UNAVAILABLE ]] && continue
        [[ $(sysctl_read "$key" || true) == "$value" ]] || { printf 'RUNTIME_DRIFT %s\n' "$key" >&2; return 1; }
    done <"$dir/baseline.tsv"
    printf ROLLED_BACK >"$dir/state"
    printf 'PASS rollback\n'
}
