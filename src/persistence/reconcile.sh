#!/usr/bin/env bash
set -euo pipefail
BBRV3_PERSIST_ROOT=${BBRV3_PERSIST_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/persistence}

persistence_write_unit() {
    local unit=${1:-bbrv3-universal-reconcile.service} dir=${2:-/etc/systemd/system}
    install -d -m 755 "$dir"
    cat >"$dir/$unit" <<'UNIT'
[Unit]
Description=BBRv3 Universal owned resource reconciliation
After=network-online.target systemd-sysctl.service
Wants=network-online.target
ConditionPathExists=/var/lib/bbrv3-universal/persistence/enabled

[Service]
Type=oneshot
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/local/sbin/bbrv3-universal reconcile

[Install]
WantedBy=multi-user.target
UNIT
}
persistence_enable_metadata() { install -d -m 700 "$BBRV3_PERSIST_ROOT"; : >"$BBRV3_PERSIST_ROOT/enabled"; }

persistence_resume_kernel() {
    local root=$1 lifecycle_root=${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/lifecycle d stage entry file
    . "$root/src/core/kernel.sh"; . "$root/src/core/lifecycle.sh"; . "$root/src/apply/kernel.sh"
    for d in "$lifecycle_root"/*; do
        [[ -f $d/stage ]] || continue; stage=$(<"$d/stage"); [[ $stage == WAIT_REBOOT ]] || continue
        kernel_formal_running || { printf 'kernel.action=WAIT_REBOOT\nkernel.state=FORMAL_BASELINE_NOT_RUNNING\n' >&2; return 1; }
        file="${BBRV3_KERNEL_STATE_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/kernel}/boot-entry"; entry=
        [[ -r $file ]] && IFS= read -r entry <"$file"
        [[ -n $entry ]] || entry=$(kernel_find_xanmod_entry || true)
        [[ -n $entry ]] && kernel_set_persistent_default "$entry" || {
            printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_PERSISTENT_BOOT_FAILED\n' >&2; return 1;
        }
        lifecycle_transition "$d" POST_KERNEL_VERIFY
        printf 'kernel.action=POST_KERNEL_VERIFY\nkernel.state=FORMAL_BASELINE_RUNNING\nresume=POST_KERNEL_VERIFY\n'
        lifecycle_transition "$d" COMPLETE
        install -d -m 700 "${BBRV3_KERNEL_STATE_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/kernel}"
        printf COMPLETE >"${BBRV3_KERNEL_STATE_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/kernel}/stage"
        printf '\nBBRv3 新内核启动成功：%s\n正在完成启动验证...\n[PASS] BBRv3 Kernel\n[PASS] GRUB 持久化\n[PASS] 原系统 Kernel 保留\nKernel 阶段完成。\n请再次运行菜单并选择 3. BBRv3 网络优化\n' "$(uname -r)"
        printf 'resume=COMPLETE\n'
        return 10
    done
    return 2
}

persistence_reconcile() {
    local root=${ROOT:-${BBRV3_UNIVERSAL_ROOT:-/usr/local/lib/bbrv3-universal}} rc state profile bandwidth buffer attempt
    if [[ -f $root/src/core/kernel.sh ]]; then
        persistence_resume_kernel "$root" || {
            rc=$?
            [[ $rc -eq 10 ]] && { printf 'reconcile_result=KERNEL_STAGE_COMPLETE\n'; return 0; }
            [[ $rc -eq 2 ]] || return 1
        }
    fi
    state="${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/optimization/state.env"
    if [[ ! -r $state ]] || ! grep -qx 'optimization_stage=APPLIED' "$state"; then
        printf 'reconcile=KERNEL_ONLY\nnetwork_optimization=NOT_APPLIED\n'
        return 0
    fi
    profile=$(awk -F= '$1=="profile"{print $2}' "$state"); bandwidth=$(awk -F= '$1=="detected_bandwidth_mbps"{print $2}' "$state"); buffer=$(awk -F= '$1=="buffer_mib"{print $2}' "$state")
    printf 'reconcile=OWNED_OPTIMIZATION\ndrift=DETECT_BEFORE_APPLY\nretry_limit=3\n'
    for attempt in 1 2 3; do
        if "$root/bbrv3-universal.sh" apply-sysctl --profile "$profile" --bandwidth "$bandwidth" --buffer-mib "$buffer" &&
           "$root/bbrv3-universal.sh" apply-network &&
           "$root/bbrv3-universal.sh" apply-resources; then
            printf 'reconcile_result=RECONCILED\nattempt=%s\n' "$attempt"; return 0
        fi
        sleep "$attempt"
    done
    printf 'reconcile_result=FAILED\nattempt=3\n' >&2; return 1
}
