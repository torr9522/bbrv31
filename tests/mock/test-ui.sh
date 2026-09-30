#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
grep -q 'COMPAT_ORIGINAL' <("$ROOT/bbrv3-universal.sh" advanced)
grep -q 'one_click=PLAN_ONLY' <("$ROOT/bbrv3-universal.sh" one-click)
grep -q 'BBRv3 Universal' <("$ROOT/bbrv3-universal.sh" status)
printf 'PASS UI/orchestration/advanced menu\n'
