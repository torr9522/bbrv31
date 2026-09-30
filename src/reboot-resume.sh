#!/usr/bin/env bash
set -euo pipefail
ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$ROOT/src/core/lifecycle.sh"
resume_start() { local d; d=$(lifecycle_new); lifecycle_transition "$d" PRECHECK; printf 'transaction=%s\nstage=PRECHECK\nretry_count=0\nreboot_count=0\n' "$(basename "$d")" >"$d/metadata.env"; printf '%s\n' "$d"; }
resume_set_stage() { local d=$1 stage=$2; lifecycle_transition "$d" "$stage"; }
resume_status() { local d=${1:?}; printf 'transaction=%s\nstage=%s\n' "$(basename "$d")" "$(<"$d/stage")"; }
case ${1:-status} in start) resume_start;; transition) resume_set_stage "$2" "$3";; status) resume_status "$2";; *) exit 2;; esac
