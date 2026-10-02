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
    if [[ -f ${root}/src/core/kernel.sh ]]; then
        . "${root}/src/core/kernel.sh"
        . "${root}/src/core/lifecycle.sh"
        kernel_resume_pending() {
            local lifecycle_root=${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/lifecycle d stage
            for d in "$lifecycle_root"/*; do
                [[ -f $d/stage ]] || continue
                stage=$(<"$d/stage")
                [[ $stage == WAIT_REBOOT ]] || continue
                if kernel_formal_running; then
                    lifecycle_transition "$d" POST_KERNEL_VERIFY
                    printf 'kernel.action=POST_KERNEL_VERIFY\nkernel.state=FORMAL_BASELINE_RUNNING\n'
                    return 0
                fi
                printf 'kernel.action=WAIT_REBOOT\nkernel.state=FORMAL_BASELINE_NOT_RUNNING\n' >&2
                return 1
            done
            return 2
        }
        if kernel_resume_pending; then
            printf 'resume=POST_KERNEL_VERIFY\n'
        else
            local rc=$?
            [[ $rc -eq 2 ]] || return 1
        fi
    fi
    printf 'reconcile=OWNED_ONLY\ndrift=DETECT_BEFORE_APPLY\nretry_limit=3\n'
    for attempt in 1 2 3; do
        if "$root/bbrv3-universal.sh" apply-network && "$root/bbrv3-universal.sh" apply-resources; then
            for d in "${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/lifecycle"/*; do
                [[ -f $d/stage && $(<"$d/stage") == POST_KERNEL_VERIFY ]] || continue
                lifecycle_transition "$d" COMPLETE
                printf 'resume=COMPLETE\n'
            done
            printf 'reconcile_result=RECONCILED\nattempt=%s\n' "$attempt"
            return 0
        fi
        sleep "$attempt"
    done
    printf 'reconcile_result=FAILED\nattempt=3\n' >&2
    return 1
}
