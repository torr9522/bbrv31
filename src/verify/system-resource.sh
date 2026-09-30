#!/usr/bin/env bash
set -euo pipefail
system_resource_verify() { local d=$1 p=${BBRV3_THP_PATH:-/sys/kernel/mm/transparent_hugepage/enabled}; [[ $(awk -F= '$1=="thp.decision"{print $2}' "$d/desired.env") != CANDIDATE ]] || { [[ -r $p ]] && grep -Eq '\[never\]|^never$' "$p" || return 1; }; local services; services=$(awk -F= '$1=="nofile.services"{print $2}' "$d/desired.env"); if [[ -z $services ]]; then grep -q 'managed-by=bbrv3-universal' "${BBRV3_LIMITS_DIR:-/etc/security/limits.d}/90-bbrv3-universal.conf" || return 1; fi; return 0; }
