#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

source "$ROOT/src/tuning-input.sh"
AUDIT="$ROOT/metadata/original-functional-audit.tsv"
[[ $(awk 'NR>1{n++} END{print n}' "$AUDIT") == 38 ]]
! awk -F '\t' 'NR>1 && $11 !~ /^(ACTIVE_AND_EQUIVALENT|ACTIVE_BUT_BEHAVIOR_CHANGED|PRESERVED_IN_AUTO|PRESERVED_MANUAL_ONLY|CODE_EXISTS_NOT_WIRED|DATA_ONLY_NOT_EXECUTED|INTENTIONALLY_SKIPPED_FOR_SAFETY|ACCIDENTALLY_MISSING|REMOVED_WITH_DOCUMENTED_REASON)$/ {bad=1} END{exit bad?0:1}' "$AUDIT"
! awk -F '\t' 'NR>1 && ($11=="CODE_EXISTS_NOT_WIRED" || $11=="DATA_ONLY_NOT_EXECUTED" || $11=="ACCIDENTALLY_MISSING") {bad=1} END{exit bad?0:1}' "$AUDIT"
check_buffer() { [[ $(tuning_buffer_value "$1" "$2") == "$3" ]]; }
for row in '100 6' '200 8' '300 10' '500 12' '700 14' '1000 16' '1500 20' '2000 24' '2500 28' '499 8' '999 12' '1999 16' '4999 24' '9999 28' '10000 32' 'bad 16' '0 16'; do read -r bw expected <<<"$row"; check_buffer "$bw" asia "$expected"; done
for row in '100 8' '200 16' '300 20' '500 32' '700 48' '1000 64' '1500 64' '2000 64' '2500 64' '499 16' '999 48' '1001 64' 'bad 64' '0 64'; do read -r bw expected <<<"$row"; check_buffer "$bw" overseas "$expected"; done
TUNING_BANDWIDTH=824 TUNING_REGION=asia TUNING_BUFFER_ACCEPT=no tuning_choose_buffer; [[ $TUNING_BUFFER == 16 && $TUNING_BUFFER_SOURCE == REJECT_FALLBACK ]]
TUNING_BANDWIDTH=824 TUNING_REGION=overseas TUNING_BUFFER_ACCEPT=no tuning_choose_buffer; [[ $TUNING_BUFFER == 32 ]]

cat >"$TMP/speedtest" <<'EOF'
#!/bin/sh
case " $* " in
  *' --servers '*) printf ' 1234) Nearby One\n 5678) Nearby Two\n';;
  *' --server-id=9999 '*) printf 'Server: Manual\nUpload: 333.75 Mbps\n';;
  *) printf 'Server: Auto\nUpload: 824.61 Mbps\n';;
esac
EOF
chmod +x "$TMP/speedtest"
TUNING_SPEEDTEST_BIN="$TMP/speedtest"; tuning_auto_speedtest >/dev/null; [[ $TUNING_BANDWIDTH == 824 ]]
TUNING_BANDWIDTH_MODE=server TUNING_SERVER_ID=9999 TUNING_REQUESTED_BANDWIDTH= TUNING_SPEEDTEST_BIN="$TMP/speedtest" tuning_choose_bandwidth; [[ $TUNING_BANDWIDTH == 333 && $TUNING_BANDWIDTH_SOURCE == SERVER_SPEEDTEST ]]
TUNING_BANDWIDTH_MODE=manual TUNING_REQUESTED_BANDWIDTH=700 tuning_choose_bandwidth; [[ $TUNING_BANDWIDTH == 700 && $TUNING_BANDWIDTH_SOURCE == MANUAL_VALUE ]]
printf '#!/bin/sh\nexit 1\n' >"$TMP/speedtest-fail"; chmod +x "$TMP/speedtest-fail"
TUNING_BANDWIDTH_MODE=auto TUNING_SPEEDTEST_BIN="$TMP/speedtest-fail" BBRV3_NONINTERACTIVE=YES tuning_choose_bandwidth; [[ $TUNING_BANDWIDTH == 1000 && $TUNING_BANDWIDTH_SOURCE == FALLBACK_1000 ]]

BBRV3_MEMORY_MB=400 BBRV3_SWAP_PRESENT=NO BBRV3_NONINTERACTIVE=YES TUNING_SWAP_CHOICE=yes tuning_choose_swap; [[ $TUNING_SWAP_SIZE == 1024 ]]
BBRV3_MEMORY_MB=953 BBRV3_SWAP_PRESENT=NO BBRV3_NONINTERACTIVE=YES TUNING_SWAP_CHOICE=yes tuning_choose_swap; [[ $TUNING_SWAP_SIZE == 1906 ]]
BBRV3_MEMORY_MB=1536 BBRV3_SWAP_PRESENT=NO BBRV3_NONINTERACTIVE=YES TUNING_SWAP_CHOICE=yes tuning_choose_swap; [[ $TUNING_SWAP_SIZE == 2304 ]]
BBRV3_MEMORY_MB=3072 BBRV3_SWAP_PRESENT=NO BBRV3_NONINTERACTIVE=YES TUNING_SWAP_CHOICE=yes tuning_choose_swap; [[ $TUNING_SWAP_SIZE == 3072 ]]

plan="$TMP/31.tsv"
BBRV3_PROJECT_ROOT="$ROOT" REQUESTED_PROFILE=ASIA_ORIGINAL REQUESTED_BANDWIDTH=824 REQUESTED_BUFFER_MB=14 REQUESTED_RAM_MB=953 "$ROOT/src/policy/sysctl-plan.sh" --output "$plan"
[[ $(awk 'NR>1{n++} END{print n}' "$plan") == 31 ]]
grep -qx $'net.core.default_qdisc\tfq\tCORE_DEFAULT\tbbr_configure_direct\t1506\t1573' "$plan"
grep -qx $'net.ipv4.tcp_congestion_control\tbbr\tCORE_DEFAULT\tbbr_configure_direct\t1506\t1573' "$plan"
grep -q $'^net.core.rmem_max\t14680064\t' "$plan"
grep -q $'^vm.swappiness\t20\t' "$plan"; grep -q $'^vm.dirty_ratio\t20\t' "$plan"; grep -q $'^vm.min_free_kbytes\t32768\t' "$plan"

source "$ROOT/src/orchestration.sh"
S="$TMP/read"; mkdir -p "$S/kernel"; printf 'formal-entry\n' >"$S/kernel/boot-entry"
[[ $(BBRV3_STATE_ROOT="$S" BBRV3_KERNEL_STATE_ROOT="$S/kernel" kernel_read_entry) == formal-entry ]]
kernel_formal_running() { return 0; }; kernel_read_entry() { printf entry; }; kernel_set_persistent_default() { [[ $1 == entry ]]; }; enable_reconcile() { :; }
out=$(BBRV3_STATE_ROOT="$TMP/noop" orchestration_install)
grep -q 'kernel.action=NOOP' <<<"$out"; grep -q '无需重新安装' <<<"$out"; ! grep -q 'orchestration=APPLIED' <<<"$out"
blocked=$("$ROOT/bbrv3-universal.sh" optimize --non-interactive --bandwidth 1000 --region asia 2>&1 || true)
grep -q 'FORMAL_KERNEL_NOT_RUNNING' <<<"$blocked"

PRE="$TMP/pre"; mkdir -p "$PRE/boot" "$PRE/kernel" "$PRE/tx" "$PRE/bin"
printf x >"$PRE/boot/vmlinuz-6.18.54-x64v3-xanmod1"; printf x >"$PRE/boot/initrd.img-6.18.54-x64v3-xanmod1"
printf 'menuentry entry\n' >"$PRE/grub.cfg"; printf 'fallback\n' >"$PRE/kernel/fallback-kernels.tsv"; printf WAIT_REBOOT >"$PRE/tx/stage"
printf '#!/bin/sh\nprintf "next_entry=entry\\n"\n' >"$PRE/bin/grub-editenv"; chmod +x "$PRE/bin/grub-editenv"
kernel_formal_installed() { return 0; }
PATH="$PRE/bin:$PATH" BBRV3_BOOT_DIR="$PRE/boot" BBRV3_KERNEL_STATE_ROOT="$PRE/kernel" BBRV3_GRUB_CFG="$PRE/grub.cfg" BBRV3_GRUB_ENV_FILE="$PRE/grubenv" kernel_pre_reboot_verify "$PRE/tx" entry

cat >"$TMP/reboot" <<EOF
#!/bin/sh
echo reboot >>'$TMP/reboot.log'
EOF
chmod +x "$TMP/reboot"
out=$(BBRV3_REBOOT_COUNTDOWN=3 BBRV3_COUNTDOWN_SLEEP=0 BBRV3_REBOOT_COMMAND="$TMP/reboot" kernel_reboot_summary; BBRV3_REBOOT_COUNTDOWN=3 BBRV3_COUNTDOWN_SLEEP=0 BBRV3_REBOOT_COMMAND="$TMP/reboot" kernel_countdown_reboot)
grep -q '\[PASS\] GRUB 启动项' <<<"$out"; grep -q 'SSH 连接断开属于正常现象' <<<"$out"; grep -q '^3\.\.\.$' <<<"$out"; grep -q '^1\.\.\.$' <<<"$out"; [[ $(wc -l <"$TMP/reboot.log") == 1 ]]

FAKE="$TMP/fake-root"; STATE="$TMP/resume"; mkdir -p "$FAKE/src/core" "$FAKE/src/apply" "$STATE/lifecycle/tx" "$STATE/kernel"
printf 'WAIT_REBOOT\n' >"$STATE/lifecycle/tx/stage"; printf 'entry\n' >"$STATE/kernel/boot-entry"
cat >"$FAKE/src/core/kernel.sh" <<'EOF'
kernel_formal_running() { return 0; }
kernel_find_xanmod_entry() { printf fallback; }
EOF
cat >"$FAKE/src/apply/kernel.sh" <<'EOF'
kernel_set_persistent_default() { [[ -n $1 ]]; }
EOF
cat >"$FAKE/src/core/lifecycle.sh" <<'EOF'
lifecycle_transition() { printf '%s\n' "$2" >"$1/stage"; printf '%s\n' "$2" >>"$1/events"; }
EOF
cat >"$FAKE/bbrv3-universal.sh" <<EOF
#!/bin/sh
echo "\$*" >>'$TMP/resume-apply.log'
EOF
chmod +x "$FAKE/bbrv3-universal.sh"
source "$ROOT/src/persistence/reconcile.sh"
resume=$(ROOT="$FAKE" BBRV3_STATE_ROOT="$STATE" persistence_reconcile)
grep -q 'KERNEL_STAGE_COMPLETE' <<<"$resume"; grep -qx COMPLETE "$STATE/lifecycle/tx/stage"; [[ ! -e $TMP/resume-apply.log ]]

source "$ROOT/src/apply/network.sh"
Q="$TMP/qdisc"; mkdir -p "$Q"; printf eth0 >"$Q/interface"; printf '%s\n' 'qdisc.decision=CANDIDATE' 'qdisc.mq=YES' 'qdisc.queue_count=4' >"$Q/desired.env"
network_tc_mutation() { printf '%s\n' "$*" >>"$TMP/tc.log"; }
network_apply_qdisc "$Q"; [[ $(wc -l <"$TMP/tc.log") == 4 ]]; grep -q 'parent :1 fq' "$TMP/tc.log"; grep -q 'parent :4 fq' "$TMP/tc.log"
printf '%s\n' 'qdisc.decision=CANDIDATE' 'qdisc.mq=NO' 'qdisc.queue_count=1' >"$Q/desired.env"; : >"$TMP/tc.log"
network_apply_qdisc "$Q"; grep -qx 'qdisc replace dev eth0 root fq' "$TMP/tc.log"
source "$ROOT/src/recovery/network-rollback.sh"
network_tc_mutation() { printf '%s\n' "$*" >>"$TMP/tc.log"; }
printf VERIFIED >"$Q/state"; printf 'qdisc fq_codel 0: dev eth0 root\n' >"$Q/qdisc.baseline"
printf '%s\n' 'qdisc.decision=CANDIDATE' 'route.decision=SKIP' 'rps.decision=SKIP' 'mss.decision=SKIP' >"$Q/desired.env"
network_qdisc_text() { printf 'qdisc fq 8001: dev eth0 root\n'; }; : >"$TMP/tc.log"
network_rollback_transaction "$Q" >/dev/null; grep -qx 'qdisc replace dev eth0 root fq_codel' "$TMP/tc.log"

printf 'PASS v0.1.9 runtime functional parity and workflow contracts\n'
