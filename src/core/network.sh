#!/usr/bin/env bash
set -euo pipefail

BBRV3_NETWORK_STATE_ROOT=${BBRV3_NETWORK_STATE_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/network}
BBRV3_NETWORK_LOCK=${BBRV3_NETWORK_LOCK:-$BBRV3_NETWORK_STATE_ROOT/lock}
BBRV3_NETWORK_TC_BIN=${BBRV3_NETWORK_TC_BIN:-tc}
BBRV3_NETWORK_IP_BIN=${BBRV3_NETWORK_IP_BIN:-ip}
BBRV3_NETWORK_IPTABLES_BIN=${BBRV3_NETWORK_IPTABLES_BIN:-iptables}
BBRV3_NETWORK_SYSFS_ROOT=${BBRV3_NETWORK_SYSFS_ROOT:-/sys}

network_root_path() { [[ ${BBRV3_NETWORK_SYSFS_ROOT:-/sys} == /sys ]] && printf '%s' "$1" || printf '%s%s' "${BBRV3_NETWORK_SYSFS_ROOT%/}" "$1"; }
network_ensure_root() { [[ ! -L $BBRV3_NETWORK_STATE_ROOT ]] || return 1; install -d -m 700 "$BBRV3_NETWORK_STATE_ROOT" "$BBRV3_NETWORK_STATE_ROOT/transactions"; }
network_lock() { network_ensure_root; exec 8>"$BBRV3_NETWORK_LOCK"; flock -n 8; }
network_hash() { sha256sum "$1" | awk '{print $1}'; }
network_fact() { local k=$1; [[ -n ${BBRV3_NETWORK_FACTS:-} ]] && awk -F= -v k="$k" '$1==k{sub(/^[^=]*=/,"",$0); print; exit}' "$BBRV3_NETWORK_FACTS"; }
network_new_transaction() { network_ensure_root; local id; id="$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM$RANDOM"; install -d -m 700 "$BBRV3_NETWORK_STATE_ROOT/transactions/$id"; printf '%s\n' "$BBRV3_NETWORK_STATE_ROOT/transactions/$id"; }
network_latest() { find "$BBRV3_NETWORK_STATE_ROOT/transactions" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1{sub(/^[^ ]+ /,"",$0);print}'; }
network_normalize() { awk '{$1=$1; print}'; }
network_qdisc_text() { [[ -n ${BBRV3_NETWORK_FACTS:-} ]] && { network_fact qdisc.current; return; }; "$BBRV3_NETWORK_TC_BIN" qdisc show 2>/dev/null || true; }
network_route_text() { [[ -n ${BBRV3_NETWORK_FACTS:-} ]] && { network_fact route.current; return; }; "$BBRV3_NETWORK_IP_BIN" -4 route show default 2>/dev/null || true; }
network_default_if() { local r; r=$(network_route_text); awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$r"; }
network_tc_mutation() { printf 'tc %q\n' "$*" >>"${NETWORK_AUDIT_FILE:-/dev/null}"; "$BBRV3_NETWORK_TC_BIN" "$@"; }
network_ip_mutation() { printf 'ip %q\n' "$*" >>"${NETWORK_AUDIT_FILE:-/dev/null}"; "$BBRV3_NETWORK_IP_BIN" "$@"; }
network_iptables_mutation() { printf 'iptables %q\n' "$*" >>"${NETWORK_AUDIT_FILE:-/dev/null}"; "$BBRV3_NETWORK_IPTABLES_BIN" "$@"; }
