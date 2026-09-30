#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export BBRV3_UNIVERSAL_ROOT=$ROOT
source "$ROOT/src/common.sh"
source "$ROOT/src/detect/cpu.sh"
source "$ROOT/src/detect/memory.sh"
source "$ROOT/src/policy/rps-rfs.sh"
source "$ROOT/src/policy/network.sh"
source "$ROOT/src/policy/system.sh"

[[ $(memory_class 400) == LT_512M ]]
[[ $(memory_class 512) == 512M_TO_LT_1G ]]
[[ $(memory_class 1024) == 1G_TO_LT_2G ]]
[[ $(memory_class 2048) == 2G_TO_LT_4G ]]
[[ $(memory_class 4096) == GE_4G ]]
cpu_has_all ' cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3 ' cx16 lahf_lm
! cpu_has_all ' cx16 ' avx2
[[ $(cpu_level_from_flags x86_64 'cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3') == x86-64-v2 ]]
[[ $(cpu_level_from_flags x86_64 'cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3 avx avx2 bmi1 bmi2 f16c fma abm movbe xsave') == x86-64-v3 ]]
[[ $(cpu_level_from_flags aarch64 '') == arm64 ]]
out=$(policy_rps_rfs 1 4 PRESENT); grep -qx 'rps_rfs_policy=SKIP' <<<"$out"
out=$(policy_rps_rfs 2 1 UNAVAILABLE); grep -qx 'rps_rfs_policy=CANDIDATE' <<<"$out"
out=$(policy_rps_rfs 2 4 PRESENT); grep -qx 'rps_rfs_policy=DEFAULT_SKIP' <<<"$out"
out=$(policy_network 0 YES pfifo_fast NO NO NO NO NO NO NO); grep -qx 'mss_policy=SKIP' <<<"$out"
out=$(policy_network 1 YES pfifo_fast NO NO NO NO NO NO NO); grep -qx 'mss_policy=CANDIDATE' <<<"$out"
out=$(policy_network 0 YES cake YES NO NO NO NO NO NO); grep -qx 'qdisc_policy=BLOCK_AUTO' <<<"$out"
out=$(policy_system always '' enabled amd64 debian 12 x86-64-v3); grep -qx 'kernel_install_policy=BLOCKED' <<<"$out"; grep -qx 'kernel_block_reason=SECURE_BOOT_ENABLED' <<<"$out"
printf 'PASS unit detection and policy assertions\n'
