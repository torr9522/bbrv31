#!/usr/bin/env bash
set -euo pipefail
BBRV3_RESOURCE_STATE_ROOT=${BBRV3_RESOURCE_STATE_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/system}
resource_ensure_root() { [[ ! -L $BBRV3_RESOURCE_STATE_ROOT ]] || return 1; install -d -m 700 "$BBRV3_RESOURCE_STATE_ROOT" "$BBRV3_RESOURCE_STATE_ROOT/transactions"; }
resource_lock() { resource_ensure_root; exec 7>"$BBRV3_RESOURCE_STATE_ROOT/lock"; flock -n 7; }
resource_new_transaction() { resource_ensure_root; local id="$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM$RANDOM"; install -d -m 700 "$BBRV3_RESOURCE_STATE_ROOT/transactions/$id"; printf '%s\n' "$BBRV3_RESOURCE_STATE_ROOT/transactions/$id"; }
resource_latest() { find "$BBRV3_RESOURCE_STATE_ROOT/transactions" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1{sub(/^[^ ]+ /,"",$0);print}'; }
resource_fact() { [[ -n ${BBRV3_RESOURCE_FACTS:-} ]] && awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"",$0); print; exit}' "$BBRV3_RESOURCE_FACTS"; }
