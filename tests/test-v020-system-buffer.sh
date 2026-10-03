#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BUFFER_RE='^(net\.core\.(rmem_max|wmem_max)|net\.ipv4\.tcp_(rmem|wmem))='

new_env() {
    CASE=$TMP/$1; SYS=$CASE/sysroot; STATE=$CASE/state; VALUES=$CASE/values
    mkdir -p "$SYS/etc/sysctl.d" "$STATE"; : >"$SYS/etc/sysctl.conf"
    awk -F '\t' 'NR>1 {print $2"=0"}' "$ROOT/data/original-sysctl.tsv" >"$VALUES"
    sed -i \
      -e 's/^net.core.rmem_max=.*/net.core.rmem_max=212992/' \
      -e 's/^net.core.wmem_max=.*/net.core.wmem_max=425984/' \
      -e 's/^net.ipv4.tcp_rmem=.*/net.ipv4.tcp_rmem=4096 131072 6291456/' \
      -e 's/^net.ipv4.tcp_wmem=.*/net.ipv4.tcp_wmem=4096 16384 4194304/' "$VALUES"
    export BBRV3_UNIVERSAL_ROOT=$ROOT BBRV3_SYSCTL_ROOT=$SYS BBRV3_STATE_ROOT=$STATE
    export BBRV3_SYSCTL_BIN=$ROOT/tests/mock/fake-sysctl MOCK_SYSCTL_VALUES=$VALUES BBRV3_MOCK=1
    unset MOCK_FAIL_KEY MOCK_FAIL_WRITE_KEY MOCK_FAIL_WRITE_ONCE_KEY MOCK_READBACK_KEY MOCK_READBACK_VALUE || true
    CLI=$ROOT/bbrv3-universal.sh OWNED=$SYS/etc/sysctl.d/90-bbrv3-universal.conf
}
value() { awk -F= -v k="$1" '$1==k{print substr($0,index($0,"=")+1)}' "$VALUES"; }
assert_original_buffer() {
    [[ $(value net.core.rmem_max) == 212992 ]]
    [[ $(value net.core.wmem_max) == 425984 ]]
    [[ $(value net.ipv4.tcp_rmem) == '4096 131072 6291456' ]]
    [[ $(value net.ipv4.tcp_wmem) == '4096 16384 4194304' ]]
}
assert_system_owned() {
    [[ -f $OWNED ]]
    [[ $(grep -Ec '^[^#].*=' "$OWNED") == 27 ]]
    ! grep -Eq "$BUFFER_RE" "$OWNED"
}
apply_managed() { "$CLI" apply-sysctl --profile "$1" --bandwidth "${2:-1000}" --buffer-mib "$3" --ram-mb 4096 >/dev/null; }

# A fresh System selection captures evidence but never writes the four live values.
new_env fresh
before=$(sha256sum "$VALUES")
"$CLI" apply-sysctl --profile SYSTEM_DEFAULT --bandwidth 1000 --ram-mb 4096 >/dev/null
assert_original_buffer; assert_system_owned
[[ $(awk -F '\t' 'END{print NR-1}' "$STATE/buffer-baseline/baseline.tsv") == 4 ]]
baseline_hash=$(sha256sum "$STATE/buffer-baseline/baseline.tsv")
grep -qx LIVE_PRE_PROJECT "$STATE/buffer-baseline/source"
[[ $(awk -F= '$1=="net.core.somaxconn"{print $2}' "$VALUES") == 4096 ]]
[[ $before != "$(sha256sum "$VALUES")" ]]

# System -> Global reclaims all four; Global -> System restores the immutable original.
apply_managed GLOBAL_MIXED 7000 64
[[ $(value net.core.rmem_max) == 67108864 ]]
grep -Eq "$BUFFER_RE" "$OWNED"
[[ $baseline_hash == "$(sha256sum "$STATE/buffer-baseline/baseline.tsv")" ]]
"$CLI" apply-sysctl --profile SYSTEM_DEFAULT --bandwidth 7000 --ram-mb 4096 >/dev/null
assert_original_buffer; assert_system_owned
[[ $baseline_hash == "$(sha256sum "$STATE/buffer-baseline/baseline.tsv")" ]]
apply_managed GLOBAL_MIXED 7000 64
"$CLI" apply-sysctl --profile SYSTEM_DEFAULT --bandwidth 7000 --ram-mb 4096 >/dev/null
assert_original_buffer; assert_system_owned
[[ $baseline_hash == "$(sha256sum "$STATE/buffer-baseline/baseline.tsv")" ]]

# Each existing managed policy restores the same pre-project baseline.
for spec in 'ASIA_ORIGINAL 1000 16' 'OVERSEAS_ORIGINAL 700 48' 'GLOBAL_MIXED 7000 64'; do
    read -r profile bandwidth buffer <<<"$spec"; new_env "managed-${profile,,}"
    apply_managed "$profile" "$bandwidth" "$buffer"
    "$CLI" apply-sysctl --profile SYSTEM_DEFAULT --bandwidth "$bandwidth" --ram-mb 4096 >/dev/null
    assert_original_buffer; assert_system_owned
done

# v0.1.x migration accepts only the earliest transaction proving owned-file ABSENT.
new_env migration
apply_managed GLOBAL_MIXED 7000 64
rm -rf "$STATE/buffer-baseline"
"$CLI" apply-sysctl --profile SYSTEM_DEFAULT --bandwidth 7000 --ram-mb 4096 >/dev/null
assert_original_buffer
grep -q '^transaction:' "$STATE/buffer-baseline/source"

# Managed evidence without a trustworthy baseline blocks before any mutation.
new_env missing
cat >"$OWNED" <<'EOF'
# managed-by=bbrv3-universal
net.core.rmem_max=67108864
EOF
cp "$VALUES" "$CASE/before-values"; cp "$OWNED" "$CASE/before-owned"
if "$CLI" apply-sysctl --profile SYSTEM_DEFAULT --bandwidth 1000 --ram-mb 4096 >"$CASE/out" 2>"$CASE/err"; then exit 1; fi
grep -q MISSING_TRUSTED_BASELINE "$CASE/err"
cmp "$VALUES" "$CASE/before-values"; cmp "$OWNED" "$CASE/before-owned"

# A restore write failure rolls live values and the owned file back to Global.
new_env rollback
apply_managed GLOBAL_MIXED 7000 64
cp "$OWNED" "$CASE/global-owned"
MOCK_FAIL_WRITE_ONCE_KEY=net.ipv4.tcp_rmem; export MOCK_FAIL_WRITE_ONCE_KEY
if "$CLI" apply-sysctl --profile SYSTEM_DEFAULT --bandwidth 7000 --ram-mb 4096 >/dev/null 2>&1; then exit 1; fi
unset MOCK_FAIL_WRITE_ONCE_KEY
[[ $(value net.core.rmem_max) == 67108864 ]]
[[ $(value net.ipv4.tcp_rmem) == '4096 87380 67108864' ]]
cmp "$OWNED" "$CASE/global-owned"
latest=$(find "$STATE/transactions" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | awk 'NR==1{sub(/^[^ ]+ /,""); print}')
[[ $(<"$latest/state") == ROLLED_BACK ]]

# Reconcile carries System policy without a buffer value or write request.
fake_root=$TMP/reconcile-root; mkdir -p "$fake_root/src/persistence" "$TMP/reconcile-state/optimization"
cp "$ROOT/src/persistence/reconcile.sh" "$fake_root/src/persistence/reconcile.sh"
cat >"$fake_root/bbrv3-universal.sh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>'$TMP/reconcile.log'
EOF
chmod +x "$fake_root/bbrv3-universal.sh"
cat >"$TMP/reconcile-state/optimization/state.env" <<'EOF'
optimization_stage=APPLIED
detected_bandwidth_mbps=1000
profile=SYSTEM_DEFAULT
buffer_mib=N/A
buffer_policy=system
network_type=system
EOF
ROOT=$fake_root BBRV3_STATE_ROOT=$TMP/reconcile-state bash -c '. "$ROOT/src/persistence/reconcile.sh"; persistence_reconcile' >/dev/null
grep -qx 'apply-sysctl --profile SYSTEM_DEFAULT --bandwidth 1000' "$TMP/reconcile.log"
! grep -q buffer-mib "$TMP/reconcile.log"
grep -qx apply-network "$TMP/reconcile.log"; grep -qx apply-resources "$TMP/reconcile.log"

# Menu dispatch, default Global, and System has no recommendation prompt.
source "$ROOT/src/tuning-input.sh"
tuning_is_interactive() { return 0; }
TUNING_REQUESTED_REGION= tuning_choose_region <<<'4'
[[ $TUNING_REGION == system && $TUNING_PROFILE == SYSTEM_DEFAULT ]]
TUNING_BANDWIDTH=1000 TUNING_REGION=system TUNING_BUFFER_ACCEPT=ask
tuning_choose_buffer >"$TMP/system-buffer.out" 2>&1
[[ ! -s $TMP/system-buffer.out && $TUNING_BUFFER == N/A ]]
TUNING_REQUESTED_REGION= tuning_choose_region <<<' '
[[ $TUNING_REGION == global && $TUNING_PROFILE == GLOBAL_MIXED ]]

printf 'PASS v0.2.0 System TCP Buffer ownership, baseline, rollback and persistence contracts\n'
