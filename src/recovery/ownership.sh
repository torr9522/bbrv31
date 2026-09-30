#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/paths.sh"

owned_marker() { grep -Fqx '# managed-by=bbrv3-universal' "$1" 2>/dev/null; }
owned_file_status() {
    local path; path=$(owned_path)
    if [[ ! -e $path ]]; then printf ABSENT; elif owned_marker "$path"; then printf OWNED; else printf FOREIGN; fi
}
capture_ownership() {
    local dir=$1 path; path=$(owned_path)
    printf 'path\tstatus\tsha256\n' >"$dir/ownership.tsv"
    if [[ -e $path ]]; then printf '%s\t%s\t%s\n' "$BBRV3_SYSCTL_PATH" "$(owned_file_status)" "$(hash_file "$path")" >>"$dir/ownership.tsv"; cp -a "$path" "$dir/owned-before.conf"; else printf '%s\tABSENT\t-\n' "$BBRV3_SYSCTL_PATH" >>"$dir/ownership.tsv"; fi
}
