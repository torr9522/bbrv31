#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

source "$ROOT/src/tuning-input.sh"

check_buffer() { [[ $(tuning_buffer_value "$1" "$2") == "$3" ]]; }

# v0.1.9 Asia and Overseas values are immutable compatibility contracts.
for row in '100 6' '200 8' '300 10' '500 12' '700 14' '1000 16' '1500 20' '2000 24' '2500 28' '499 8' '999 12' '1999 16' '4999 24' '9999 28' '10000 32' 'bad 16' '0 16'; do
    read -r bw expected <<<"$row"; check_buffer "$bw" asia "$expected"
done
for row in '100 8' '200 16' '300 20' '500 32' '700 48' '1000 64' '1500 64' '2000 64' '2500 64' '499 16' '999 48' '1001 64' 'bad 64' '0 64'; do
    read -r bw expected <<<"$row"; check_buffer "$bw" overseas "$expected"
done
TUNING_BANDWIDTH=824 TUNING_REGION=asia TUNING_BUFFER_ACCEPT=no tuning_choose_buffer
[[ $TUNING_BUFFER == 16 ]]
TUNING_BANDWIDTH=824 TUNING_REGION=overseas TUNING_BUFFER_ACCEPT=no tuning_choose_buffer
[[ $TUNING_BUFFER == 32 ]]

# Global is a distinct semantic that reuses the exact Overseas curve.
for row in '100 8' '200 16' '300 20' '500 32' '700 48' '1000 64' '1500 64' '2000 64' '2500 64' '499 16' '999 48' '1001 64' '7000 64' 'bad 64' '0 64'; do
    read -r bw expected <<<"$row"; check_buffer "$bw" global "$expected"
done
TUNING_BANDWIDTH=824 TUNING_REGION=global TUNING_BUFFER_ACCEPT=no tuning_choose_buffer
[[ $TUNING_BUFFER == 32 ]]

cat >"$TMP/speedtest" <<'EOF'
#!/bin/sh
case " $* " in
  *' --servers '*) printf ' 1234) Nearby One\n 5678) Nearby Two\n';;
  *' --server-id=9001 '*) printf 'Server: Manual\nDownload: 500.50 Mbps\nUpload: 900.25 Mbps\n';;
  *) printf 'Server: Auto\nDownload: %s Mbps\nUpload: %s Mbps\n' "${MOCK_DOWNLOAD:-800.75}" "${MOCK_UPLOAD:-600.25}";;
esac
EOF
chmod +x "$TMP/speedtest"

TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_run_speedtest
TUNING_REGION=global tuning_finalize_bandwidth
[[ $TUNING_DOWNLOAD_MBPS == 800 && $TUNING_UPLOAD_MBPS == 600 && $TUNING_EFFECTIVE_MBPS == 800 && $TUNING_BANDWIDTH == 800 ]]

MOCK_DOWNLOAD=500 MOCK_UPLOAD=900 TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_run_speedtest
TUNING_REGION=global tuning_finalize_bandwidth
[[ $TUNING_EFFECTIVE_MBPS == 900 ]]

# Asia and Overseas retain the v0.1.9 upload-only bandwidth input.
MOCK_DOWNLOAD=900 MOCK_UPLOAD=500 TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_run_speedtest
TUNING_REGION=asia tuning_finalize_bandwidth
[[ $TUNING_EFFECTIVE_MBPS == 500 && $TUNING_BANDWIDTH == 500 ]]
MOCK_DOWNLOAD=900 MOCK_UPLOAD=500 TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_run_speedtest
TUNING_REGION=overseas tuning_finalize_bandwidth
[[ $TUNING_EFFECTIVE_MBPS == 500 && $TUNING_BANDWIDTH == 500 ]]

MOCK_DOWNLOAD=7000 MOCK_UPLOAD=6500 TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_run_speedtest
TUNING_REGION=global tuning_finalize_bandwidth
[[ $TUNING_EFFECTIVE_MBPS == 7000 && $(tuning_buffer_value "$TUNING_EFFECTIVE_MBPS" global) == 64 ]]

MOCK_DOWNLOAD=invalid MOCK_UPLOAD=700 TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_run_speedtest
TUNING_REGION=global tuning_finalize_bandwidth
[[ $TUNING_EFFECTIVE_MBPS == 700 ]]

rc=0
MOCK_DOWNLOAD=500 MOCK_UPLOAD=invalid TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_run_speedtest || rc=$?
[[ $rc == 2 ]]
TUNING_REGION=global tuning_finalize_bandwidth
[[ $TUNING_EFFECTIVE_MBPS == 500 ]]

rc=0
MOCK_DOWNLOAD=invalid MOCK_UPLOAD=invalid TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_run_speedtest || rc=$?
[[ $rc != 0 ]]

MOCK_DOWNLOAD=invalid MOCK_UPLOAD=invalid TUNING_BANDWIDTH_MODE=auto TUNING_SPEEDTEST_BIN="$TMP/speedtest" BBRV3_NONINTERACTIVE=YES tuning_choose_bandwidth
TUNING_REGION=global tuning_finalize_bandwidth
[[ $TUNING_BANDWIDTH_SOURCE == FALLBACK_1000 && $TUNING_EFFECTIVE_MBPS == 1000 && $(tuning_buffer_value "$TUNING_EFFECTIVE_MBPS" global) == 64 ]]

TUNING_BANDWIDTH_MODE=server TUNING_SERVER_ID=9001 TUNING_REQUESTED_BANDWIDTH= TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_choose_bandwidth
TUNING_REGION=global tuning_finalize_bandwidth
[[ $TUNING_DOWNLOAD_MBPS == 500 && $TUNING_UPLOAD_MBPS == 900 && $TUNING_EFFECTIVE_MBPS == 900 ]]

TUNING_BANDWIDTH_MODE=manual TUNING_REQUESTED_BANDWIDTH=500 tuning_choose_bandwidth
TUNING_REGION=global tuning_finalize_bandwidth
[[ $TUNING_EFFECTIVE_MBPS == 500 && $TUNING_DOWNLOAD_MBPS == N/A && $TUNING_UPLOAD_MBPS == N/A && $(tuning_buffer_value "$TUNING_EFFECTIVE_MBPS" global) == 32 ]]

tuning_is_interactive() { return 0; }
TUNING_REQUESTED_REGION= tuning_choose_region <<<''
[[ $TUNING_REGION == global && $TUNING_PROFILE == GLOBAL_MIXED ]]

TUNING_REGION=global TUNING_BUFFER=64 BBRV3_MEMORY_MB=2047
warning=$(tuning_low_memory_global_guard <<<'y' 2>&1)
grep -q '内存低于 2 GiB' <<<"$warning"
TUNING_REGION=global TUNING_BUFFER=64 BBRV3_MEMORY_MB=2047
if tuning_low_memory_global_guard <<<'n' >/dev/null; then exit 1; fi
TUNING_REGION=global TUNING_BUFFER=64 BBRV3_MEMORY_MB=2048
[[ -z $(tuning_low_memory_global_guard) ]]

tuning_is_interactive() { return 1; }
TUNING_REGION=global TUNING_BUFFER=64 BBRV3_MEMORY_MB=1024 TUNING_ACCEPT_LOW_MEMORY_GLOBAL=NO
if tuning_low_memory_global_guard >/dev/null 2>&1; then exit 1; fi
TUNING_ACCEPT_LOW_MEMORY_GLOBAL=YES tuning_low_memory_global_guard >/dev/null

# An interactive decline returns to network type selection and performs no apply.
tuning_choose_swap() { TUNING_CREATE_SWAP=NO; TUNING_SWAP_SIZE=0; TUNING_SWAP_STATUS=SKIP; }
tuning_choose_bandwidth() { TUNING_BANDWIDTH=500; TUNING_EFFECTIVE_MBPS=500; TUNING_BANDWIDTH_SOURCE=MANUAL_VALUE; TUNING_DOWNLOAD_MBPS=N/A; TUNING_UPLOAD_MBPS=N/A; }
tuning_is_interactive() { return 0; }
TUNING_REQUESTED_REGION= TUNING_BUFFER_ACCEPT=yes BBRV3_MEMORY_MB=1024
tuning_collect_inputs <<<'3
n
1'
[[ $TUNING_REGION == asia && $TUNING_PROFILE == ASIA_ORIGINAL && $TUNING_BUFFER == 12 ]]

plan="$TMP/global-31.tsv"
BBRV3_PROJECT_ROOT="$ROOT" REQUESTED_PROFILE=GLOBAL_MIXED REQUESTED_BANDWIDTH=7000 REQUESTED_BUFFER_MB=64 REQUESTED_RAM_MB=4096 "$ROOT/src/policy/sysctl-plan.sh" --output "$plan"
[[ $(awk 'NR>1{n++} END{print n}' "$plan") == 31 ]]
grep -qx 'profile=GLOBAL_MIXED' "$plan.meta"
grep -q $'^net.core.rmem_max\t67108864\t' "$plan"
grep -q $'^net.core.wmem_max\t67108864\t' "$plan"
grep -q $'^net.ipv4.tcp_rmem\t4096 87380 67108864\t' "$plan"
grep -q $'^net.ipv4.tcp_wmem\t4096 65536 67108864\t' "$plan"

source "$ROOT/src/orchestration.sh"
kernel_formal_running() { return 0; }
orchestration_apply_policy() {
    mkdir -p "$(state_root)/optimization"
    printf 'optimization_stage=APPLIED\nprofile=%s\nbuffer_mib=%s\n' "$1" "$3" >"$(state_root)/optimization/state.env"
    printf 'apply\n' >>"$TMP/apply.log"
}
rc=0
BBRV3_STATE_ROOT="$TMP/blocked-state" BBRV3_MEMORY_MB=1024 BBRV3_SWAP_PRESENT=YES orchestration_optimize --non-interactive --bandwidth 500 --region global >"$TMP/blocked.out" 2>&1 || rc=$?
[[ $rc != 0 && ! -e $TMP/apply.log ]]
grep -q 'GLOBAL_LOW_MEMORY_NOT_ACCEPTED' "$TMP/blocked.out"

BBRV3_STATE_ROOT="$TMP/accepted-state" BBRV3_MEMORY_MB=1024 BBRV3_SWAP_PRESENT=YES orchestration_optimize --non-interactive --bandwidth 500 --region global --accept-low-memory-global >"$TMP/accepted.out" 2>&1
[[ $(wc -l <"$TMP/apply.log") == 1 ]]
state="$TMP/accepted-state/optimization/state.env"
grep -qx 'profile=GLOBAL_MIXED' "$state"
grep -qx 'network_type=global' "$state"
grep -qx 'download_mbps=N/A' "$state"
grep -qx 'upload_mbps=N/A' "$state"
grep -qx 'effective_mbps=500' "$state"
grep -qx 'buffer_mib=32' "$state"

# Reconcile reuses the Global profile/effective bandwidth/buffer and preserves metadata.
fake_root="$TMP/fake-root"
mkdir -p "$fake_root/src/persistence" "$TMP/reconcile-state/optimization"
cp "$ROOT/src/persistence/reconcile.sh" "$fake_root/src/persistence/reconcile.sh"
cat >"$fake_root/bbrv3-universal.sh" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >>'$TMP/reconcile.log'
EOF
chmod +x "$fake_root/bbrv3-universal.sh"
cat >"$TMP/reconcile-state/optimization/state.env" <<'EOF'
optimization_stage=APPLIED
detected_bandwidth_mbps=7000
profile=GLOBAL_MIXED
buffer_mib=64
region=global
network_type=global
bandwidth_source=AUTO_SPEEDTEST
download_mbps=7000
upload_mbps=6500
effective_mbps=7000
speedtest_server=1234
EOF
ROOT="$fake_root" BBRV3_STATE_ROOT="$TMP/reconcile-state" bash -c '. "$ROOT/src/persistence/reconcile.sh"; persistence_reconcile' >"$TMP/reconcile.out"
grep -q '^apply-sysctl --profile GLOBAL_MIXED --bandwidth 7000 --buffer-mib 64$' "$TMP/reconcile.log"
grep -q '^apply-network$' "$TMP/reconcile.log"
grep -q '^apply-resources$' "$TMP/reconcile.log"
grep -q '^reconcile_result=RECONCILED$' "$TMP/reconcile.out"
grep -qx 'network_type=global' "$TMP/reconcile-state/optimization/state.env"
grep -qx 'effective_mbps=7000' "$TMP/reconcile-state/optimization/state.env"

# Status remains compatible with v0.1.9 state files and exposes Global state.
mkdir -p "$TMP/legacy-state/optimization"
printf 'optimization_stage=APPLIED\nprofile=OVERSEAS_ORIGINAL\n' >"$TMP/legacy-state/optimization/state.env"
legacy_status=$(BBRV3_STATE_ROOT="$TMP/legacy-state" "$ROOT/bbrv3-universal.sh" status)
grep -q '^Network type: OVERSEAS$' <<<"$legacy_status"
global_status=$(BBRV3_STATE_ROOT="$TMP/accepted-state" "$ROOT/bbrv3-universal.sh" status)
grep -q '^Network type: GLOBAL$' <<<"$global_status"

TUNING_REGION=global TUNING_DOWNLOAD_MBPS=7000 TUNING_UPLOAD_MBPS=6500 TUNING_EFFECTIVE_MBPS=7000 TUNING_BUFFER=64
summary=$(optimization_summary)
grep -q '网络类型：全球混合 / 代理节点' <<<"$summary"
grep -q 'Download：7000 Mbps' <<<"$summary"
grep -q 'Upload：6500 Mbps' <<<"$summary"
grep -q '有效带宽：7000 Mbps' <<<"$summary"
grep -q 'TCP Buffer：64 MiB' <<<"$summary"

# Global adds no RTT probe or TCP global/default-memory tuning.
! grep -En 'ping[[:space:]]|1\\.1\\.1\\.1|8\\.8\\.8\\.8|tcp_mem|rmem_default|wmem_default' \
    "$ROOT/src/tuning-input.sh" "$ROOT/src/policy/buffer.sh" "$ROOT/metadata/global-policy.tsv"

printf 'PASS v0.1.10 Global/Mixed policy and v0.1.9 region compatibility contracts\n'
