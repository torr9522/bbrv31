#!/usr/bin/env bash
set -euo pipefail
atomic_copy() {
    local source=$1 destination=$2 tmp
    mkdir -p "$(dirname "$destination")"
    tmp=$(mktemp "$(dirname "$destination")/.bbrv3-atomic.XXXXXX")
    chmod 0644 "$tmp"; cp "$source" "$tmp"; mv -f "$tmp" "$destination"
}
