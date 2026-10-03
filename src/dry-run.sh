#!/usr/bin/env bash
set -euo pipefail

ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$ROOT/src/loader.sh"

usage() { printf 'usage: %s --profile asia|overseas --bandwidth Mbps --ram-mb MB --cpu-count N\n' "$0"; }
profile=asia bandwidth=0 ram_mb=0 cpu_count=1
while [[ $# -gt 0 ]]; do
  case $1 in
    --profile) profile=$2; shift 2;;
    --bandwidth) bandwidth=$2; shift 2;;
    --ram-mb) ram_mb=$2; shift 2;;
    --cpu-count) cpu_count=$2; shift 2;;
    *) usage >&2; exit 2;;
  esac
done
[[ $profile == asia || $profile == overseas ]] || { usage >&2; exit 2; }
[[ $bandwidth =~ ^[0-9]+$ && $bandwidth -gt 0 && $ram_mb =~ ^[0-9]+$ && $ram_mb -gt 0 && $cpu_count =~ ^[0-9]+$ && $cpu_count -gt 0 ]] || { usage >&2; exit 2; }
load_validate >/dev/null

buffer=0
if [[ $profile == asia ]]; then
  case $bandwidth in
    100) buffer=6;; 200) buffer=8;; 300) buffer=10;; 500) buffer=12;; 700) buffer=14;;
    1000) buffer=16;; 1500) buffer=20;; 2000) buffer=24;; 2500) buffer=28;;
    *) if (( bandwidth < 500 )); then buffer=8; elif (( bandwidth < 1000 )); then buffer=12; elif (( bandwidth < 2000 )); then buffer=16; elif (( bandwidth < 5000 )); then buffer=24; elif (( bandwidth < 10000 )); then buffer=28; else buffer=32; fi;;
  esac
else
  case $bandwidth in
    100) buffer=8;; 200) buffer=16;; 300) buffer=20;; 500) buffer=32;; 700) buffer=48;;
    1000|1500|2000|2500) buffer=64;;
    *) if (( bandwidth < 500 )); then buffer=16; elif (( bandwidth < 1000 )); then buffer=48; else buffer=64; fi;;
  esac
fi
if (( ram_mb < 2048 )); then vm_swappiness=20; vm_dirty_ratio=20; vm_min_free_kbytes=32768; low_memory=YES; else vm_swappiness=5; vm_dirty_ratio=15; vm_min_free_kbytes=65536; low_memory=NO; fi
(( cpu_count > 1 )) && rps_rfs=CONSIDER || rps_rfs=SKIP
printf 'profile=%s\nbandwidth_mbps=%s\nbuffer_mb=%s\nram_mb=%s\nlow_memory=%s\nvm.swappiness=%s\nvm.dirty_ratio=%s\nvm.min_free_kbytes=%s\nrps_rfs=%s\nsysctl_count=31\nsystem_mutation=NO\n' "$profile" "$bandwidth" "$buffer" "$ram_mb" "$low_memory" "$vm_swappiness" "$vm_dirty_ratio" "$vm_min_free_kbytes" "$rps_rfs"
