#!/usr/bin/env bash
set -euo pipefail
ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$ROOT/src/core/system-resource.sh"
source "$ROOT/src/policy/system-resource-plan.sh"
source "$ROOT/src/recovery/system-resource-baseline.sh"
source "$ROOT/src/apply/system-resource.sh"
source "$ROOT/src/verify/system-resource.sh"
source "$ROOT/src/recovery/system-resource-rollback.sh"

parse_resource_args() {
    RESOURCE_FIXTURE= RESOURCE_TRANSACTION= RESOURCE_CREATE_SWAP=NO RESOURCE_SWAP_SIZE=
    while (($#)); do
        case $1 in
            --fixture) RESOURCE_FIXTURE=$2; shift 2;;
            --transaction) RESOURCE_TRANSACTION=$2; shift 2;;
            --create-swap) RESOURCE_CREATE_SWAP=YES; shift;;
            --swap-size) RESOURCE_SWAP_SIZE=$2; shift 2;;
            *) return 2;;
        esac
    done
}

resource_plan() {
    local d=$1 thp=always services= swap=NO memory=4096
    if [[ -n ${RESOURCE_FIXTURE:-} ]]; then
        export BBRV3_RESOURCE_FACTS="$RESOURCE_FIXTURE/facts.env"
        thp=$(resource_fact thp.state); services=$(resource_fact nofile.known_services)
        swap=$(resource_fact swap.present); memory=$(resource_fact memory.total_mib)
        [[ -n $memory ]] || memory=$(resource_fact memory.class)
        [[ $memory =~ ^[0-9]+$ ]] || case $memory in LT_512M) memory=400;; 512M_TO_LT_1G) memory=768;; 1G_TO_LT_2G) memory=1536;; 2G_TO_LT_4G) memory=3072;; *) memory=4096;; esac
    else
        unset BBRV3_RESOURCE_FACTS
        [[ -r /sys/kernel/mm/transparent_hugepage/enabled ]] && thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled)
        services=$(for svc in xray sing-box hysteria tuic nginx caddy; do systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | awk -v s="${svc}.service" '$1==s{print s; exit}' || true; done | sed 's/\.service$//' | paste -sd, - || true)
        swapon --show --noheadings 2>/dev/null | grep -q . && swap=YES
        memory=$(awk '/^MemTotal:/{printf "%d",$2/1024}' /proc/meminfo)
    fi
    system_resource_plan "${thp:-always}" "${services:-}" "${swap:-NO}" "${memory:-4096}" >"$d/desired.env"
}

plan_resource_command() { local d; d=$(mktemp -d); resource_plan "$d"; cat "$d/desired.env"; printf 'system_mutation=NO\n'; rm -rf "$d"; }
apply_resource_command() {
    resource_lock || return 1
    local d recommended; d=$(resource_new_transaction); resource_plan "$d"; system_resource_baseline "$d"
    recommended=$(awk -F= '$1=="swap.recommended_mb"{print $2}' "$d/desired.env")
    BBRV3_CREATE_SWAP=$RESOURCE_CREATE_SWAP BBRV3_SWAP_SIZE_MB=${RESOURCE_SWAP_SIZE:-${recommended:-512}} system_resource_apply "$d"
    system_resource_verify "$d" || { printf VERIFY_FAILED >"$d/state"; return 1; }
}
find_resource_transaction() { if [[ -n ${RESOURCE_TRANSACTION:-} ]]; then printf '%s/transactions/%s\n' "$BBRV3_RESOURCE_STATE_ROOT" "$RESOURCE_TRANSACTION"; else resource_latest; fi; }
verify_resource_command() { local d; d=$(find_resource_transaction); [[ -n $d ]] || return 1; printf 'state=%s\n' "$(<"$d/state")"; system_resource_verify "$d" && printf 'verify=PASS\n'; }
rollback_resource_command() { resource_lock || return 1; local d; d=$(find_resource_transaction); [[ -n $d ]] || return 1; system_resource_rollback "$d"; system_resource_verify "$d" || true; }

cmd=${1:-}; shift || true; parse_resource_args "$@" || exit 2
case $cmd in
    plan-resources) plan_resource_command;;
    apply-resources) [[ $EUID -eq 0 ]] || exit 1; apply_resource_command;;
    verify-resources) verify_resource_command;;
    rollback-resources|recover-resources) [[ $EUID -eq 0 ]] || exit 1; rollback_resource_command;;
    *) exit 2;;
esac
