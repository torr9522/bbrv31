#!/usr/bin/env bash
set -euo pipefail
BBRV3_PERSIST_ROOT=${BBRV3_PERSIST_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/persistence}
persistence_write_unit() {
    local unit=${1:-bbrv3-universal-reconcile.service} dir=${2:-/etc/systemd/system}; install -d -m 755 "$dir"; cat >"$dir/$unit" <<'UNIT'
[Unit]
Description=BBRv3 Universal owned resource reconciliation
After=network-online.target systemd-sysctl.service
Wants=network-online.target
ConditionPathExists=/var/lib/bbrv3-universal/persistence/enabled

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bbrv3-universal reconcile
UNIT
}
persistence_enable_metadata() { install -d -m 700 "$BBRV3_PERSIST_ROOT"; : >"$BBRV3_PERSIST_ROOT/enabled"; }
persistence_reconcile() { printf 'reconcile=OWNED_ONLY\ndrift=DETECT_BEFORE_APPLY\nretry_limit=3\n'; }
