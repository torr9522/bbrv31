#!/usr/bin/env bash
set -euo pipefail
ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$ROOT/src/orchestration.sh"
status_ui() {
    local state=${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/optimization/state.env optimization=NOT_APPLIED profile=NONE network_type=NONE
    if [[ -r $state ]]; then
        optimization=$(awk -F= '$1=="optimization_stage"{print $2}' "$state")
        profile=$(awk -F= '$1=="profile"{print $2}' "$state")
        network_type=$(awk -F= '$1=="network_type"{print toupper($2)}' "$state")
        if [[ -z $network_type ]]; then
            case $profile in
                ASIA_ORIGINAL) network_type=ASIA;;
                OVERSEAS_ORIGINAL) network_type=OVERSEAS;;
                GLOBAL_MIXED) network_type=GLOBAL;;
                *) network_type=NONE;;
            esac
        fi
    fi
    printf 'BBRv3 Universal\nKernel: %s\nCPU level: %s\nProfile: %s\nNetwork type: %s\nNetwork optimization: %s\nNetwork: plan with ownership/drift guards\nSystem: sysctl/THP/nofile/swap layers available\nPersistence: owned reconcile\nRollback: transaction based\n' "$(uname -r)" "$(awk -F= '$1=="cpu.level"{print $2}' <("$ROOT/src/detect/all.sh" 2>/dev/null) || printf unknown)" "$profile" "$network_type" "$optimization"
}
detail_ui() { status_ui; "$ROOT/bbrv3-universal.sh" detect; "$ROOT/bbrv3-universal.sh" plan-network; "$ROOT/bbrv3-universal.sh" plan-resources; }
one_click() { if [[ ${1:-} == --apply ]]; then orchestration_apply "${@:2}"; else printf 'one_click=PLAN_ONLY\nprofile=AUTO\nsteps=preflight,kernel,sysctl,network,system,persist,verify\nsystem_mutation=NO\n'; fi; }
advanced_ui() { printf '%s\n' 'PROFILE: ASIA_ORIGINAL OVERSEAS_ORIGINAL GLOBAL_MIXED COMPAT_ORIGINAL (temporary upstream profiles are audit-only)' 'NETWORK: bandwidth buffer fq qdisc rps-rfs mss route-iw' 'SYSTEM: thp vm nofile swap' 'KERNEL: install update uninstall fallback status' 'SAFETY: baseline ownership transaction drift rollback verify recover'; }
case ${1:-status} in
  status) status_ui;; status-detail) detail_ui;;
  one-click) shift; one_click "$@";; install) shift; orchestration_install "$@";; optimize) shift; orchestration_optimize "$@";; apply) shift; orchestration_apply "$@";;
  rollback-all) shift; orchestration_rollback "$@";; recover-all) shift; orchestration_recover "$@";; reboot) shift; orchestration_reboot "$@";; uninstall) shift; orchestration_uninstall "$@";;
  advanced) advanced_ui; printf '%s\n' 'CAKE: audited; intentionally not applied by the FQ workflow' 'MENU99: frozen upstream/reference isolation';;
  menu99) printf 'upstream=%s\nsource=%s\n' 'e5f3e8d262a442b3c3f3167885998a84fdd17136' '/root/bbrv3-original-extraction/bbrv3-only-original.sh';;
  reconcile) . "$ROOT/src/persistence/reconcile.sh"; persistence_reconcile;;
  *) printf '%s\n' 'Commands: install optimize apply status status-detail one-click rollback-all recover-all reboot uninstall advanced menu99 reconcile'; exit 2;;
esac
