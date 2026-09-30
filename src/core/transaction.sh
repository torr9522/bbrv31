#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths.sh"
new_transaction() {
    ensure_state_root
    local id="$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM$RANDOM"
    local dir="$BBRV3_STATE_ROOT/transactions/$id"
    install -d -m 700 "$dir"
    printf '%s\n' "$dir"
}
with_lock() {
    ensure_state_root
    exec 9>"$BBRV3_STATE_ROOT/lock"
    flock -n 9 || { printf 'OPERATION_IN_PROGRESS\n' >&2; return 1; }
}
latest_transaction() {
    find "$BBRV3_STATE_ROOT/transactions" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1{sub(/^[^ ]+ /,""); print}'
}
