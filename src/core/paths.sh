#!/usr/bin/env bash
set -euo pipefail

BBRV3_PROJECT_ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
BBRV3_STATE_ROOT=${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}
BBRV3_SYSCTL_PATH=${BBRV3_SYSCTL_PATH:-/etc/sysctl.d/90-bbrv3-universal.conf}
BBRV3_SYSCTL_ROOT=${BBRV3_SYSCTL_ROOT:-/}
BBRV3_SYSCTL_BIN=${BBRV3_SYSCTL_BIN:-sysctl}
source "$BBRV3_PROJECT_ROOT/metadata/versions.env"

state_path() { printf '%s%s' "$BBRV3_STATE_ROOT" "$1"; }
root_path() { [[ $BBRV3_SYSCTL_ROOT == / ]] && printf '%s' "$1" || printf '%s%s' "${BBRV3_SYSCTL_ROOT%/}" "$1"; }
owned_path() { root_path "$BBRV3_SYSCTL_PATH"; }
sysctl_file_root() { root_path "$1"; }
ensure_state_root() {
    [[ ! -L $BBRV3_STATE_ROOT ]] || { printf 'STATE_ROOT_SYMLINK\n' >&2; return 1; }
    install -d -m 700 "$BBRV3_STATE_ROOT" "$BBRV3_STATE_ROOT/transactions" || return 1
}
hash_file() { sha256sum "$1" | awk '{print $1}'; }
sysctl_read() {
    # procps may render vector sysctls with tabs while plans use spaces.
    "$BBRV3_SYSCTL_BIN" -n "$1" 2>/dev/null | awk '{$1=$1; print}'
}
sysctl_write() { "$BBRV3_SYSCTL_BIN" -w "$1=$2"; }
