#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/src/common.sh"
if [[ -n ${BBRV3_FIXTURE_ROOT:-} && -s ${BBRV3_FIXTURE_ROOT:-}/facts.env ]]; then
    { cat "$BBRV3_FIXTURE_ROOT/facts.env"; [[ -f "$BBRV3_ROOT/tests/fixtures/common.env" ]] && cat "$BBRV3_ROOT/tests/fixtures/common.env"; } |
      awk -F= '!/^#/ && NF >= 1 { if (!seen[$1]++) print }' | sort
    exit 0
fi
source "$BBRV3_ROOT/src/detect/platform.sh"
source "$BBRV3_ROOT/src/detect/cpu.sh"
source "$BBRV3_ROOT/src/detect/memory.sh"
source "$BBRV3_ROOT/src/detect/swap.sh"
source "$BBRV3_ROOT/src/detect/virtualization.sh"
source "$BBRV3_ROOT/src/detect/network.sh"
source "$BBRV3_ROOT/src/detect/qdisc.sh"
source "$BBRV3_ROOT/src/detect/capabilities.sh"
source "$BBRV3_ROOT/src/detect/hardware.sh"
source "$BBRV3_ROOT/src/detect/system.sh"
detect_platform
detect_cpu
detect_memory
detect_swap
detect_virtualization
detect_network
detect_qdisc
detect_capabilities
detect_hardware
detect_system
