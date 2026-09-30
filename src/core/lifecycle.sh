#!/usr/bin/env bash
set -euo pipefail
BBRV3_LIFECYCLE_ROOT=${BBRV3_LIFECYCLE_ROOT:-${BBRV3_STATE_ROOT:-/var/lib/bbrv3-universal}/lifecycle}
LIFECYCLE_STAGES='PRECHECK KERNEL_INSTALL WAIT_REBOOT POST_KERNEL_VERIFY NETWORK_DETECT PROFILE_SELECT SYSCTL_APPLY NETWORK_APPLY SYSTEM_RESOURCE_APPLY PERSIST VERIFY COMPLETE ROLLBACK FAILED'
lifecycle_init() { [[ ! -L $BBRV3_LIFECYCLE_ROOT ]] || return 1; install -d -m 700 "$BBRV3_LIFECYCLE_ROOT"; }
lifecycle_new() { lifecycle_init; local id="$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM$RANDOM"; install -d -m 700 "$BBRV3_LIFECYCLE_ROOT/$id"; printf '%s\n' "$BBRV3_LIFECYCLE_ROOT/$id"; }
lifecycle_transition() { local d=$1 stage=$2; grep -qw "$stage" <<<"$LIFECYCLE_STAGES" || return 1; printf '%s\n' "$stage" >"$d/stage"; printf '%s\n' "$stage" >>"$d/events"; }
