#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
new_env() {
  unset MOCK_FAIL_KEY MOCK_FAIL_WRITE_KEY MOCK_READBACK_KEY MOCK_READBACK_VALUE || true
  TMP=$(mktemp -d); SYS=$TMP/sysroot; STATE=$TMP/state; VALUES=$TMP/values
  mkdir -p "$SYS/etc/sysctl.d" "$STATE"; : >"$SYS/etc/sysctl.conf"
  awk -F '\t' 'NR>1 {print $2"=0"}' "$ROOT/data/original-sysctl.tsv" >"$VALUES"
  export BBRV3_UNIVERSAL_ROOT=$ROOT BBRV3_SYSCTL_ROOT=$SYS BBRV3_STATE_ROOT=$STATE BBRV3_SYSCTL_BIN=$ROOT/tests/mock/fake-sysctl MOCK_SYSCTL_VALUES=$VALUES BBRV3_MOCK=1
  CLI=$ROOT/bbrv3-universal.sh
}
new_env
printf 'net.core.somaxconn=4096\n' >"$SYS/etc/sysctl.d/95-same.conf"
out=$($CLI plan-sysctl --profile ASIA_ORIGINAL --bandwidth 1000)
grep -q SAME_VALUE <<<"$out"
printf 'PASS same-value conflict\n'
new_env
printf 'net.core.somaxconn=1\n' >"$SYS/etc/sysctl.d/50-low.conf"
out=$($CLI plan-sysctl --profile ASIA_ORIGINAL --bandwidth 1000)
grep -q DIFFERENT_VALUE_LOWER_PRIORITY <<<"$out"
printf 'PASS lower-priority warning\n'
new_env
printf 'net.core.somaxconn=1\n' >"$SYS/etc/sysctl.d/95-high.conf"
if $CLI apply-sysctl --profile ASIA_ORIGINAL --bandwidth 1000 >/dev/null 2>/tmp/p3-high.err; then exit 1; fi
grep -q BLOCKING_CONFLICT /tmp/p3-high.err
[[ ! -e "$SYS/etc/sysctl.d/90-bbrv3-universal.conf" ]]
printf 'PASS higher-priority conflict\n'
new_env
printf '# foreign\nnet.core.somaxconn=1\n' >"$SYS/etc/sysctl.d/90-bbrv3-universal.conf"
if $CLI apply-sysctl --profile ASIA_ORIGINAL --bandwidth 1000 >/dev/null 2>/tmp/p3-foreign.err; then exit 1; fi
grep -q BLOCKING_CONFLICT /tmp/p3-foreign.err
printf 'PASS foreign owned path\n'
new_env
MOCK_FAIL_KEY=net.core.somaxconn; export MOCK_FAIL_KEY
if $CLI apply-sysctl --profile ASIA_ORIGINAL --bandwidth 1000 >/dev/null; then exit 1; fi
latest=$(find "$STATE/transactions" -mindepth 1 -maxdepth 1 -type d | sort | head -1); [[ $(<"$latest/state") == ROLLED_BACK ]]
printf 'PASS partial failure rollback\n'
new_env
MOCK_READBACK_KEY=net.core.somaxconn MOCK_READBACK_VALUE=999; export MOCK_READBACK_KEY MOCK_READBACK_VALUE
if $CLI apply-sysctl --profile ASIA_ORIGINAL --bandwidth 1000 >/dev/null; then exit 1; fi
printf 'PASS readback mismatch rollback\n'
new_env
awk -F= '$1!="kernel.numa_balancing"' "$VALUES" >"$VALUES.new"; mv -f "$VALUES.new" "$VALUES"
out=$($CLI verify-sysctl --profile ASIA_ORIGINAL --bandwidth 1000)
grep -q $'kernel.numa_balancing\t0\tUNAVAILABLE\tUNSUPPORTED' <<<"$out"
printf 'PASS unsupported key classification\n'
new_env
$CLI apply-sysctl --profile ASIA_ORIGINAL --bandwidth 1000 >/dev/null
sed -i 's/^net.core.somaxconn=.*/net.core.somaxconn=999/' "$VALUES"
if $CLI rollback-sysctl >/dev/null 2>/tmp/p3-runtime-drift.err; then exit 1; fi
grep -q RUNTIME_DRIFT /tmp/p3-runtime-drift.err
sed -i 's/^net.core.somaxconn=.*/net.core.somaxconn=4096/' "$VALUES"
$CLI rollback-sysctl >/dev/null
printf 'PASS runtime drift block\n'
new_env
$CLI apply-sysctl --profile ASIA_ORIGINAL --bandwidth 1000 >/dev/null
latest=$(find "$STATE/transactions" -mindepth 1 -maxdepth 1 -type d | sort | tail -1); printf APPLYING >"$latest/state"
$CLI recover-sysctl >/tmp/p3-recover.out
grep -q 'PASS rollback' /tmp/p3-recover.out
printf 'PASS unfinished transaction recovery\n'
printf 'PASS conflict/failure/recovery scenarios\n'
