#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/bin" "$S/assets" "$S/tree/bbrv3-universal-vtest"
printf '#!/bin/bash\nprintf "MENU_OK\\n"\n' >"$S/tree/bbrv3-universal-vtest/bbrv3-universal.sh"
chmod +x "$S/tree/bbrv3-universal-vtest/bbrv3-universal.sh"
tar -C "$S/tree" -cf - bbrv3-universal-vtest | zstd -q -o "$S/assets/bbrv3-universal-vtest-source.tar.zst"
(cd "$S/assets"; sha256sum *.zst >bbrv3-universal-vtest-source.tar.zst.sha256)
cat >"$S/bin/curl" <<'EOF'
#!/bin/bash
while (( $# )); do
    case $1 in https://*) url=$1;; -o) shift; target=$1;; esac
    shift
done
asset=${url##*/}
if [[ $asset == *.deb* ]]; then exit 22; fi
cp "$LAUNCHER_ASSETS/$asset" "$target"
EOF
chmod +x "$S/bin/curl"
export PATH="$S/bin:$PATH" LAUNCHER_ASSETS="$S/assets"
BBRV3_VERSION=vtest BBRV3_INSTALL_DIR="$S/missing" bash "$ROOT/bbrv3.sh" >"$S/out" 2>"$S/err"
grep -qx MENU_OK "$S/out"
[[ ! -s $S/err ]]
printf '%064d\n' 0 >"$S/assets/bbrv3-universal-vtest-source.tar.zst.sha256"
if BBRV3_VERSION=vtest BBRV3_INSTALL_DIR="$S/missing" bash "$ROOT/bbrv3.sh" >"$S/out" 2>"$S/err"; then exit 1; fi
grep -q 'checksum mismatch' "$S/err"
printf 'invalid archive' >"$S/assets/bbrv3-universal-vtest-source.tar.zst"
(cd "$S/assets"; sha256sum *.zst >bbrv3-universal-vtest-source.tar.zst.sha256)
if BBRV3_VERSION=vtest BBRV3_INSTALL_DIR="$S/missing" bash "$ROOT/bbrv3.sh" >"$S/out" 2>"$S/err"; then exit 1; fi
grep -q 'decompression check failed' "$S/err"
printf 'PASS quiet launcher success and visible checksum failure\n'
