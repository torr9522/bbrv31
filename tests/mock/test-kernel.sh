#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd); source "$ROOT/src/policy/kernel-plan.sh"
grep -qx 'kernel.decision=CANDIDATE' <(kernel_policy debian 12 amd64 x86-64-v3 disabled KVM)
grep -qx 'kernel.reason=CPU_BELOW_X64V3' <(kernel_policy debian 12 amd64 x86-64-v2 disabled KVM)
grep -qx 'kernel.reason=SECURE_BOOT_ENABLED' <(kernel_policy debian 12 amd64 x86-64-v3 enabled KVM)
grep -q 'update-initramfs -u -k all' "$ROOT/src/apply/kernel.sh"
grep -q 'kernel_find_xanmod_entry' "$ROOT/src/apply/kernel.sh"
S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
mkdir -p "$S/bin" "$S/state"
printf 'GRUB_DEFAULT="Advanced options>Linux 6.10.10"\nGRUB_TIMEOUT=5\n' >"$S/defaults"
printf 'saved_entry=old-kernel\n' >"$S/grubenv"
cat >"$S/bin/update-grub" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$S/bin/grub-set-default" <<'EOF'
#!/bin/sh
printf 'saved_entry=%s\n' "$1" >"$BBRV3_GRUB_ENV_FILE"
EOF
cat >"$S/bin/grub-editenv" <<'EOF'
#!/bin/sh
cat "$1"
EOF
chmod +x "$S/bin/"*
source "$ROOT/src/apply/kernel.sh"
entry=gnulinux-6.18.54-x64v3-xanmod1-advanced-test
PATH="$S/bin:$PATH" BBRV3_GRUB_DEFAULT_FILE="$S/defaults" BBRV3_GRUB_ENV_FILE="$S/grubenv" kernel_set_persistent_default "$entry" "$S/state"
grep -qx 'GRUB_DEFAULT=saved' "$S/defaults"
grep -Fqx "saved_entry=$entry" "$S/grubenv"
grep -q '6.10.10' "$S/state/grub.default.before"
grep -qx PERSISTENT_READY "$S/state/boot-state"
printf 'PASS kernel policy/preflight fixtures\n'
