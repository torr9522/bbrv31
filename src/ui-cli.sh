#!/usr/bin/env bash
set -euo pipefail
ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
status_ui() { printf 'BBRv3 Universal\nKernel: %s\nCPU level: %s\nProfile: AUTO\nNetwork: plan with ownership/drift guards\nSystem: sysctl/THP/nofile/swap layers available\nPersistence: owned reconcile\nRollback: transaction based\n' "$(uname -r)" "$(awk -F= '$1=="cpu.level"{print $2}' <("$ROOT/src/detect/all.sh" 2>/dev/null) || printf unknown)"; }
detail_ui() { status_ui; "$ROOT/bbrv3-universal.sh" detect; "$ROOT/bbrv3-universal.sh" plan-network; "$ROOT/bbrv3-universal.sh" plan-resources; }
one_click() { printf 'one_click=PLAN_ONLY\nprofile=AUTO\nsteps=preflight,kernel,sysctl,network,system,persist,verify\nsystem_mutation=NO\n'; }
advanced_ui() { printf '%s\n' 'PROFILE: AUTO ASIA_ORIGINAL OVERSEAS_ORIGINAL COMPAT_ORIGINAL LOW_SPEC XINCHENDAHAI REALITY XINCHENDAHAI_ORIGINAL' 'NETWORK: bandwidth buffer fq cake qdisc rps-rfs mss route-iw' 'SYSTEM: thp vm nofile swap' 'KERNEL: install update uninstall fallback status' 'SAFETY: baseline ownership transaction drift rollback verify recover'; }
case ${1:-status} in status) status_ui;; status-detail) detail_ui;; one-click) one_click;; advanced) advanced_ui;; rollback-all|recover-all) printf '%s\n' 'rollback/recover uses owned transactions';; *) printf '%s\n' 'Commands: status status-detail one-click advanced rollback-all recover-all'; exit 2;; esac
