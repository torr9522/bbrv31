#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); source "$ROOT/src/policy/kernel-plan.sh"
grep -qx 'kernel.decision=CANDIDATE' <(kernel_policy debian 12 amd64 x86-64-v3 disabled KVM)
grep -qx 'kernel.reason=CPU_BELOW_X64V3' <(kernel_policy debian 12 amd64 x86-64-v2 disabled KVM)
grep -qx 'kernel.reason=SECURE_BOOT_ENABLED' <(kernel_policy debian 12 amd64 x86-64-v3 enabled KVM)
grep -q 'update-initramfs -u -k all' "$ROOT/src/apply/kernel.sh"
printf 'PASS kernel policy/preflight fixtures\n'
