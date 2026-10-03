#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/paths.sh"

buffer_keys() {
    printf '%s\n' net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem
}

buffer_baseline_dir() { printf '%s/buffer-baseline\n' "$BBRV3_STATE_ROOT"; }
buffer_baseline_file() { printf '%s/baseline.tsv\n' "$(buffer_baseline_dir)"; }
buffer_baseline_checksum() { printf '%s/baseline.tsv.sha256\n' "$(buffer_baseline_dir)"; }

valid_buffer_value() {
    [[ ${1:-} =~ ^[0-9]+([[:space:]]+[0-9]+)*$ ]]
}

validate_buffer_baseline() {
    local file=${1:-$(buffer_baseline_file)} checksum=${2:-$(buffer_baseline_checksum)} key value count=0
    [[ -f $file && -f $checksum ]] || return 1
    [[ $(hash_file "$file") == "$(awk 'NR==1{print $1}' "$checksum")" ]] || return 1
    [[ $(sed -n '1p' "$file") == $'key\tvalue' ]] || return 1
    while IFS=$'\t' read -r key value; do
        [[ $key == key ]] && continue
        case $key in
            net.core.rmem_max|net.core.wmem_max|net.ipv4.tcp_rmem|net.ipv4.tcp_wmem) ;;
            *) return 1;;
        esac
        valid_buffer_value "$value" || return 1
        count=$((count + 1))
    done <"$file"
    [[ $count -eq 4 ]] || return 1
    while IFS= read -r key; do [[ $(awk -F '\t' -v k="$key" '$1==k{n++} END{print n+0}' "$file") -eq 1 ]] || return 1; done < <(buffer_keys)
}

write_buffer_baseline() {
    local source=$1 origin=$2 dir file checksum tmp
    dir=$(buffer_baseline_dir); file=$(buffer_baseline_file); checksum=$(buffer_baseline_checksum)
    install -d -m 700 "$dir"
    tmp=$(mktemp "$dir/.baseline.XXXXXX")
    cp "$source" "$tmp"
    chmod 400 "$tmp"
    mv "$tmp" "$file"
    printf '%s  baseline.tsv\n' "$(hash_file "$file")" >"$checksum"
    chmod 400 "$checksum"
    printf '%s\n' "$origin" >"$dir/source"
    chmod 400 "$dir/source"
}

extract_transaction_buffer_baseline() {
    local tx=$1 out=$2 key value
    [[ -f $tx/ownership.tsv && -f $tx/baseline.tsv ]] || return 1
    [[ $(awk -F '\t' 'NR==2{print $2}' "$tx/ownership.tsv") == ABSENT ]] || return 1
    printf 'key\tvalue\n' >"$out"
    while IFS= read -r key; do
        value=$(awk -F '\t' -v k="$key" '$1==k{print $2; exit}' "$tx/baseline.tsv")
        valid_buffer_value "$value" || return 1
        printf '%s\t%s\n' "$key" "$value" >>"$out"
    done < <(buffer_keys)
}

buffer_managed_evidence_exists() {
    local path; path=$(owned_path)
    [[ $(owned_file_status) == OWNED ]] && grep -Eq '^(net\.core\.(rmem_max|wmem_max)|net\.ipv4\.tcp_(rmem|wmem))=' "$path" && return 0
    [[ -f $BBRV3_STATE_ROOT/optimization/state.env ]] && grep -Eq '^profile=(ASIA_ORIGINAL|OVERSEAS_ORIGINAL|GLOBAL_MIXED|COMPAT_ORIGINAL)$' "$BBRV3_STATE_ROOT/optimization/state.env" && return 0
    find "$BBRV3_STATE_ROOT/transactions" -mindepth 2 -maxdepth 2 -name desired.tsv -type f -exec grep -El '^(net\.core\.(rmem_max|wmem_max)|net\.ipv4\.tcp_(rmem|wmem))[[:space:]]' {} + 2>/dev/null | grep -q .
}

ensure_buffer_baseline() {
    local file checksum tx candidate
    file=$(buffer_baseline_file); checksum=$(buffer_baseline_checksum)
    if [[ -e $file || -e $checksum ]]; then
        validate_buffer_baseline "$file" "$checksum" || { printf 'INVALID_BUFFER_BASELINE\n' >&2; return 1; }
        return 0
    fi
    candidate=$(mktemp)
    while IFS= read -r tx; do
        if extract_transaction_buffer_baseline "$tx" "$candidate"; then
            write_buffer_baseline "$candidate" "transaction:$(basename "$tx")"
            rm -f "$candidate"
            return 0
        fi
    done < <(find "$BBRV3_STATE_ROOT/transactions" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | awk '{sub(/^[^ ]+ /,""); print}')
    if buffer_managed_evidence_exists; then
        rm -f "$candidate"
        [[ ${1:-} == allow-managed-missing ]] || printf 'MISSING_TRUSTED_BASELINE\n' >&2
        return 2
    fi
    printf 'key\tvalue\n' >"$candidate"
    while IFS= read -r key; do
        value=$(sysctl_read "$key" || true)
        valid_buffer_value "$value" || { rm -f "$candidate"; printf 'BUFFER_BASELINE_CAPTURE_FAILED %s\n' "$key" >&2; return 1; }
        printf '%s\t%s\n' "$key" "$value" >>"$candidate"
    done < <(buffer_keys)
    write_buffer_baseline "$candidate" LIVE_PRE_PROJECT
    rm -f "$candidate"
}

owned_manages_buffer() {
    local path; path=$(owned_path)
    [[ $(owned_file_status) == OWNED ]] && grep -Eq '^(net\.core\.(rmem_max|wmem_max)|net\.ipv4\.tcp_(rmem|wmem))=' "$path"
}

append_buffer_restore_plan() {
    local plan=$1 key value file; file=$(buffer_baseline_file)
    validate_buffer_baseline || return 1
    while IFS= read -r key; do
        value=$(awk -F '\t' -v k="$key" '$1==k{print $2; exit}' "$file")
        printf '%s\t%s\tBUFFER_BASELINE_RESTORE\tpre_project_baseline\t0\t0\n' "$key" "$value" >>"$plan"
    done < <(buffer_keys)
}
