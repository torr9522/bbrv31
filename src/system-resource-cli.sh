#!/usr/bin/env bash
set -euo pipefail
ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$ROOT/src/core/system-resource.sh"; source "$ROOT/src/policy/system-resource-plan.sh"; source "$ROOT/src/recovery/system-resource-baseline.sh"; source "$ROOT/src/apply/system-resource.sh"; source "$ROOT/src/verify/system-resource.sh"; source "$ROOT/src/recovery/system-resource-rollback.sh"
parse_resource_args() { RESOURCE_FIXTURE=; while (($#)); do case $1 in --fixture) RESOURCE_FIXTURE=$2; shift 2;; *) return 2;; esac; done; }
resource_plan() { local d=$1 thp=always services= swap=NO memory=GE_4G; if [[ -n ${RESOURCE_FIXTURE:-} ]]; then export BBRV3_RESOURCE_FACTS="$RESOURCE_FIXTURE/facts.env"; thp=$(resource_fact thp.state); services=$(resource_fact nofile.known_services); swap=$(resource_fact swap.present); memory=$(resource_fact memory.class); fi; system_resource_plan "${thp:-always}" "${services:-}" "${swap:-NO}" "${memory:-GE_4G}" >"$d/desired.env"; }
plan_resource_command() { local d; d=$(mktemp -d); resource_plan "$d"; cat "$d/desired.env"; printf 'system_mutation=NO\n'; rm -rf "$d"; }
apply_resource_command() { resource_lock || return 1; local d; d=$(resource_new_transaction); resource_plan "$d"; system_resource_baseline "$d"; system_resource_apply "$d"; system_resource_verify "$d"; }
find_resource_transaction() { resource_latest; }
verify_resource_command() { local d; d=$(find_resource_transaction); [[ -n $d ]] || return 1; printf 'state=%s\n' "$(<"$d/state")"; system_resource_verify "$d" && printf 'verify=PASS\n'; }
rollback_resource_command() { resource_lock || return 1; local d; d=$(find_resource_transaction); [[ -n $d ]] || return 1; system_resource_rollback "$d"; system_resource_verify "$d" || true; }
cmd=${1:-}; shift || true; parse_resource_args "$@" || exit 2; case $cmd in plan-resources) plan_resource_command;; apply-resources) [[ $EUID -eq 0 ]] || exit 1; apply_resource_command;; verify-resources) verify_resource_command;; rollback-resources|recover-resources) [[ $EUID -eq 0 ]] || exit 1; rollback_resource_command;; *) exit 2;; esac
