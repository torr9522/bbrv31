#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
chmod 0755 "$ROOT/bbrv3.sh" "$ROOT/src/menu.sh"
out=$(mktemp)
printf '0\n' | "$ROOT/bbrv3-universal.sh" menu >"$out"
grep -q 'BBRv3 Universal 一键安装管理脚本' "$out"
grep -q -- '---------------- BBRv3 安装 ----------------' "$out"
grep -q '请输入数字：' "$out"
grep -q 'BBRv3 Kernel：' "$out"
printf 'abc\n0\n' | "$ROOT/bbrv3-universal.sh" menu >"$out"
grep -q '无效选项' "$out"
printf 'PASS status-first menu render/input/exit\n'
