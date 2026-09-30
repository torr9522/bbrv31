#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); source "$ROOT/src/policy/compatibility.sh"
out=$(compat_original_plan)
grep -qx 'profile=COMPAT_ORIGINAL' <<<"$out"
grep -qx 'sysctl=31/31:Phase3-owned' <<<"$out"
grep -qx 'route_iw=initcwnd32-initrwnd32' <<<"$out"
grep -qx 'nofile=524288-limits-and-service-aware' <<<"$out"
printf 'PASS compatibility static parity\n'
