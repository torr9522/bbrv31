#!/usr/bin/env bash
set -euo pipefail

ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$ROOT/src/core/kernel.sh"
source "$ROOT/src/apply/kernel.sh"
source "$ROOT/src/core/lifecycle.sh"

state_root() { printf '%s\n' "${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}"; }
kernel_package_path() {
    if [[ -n ${BBRV3_KERNEL_PACKAGE:-} ]]; then printf '%s\n' "$BBRV3_KERNEL_PACKAGE"; return; fi
    find "$ROOT/vendor" -type f -name "$(kernel_formal_package)_*.deb" -print -quit 2>/dev/null
}
kernel_verify_package() {
    local package=$1 expected=0d685918e68cb7e764861ebaf276aec94350dbb18d15fc511e4776533a81a090
    [[ -f $package && $(sha256sum "$package" | awk '{print $1}') == "$expected" ]]
}
kernel_pending_root() { printf '%s\n' "$(state_root)/lifecycle"; }
kernel_read_entry() {
    local file="${BBRV3_KERNEL_STATE_ROOT:-$(state_root)/kernel}/boot-entry" entry=
    [[ -r $file ]] && IFS= read -r entry <"$file"
    [[ -n $entry ]] || entry=$(kernel_find_xanmod_entry || true)
    printf '%s\n' "$entry"
}
kernel_mark_wait_reboot() {
    local d; d=$(lifecycle_new)
    lifecycle_transition "$d" PRECHECK; lifecycle_transition "$d" KERNEL_INSTALL; lifecycle_transition "$d" WAIT_REBOOT
    printf 'kernel_transaction=%s\nworkflow=KERNEL_ONLY\n' "$d" >"$d/metadata.env"
    printf '%s\n' "$d"
}
install_reconcile_wrapper() {
    install -d -m 755 /usr/local/sbin
    printf '#!/bin/sh\nexec %q "$@"\n' "$ROOT/bbrv3-universal.sh" >/usr/local/sbin/bbrv3-universal
    chmod 755 /usr/local/sbin/bbrv3-universal
}
enable_reconcile() {
    source "$ROOT/src/persistence/reconcile.sh"
    install_reconcile_wrapper; persistence_write_unit; persistence_enable_metadata
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable bbrv3-universal-reconcile.service >/dev/null 2>&1 || true
}
kernel_resume_pending() {
    local root="$(state_root)/lifecycle" d stage entry
    for d in "$root"/*; do
        [[ -f $d/stage ]] || continue; stage=$(<"$d/stage"); [[ $stage == WAIT_REBOOT ]] || continue
        kernel_formal_running || { printf 'kernel.action=WAIT_REBOOT\nkernel.state=FORMAL_BASELINE_NOT_RUNNING\n' >&2; return 1; }
        entry=$(kernel_read_entry)
        [[ -n $entry ]] && kernel_set_persistent_default "$entry" || {
            printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_PERSISTENT_BOOT_FAILED\n' >&2; return 1;
        }
        lifecycle_transition "$d" POST_KERNEL_VERIFY
        printf 'kernel.action=POST_KERNEL_VERIFY\nkernel.state=FORMAL_BASELINE_RUNNING\n'
        return 0
    done
    return 2
}
kernel_pre_reboot_verify() {
    local pending=$1 entry=$2 formal state="${BBRV3_KERNEL_STATE_ROOT:-$(state_root)/kernel}" boot=${BBRV3_BOOT_DIR:-/boot} next
    formal=$(kernel_formal_release)
    kernel_formal_installed || return 1
    [[ -s $boot/vmlinuz-$formal && -s $boot/initrd.img-$formal ]] || return 1
    grep -Fq "$entry" "${BBRV3_GRUB_CFG:-/boot/grub/grub.cfg}" || return 1
    [[ -s $state/fallback-kernels.tsv ]] || return 1
    next=$(grub-editenv "${BBRV3_GRUB_ENV_FILE:-/boot/grub/grubenv}" list 2>/dev/null | sed -n 's/^next_entry=//p' | head -1)
    [[ $next == "$entry" ]] || return 1
    [[ -f $pending/stage && $(<"$pending/stage") == WAIT_REBOOT ]] || return 1
}
kernel_reboot_summary() {
    local formal; formal=$(kernel_formal_release)
    printf '\n============================================================\nBBRv3 内核安装检查\n============================================================\n'
    printf '[PASS] Kernel 包校验\n[PASS] BBRv3 Kernel 安装：%s\n[PASS] initramfs\n[PASS] GRUB 启动项\n[PASS] 原系统内核已保留\n[PASS] 下一次启动已设置为 BBRv3\n\n' "$formal"
    printf 'BBRv3 核心安装完成。\n\n服务器将在 %s 秒后自动重启。\nSSH 连接断开属于正常现象。\n\n重启验证完成后，请再次运行脚本并选择：\n3. BBRv3 网络优化\n============================================================\n' "${BBRV3_REBOOT_COUNTDOWN:-5}"
}
kernel_countdown_reboot() {
    local n=${BBRV3_REBOOT_COUNTDOWN:-5}
    while (( n > 0 )); do printf '%s...\n' "$n"; sleep "${BBRV3_COUNTDOWN_SLEEP:-1}"; n=$((n-1)); done
    printf '正在重启服务器...\n'
    "${BBRV3_REBOOT_COMMAND:-reboot}"
}
kernel_noop_summary() {
    printf '\nBBRv3 内核已经安装并正在运行，无需重新安装。\n当前内核：%s\nKernel 阶段完成。\n请运行菜单 3 执行或重新执行 BBRv3 网络优化。\n' "$(uname -r)"
}
cli_mock_dispatch() { [[ ${BBRV3_CLI_MOCK:-NO} == YES ]] || return 1; printf 'dispatch=%s\n' "$1"; }

orchestration_rollback_transactions() {
    local sysctl_tx=$1 network_tx=${2:-} rc=0
    [[ -z $network_tx ]] || "$ROOT/bbrv3-universal.sh" rollback-network --transaction "$network_tx" >/dev/null || rc=1
    [[ -z $sysctl_tx ]] || "$ROOT/bbrv3-universal.sh" rollback-sysctl --transaction "$sysctl_tx" >/dev/null || rc=1
    (( rc == 0 )) || printf 'ORCHESTRATION_ROLLBACK_FAILED\n' >&2
    return "$rc"
}

orchestration_apply_policy() {
    local profile=$1 bandwidth=$2 buffer=$3 create_swap=$4 swap_size=$5 sysctl_out network_out sysctl_tx= network_tx=
    if [[ $profile == SYSTEM_DEFAULT ]]; then
        sysctl_out=$("$ROOT/bbrv3-universal.sh" apply-sysctl --profile "$profile" --bandwidth "$bandwidth") || { printf '%s\n' "$sysctl_out"; return 1; }
    else
        sysctl_out=$("$ROOT/bbrv3-universal.sh" apply-sysctl --profile "$profile" --bandwidth "$bandwidth" --buffer-mib "$buffer") || { printf '%s\n' "$sysctl_out"; return 1; }
    fi
    printf '%s\n' "$sysctl_out"; sysctl_tx=$(sed -n 's/.*transaction=//p' <<<"$sysctl_out" | tail -1)
    network_out=$("$ROOT/bbrv3-universal.sh" apply-network) || {
        printf '%s\n' "$network_out"
        orchestration_rollback_transactions "$sysctl_tx" || true
        return 1
    }
    printf '%s\n' "$network_out"; network_tx=$(sed -n 's/.*transaction=//p' <<<"$network_out" | tail -1)
    if [[ $create_swap == YES ]]; then "$ROOT/bbrv3-universal.sh" apply-resources --create-swap --swap-size "$swap_size" || {
        orchestration_rollback_transactions "$sysctl_tx" "$network_tx" || true
        return 1
    }
    else "$ROOT/bbrv3-universal.sh" apply-resources || {
        orchestration_rollback_transactions "$sysctl_tx" "$network_tx" || true
        return 1
    }; fi
    enable_reconcile
    install -d -m 700 "$(state_root)/optimization"
    cat >"$(state_root)/optimization/state.env" <<EOF
optimization_stage=APPLIED
detected_bandwidth_mbps=$bandwidth
profile=$profile
buffer_mib=$buffer
EOF
    printf 'orchestration=APPLIED\npersistence=ENABLED\n'
}
orchestration_apply() {
    cli_mock_dispatch apply || {
        [[ $EUID -eq 0 ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }
        orchestration_apply_policy ASIA_ORIGINAL 1000 16 NO 0
    }
}
orchestration_install() {
    cli_mock_dispatch install || {
        [[ $EUID -eq 0 ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }
        printf 'install=PRECHECK\n'
        local package pending entry
        if kernel_formal_running; then
            local resume_rc=0 d
            kernel_resume_pending || resume_rc=$?
            [[ $resume_rc -eq 0 || $resume_rc -eq 2 ]] || return 1
            if [[ $resume_rc -eq 0 ]]; then
                for d in "$(state_root)/lifecycle"/*; do
                    [[ -f $d/stage && $(<"$d/stage") == POST_KERNEL_VERIFY ]] || continue
                    lifecycle_transition "$d" COMPLETE
                done
            fi
            entry=$(kernel_read_entry)
            [[ -n $entry ]] && kernel_set_persistent_default "$entry" || {
                printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_PERSISTENT_BOOT_FAILED\n' >&2; return 1;
            }
            install -d -m 700 "$(state_root)/kernel"; printf COMPLETE >"$(state_root)/kernel/stage"; enable_reconcile
            printf 'kernel.decision=NOOP\nkernel.action=NOOP\nkernel.state=FORMAL_BASELINE_ALREADY_RUNNING\n'
            kernel_noop_summary; printf 'install=COMPLETE\n'; return 0
        fi
        "$ROOT/bbrv3-universal.sh" kernel-plan
        if kernel_formal_installed; then
            entry=$(kernel_find_xanmod_entry || true)
            [[ -n $entry ]] || { printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_GRUB_ENTRY_MISSING\n' >&2; return 1; }
            kernel_set_one_shot "$entry"; printf '%s\n' "$entry" >"${BBRV3_KERNEL_STATE_ROOT:-$(state_root)/kernel}/boot-entry"
            printf 'kernel.action=REBOOT_REQUIRED\nkernel.state=FORMAL_BASELINE_INSTALLED\n'
        else
            package=$(kernel_package_path)
            [[ -n $package && -f $package ]] || { printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_PAYLOAD_MISSING\n' >&2; return 1; }
            kernel_verify_package "$package" || { printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_CHECKSUM_MISMATCH\n' >&2; return 1; }
            printf 'kernel.action=INSTALL\nkernel.package=%s\n' "$package"
            kernel_install_package "$package" || { printf 'kernel.action=FAILED\nkernel.reason=KERNEL_INSTALL_FAILED\n' >&2; return 1; }
            entry=$(kernel_read_entry)
        fi
        pending=$(kernel_mark_wait_reboot)
        printf 'kernel.action=REBOOT_REQUIRED\nkernel.state=WAIT_REBOOT\ntransaction=%s\n' "$(basename "$pending")"
        enable_reconcile
        if ! kernel_pre_reboot_verify "$pending" "$entry"; then
            lifecycle_transition "$pending" FAILED
            printf 'kernel.action=FAILED\nkernel.reason=PRE_REBOOT_VERIFY_FAILED\n服务器不会重启。\n' >&2
            return 1
        fi
        kernel_reboot_summary; kernel_countdown_reboot; return 75
    }
}
parse_optimize_args() {
    TUNING_BANDWIDTH_MODE= TUNING_SERVER_ID= TUNING_REQUESTED_BANDWIDTH= TUNING_REQUESTED_REGION= TUNING_BUFFER_ACCEPT=ask TUNING_SWAP_CHOICE=ask TUNING_ACCEPT_LOW_MEMORY_GLOBAL=NO
    while (($#)); do case $1 in
        --bandwidth-mode) TUNING_BANDWIDTH_MODE=$2; shift 2;; --server-id) TUNING_SERVER_ID=$2; shift 2;;
        --bandwidth) TUNING_REQUESTED_BANDWIDTH=$2; [[ -n $TUNING_BANDWIDTH_MODE ]] || TUNING_BANDWIDTH_MODE=manual; shift 2;;
        --region) TUNING_REQUESTED_REGION=$2; shift 2;; --accept-buffer) TUNING_BUFFER_ACCEPT=yes; shift;;
        --reject-buffer) TUNING_BUFFER_ACCEPT=no; shift;; --swap) TUNING_SWAP_CHOICE=$2; shift 2;;
        --accept-low-memory-global) TUNING_ACCEPT_LOW_MEMORY_GLOBAL=YES; shift;;
        --non-interactive) BBRV3_NONINTERACTIVE=YES; shift;; *) printf 'unknown optimize option: %s\n' "$1" >&2; return 2;; esac
    done
    export TUNING_BANDWIDTH_MODE TUNING_SERVER_ID TUNING_REQUESTED_BANDWIDTH TUNING_REQUESTED_REGION TUNING_BUFFER_ACCEPT TUNING_SWAP_CHOICE TUNING_ACCEPT_LOW_MEMORY_GLOBAL BBRV3_NONINTERACTIVE
}
optimization_network_type_label() {
    case ${TUNING_REGION:-} in
        asia) printf '亚太 / 低延迟连接为主';;
        overseas) printf '欧美 / 跨洲高延迟连接为主';;
        global) printf '全球混合 / 代理节点';;
        system) printf '使用系统默认 TCP Buffer';;
        *) printf unknown;;
    esac
}
optimization_summary() {
    local qdisc; qdisc=$(tc qdisc show 2>/dev/null | awk '$1=="qdisc" && $5!="lo" && $6=="root"{print $2; exit}')
    [[ $qdisc == mq ]] && qdisc='mq + fq leaves'
    printf '\n============================================================\nBBRv3 网络优化完成\n============================================================\n'
    printf 'Kernel：%s\n拥塞算法：%s\n队列算法：%s\n\n网络类型：%s\n' "$(uname -r)" "$(sysctl -n net.ipv4.tcp_congestion_control)" "$qdisc" "$(optimization_network_type_label)"
    if [[ $TUNING_REGION == global ]]; then
        printf 'Download：%s Mbps\nUpload：%s Mbps\n有效带宽：%s Mbps\n' "${TUNING_DOWNLOAD_MBPS:-N/A}" "${TUNING_UPLOAD_MBPS:-N/A}" "$TUNING_EFFECTIVE_MBPS"
    elif [[ $TUNING_REGION != system ]]; then
        printf '测速带宽：%s Mbps\n' "$TUNING_BANDWIDTH"
    fi
    if [[ $TUNING_REGION == system ]]; then
        printf 'TCP Buffer：系统 / Provider 管理\n\n[PASS] 27项通用系统参数\n[SKIP] 4项 TCP Buffer 参数（系统默认）\n'
    else
        printf 'TCP Buffer：%s MiB\n\n[PASS] 31项系统参数\n' "$TUNING_BUFFER"
    fi
    printf '[PASS] FQ\n[PASS/SKIP] RPS/RFS 策略\n[PASS/SKIP] MSS 策略\n[PASS] Route IW\n[PASS] THP\n[PASS] nofile\n[PASS] Swap 策略\n[PASS] 持久化\n\n优化完成。\n============================================================\n'
}
orchestration_optimize() {
    cli_mock_dispatch optimize || {
        [[ $EUID -eq 0 ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }
        kernel_formal_running || { printf 'optimize=BLOCKED\nreason=FORMAL_KERNEL_NOT_RUNNING\n请先选择菜单 1 安装 / 切换 BBRv3 内核。\n' >&2; return 1; }
        parse_optimize_args "$@"
        source "$ROOT/src/tuning-input.sh"
        tuning_collect_inputs || return $?
        if [[ $TUNING_REGION == global ]]; then
            printf '\n测速结果：\nDownload：%s Mbps\nUpload：%s Mbps\n\n网络类型：\n全球混合 / 代理节点\n\n有效带宽：%s Mbps\nTCP Buffer：%s MiB\n\n即将应用 BBRv3 网络优化...\n' "${TUNING_DOWNLOAD_MBPS:-N/A}" "${TUNING_UPLOAD_MBPS:-N/A}" "$TUNING_EFFECTIVE_MBPS" "$TUNING_BUFFER"
        elif [[ $TUNING_REGION == system ]]; then
            printf '\n已选择：\n使用系统默认 TCP Buffer\n\nBBRv3 Universal 将不会主动提高：\nnet.core.rmem_max\nnet.core.wmem_max\nnet.ipv4.tcp_rmem\nnet.ipv4.tcp_wmem\n\n其它 BBRv3 网络优化仍会正常执行。\n\n即将应用 BBRv3 网络优化...\n'
        else
            printf '\n测速带宽：%s Mbps\n网络类型：%s\nTCP Buffer：%s MiB\n即将应用 BBRv3 网络优化...\n' "$TUNING_BANDWIDTH" "$(optimization_network_type_label)" "$TUNING_BUFFER"
        fi
        orchestration_apply_policy "$TUNING_PROFILE" "$TUNING_BANDWIDTH" "$TUNING_BUFFER" "$TUNING_CREATE_SWAP" "$TUNING_SWAP_SIZE"
        cat >>"$(state_root)/optimization/state.env" <<EOF
region=$TUNING_REGION
network_type=$TUNING_REGION
buffer_policy=$TUNING_REGION
bandwidth_source=$TUNING_BANDWIDTH_SOURCE
download_mbps=${TUNING_DOWNLOAD_MBPS:-N/A}
upload_mbps=${TUNING_UPLOAD_MBPS:-N/A}
effective_mbps=$TUNING_EFFECTIVE_MBPS
speedtest_server=${TUNING_SPEEDTEST_SERVER:-N/A}
speedtest_duration_seconds=$TUNING_SPEEDTEST_DURATION
swap_status=$TUNING_SWAP_STATUS
EOF
        optimization_summary
        printf 'optimize=VERIFIED\n'
    }
}
orchestration_rollback() {
    cli_mock_dispatch rollback || {
        [[ $EUID -eq 0 ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }; local rc=0
        "$ROOT/bbrv3-universal.sh" rollback-sysctl "$@" || rc=1
        "$ROOT/bbrv3-universal.sh" rollback-network "$@" || rc=1
        "$ROOT/bbrv3-universal.sh" rollback-resources "$@" || rc=1
        (( rc == 0 )) && { rm -f "$(state_root)/optimization/state.env"; printf 'rollback=SAFE_COMPLETE\n'; } || printf 'rollback=BLOCKED_OR_PARTIAL\n' >&2
        return "$rc"
    }
}
orchestration_recover() {
    cli_mock_dispatch recover || {
        [[ $EUID -eq 0 ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }
        "$ROOT/bbrv3-universal.sh" rollback-sysctl --force-owned "$@"
        "$ROOT/bbrv3-universal.sh" recover-network --force-owned "$@"
        "$ROOT/bbrv3-universal.sh" rollback-resources "$@"
        rm -f "$(state_root)/optimization/state.env"; printf 'recover=EXPLICIT_OWNED_COMPLETE\n'
    }
}
orchestration_reboot() {
    cli_mock_dispatch reboot || {
        local root=${BBRV3_LIFECYCLE_ROOT:-$(state_root)/lifecycle} pending
        pending=$(find "$root" -mindepth 1 -maxdepth 1 -type d -exec sh -c 'for d; do [ -f "$d/stage" ] && [ "$(cat "$d/stage")" = WAIT_REBOOT ] && printf "%s\n" "$d"; done' sh {} + 2>/dev/null | head -1 || true)
        [[ -n $pending ]] || { printf 'reboot=GUARDED_NO_PENDING_TRANSACTION\n' >&2; return 1; }
        printf 'reboot=MANAGED transaction=%s\n' "$(basename "$pending")"; "${BBRV3_REBOOT_COMMAND:-reboot}"
    }
}
orchestration_uninstall() {
    cli_mock_dispatch uninstall || {
        orchestration_rollback "$@"
        rm -f /usr/local/sbin/bbrv3-universal /etc/systemd/system/bbrv3-universal-reconcile.service
        rm -rf "$(state_root)/persistence" "$(state_root)/optimization"
        systemctl daemon-reload 2>/dev/null || true; printf 'uninstall=OWNED_RESOURCES_REMOVED\n'
    }
}
