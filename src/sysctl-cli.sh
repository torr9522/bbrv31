#!/usr/bin/env bash
set -euo pipefail
ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
source "$ROOT/src/core/paths.sh"
source "$ROOT/src/core/transaction.sh"
source "$ROOT/src/apply/sysctl.sh"
source "$ROOT/src/recovery/rollback.sh"
source "$ROOT/src/recovery/buffer-baseline.sh"

require_root() { [[ $EUID -eq 0 || ${BBRV3_MOCK:-0} == 1 || $BBRV3_SYSCTL_ROOT != / ]] || { printf 'ROOT_REQUIRED\n' >&2; return 1; }; }
parse_args() {
    REQUESTED_PROFILE=ASIA_ORIGINAL REQUESTED_BANDWIDTH=1000 REQUESTED_BUFFER_MB= REQUESTED_RAM_MB= REQUESTED_DETAIL=NO FORCE_RECOVERY=NO
    while [[ $# -gt 0 ]]; do
      case $1 in
        --profile) REQUESTED_PROFILE=$2; shift 2;;
        --bandwidth) REQUESTED_BANDWIDTH=$2; shift 2;;
        --buffer-mib) REQUESTED_BUFFER_MB=$2; shift 2;;
        --ram-mb) REQUESTED_RAM_MB=$2; shift 2;;
        --fixture) export BBRV3_FIXTURE_ROOT=$2; shift 2;;
        --detail) REQUESTED_DETAIL=YES; shift;;
        --transaction) REQUESTED_TRANSACTION=$2; shift 2;;
        --force-owned) FORCE_RECOVERY=YES; shift;;
        *) printf 'unknown option: %s\n' "$1" >&2; return 2;;
      esac
    done
}
make_plan() {
    local dir=$1; REQUESTED_PROFILE=${REQUESTED_PROFILE:-ASIA_ORIGINAL} REQUESTED_BANDWIDTH=${REQUESTED_BANDWIDTH:-1000} REQUESTED_BUFFER_MB=${REQUESTED_BUFFER_MB:-} REQUESTED_RAM_MB=${REQUESTED_RAM_MB:-} \
      "$ROOT/src/policy/sysctl-plan.sh" --output "$dir/desired.tsv"
}
format_plan() {
    local dir=$1; cat "$dir/desired.tsv.meta"; printf 'desired keys:\n'; tail -n +2 "$dir/desired.tsv"; printf 'conflicts:\n'; cat "$dir/conflicts.tsv"
}
plan_command() {
    local dir; dir=$(mktemp -d)
    make_plan "$dir"; scan_conflicts "$dir/desired.tsv" "$dir/conflicts.tsv" || true
    format_plan "$dir"; printf 'system_mutation=NO\n'
}
apply_command() {
    require_root; with_lock
    local dir latest state profile operation restore= baseline_rc=0; latest=$(latest_transaction || true)
    if [[ -n $latest && -f $latest/state ]]; then state=$(<"$latest/state"); [[ $state != APPLYING && $state != ROLLING_BACK ]] || { printf 'UNFINISHED_TRANSACTION=%s\n' "$latest" >&2; return 3; }; fi
    case ${REQUESTED_PROFILE,,} in
        system|system-default|system_default)
            ensure_buffer_baseline || return 3
            ;;
        *)
            ensure_buffer_baseline allow-managed-missing || baseline_rc=$?
            (( baseline_rc == 0 || baseline_rc == 2 )) || return 3
            ;;
    esac
    dir=$(new_transaction); make_plan "$dir"
    cp "$dir/desired.tsv" "$dir/desired-persistent.tsv"
    profile=$(awk -F= '$1=="profile"{print $2}' "$dir/desired.tsv.meta")
    if ! scan_conflicts "$dir/desired.tsv" "$dir/conflicts.tsv"; then printf BLOCKING_CONFLICT >"$dir/state"; printf 'BLOCKING_CONFLICT\n' >&2; return 3; fi
    if [[ $profile == SYSTEM_DEFAULT && $(owned_file_status) == OWNED ]] && ! owned_manages_buffer && verify_plan "$dir/desired.tsv" "$dir/verify.tsv"; then printf 'NOOP already verified\n'; printf NOOP >"$dir/state"; return 0; fi
    if [[ $profile != SYSTEM_DEFAULT && $(owned_file_status) == OWNED ]] && verify_plan "$dir/desired.tsv" "$dir/verify.tsv"; then printf 'NOOP already verified\n'; printf NOOP >"$dir/state"; return 0; fi
    operation="$dir/operation.tsv"; cp "$dir/desired.tsv" "$operation"; cp "$dir/desired.tsv.meta" "$operation.meta"
    if [[ $profile == SYSTEM_DEFAULT ]] && owned_manages_buffer; then
        restore="$dir/restore.tsv"; printf 'key\tvalue\tcategory\tsource_function\tsource_line_start\tsource_line_end\n' >"$restore"
        append_buffer_restore_plan "$restore"
        tail -n +2 "$restore" >>"$operation"
        cp "$operation" "$dir/desired.tsv"; cp "$operation.meta" "$dir/desired.tsv.meta"
    fi
    if apply_transaction "$dir" "$operation" "$dir/desired-persistent.tsv" "$restore"; then return 0; fi
    printf ROLLING_BACK >"$dir/state"; rollback_transaction "$dir" || true; return 4
}
find_transaction() {
    if [[ -n ${REQUESTED_TRANSACTION:-} ]]; then printf '%s/transactions/%s\n' "$BBRV3_STATE_ROOT" "$REQUESTED_TRANSACTION"; return; fi
    local dir state
    while read -r dir; do
        [[ -f $dir/state ]] || continue
        state=$(<"$dir/state")
        [[ $state == VERIFIED || $state == APPLY_FAILED || $state == VERIFY_FAILED || $state == ROLLING_BACK ]] && { printf '%s\n' "$dir"; return; }
    done < <(find "$BBRV3_STATE_ROOT/transactions" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{sub(/^[^ ]+ /,""); print}')
}
find_unfinished() {
    local dir state
    while read -r dir; do
        [[ -f $dir/state ]] || continue
        state=$(<"$dir/state")
        [[ $state == APPLYING || $state == ROLLING_BACK ]] && { printf '%s\n' "$dir"; return; }
    done < <(find "$BBRV3_STATE_ROOT/transactions" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{sub(/^[^ ]+ /,""); print}')
}
verify_command() {
    local dir; dir=$(find_transaction); [[ -n $dir && -f $dir/desired.tsv ]] || { dir=$(mktemp -d); make_plan "$dir"; scan_conflicts "$dir/desired.tsv" "$dir/conflicts.tsv" || true; }
    printf 'owned_path=%s\nowned_status=%s\n' "$BBRV3_SYSCTL_PATH" "$(owned_file_status)"
    verify_plan "$dir/desired.tsv" "$dir/verify.tsv" || true
    cat "$dir/verify.tsv"
}
rollback_command() { require_root; with_lock; local dir; dir=$(find_transaction); [[ -n $dir ]] || { printf 'NO_TRANSACTION\n'; return 1; }; rollback_transaction "$dir"; }
recover_command() { require_root; with_lock; local dir state; dir=$(find_unfinished); [[ -n $dir && -f $dir/state ]] || { printf 'NO_UNFINISHED_TRANSACTION\n'; return 1; }; state=$(<"$dir/state"); printf ROLLING_BACK >"$dir/state"; rollback_transaction "$dir"; }

command_name=$1; shift || true; parse_args "$@"
case $command_name in
  plan-sysctl) plan_command;;
  apply-sysctl) apply_command;;
  verify-sysctl) verify_command;;
  rollback-sysctl) rollback_command;;
  recover-sysctl) recover_command;;
  *) printf 'unknown sysctl command\n' >&2; exit 2;;
esac
