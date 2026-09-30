#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
d=$(BBRV3_LIFECYCLE_ROOT="$S" "$ROOT/src/reboot-resume.sh" start)
BBRV3_LIFECYCLE_ROOT="$S" "$ROOT/src/reboot-resume.sh" transition "$d" NETWORK_DETECT >/dev/null
grep -qx NETWORK_DETECT "$d/stage"; printf 'PASS lifecycle/resume state machine\n'
grep -q 'apply-network' "$ROOT/src/persistence/reconcile.sh"
grep -q 'apply-resources' "$ROOT/src/persistence/reconcile.sh"
