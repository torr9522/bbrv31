#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
export BBRV3_UNIVERSAL_ROOT=$ROOT
export PHASE2_READ_ONLY=1
usage() { printf '%s\n' 'Usage:' '  bbrv3-universal.sh validate-data' '  bbrv3-universal.sh detect [--fixture DIR]' '  bbrv3-universal.sh dry-run [options]' '  bbrv3-universal.sh compat-plan' '  bbrv3-universal.sh plan-sysctl [--profile PROFILE] [--bandwidth N] [--ram-mb N] [--fixture DIR]' '  bbrv3-universal.sh apply-sysctl [options]' '  bbrv3-universal.sh verify-sysctl [options]' '  bbrv3-universal.sh rollback-sysctl [--transaction ID]' '  bbrv3-universal.sh recover-sysctl' '  bbrv3-universal.sh plan-network [--fixture DIR]' '  bbrv3-universal.sh apply-network [--fixture DIR] [--only RESOURCE]' '  bbrv3-universal.sh verify-network [--transaction ID]' '  bbrv3-universal.sh rollback-network [--transaction ID]' '  bbrv3-universal.sh recover-network'; }
fixture= profile=auto bandwidth=1000 bandwidth_source=MANUAL_PRESET ram= cpu= detail_mode=NO
command_name=${1:-}; shift || true
case $command_name in compat-plan) source "$ROOT/src/policy/compatibility.sh"; compat_original_plan; exit 0;; plan-sysctl|apply-sysctl|verify-sysctl|rollback-sysctl|recover-sysctl) exec "$ROOT/src/sysctl-cli.sh" "$command_name" "$@";; plan-network|apply-network|verify-network|rollback-network|recover-network) exec "$ROOT/src/network-cli.sh" "$command_name" "$@";; plan-resources|apply-resources|verify-resources|rollback-resources|recover-resources) exec "$ROOT/src/system-resource-cli.sh" "$command_name" "$@";; kernel-plan|kernel-status|kernel-install|kernel-update|kernel-uninstall) exec "$ROOT/src/kernel-cli.sh" "$command_name" "$@";; status|status-detail|rollback-all|recover-all|one-click|advanced|menu99|reconcile|rollback-all|recover-all) exec "$ROOT/src/ui-cli.sh" "$command_name" "$@";; apply|install|optimize|reboot|rollback) printf 'NOT_IMPLEMENTED_IN_PHASE3_SCOPE\n'; exit 3;; esac
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
