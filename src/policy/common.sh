#!/usr/bin/env bash
BBRV3_ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
POLICY_ROOT=$BBRV3_ROOT
[[ -v POLICY_VERSION ]] || source "$BBRV3_ROOT/metadata/versions.env"
policy_get() { awk -F= -v key="$1" '$1==key {sub(/^[^=]*=/, ""); print; exit}' "$POLICY_INPUT"; }
policy_has() { [[ -n $(policy_get "$1") ]]; }
policy_kv() { printf '%s=%s\n' "$1" "${2:-}"; }
