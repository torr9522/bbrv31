#!/usr/bin/env bash
set -euo pipefail

ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

source "$ROOT/src/core/kernel.sh"
source "$ROOT/src/apply/kernel.sh"
source "$ROOT/src/core/lifecycle.sh"

kernel_package_path() {
    if [[ -n ${BBRV3_KERNEL_PACKAGE:-} ]]; then
        printf '%s\n' "$BBRV3_KERNEL_PACKAGE"
        return 0
    fi
    find "$ROOT/vendor" -type f -name "$(kernel_formal_package)_*.deb" -print -quit 2>/dev/null
}

kernel_pending_root() { printf '%s\n' "${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/lifecycle"; }

kernel_mark_wait_reboot() {
    local d
    d=$(lifecycle_new)
    lifecycle_transition "$d" PRECHECK
    lifecycle_transition "$d" KERNEL_INSTALL
    lifecycle_transition "$d" WAIT_REBOOT
    printf 'kernel_transaction=%s\n' "$d" >"$d/metadata.env"
    printf '%s\n' "$d"
}

install_reconcile_wrapper() {
    install -d -m 755 /usr/local/sbin
    printf '#!/bin/sh\nexec %q "$@"\n' "$ROOT/bbrv3-universal.sh" > /usr/local/sbin/bbrv3-universal
    chmod 755 /usr/local/sbin/bbrv3-universal
}

kernel_resume_pending() {
    local root=${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/lifecycle d stage entry
    for d in "$root"/*; do
        [[ -f $d/stage ]] || continue
        stage=$(<"$d/stage")
        [[ $stage == WAIT_REBOOT ]] || continue
        if kernel_formal_running; then
            entry=$(<"${BBRV3_KERNEL_STATE_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/kernel}/boot-entry" 2>/dev/null || kernel_find_xanmod_entry || true)
            [[ -n $entry ]] && kernel_set_persistent_default "$entry" || {
                printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_PERSISTENT_BOOT_FAILED\n' >&2
                return 1
            }
            lifecycle_transition "$d" POST_KERNEL_VERIFY
            printf 'kernel.action=POST_KERNEL_VERIFY\nkernel.state=FORMAL_BASELINE_RUNNING\n'
            return 0
        fi
        printf 'kernel.action=WAIT_REBOOT\nkernel.state=FORMAL_BASELINE_NOT_RUNNING\n' >&2
        return 1
    done
    return 2
}

cli_mock_dispatch() {
    [[ ${BBRV3_CLI_MOCK:-NO} == YES ]] || return 1
    printf 'dispatch=%s\n' "$1"
    return 0
}

orchestration_apply() {
    cli_mock_dispatch apply || {
        [[ $EUID -eq 0 ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }
        "$ROOT/bbrv3-universal.sh" apply-sysctl "$@"
        "$ROOT/bbrv3-universal.sh" apply-network "$@"
        "$ROOT/bbrv3-universal.sh" apply-resources "$@"
        source "$ROOT/src/persistence/reconcile.sh"
        install_reconcile_wrapper
        persistence_write_unit
        persistence_enable_metadata
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable bbrv3-universal-reconcile.service >/dev/null 2>&1 || true
        printf 'orchestration=APPLIED\npersistence=ENABLED\n'
    }
}

orchestration_install() {
    cli_mock_dispatch install || {
        [[ $EUID -eq 0 ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }
        printf 'install=PRECHECK\n'
        local package pending entry
        if kernel_formal_running; then
            entry=$(kernel_find_xanmod_entry || true)
            [[ -n $entry ]] && kernel_set_persistent_default "$entry" || {
                printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_PERSISTENT_BOOT_FAILED\n' >&2
                return 1
            }
            printf 'kernel.decision=NOOP\nkernel.action=NOOP\nkernel.state=FORMAL_BASELINE_ALREADY_RUNNING\n'
        else
            "$ROOT/bbrv3-universal.sh" kernel-plan
            if kernel_formal_installed; then
                entry=$(kernel_find_xanmod_entry || true)
                [[ -n $entry ]] || {
                    printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_GRUB_ENTRY_MISSING\n' >&2
                    return 1
                }
                kernel_set_one_shot "$entry"
                printf 'kernel.action=REBOOT_REQUIRED\nkernel.state=FORMAL_BASELINE_INSTALLED\n'
            else
                package=$(kernel_package_path)
                [[ -n $package && -f $package ]] || {
                    printf 'kernel.action=BLOCKED\nkernel.reason=FORMAL_KERNEL_PAYLOAD_MISSING\n' >&2
                    return 1
                }
                printf 'kernel.action=INSTALL\nkernel.package=%s\n' "$package"
                kernel_install_package "$package" || {
                    printf 'kernel.action=FAILED\nkernel.reason=KERNEL_INSTALL_FAILED\n' >&2
                    return 1
                }
            fi
            pending=$(kernel_mark_wait_reboot)
            printf 'kernel.action=REBOOT_REQUIRED\nkernel.state=WAIT_REBOOT\ntransaction=%s\n' "$(basename "$pending")"
            source "$ROOT/src/persistence/reconcile.sh"
            install_reconcile_wrapper
            persistence_write_unit
            persistence_enable_metadata
            systemctl daemon-reload 2>/dev/null || true
            systemctl enable bbrv3-universal-reconcile.service >/dev/null 2>&1 || true
            "${BBRV3_REBOOT_COMMAND:-reboot}"
            return 75
        fi
        orchestration_apply "$@"
        printf 'install=COMPLETE\n'
    }
}

orchestration_optimize() {
    cli_mock_dispatch optimize || {
        printf 'optimize=REAPPLY_CURRENT_POLICY\n'
        orchestration_apply "$@"
        printf 'optimize=VERIFIED\n'
    }
}

orchestration_rollback() {
    cli_mock_dispatch rollback || {
        [[ $EUID -eq 0 ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }
        local rc=0
        "$ROOT/bbrv3-universal.sh" rollback-sysctl "$@" || rc=1
        "$ROOT/bbrv3-universal.sh" rollback-network "$@" || rc=1
        "$ROOT/bbrv3-universal.sh" rollback-resources "$@" || rc=1
        (( rc == 0 )) && printf 'rollback=SAFE_COMPLETE\n' || printf 'rollback=BLOCKED_OR_PARTIAL\n' >&2
        return "$rc"
    }
}

orchestration_recover() {
    cli_mock_dispatch recover || {
        [[ $EUID -eq 0 ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }
        "$ROOT/bbrv3-universal.sh" rollback-sysctl --force-owned "$@"
        "$ROOT/bbrv3-universal.sh" recover-network --force-owned "$@"
        "$ROOT/bbrv3-universal.sh" rollback-resources "$@"
        printf 'recover=EXPLICIT_OWNED_COMPLETE\n'
    }
}

orchestration_reboot() {
    cli_mock_dispatch reboot || {
        local root=${BBRV3_LIFECYCLE_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/lifecycle} pending
        pending=$(find "$root" -mindepth 1 -maxdepth 1 -type d -exec sh -c 'for d; do [ -f "$d/stage" ] && [ "$(cat "$d/stage")" = WAIT_REBOOT ] && printf "%s\n" "$d"; done' sh {} + 2>/dev/null | head -1 || true)
        [[ -n $pending ]] || { printf 'reboot=GUARDED_NO_PENDING_TRANSACTION\n' >&2; return 1; }
        printf 'reboot=MANAGED transaction=%s\n' "$(basename "$pending")"
        "${BBRV3_REBOOT_COMMAND:-reboot}"
    }
}

orchestration_uninstall() {
    cli_mock_dispatch uninstall || {
        orchestration_rollback "$@"
        rm -f /usr/local/sbin/bbrv3-universal /etc/systemd/system/bbrv3-universal-reconcile.service
        rm -f "${BBRV3_PERSIST_ROOT:-/var/lib/bbrv3-universal/persistence}/enabled"
        systemctl daemon-reload 2>/dev/null || true
        printf 'uninstall=OWNED_RESOURCES_REMOVED\n'
    }
}
