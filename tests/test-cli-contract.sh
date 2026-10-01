#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/bbrv3-universal.sh"
contract="$ROOT/metadata/cli-contract.tsv"
[[ -s $contract ]]
while IFS=$'\t' read -r command alias public root scope reboot handler status; do
  [[ $command == command || -z $command ]] && continue
  [[ $public == YES && $status == IMPLEMENTED ]]
  [[ $handler != *NOT_IMPLEMENTED* ]]
  out=$(BBRV3_CLI_MOCK=YES "$CLI" "$command" 2>&1 || true)
  if [[ $command == detect || $command == dry-run ]]; then
    [[ -n $out ]]
  elif [[ $command == status ]]; then
    grep -q '^BBRv3 Universal$' <<<"$out"
  elif [[ $command == advanced ]]; then
    grep -q '^NETWORK:' <<<"$out"
  elif [[ $command == one-click ]]; then
    grep -q '^one_click=PLAN_ONLY$' <<<"$out"
  else
    grep -qx "dispatch=$command" <<<"$out"
  fi
done <"$contract"
! grep -Rqs 'NOT_IMPLEMENTED_IN_PHASE3_SCOPE' "$ROOT/bbrv3-universal.sh" "$ROOT/src"
! grep -RqsE 'PHASE2_ONLY|MOCK_ONLY' "$ROOT/bbrv3-universal.sh" "$ROOT/src"
guard=$(BBRV3_LIFECYCLE_ROOT=$(mktemp -d) "$CLI" reboot 2>&1 || true)
grep -q 'GUARDED_NO_PENDING_TRANSACTION' <<<"$guard"
printf 'PASS CLI contract, dispatch, placeholder and reboot guard audit\n'
