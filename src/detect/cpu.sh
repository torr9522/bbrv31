#!/usr/bin/env bash

cpu_has_all() {
    local flags=" $1 " feature
    shift
    for feature; do [[ $flags == *" $feature "* ]] || return 1; done
}

cpu_level_from_flags() {
    local arch=$1 flags=$2 level=unknown
    if [[ $arch == x86_64 ]]; then
        level=x86-64-v1
        cpu_has_all "$flags" cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3 && level=x86-64-v2
        cpu_has_all "$flags" avx avx2 bmi1 bmi2 f16c fma abm movbe xsave && level=x86-64-v3
        cpu_has_all "$flags" avx512f avx512bw avx512cd avx512dq avx512vl && level=x86-64-v4
    elif [[ $arch == aarch64 ]]; then level=arm64; fi
    printf '%s\n' "$level"
}

detect_cpu() {
    local count model vendor flags level=unknown
    count=$(nproc 2>/dev/null || awk '/^processor/{n++} END{print n+0}' /proc/cpuinfo)
    model=$(awk -F: '/model name/{sub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo)
    vendor=$(awk -F: '/vendor_id/{sub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo)
    flags=$(awk -F: '/^(flags|Features)/{sub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo)
    level=$(cpu_level_from_flags "$(uname -m)" "$flags")
    kv cpu.count "$count"
    kv cpu.model "${model:-unknown}"
    kv cpu.vendor "${vendor:-unknown}"
    kv cpu.level "$level"
}
