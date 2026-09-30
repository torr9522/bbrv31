#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/system-resource.sh"

swap_create_owned() {
    local d=$1 path=${BBRV3_SWAP_PATH:-/var/lib/bbrv3-universal/swapfile} size=${BBRV3_SWAP_SIZE_MB:-512}
    [[ ! -e $path ]] || return 2
    install -d -m 700 "$(dirname "$path")"; truncate -s "${size}M" "$path"; chmod 600 "$path"; mkswap "$path" >/"$d/swap-create.out"; swapon "$path"; printf '%s\n' "$path" >"$d/owned-swap.path"; printf 'CREATED\n' >"$d/swap.result"
}
swap_rollback_owned() { local d=$1; [[ -s $d/owned-swap.path ]] || return 0; local path; path=$(<"$d/owned-swap.path"); swapoff "$path" 2>/dev/null || true; rm -f "$path"; }
