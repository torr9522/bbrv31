#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
SYS=$TMP/sysroot STATE=$TMP/state VALUES=$TMP/values
mkdir -p "$SYS/etc/sysctl.d" "$STATE"
: >"$SYS/etc/sysctl.conf"
cat >"$VALUES" <<'EOF'
net.core.default_qdisc=pfifo_fast
net.ipv4.tcp_congestion_control=cubic
net.core.rmem_max=212992
net.core.wmem_max=212992
net.ipv4.tcp_rmem=4096 87380 212992
net.ipv4.tcp_wmem=4096 16384 212992
net.ipv4.tcp_tw_reuse=0
net.ipv4.ip_local_port_range=32768 60999
net.core.somaxconn=128
net.ipv4.tcp_max_syn_backlog=128
net.core.netdev_max_backlog=1000
net.ipv4.tcp_slow_start_after_idle=1
net.ipv4.tcp_mtu_probing=0
net.ipv4.tcp_notsent_lowat=4294967295
net.ipv4.tcp_fin_timeout=60
net.ipv4.tcp_max_tw_buckets=262144
net.ipv4.tcp_fastopen=1
net.ipv4.tcp_keepalive_time=7200
net.ipv4.tcp_keepalive_intvl=75
net.ipv4.tcp_keepalive_probes=9
net.ipv4.udp_rmem_min=4096
net.ipv4.udp_wmem_min=4096
net.ipv4.tcp_syncookies=1
vm.swappiness=60
vm.dirty_ratio=20
vm.dirty_background_ratio=10
vm.overcommit_memory=0
vm.min_free_kbytes=67584
vm.vfs_cache_pressure=100
kernel.sched_autogroup_enabled=1
kernel.numa_balancing=1
EOF
export BBRV3_UNIVERSAL_ROOT=$ROOT BBRV3_SYSCTL_ROOT=$SYS BBRV3_STATE_ROOT=$STATE BBRV3_SYSCTL_BIN=$ROOT/tests/mock/fake-sysctl MOCK_SYSCTL_VALUES=$VALUES BBRV3_MOCK=1
CLI=$ROOT/bbrv3-universal.sh
plan=$($CLI plan-sysctl --profile ASIA_ORIGINAL --bandwidth 1000 --ram-mb 953)
grep -q 'sysctl_count=31' <<<"$plan"
apply=$($CLI apply-sysctl --profile ASIA_ORIGINAL --bandwidth 1000 --ram-mb 953)
grep -q 'PASS apply' <<<"$apply"
owned=$SYS/etc/sysctl.d/90-bbrv3-universal.conf
grep -q '^# managed-by=bbrv3-universal$' "$owned"
[[ $(awk -F= '$1=="net.core.rmem_max"{print $2}' "$VALUES") == 16777216 ]]
second=$($CLI apply-sysctl --profile ASIA_ORIGINAL --bandwidth 1000 --ram-mb 953); grep -q NOOP <<<"$second"
printf '# external drift\n' >>"$owned"
if $CLI rollback-sysctl >/tmp/phase3-drift.out 2>/tmp/phase3-drift.err; then exit 1; fi
grep -q FILE_DRIFT /tmp/phase3-drift.err
sed -i '$d' "$owned"
$CLI rollback-sysctl >/tmp/phase3-rollback.out
grep -q 'PASS rollback' /tmp/phase3-rollback.out
[[ ! -e $owned ]]
[[ $(awk -F= '$1=="net.core.default_qdisc"{print $2}' "$VALUES") == pfifo_fast ]]

global_apply=$($CLI apply-sysctl --profile GLOBAL_MIXED --bandwidth 7000 --buffer-mib 64 --ram-mb 4096)
grep -q 'PASS apply' <<<"$global_apply"
grep -q '^# profile=GLOBAL_MIXED$' "$owned"
[[ $(awk -F= '$1=="net.core.rmem_max"{print $2}' "$VALUES") == 67108864 ]]
global_verify=$($CLI verify-sysctl --profile GLOBAL_MIXED --bandwidth 7000 --buffer-mib 64 --ram-mb 4096)
[[ $(awk -F '\t' 'NR>1 && $4=="MATCH"{n++} END{print n+0}' <<<"$global_verify") == 31 ]]
$CLI rollback-sysctl >/tmp/v0110-global-rollback.out
grep -q 'PASS rollback' /tmp/v0110-global-rollback.out
[[ ! -e $owned ]]
[[ $(awk -F= '$1=="net.core.rmem_max"{print $2}' "$VALUES") == 212992 ]]
printf 'PASS mock apply/verify/idempotency/drift/rollback\n'
