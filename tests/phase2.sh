#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI=$ROOT/bbrv3-universal.sh
FIX=$ROOT/tests/fixtures

expect() { grep -qx "$2" <<<"$1" || { printf 'FAIL expected %s\n' "$2" >&2; return 1; }; }
run() { "$CLI" dry-run --fixture "$FIX/$1" --profile "${2:-auto}" --bandwidth "${3:-1000}" --detail; }

"$CLI" validate-data >/dev/null
[[ $(awk 'NR>1 {n++} END{print n+0}' "$ROOT/data/original-sysctl.tsv") -eq 31 ]]
[[ $(awk 'NR>1 {n++} END{print n+0}' "$ROOT/metadata/profile-metadata.tsv") -eq 8 ]]
[[ $(awk 'NR>1 {n++} END{print n+0}' "$ROOT/metadata/source-map.tsv") -ge 23 ]]
o=$(run debian12-kvm-1c953m-pfifo asia-original 1000)
expect "$o" 'buffer_original_mb=16'; expect "$o" 'memory_mode=512M_TO_LT_1G'; expect "$o" 'rps_rfs_policy=SKIP'; expect "$o" 'system_mutation=NO'
o=$(run debian12-kvm-1c953m-pfifo asia-original 500); expect "$o" 'buffer_original_mb=12'
o=$(run debian12-kvm-1c953m-pfifo overseas-original 1000); expect "$o" 'buffer_original_mb=64'
o=$(run debian12-kvm-1c953m-pfifo overseas-original 500); expect "$o" 'buffer_original_mb=32'
o=$(run debian12-kvm-1c953m-pfifo global 1000); expect "$o" 'profile=GLOBAL_MIXED'; expect "$o" 'buffer_original_mb=64'
o=$(run debian12-kvm-1c953m-pfifo compat-original 1000); expect "$o" 'profile=COMPAT_ORIGINAL'; expect "$o" 'buffer_original_mb=16'
o=$(run debian12-kvm-2c2g-mq auto 1000)
expect "$o" 'qdisc_policy=KEEP_MQ_AND_MANAGE_LEAF'; expect "$o" 'rps_rfs_policy=DEFAULT_SKIP'
o=$(run debian12-existing-cake auto 1000); expect "$o" 'qdisc_policy=BLOCK_AUTO'
o=$(run debian12-existing-htb auto 1000); expect "$o" 'qdisc_policy=BLOCK_AUTO'
o=$(run secureboot-enabled auto 1000); expect "$o" 'kernel_install_policy=BLOCKED'; expect "$o" 'kernel_block_reason=SECURE_BOOT_ENABLED'
o=$(run unsupported-arm64 auto 1000); expect "$o" 'platform_support=UNSUPPORTED'; expect "$o" 'kernel_compatibility=NO'
o=$(run unsupported-ubuntu auto 1000); expect "$o" 'platform_support=SUPPORTED_WITH_LIMITS'
o=$(run debian12-mss-forward-off auto 1000); expect "$o" 'mss_policy=SKIP'
o=$(run debian12-mss-forward-on auto 1000); expect "$o" 'mss_policy=CANDIDATE'
o=$(run debian12-thp-absent auto 1000); expect "$o" 'thp_policy=SKIP'
o=$(run debian12-nofile-xray auto 1000); expect "$o" 'nofile_policy=SERVICE_AWARE_CANDIDATE'
for ram in 512 1024 2048; do o=$("$CLI" dry-run --fixture "$FIX/debian12-kvm-1c953m-pfifo" --ram-mb "$ram" --cpu-count 1 --bandwidth 1000 --detail); grep -q '^system_mutation=NO$' <<<"$o"; done
for fixture in "$FIX"/*; do
  [[ -f $fixture/facts.env ]] || continue
  o=$("$CLI" dry-run --fixture "$fixture" --bandwidth 1000 --detail)
  grep -q '^system_mutation=NO$' <<<"$o"
done
# Mutation tripwire: Phase 2 source may not contain any write-style system command.
if rg -n -P --glob '*.sh' 'sysctl[[:space:]]+-w|sysctl[[:space:]]+-p|tc[[:space:]]+qdisc[[:space:]]+(add|change|replace|del)|ip[[:space:]]+route[[:space:]]+(add|change|replace|del)|iptables[[:space:]]+-[AIDF]|nft[[:space:]]+(add|delete|flush)|(^|[[:space:];])swapon[[:space:]]+(?!--show(?:=|[[:space:]]))|(^|[[:space:];])swapoff([[:space:]]|$)|(^|[[:space:];])mkswap([[:space:]]|$)|systemctl[[:space:]]+(enable|start|restart)|(^|[[:space:]])(reboot|shutdown)([[:space:]]|$)' "$ROOT/src/detect" "$ROOT/src/policy" "$ROOT/src/ui" "$ROOT/src/common.sh" "$ROOT/src/loader.sh" "$ROOT/src/dry-run.sh" "$ROOT/bbrv3-universal.sh"; then
  printf 'FAIL mutation command found\n' >&2; exit 1
fi
printf 'PASS phase2 integration and mutation tripwire\n'
