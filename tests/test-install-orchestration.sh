#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp)
if "$ROOT/bbrv3-universal.sh" install >"$out" 2>&1; then
    printf 'install unexpectedly succeeded without a formal kernel package\n' >&2
    exit 1
fi
grep -q '^kernel.action=BLOCKED$' "$out"
grep -q '^kernel.reason=FORMAL_KERNEL_PAYLOAD_MISSING$' "$out"
! grep -q '^install=COMPLETE$' "$out"
printf 'PASS public install blocks before tuning when kernel payload is missing\n'
