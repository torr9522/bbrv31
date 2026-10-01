#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_VERSION=${BBRV3_VERSION:-v0.1.0-rc1}
REPOSITORY=${BBRV3_REPOSITORY:-torr9522/bbrv31}
INSTALL_DIR=${BBRV3_INSTALL_DIR:-/opt/bbrv3-universal}
ARCHIVE_NAME="bbrv3-universal-${TARGET_VERSION}-source.tar.zst"
BASE_URL="https://github.com/${REPOSITORY}/releases/download/${TARGET_VERSION}"

die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die 'root privileges are required (run with sudo or as root)'
[[ -r /etc/os-release ]] || die 'cannot identify the operating system'
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 12 ]] || die 'supported platform is Debian 12 only'
[[ $(uname -m) == x86_64 ]] || die 'supported architecture is AMD64/x86_64 only'
for cmd in curl tar zstd sha256sum; do command -v "$cmd" >/dev/null 2>&1 || die "missing dependency: $cmd"; done
[[ ! -e $INSTALL_DIR ]] || die "install directory already exists: $INSTALL_DIR (remove it only after reviewing its contents)"

tmp=$(mktemp -d)
stage=${INSTALL_DIR}.staging.$$
cleanup() { rm -rf "$tmp"; rmdir "$stage" 2>/dev/null || true; }
trap cleanup EXIT
mkdir -p "$stage"
archive="$tmp/$ARCHIVE_NAME"
checksum="$tmp/$ARCHIVE_NAME.sha256"
curl -fsSL --retry 3 "$BASE_URL/$ARCHIVE_NAME" -o "$archive"
curl -fsSL --retry 3 "$BASE_URL/$ARCHIVE_NAME.sha256" -o "$checksum"
expected=$(awk 'NF {print $1; exit}' "$checksum")
[[ $expected =~ ^[0-9a-fA-F]{64}$ ]] || die 'invalid release checksum file'
actual=$(sha256sum "$archive" | awk '{print $1}')
[[ $actual == "$expected" ]] || die 'release archive checksum mismatch'
zstd -t "$archive" >/dev/null
tar -xf "$archive" -C "$tmp"
payload="$tmp/bbrv3-universal-${TARGET_VERSION}"
[[ -x "$payload/bbrv3-universal.sh" ]] || die 'release payload is missing its entrypoint'
cp -a "$payload/." "$stage/"
printf '%s\n' "$TARGET_VERSION" >"$stage/.bbrv3-universal-version"
mv "$stage" "$INSTALL_DIR"
stage=
printf 'bootstrap=VERIFIED\nversion=%s\ninstall_dir=%s\n' "$TARGET_VERSION" "$INSTALL_DIR"
if [[ ${BBRV3_BOOTSTRAP_TEST:-NO} == YES ]]; then
    printf 'bootstrap=test-only-no-mutation\n'
    exit 0
fi
exec "$INSTALL_DIR/bbrv3-universal.sh" install
