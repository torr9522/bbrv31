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

[Install]
WantedBy=multi-user.target
UNIT
}
persistence_enable_metadata() { install -d -m 700 "$BBRV3_PERSIST_ROOT"; : >"$BBRV3_PERSIST_ROOT/enabled"; }
persistence_reconcile() {
    local root=${ROOT:-${BBRV3_UNIVERSAL_ROOT:-/usr/local/lib/bbrv3-universal}} attempt
    printf 'reconcile=OWNED_ONLY\ndrift=DETECT_BEFORE_APPLY\nretry_limit=3\n'
    for attempt in 1 2 3; do
        if "$root/bbrv3-universal.sh" apply-network && "$root/bbrv3-universal.sh" apply-resources; then
            printf 'reconcile_result=RECONCILED\nattempt=%s\n' "$attempt"
            return 0
        fi
        sleep "$attempt"
    done
    printf 'reconcile_result=FAILED\nattempt=3\n' >&2
    return 1
}
