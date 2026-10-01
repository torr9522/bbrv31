#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
target="$tmp/payload"
expected_version=${BBRV3_TEST_VERSION:-v0.1.1}
BBRV3_INSTALL_DIR="$target" BBRV3_VERSION="$expected_version" BBRV3_BOOTSTRAP_TEST=YES "$ROOT/bootstrap.sh" >/tmp/bbrv3-bootstrap-test.out
[[ -x $target/bbrv3-universal.sh ]]
[[ $(<"$target/.bbrv3-universal-version") == "$expected_version" ]]
existing="$tmp/existing"
mkdir -p "$existing"
printf sentinel >"$existing/sentinel"
if BBRV3_INSTALL_DIR="$existing" BBRV3_VERSION="$expected_version" BBRV3_BOOTSTRAP_TEST=YES "$ROOT/bootstrap.sh" >/tmp/bbrv3-bootstrap-existing.out 2>&1; then
    exit 1
fi
[[ $(<"$existing/sentinel") == sentinel ]]
printf 'PASS bootstrap release download/checksum/extract/idempotency guard\n'
