#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/paths.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../recovery" && pwd)/baseline.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../verify" && pwd)/sysctl.sh"

sysctl_keys() { tail -n +2 "$BBRV3_PROJECT_ROOT/data/original-sysctl.tsv" | awk -F '\t' '{print $2}'; }
plan_value() { awk -F '\t' -v k="$1" '$1==k {print $2; exit}' "$2"; }
key_category() { awk -F '\t' -v k="$1" '$2==k {print $7; exit}' "$BBRV3_PROJECT_ROOT/data/original-sysctl.tsv"; }

scan_conflicts() {
    local plan=$1 out=$2 root=${BBRV3_SYSCTL_ROOT:-/} owned status path key desired line source val base rank desired_rank
    status=$(owned_file_status); path=$(owned_path)
    printf 'key\tsource_file\tsource_line\tcurrent_declared_value\tdesired_value\tpriority\tconflict_type\n' >"$out"
    if [[ $status == FOREIGN ]]; then
        printf '*\t%s\t0\tFOREIGN\t-\t1000\tFOREIGN_FILE_AT_OWNED_PATH\n' "$BBRV3_SYSCTL_PATH" >>"$out"
    elif [[ $status == OWNED ]]; then
        printf '*\t%s\t0\tOWNED\t-\t90\tOWNED_FILE_EXISTING\n' "$BBRV3_SYSCTL_PATH" >>"$out"
    fi
    while IFS=$'\t' read -r key desired category source start end; do
        [[ $key == key || -z $key ]] && continue
        while IFS=$'\t' read -r source line val; do
            [[ -n $source ]] || continue
            [[ $source == "$path" ]] && continue
            base=$(basename "$source")
            if [[ $source == */sysctl.conf ]]; then rank=999; else rank=$(sed -nE 's/^([0-9]+).*/\1/p' <<<"$base"); rank=${rank:-50}; fi
            if [[ $val == "$desired" ]]; then type=SAME_VALUE
            elif (( rank > 90 )); then type=DIFFERENT_VALUE_HIGHER_PRIORITY
            else type=DIFFERENT_VALUE_LOWER_PRIORITY; fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$source" "$line" "$val" "$desired" "$rank" "$type" >>"$out"
        done < <(scan_key_sources "$key" "$root")
    done <"$plan"
    if awk -F '\t' 'NR>1 && ($7=="FOREIGN_FILE_AT_OWNED_PATH" || $7=="DIFFERENT_VALUE_HIGHER_PRIORITY") {found=1} END{exit !found}' "$out"; then return 3; fi
}

scan_key_sources() {
    local key=$1 root=$2 file line val dir
    for file in "$(root_path /etc/sysctl.conf)"; do
        [[ -f $file ]] || continue
        while IFS=: read -r line val; do
            val=${val#*=}; val=${val# }; printf '%s\t%s\t%s\n' "$file" "$line" "$val"
        done < <(grep -nE "^[[:space:]]*${key//./\\.}[[:space:]]*=" "$file" || true)
    done
    for dir in /etc/sysctl.d /run/sysctl.d /usr/local/lib/sysctl.d /usr/lib/sysctl.d /lib/sysctl.d; do
        [[ -d $(root_path "$dir") ]] || continue
        while IFS= read -r -d '' file; do
            [[ "$file" == "$(owned_path)" ]] && continue
            while IFS=: read -r line val; do
                val=${val#*=}; val=${val# }; printf '%s\t%s\t%s\n' "$file" "$line" "$val"
            done < <(grep -nE "^[[:space:]]*${key//./\\.}[[:space:]]*=" "$file" || true)
        done < <(find "$(root_path "$dir")" -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null | sort -z)
    done
}

atomic_write_owned() {
    local source=$1 path tmp; path=$(owned_path)
    mkdir -p "$(dirname "$path")"; tmp=$(mktemp "$(dirname "$path")/.bbrv3-universal.XXXXXX")
    chmod 0644 "$tmp"; cp "$source" "$tmp"; chmod 0644 "$tmp"; sync -f "$tmp" 2>/dev/null || true; mv -f "$tmp" "$path"; sync -f "$(dirname "$path")" 2>/dev/null || true
}

apply_transaction() {
    local dir=$1 plan=$2 path; path=$(owned_path)
    [[ $(owned_file_status) != FOREIGN ]] || { printf 'FOREIGN_FILE_AT_OWNED_PATH\n' >&2; return 3; }
    printf PREPARED >"$dir/state"
    capture_baseline "$dir" "$plan"
    printf APPLYING >"$dir/state"
    local tmp="$dir/owned.new"
    {
      printf '# managed-by=bbrv3-universal\n# schema-version=%s\n# policy-version=%s\n# transaction-id=%s\n# profile=%s\n# source-baseline=6630447fa25c42f4050c5745540cab2eef15f9e8f6dca201288bf98d4b602993\n' "$SCHEMA_VERSION" "$POLICY_VERSION" "$(basename "$dir")" "$(awk -F= '$1=="profile"{print $2; exit}' "${plan}.meta")"
      tail -n +2 "$plan" | awk -F '\t' '{print $1"="$2}'
    } >"$tmp"
    atomic_write_owned "$tmp"; hash_file "$path" >"$dir/applied.sha256"
    if ! "$BBRV3_SYSCTL_BIN" -p "$path" >"$dir/apply.out" 2>"$dir/apply.err"; then
        printf APPLY_FAILED >"$dir/state"; return 4
    fi
    if ! verify_plan "$plan" "$dir/verify.tsv"; then printf VERIFY_FAILED >"$dir/state"; return 5; fi
    printf VERIFIED >"$dir/state"
    printf 'PASS apply transaction=%s\n' "$(basename "$dir")"
}
