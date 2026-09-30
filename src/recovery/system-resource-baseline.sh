#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/system-resource.sh"
system_resource_baseline() {
    local d=$1 p=${BBRV3_THP_PATH:-/sys/kernel/mm/transparent_hugepage/enabled}; cat "$p" >"$d/thp.baseline" 2>/dev/null || : >"$d/thp.baseline"
    ulimit -n >"$d/nofile.shell"; cat /proc/sys/fs/file-max >"$d/nofile.filemax" 2>/dev/null || true; cat /proc/sys/fs/nr_open >"$d/nofile.nr_open" 2>/dev/null || true
    swapon --show=NAME,TYPE,SIZE,PRIO --bytes >"$d/swap.baseline" 2>/dev/null || : >"$d/swap.baseline"
    sha256sum "$d/thp.baseline" "$d/nofile.shell" "$d/swap.baseline" >"$d/baseline.sha256"
}
