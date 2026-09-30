#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
export BBRV3_UNIVERSAL_ROOT=$ROOT
export PHASE2_READ_ONLY=1
usage() { printf '%s\n' 'Usage:' '  bbrv3-universal.sh validate-data' '  bbrv3-universal.sh detect [--fixture DIR]' '  bbrv3-universal.sh dry-run [--profile auto|asia-original|overseas-original|compat-original] [--bandwidth N] [--ram-mb N] [--cpu-count N] [--fixture DIR] [--detail]'; }
fixture= profile=auto bandwidth=1000 bandwidth_source=MANUAL_PRESET ram= cpu= detail_mode=NO
command_name=${1:-}; shift || true
case $command_name in apply|install|optimize|reboot|rollback) printf 'NOT_IMPLEMENTED_IN_PHASE2\n'; exit 3;; esac
while [[ $# -gt 0 ]]; do
  case $1 in
    --fixture) fixture=$2; shift 2;;
    --profile) profile=$2; shift 2;;
    --bandwidth) bandwidth=$2; bandwidth_source=MANUAL_VALUE; shift 2;;
    --bandwidth-source) bandwidth_source=$2; shift 2;;
    --ram-mb) ram=$2; shift 2;;
    --cpu-count) cpu=$2; shift 2;;
    --detail) detail_mode=YES; shift;;
    -h|--help) usage; exit 0;;
    *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2;;
  esac
done
if [[ -n $fixture ]]; then export BBRV3_FIXTURE_ROOT=$fixture; fi
if [[ $command_name == validate-data ]]; then exec "$ROOT/src/loader.sh" --check; fi
[[ $command_name == detect || $command_name == dry-run ]] || { usage >&2; exit 2; }
if [[ $command_name == detect ]]; then exec "$ROOT/src/detect/all.sh"; fi
tmp=$(mktemp -d); trap 'rmdir "$tmp" 2>/dev/null || true' EXIT
"$ROOT/src/detect/all.sh" >"$tmp/detect"
if [[ -n $ram ]]; then sed -i "s/^memory.total_mib=.*/memory.total_mib=$ram/" "$tmp/detect"; fi
if [[ -n $cpu ]]; then sed -i "s/^cpu.count=.*/cpu.count=$cpu/" "$tmp/detect"; fi
POLICY_INPUT=$tmp/detect REQUESTED_PROFILE=$profile REQUESTED_BANDWIDTH=$bandwidth REQUESTED_BANDWIDTH_SOURCE=$bandwidth_source "$ROOT/src/policy/decision.sh" >"$tmp/decision"
cat "$tmp/detect" "$tmp/decision" >"$tmp/output"
if [[ $detail_mode == YES ]]; then "$ROOT/src/ui/dry-run.sh" detail "$tmp/output"; else "$ROOT/src/ui/dry-run.sh" summary "$tmp/output"; fi
