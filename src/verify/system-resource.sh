#!/usr/bin/env bash
set -euo pipefail
system_resource_verify() { local d=$1 p=${BBRV3_THP_PATH:-/sys/kernel/mm/transparent_hugepage/enabled}; [[ $(awk -F= '$1=="thp.decision"{print $2}' "$d/desired.env") != CANDIDATE ]] || { [[ -r $p ]] && grep -Eq '\[never\]|^never$' "$p" || return 1; }; return 0; }
