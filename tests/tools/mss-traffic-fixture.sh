#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STATE=$(mktemp -d)
FIX=$(mktemp -d)
L=bbrv3-mss-l
R=bbrv3-mss-r
cleanup() {
  set +e
  kill "${HTTP_PID:-}" 2>/dev/null || true
  ip netns del "$L" 2>/dev/null || true
  ip netns del "$R" 2>/dev/null || true
  rm -rf "$STATE" "$FIX"
}
trap cleanup EXIT
ip netns add "$L"
ip netns add "$R"
ip link add bbrv3-mss-l type veth peer name bbrv3-mss-lr
ip link add bbrv3-mss-rr type veth peer name bbrv3-mss-r
ip link set bbrv3-mss-l netns "$L"
ip link set bbrv3-mss-r netns "$R"
ip link set bbrv3-mss-lr netns "$R"
ip link set bbrv3-mss-rr netns "$R"
ip netns exec "$L" ip link set lo up
ip netns exec "$L" ip link set bbrv3-mss-l up
ip netns exec "$L" ip addr add 10.200.1.2/24 dev bbrv3-mss-l
ip netns exec "$L" ip route add 10.200.2.0/24 via 10.200.1.1
ip netns exec "$R" ip link set lo up
ip netns exec "$R" ip link set bbrv3-mss-r up
ip netns exec "$R" ip link set bbrv3-mss-lr up
ip netns exec "$R" ip link set bbrv3-mss-rr up
ip netns exec "$R" ip addr add 10.200.2.2/24 dev bbrv3-mss-r
ip netns exec "$R" ip addr add 10.200.1.1/24 dev bbrv3-mss-lr
ip netns exec "$R" ip addr add 10.200.2.1/24 dev bbrv3-mss-rr
ip netns exec "$R" sysctl -qw net.ipv4.ip_forward=1
cat >"$FIX/facts.env" <<EOF
route.current=default via 10.200.1.1 dev bbrv3-mss-lr initcwnd 32 initrwnd 32
qdisc.root=fq
qdisc.mq_root=NO
qdisc.fq_present=YES
qdisc.cake_present=NO
qdisc.htb_present=NO
qdisc.tbf_present=NO
qdisc.filters=NO
qdisc.classes=NO
cpu.count=2
network.rx_queue_count=1
network.rss=NO
capability.ip_forward=1
capability.iptables_backend=nft-only
EOF
set +e
ip netns exec "$R" env BBRV3_NETWORK_STATE_ROOT="$STATE" BBRV3_NETWORK_FACTS="$FIX/facts.env" "$ROOT/bbrv3-universal.sh" plan-network --fixture "$FIX" >"$FIX/plan.out" 2>&1
cat "$FIX/plan.out"
ip netns exec "$R" env BBRV3_UNIVERSAL_ROOT="$ROOT" BBRV3_NETWORK_STATE_ROOT="$STATE" BBRV3_NETWORK_FACTS="$FIX/facts.env" "$ROOT/src/network-cli.sh" apply-network --fixture "$FIX" --detail >"$FIX/apply.out" 2>&1
apply_rc=$?
set -e
cat "$FIX/apply.out"
[[ $apply_rc == 0 ]] || { echo "apply_rc=$apply_rc" >&2; exit $apply_rc; }
tx=$(find "$STATE/transactions" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)
ip netns exec "$R" python3 -m http.server 18080 --directory / >/dev/null 2>&1 & HTTP_PID=$!
sleep 1
ip netns exec "$L" curl -fsS --max-time 3 http://10.200.2.2:18080/ >/dev/null
printf 'PASS product-owned MSS forwarding traffic\n'
cat "$FIX/apply.out"
ip netns exec "$R" env BBRV3_NETWORK_STATE_ROOT="$STATE" BBRV3_NETWORK_FACTS="$FIX/facts.env" "$ROOT/bbrv3-universal.sh" rollback-network --transaction "$(basename "$tx")" >/dev/null
printf 'PASS product-owned MSS rollback\n'
