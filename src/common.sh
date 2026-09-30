#!/usr/bin/env bash

BBRV3_ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$BBRV3_ROOT/metadata/versions.env"
readonly SCHEMA_VERSION POLICY_VERSION PHASE2_READ_ONLY

kv() { printf '%s=%s\n' "$1" "${2:-}"; }
available() { command -v "$1" >/dev/null 2>&1; }
bool() { [[ $1 == 1 ]] && printf YES || printf NO; }
first_word_after() { awk -v key="$1" '{for(i=1;i<=NF;i++) if($i==key && i<NF){print $(i+1); exit}}'; }

fixture_value() {
    local key=$1 file=${BBRV3_FIXTURE_ROOT:-}/facts.env
    [[ -n ${BBRV3_FIXTURE_ROOT:-} && -f $file ]] || return 1
    awk -F= -v key="$key" '$1==key {sub(/^[^=]*=/, ""); print; found=1; exit} END {exit !found}' "$file"
}
