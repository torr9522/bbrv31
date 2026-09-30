#!/usr/bin/env bash

detect_virtualization() {
    local raw=unknown class=unknown
    available systemd-detect-virt && raw=$(systemd-detect-virt 2>/dev/null || printf none)
    case $raw in
      kvm) class=KVM;; qemu) class=QEMU;; vmware) class=VMWARE;; microsoft) class=HYPER_V;; xen) class=XEN;;
      openvz) class=OPENVZ;; lxc|lxc-libvirt|systemd-nspawn|docker|podman) class=CONTAINER;; none) class=BARE_METAL;; *) class=UNKNOWN;;
    esac
    kv virtualization.raw "$raw"
    kv virtualization.class "$class"
}
