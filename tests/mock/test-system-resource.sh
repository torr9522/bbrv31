#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); FIX=$(mktemp -d); STATE=$(mktemp -d); THP=$(mktemp); trap 'rm -rf "$FIX" "$STATE" "$THP"' EXIT
printf '%s\n' 'thp.state=always [madvise] never' 'nofile.known_services=xray' 'swap.present=YES' 'memory.class=1G_TO_LT_2G' >"$FIX/facts.env"; printf 'always [madvise] never\n' >"$THP"
out=$(BBRV3_RESOURCE_STATE_ROOT="$STATE" "$ROOT/bbrv3-universal.sh" plan-resources --fixture "$FIX"); grep -qx 'thp.decision=CANDIDATE' <<<"$out"; grep -qx 'nofile.decision=CANDIDATE' <<<"$out"; grep -qx 'swap.decision=RESPECT' <<<"$out"
unset BBRV3_RESOURCE_FACTS
BBRV3_RESOURCE_STATE_ROOT="$STATE" BBRV3_THP_PATH="$THP" "$ROOT/bbrv3-universal.sh" apply-resources --fixture "$FIX" >/dev/null; BBRV3_RESOURCE_STATE_ROOT="$STATE" BBRV3_THP_PATH="$THP" "$ROOT/bbrv3-universal.sh" rollback-resources >/dev/null; grep -qx 'madvise' "$THP"; printf 'PASS system resource mock/rollback\n'
