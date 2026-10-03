#!/usr/bin/env bash
set -euo pipefail

TUNING_SPEEDTEST_BIN=${BBRV3_SPEEDTEST_BIN:-speedtest}

tuning_is_interactive() { [[ -t 0 && ${BBRV3_NONINTERACTIVE:-NO} != YES ]]; }

tuning_install_speedtest() {
    command -v "$TUNING_SPEEDTEST_BIN" >/dev/null 2>&1 && return 0
    local arch url tmp
    arch=$(uname -m)
    case $arch in
        x86_64) url=https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz ;;
        aarch64) url=https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-aarch64.tgz ;;
        *) return 1 ;;
    esac
    tmp=$(mktemp -d)
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 "$url" -o "$tmp/speedtest.tgz" || { rm -rf "$tmp"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$tmp/speedtest.tgz" || { rm -rf "$tmp"; return 1; }
    else
        rm -rf "$tmp"; return 1
    fi
    tar -xzf "$tmp/speedtest.tgz" -C "$tmp" speedtest || { rm -rf "$tmp"; return 1; }
    install -m 755 "$tmp/speedtest" /usr/local/bin/speedtest
    rm -rf "$tmp"
    TUNING_SPEEDTEST_BIN=/usr/local/bin/speedtest
}

tuning_parse_upload() {
    sed -nE 's/.*[Uu]pload:[[:space:]]*([0-9]+([.][0-9]+)?).*/\1/p' | head -1
}

tuning_run_speedtest() {
    local server=${1:-} output upload started ended rc=0
    started=$(date +%s)
    if [[ -n $server ]]; then
        output=$($TUNING_SPEEDTEST_BIN --accept-license --accept-gdpr --server-id="$server" 2>&1) || rc=$?
    else
        output=$($TUNING_SPEEDTEST_BIN --accept-license --accept-gdpr 2>&1) || rc=$?
    fi
    ended=$(date +%s)
    printf '%s\n' "$output" >&2
    TUNING_SPEEDTEST_DURATION=$((ended - started))
    upload=$(tuning_parse_upload <<<"$output")
    [[ $rc -eq 0 && -n $upload && $output != *FAILED* && $output != *Error* && $output != *error* ]] || return 1
    upload=${upload%.*}
    [[ $upload =~ ^[0-9]+$ && $upload -gt 0 ]] || return 1
    TUNING_BANDWIDTH=$upload
}

tuning_auto_speedtest() {
    local servers server attempts=0
    servers=$($TUNING_SPEEDTEST_BIN --accept-license --accept-gdpr --servers 2>/dev/null |
        sed -nE 's/^[[:space:]]*([0-9]+).*/\1/p' | head -n 10 || true)
    if [[ -z $servers ]]; then
        tuning_run_speedtest
        return
    fi
    while read -r server; do
        [[ -n $server ]] || continue
        attempts=$((attempts + 1))
        printf '正在测试 Speedtest 服务器 #%s（尝试 %s/5）...\n' "$server" "$attempts" >&2
        tuning_run_speedtest "$server" && return 0
        (( attempts >= 5 )) && break
    done <<<"$servers"
    return 1
}

tuning_read_positive() {
    local prompt=$1 value
    while :; do
        read -r -p "$prompt" value || return 1
        [[ $value =~ ^[0-9]+$ && $value -gt 0 ]] && { printf '%s\n' "$value"; return 0; }
        printf '请输入有效的正整数。\n' >&2
    done
}

tuning_fallback_bandwidth() {
    local answer value
    if ! tuning_is_interactive; then TUNING_BANDWIDTH=1000; TUNING_BANDWIDTH_SOURCE=FALLBACK_1000; return 0; fi
    printf '测速失败。可以使用默认值 1000 Mbps，或手工输入上传带宽。\n' >&2
    read -r -p '使用默认值 1000 Mbps？(Y/N) [Y]: ' answer || answer=Y
    answer=${answer:-Y}
    if [[ $answer =~ ^[Yy]$ ]]; then
        TUNING_BANDWIDTH=1000; TUNING_BANDWIDTH_SOURCE=FALLBACK_1000
    else
        value=$(tuning_read_positive '请输入上传带宽（Mbps）: ')
        TUNING_BANDWIDTH=$value; TUNING_BANDWIDTH_SOURCE=MANUAL_AFTER_FAILURE
    fi
}

tuning_choose_bandwidth() {
    local mode=${TUNING_BANDWIDTH_MODE:-} server=${TUNING_SERVER_ID:-} value=${TUNING_REQUESTED_BANDWIDTH:-} choice preset
    if [[ -z $mode ]]; then
        if tuning_is_interactive; then
            printf '\n=== 服务器带宽检测 ===\n1. 自动测速（推荐）\n2. 指定 Speedtest Server ID\n3. 手工选择/输入带宽\n' >&2
            read -r -p '请输入选择 [1]: ' choice || choice=1
            case ${choice:-1} in 1) mode=auto;; 2) mode=server;; 3) mode=manual;; *) mode=auto;; esac
        else
            mode=auto
        fi
    fi
    case $mode in
        auto)
            tuning_install_speedtest && tuning_auto_speedtest && TUNING_BANDWIDTH_SOURCE=AUTO_SPEEDTEST || tuning_fallback_bandwidth
            ;;
        server)
            [[ -n $server ]] || server=$(tuning_read_positive '请输入 Speedtest Server ID: ')
            if tuning_install_speedtest && tuning_run_speedtest "$server"; then
                TUNING_BANDWIDTH_SOURCE=SERVER_SPEEDTEST; TUNING_SPEEDTEST_SERVER=$server
            else
                tuning_fallback_bandwidth
            fi
            ;;
        manual)
            if [[ -z $value ]]; then
                printf '档位：1=100 2=200 3=300 4=500 5=700 6=1000 7=1500 8=2000 9=2500 10=自定义\n' >&2
                read -r -p '请输入选择 [6]: ' preset || preset=6
                case ${preset:-6} in
                    1) value=100;; 2) value=200;; 3) value=300;; 4) value=500;; 5) value=700;;
                    6) value=1000;; 7) value=1500;; 8) value=2000;; 9) value=2500;;
                    10) value=$(tuning_read_positive '请输入上传带宽（Mbps）: ');;
                    *) value=1000;;
                esac
            fi
            [[ $value =~ ^[0-9]+$ && $value -gt 0 ]] || return 1
            TUNING_BANDWIDTH=$value; TUNING_BANDWIDTH_SOURCE=MANUAL_VALUE; TUNING_SPEEDTEST_DURATION=0
            ;;
        *) return 1 ;;
    esac
}

tuning_choose_region() {
    local requested=${TUNING_REQUESTED_REGION:-} choice
    if [[ -z $requested ]]; then
        if tuning_is_interactive; then
            printf '\n请选择主要线路地区：\n1. 亚太\n2. 美国 / 欧洲\n' >&2
            read -r -p '请输入选择 [1]: ' choice || choice=1
            [[ ${choice:-1} == 2 ]] && requested=overseas || requested=asia
        else
            requested=asia
        fi
    fi
    case ${requested,,} in asia|apac) TUNING_REGION=asia; TUNING_PROFILE=ASIA_ORIGINAL;; overseas|us|eu|europe) TUNING_REGION=overseas; TUNING_PROFILE=OVERSEAS_ORIGINAL;; *) return 1;; esac
}

tuning_buffer_value() {
    local bw=$1 region=$2
    if ! [[ $bw =~ ^[0-9]+$ ]] || (( bw <= 0 )); then [[ $region == overseas ]] && printf 64 || printf 16; return; fi
    if [[ $region == overseas ]]; then
        case $bw in 100) printf 8;; 200) printf 16;; 300) printf 20;; 500) printf 32;; 700) printf 48;; 1000|1500|2000|2500) printf 64;; *) if ((bw<500)); then printf 16; elif ((bw<1000)); then printf 48; else printf 64; fi;; esac
    else
        case $bw in 100) printf 6;; 200) printf 8;; 300) printf 10;; 500) printf 12;; 700) printf 14;; 1000) printf 16;; 1500) printf 20;; 2000) printf 24;; 2500) printf 28;; *) if ((bw<500)); then printf 8; elif ((bw<1000)); then printf 12; elif ((bw<2000)); then printf 16; elif ((bw<5000)); then printf 24; elif ((bw<10000)); then printf 28; else printf 32; fi;; esac
    fi
}

tuning_choose_buffer() {
    local answer
    TUNING_BUFFER=$(tuning_buffer_value "$TUNING_BANDWIDTH" "$TUNING_REGION")
    if [[ ${TUNING_BUFFER_ACCEPT:-ask} == no ]]; then
        [[ $TUNING_REGION == overseas ]] && TUNING_BUFFER=32 || TUNING_BUFFER=16
        TUNING_BUFFER_SOURCE=REJECT_FALLBACK
        return
    elif tuning_is_interactive && [[ ${TUNING_BUFFER_ACCEPT:-ask} == ask ]]; then
        read -r -p "使用推荐 TCP Buffer ${TUNING_BUFFER} MiB？(Y/N) [Y]: " answer || answer=Y
        if [[ ! ${answer:-Y} =~ ^[Yy]$ ]]; then
            [[ $TUNING_REGION == overseas ]] && TUNING_BUFFER=32 || TUNING_BUFFER=16
            TUNING_BUFFER_SOURCE=REJECT_FALLBACK
            return
        fi
    fi
    TUNING_BUFFER_SOURCE=ORIGINAL_TABLE
}

tuning_choose_swap() {
    local memory swap_present recommended answer requested=${TUNING_SWAP_CHOICE:-ask}
    memory=${BBRV3_MEMORY_MB:-$(awk '/^MemTotal:/{printf "%d",$2/1024}' /proc/meminfo)}
    swap_present=${BBRV3_SWAP_PRESENT:-NO}; [[ -n ${BBRV3_SWAP_PRESENT:-} ]] || { swapon --show --noheadings 2>/dev/null | grep -q . && swap_present=YES; }
    TUNING_CREATE_SWAP=NO TUNING_SWAP_SIZE=0 TUNING_SWAP_STATUS=SKIP
    if [[ $swap_present == YES ]]; then TUNING_SWAP_STATUS=EXISTING; return 0; fi
    if (( memory < 512 )); then recommended=1024
    elif (( memory < 1024 )); then recommended=$((memory * 2))
    elif (( memory < 2048 )); then recommended=$((memory * 3 / 2))
    elif (( memory < 4096 )); then recommended=$memory
    else return 0
    fi
    if [[ $requested == ask ]] && tuning_is_interactive; then
        printf '\n当前内存 %s MiB，未检测到 Swap；原版策略建议 %s MiB。\n' "$memory" "$recommended" >&2
        read -r -p '现在创建项目管理的 Swap？(Y/N) [Y]: ' answer || answer=Y
        [[ ${answer:-Y} =~ ^[Yy]$ ]] && requested=yes || requested=no
    elif [[ $requested == ask ]]; then requested=yes
    fi
    if [[ $requested == yes ]]; then TUNING_CREATE_SWAP=YES; TUNING_SWAP_SIZE=$recommended; TUNING_SWAP_STATUS=CREATE
    else TUNING_SWAP_STATUS=DECLINED; fi
}

tuning_collect_inputs() {
    TUNING_SPEEDTEST_DURATION=0 TUNING_SPEEDTEST_SERVER=
    tuning_choose_swap
    tuning_choose_bandwidth
    tuning_choose_region
    tuning_choose_buffer
}
