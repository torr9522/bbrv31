#!/usr/bin/env bash
set -euo pipefail

ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

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
        install -d -m 755 /usr/local/sbin
        printf '#!/bin/sh\nexec %q "$@"\n' "$ROOT/bbrv3-universal.sh" > /usr/local/sbin/bbrv3-universal
        chmod 755 /usr/local/sbin/bbrv3-universal
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
        "$ROOT/bbrv3-universal.sh" kernel-plan
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
