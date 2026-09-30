#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/system-resource.sh"

swap_create_owned() {
    local d=$1 path=${BBRV3_SWAP_PATH:-/var/lib/bbrv3-universal/swapfile} size=${BBRV3_SWAP_SIZE_MB:-512}
    [[ ! -e $path ]] || return 2
    install -d -m 700 "$(dirname "$path")"; if command -v fallocate >/dev/null 2>&1; then fallocate -l "${size}M" "$path"; else dd if=/dev/zero of="$path" bs=1M count="$size" status=none; fi; chmod 600 "$path"; mkswap "$path" >"$d/swap-create.out"; swapon "$path" || return 1; printf '%s\n' "$path" >"$d/owned-swap.path"; local fstab=${BBRV3_FSTAB_PATH:-/etc/fstab}; printf '%s none swap sw 0 0 # bbrv3-universal\n' "$path" >>"$fstab"; printf 'CREATED\n' >"$d/swap.result"
}
swap_rollback_owned() { local d=$1; [[ -s $d/owned-swap.path ]] || return 0; local path; path=$(<"$d/owned-swap.path"); swapoff "$path" 2>/dev/null || true; local fstab=${BBRV3_FSTAB_PATH:-/etc/fstab}; [[ -f $fstab ]] && sed -i '\|# bbrv3-universal$|d' "$fstab"; rm -f "$path"; }
