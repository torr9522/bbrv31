#!/usr/bin/env bash

detect_platform() {
    local os=unknown version=unknown arch kernel pid1 systemd=NO boot=BIOS secure=unknown sb
    if [[ -r /etc/os-release ]]; then
        os=$(awk -F= '$1=="ID" {gsub(/"/,"",$2); print $2}' /etc/os-release)
        version=$(awk -F= '$1=="VERSION_ID" {gsub(/"/,"",$2); print $2}' /etc/os-release)
    fi
    arch=$(uname -m 2>/dev/null || printf unknown)
    [[ $arch == x86_64 ]] && arch=amd64
    [[ $arch == aarch64 ]] && arch=arm64
    kernel=$(uname -r 2>/dev/null || printf unknown)
    pid1=$(cat /proc/1/comm 2>/dev/null || printf unknown)
    [[ $pid1 == systemd ]] && systemd=YES
    [[ -d /sys/firmware/efi ]] && boot=UEFI
    if available mokutil; then
        sb=$(mokutil --sb-state 2>/dev/null || true)
        case $sb in *enabled*) secure=enabled;; *disabled*) secure=disabled;; esac
    elif [[ $boot == BIOS ]]; then secure=not_applicable; fi
    kv detection.mode READ_ONLY
    kv platform.os "$os"
    kv platform.version "$version"
    kv platform.arch "$arch"
    kv platform.kernel "$kernel"
    kv platform.pid1 "$pid1"
    kv platform.systemd "$systemd"
    kv boot.mode "$boot"
    kv boot.secure_boot "$secure"
}
