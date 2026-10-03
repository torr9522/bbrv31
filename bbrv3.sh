#!/usr/bin/env bash
set -Eeuo pipefail

VERSION_TARGET=${BBRV3_VERSION:-v0.1.8}
REPOSITORY=${BBRV3_REPOSITORY:-torr9522/bbrv31}
INSTALL_DIR=${BBRV3_INSTALL_DIR:-/opt/bbrv3-universal}
ARCHIVE_NAME="bbrv3-universal-${VERSION_TARGET}-source.tar.zst"
KERNEL_PACKAGE_NAME="linux-image-6.18.54-x64v3-xanmod1_6.18.54-x64v3-xanmod1-0.20260925.g8bab3e0_amd64.deb"
BASE_URL="https://github.com/${REPOSITORY}/releases/download/${VERSION_TARGET}"

die() { printf 'bbrv3: %s\n' "$*" >&2; exit 1; }
fetch_payload() {
    local tmp=$1 archive="$tmp/$ARCHIVE_NAME" checksum="$tmp/$ARCHIVE_NAME.sha256" package="$tmp/$KERNEL_PACKAGE_NAME" package_checksum="$tmp/$KERNEL_PACKAGE_NAME.sha256"
    command -v curl >/dev/null || die 'curl is required'
    command -v zstd >/dev/null || die 'zstd is required'
    curl -fsSL --retry 3 "$BASE_URL/$ARCHIVE_NAME" -o "$archive" || die 'source archive download failed'
    curl -fsSL --retry 3 "$BASE_URL/$ARCHIVE_NAME.sha256" -o "$checksum" || die 'source checksum download failed'
    [[ $(sha256sum "$archive" | awk '{print $1}') == $(awk 'NF {print $1; exit}' "$checksum") ]] || die 'source archive checksum mismatch'
    zstd -tq "$archive" 2>/dev/null || die 'source archive decompression check failed'
    tar -xf "$archive" -C "$tmp" || die 'source archive extraction failed'
    local payload="$tmp/bbrv3-universal-${VERSION_TARGET}"
    [[ -x $payload/bbrv3-universal.sh ]] || die 'payload entrypoint missing'
    if curl -fsSL --retry 3 "$BASE_URL/$KERNEL_PACKAGE_NAME" -o "$package" && curl -fsSL --retry 3 "$BASE_URL/$KERNEL_PACKAGE_NAME.sha256" -o "$package_checksum"; then
        [[ $(sha256sum "$package" | awk '{print $1}') == $(awk 'NF {print $1; exit}' "$package_checksum") ]] || die 'kernel package checksum mismatch'
        mkdir -p "$payload/vendor/xanmod/packages"
        install -m 644 "$package" "$payload/vendor/xanmod/packages/$KERNEL_PACKAGE_NAME"
    fi
    printf '%s\n' "$payload"
}

if [[ ${1:-} == --update ]]; then
    [[ $EUID -eq 0 ]] || die 'root privileges are required for update'
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    payload=$(fetch_payload "$tmp")
    [[ -x $INSTALL_DIR/bbrv3-universal.sh ]] || die 'project is not installed'
    cp -a "$payload/." "$INSTALL_DIR/"
    printf 'update=COMPLETE version=%s\n' "$VERSION_TARGET"
    exec "$INSTALL_DIR/bbrv3-universal.sh" menu
fi

if [[ -x $INSTALL_DIR/bbrv3-universal.sh ]]; then
    installed_version=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || true)
    if [[ $installed_version == "${VERSION_TARGET#v}" ]]; then
        exec "$INSTALL_DIR/bbrv3-universal.sh" menu
    fi
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    payload=$(fetch_payload "$tmp")
    BBRV3_MENU_PROJECT_ROOT="$INSTALL_DIR" BBRV3_UNIVERSAL_ROOT="$payload" exec "$payload/bbrv3-universal.sh" menu
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
payload=$(fetch_payload "$tmp")
BBRV3_MENU_PAYLOAD_ROOT="$payload" BBRV3_MENU_PROJECT_ROOT="$INSTALL_DIR" BBRV3_UNIVERSAL_ROOT="$payload" exec "$payload/bbrv3-universal.sh" menu
