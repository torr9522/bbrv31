#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
"$ROOT/src/loader.sh" --check
for case_args in \
  '--profile asia --bandwidth 1000 --ram-mb 953 --cpu-count 1' \
  '--profile overseas --bandwidth 1000 --ram-mb 2048 --cpu-count 2' \
  '--profile asia --bandwidth 500 --ram-mb 1024 --cpu-count 1' \
  '--profile overseas --bandwidth 500 --ram-mb 1024 --cpu-count 1'; do
  output=$("$ROOT/src/dry-run.sh" $case_args)
  grep -q '^system_mutation=NO$' <<<"$output"
  grep -q '^sysctl_count=31$' <<<"$output"
  printf '%s\n' "$output" | sed -n '1,5p'
done
printf 'PASS mock dry-run\n'
