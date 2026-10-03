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

tuning_parse_speed() {
    local metric=$1
    sed -nE "s/.*${metric}:[[:space:]]*([0-9]+([.][0-9]+)?).*/\\1/Ip" | head -1
}

tuning_normalize_mbps() {
    local value=${1:-}
    [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    value=${value%%.*}
    (( value > 0 )) || return 1
    printf '%s\n' "$value"
}

tuning_valid_mbps() {
    [[ ${1:-} =~ ^[0-9]+$ ]] && (( $1 > 0 ))
}

tuning_run_speedtest() {
    local server=${1:-} output download upload started ended rc=0
    started=$(date +%s)
    if [[ -n $server ]]; then
        output=$($TUNING_SPEEDTEST_BIN --accept-license --accept-gdpr --server-id="$server" 2>&1) || rc=$?
    else
        output=$($TUNING_SPEEDTEST_BIN --accept-license --accept-gdpr 2>&1) || rc=$?
    fi
    ended=$(date +%s)
    printf '%s\n' "$output" >&2
    TUNING_SPEEDTEST_DURATION=$((ended - started))
    TUNING_DOWNLOAD_MBPS=N/A TUNING_UPLOAD_MBPS=N/A
    (( rc == 0 )) && [[ $output != *FAILED* && $output != *Error* && $output != *error* ]] || return 1
    download=$(tuning_parse_speed Download <<<"$output")
    upload=$(tuning_parse_speed Upload <<<"$output")
    download=$(tuning_normalize_mbps "$download" 2>/dev/null || true)
    upload=$(tuning_normalize_mbps "$upload" 2>/dev/null || true)
    [[ -n $download ]] && TUNING_DOWNLOAD_MBPS=$download
    if [[ -n $upload ]]; then
        TUNING_UPLOAD_MBPS=$upload
        TUNING_BANDWIDTH=$upload
        return 0
    fi
    [[ -n $download ]] && return 2
    return 1
}

tuning_auto_speedtest() {
    local servers server attempts=0 rc partial_download=N/A partial_server=
    servers=$($TUNING_SPEEDTEST_BIN --accept-license --accept-gdpr --servers 2>/dev/null |
        sed -nE 's/^[[:space:]]*([0-9]+).*/\1/p' | head -n 10 || true)
    if [[ -z $servers ]]; then
        rc=0; tuning_run_speedtest || rc=$?
        TUNING_SPEEDTEST_SERVER=AUTO
        return "$rc"
    fi
    while read -r server; do
        [[ -n $server ]] || continue
        attempts=$((attempts + 1))
        printf '正在测试 Speedtest 服务器 #%s（尝试 %s/5）...\n' "$server" "$attempts" >&2
        rc=0; tuning_run_speedtest "$server" || rc=$?
        if (( rc == 0 )); then TUNING_SPEEDTEST_SERVER=$server; return 0; fi
        if (( rc == 2 )) && tuning_valid_mbps "$TUNING_DOWNLOAD_MBPS"; then
            if ! tuning_valid_mbps "$partial_download" || (( TUNING_DOWNLOAD_MBPS > partial_download )); then
                partial_download=$TUNING_DOWNLOAD_MBPS; partial_server=$server
            fi
        fi
        (( attempts >= 5 )) && break
    done <<<"$servers"
    if tuning_valid_mbps "$partial_download"; then
        TUNING_DOWNLOAD_MBPS=$partial_download TUNING_UPLOAD_MBPS=N/A TUNING_SPEEDTEST_SERVER=$partial_server
        return 2
    fi
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
    if ! tuning_is_interactive; then TUNING_BANDWIDTH=1000; TUNING_EFFECTIVE_MBPS=1000; TUNING_BANDWIDTH_SOURCE=FALLBACK_1000; return 0; fi
    printf '测速失败。可以使用默认值 1000 Mbps，或手工输入上传带宽。\n' >&2
    read -r -p '使用默认值 1000 Mbps？(Y/N) [Y]: ' answer || answer=Y
    answer=${answer:-Y}
    if [[ $answer =~ ^[Yy]$ ]]; then
        TUNING_BANDWIDTH=1000; TUNING_EFFECTIVE_MBPS=1000; TUNING_BANDWIDTH_SOURCE=FALLBACK_1000
    else
        value=$(tuning_read_positive '请输入上传带宽（Mbps）: ')
        TUNING_BANDWIDTH=$value; TUNING_EFFECTIVE_MBPS=$value; TUNING_BANDWIDTH_SOURCE=MANUAL_AFTER_FAILURE
    fi
}

tuning_choose_bandwidth() {
    local mode=${TUNING_BANDWIDTH_MODE:-} server=${TUNING_SERVER_ID:-} value=${TUNING_REQUESTED_BANDWIDTH:-} choice preset rc
    TUNING_DOWNLOAD_MBPS=N/A TUNING_UPLOAD_MBPS=N/A TUNING_EFFECTIVE_MBPS= TUNING_SPEEDTEST_SERVER=
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
            rc=1
            if tuning_install_speedtest; then rc=0; tuning_auto_speedtest || rc=$?; fi
            if (( rc == 0 || rc == 2 )); then TUNING_BANDWIDTH_SOURCE=AUTO_SPEEDTEST; else tuning_fallback_bandwidth; fi
            ;;
        server)
            [[ -n $server ]] || server=$(tuning_read_positive '请输入 Speedtest Server ID: ')
            rc=1
            if tuning_install_speedtest; then rc=0; tuning_run_speedtest "$server" || rc=$?; fi
            if (( rc == 0 || rc == 2 )); then TUNING_BANDWIDTH_SOURCE=SERVER_SPEEDTEST; TUNING_SPEEDTEST_SERVER=$server
            else tuning_fallback_bandwidth; fi
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
            TUNING_BANDWIDTH=$value; TUNING_EFFECTIVE_MBPS=$value; TUNING_BANDWIDTH_SOURCE=MANUAL_VALUE; TUNING_SPEEDTEST_DURATION=0
            ;;
        *) return 1 ;;
    esac
}

tuning_choose_region() {
    local requested=${TUNING_REQUESTED_REGION:-} choice
    if [[ -z $requested ]]; then
        if tuning_is_interactive; then
            printf '\n请选择主要网络类型：\n1. 亚太 / 低延迟连接为主\n2. 欧美 / 跨洲高延迟连接为主\n3. 全球混合 / 代理节点（推荐）\n' >&2
            read -r -p '请输入选择 [3]: ' choice || choice=3
            case ${choice:-3} in 1) requested=asia;; 2) requested=overseas;; *) requested=global;; esac
        else
            requested=asia
        fi
    fi
    case ${requested,,} in
        asia|apac) TUNING_REGION=asia; TUNING_PROFILE=ASIA_ORIGINAL;;
        overseas|us|eu|europe) TUNING_REGION=overseas; TUNING_PROFILE=OVERSEAS_ORIGINAL;;
        global|mixed|proxy|global_mixed) TUNING_REGION=global; TUNING_PROFILE=GLOBAL_MIXED;;
        *) return 1;;
    esac
}

tuning_finalize_bandwidth() {
    local download=${TUNING_DOWNLOAD_MBPS:-N/A} upload=${TUNING_UPLOAD_MBPS:-N/A}
    if [[ ${TUNING_BANDWIDTH_SOURCE:-} == MANUAL_VALUE || ${TUNING_BANDWIDTH_SOURCE:-} == MANUAL_AFTER_FAILURE || ${TUNING_BANDWIDTH_SOURCE:-} == FALLBACK_1000 ]]; then
        tuning_valid_mbps "${TUNING_BANDWIDTH:-}" || return 1
        TUNING_EFFECTIVE_MBPS=$TUNING_BANDWIDTH
        return 0
    fi
    if [[ $TUNING_REGION == global ]]; then
        if tuning_valid_mbps "$download" && tuning_valid_mbps "$upload"; then
            (( download > upload )) && TUNING_EFFECTIVE_MBPS=$download || TUNING_EFFECTIVE_MBPS=$upload
        elif tuning_valid_mbps "$download"; then TUNING_EFFECTIVE_MBPS=$download
        elif tuning_valid_mbps "$upload"; then TUNING_EFFECTIVE_MBPS=$upload
        else tuning_fallback_bandwidth; return
        fi
    else
        if tuning_valid_mbps "$upload"; then TUNING_EFFECTIVE_MBPS=$upload
        else tuning_fallback_bandwidth; return
        fi
    fi
    TUNING_BANDWIDTH=$TUNING_EFFECTIVE_MBPS
}

tuning_buffer_value() {
    local bw=$1 region=$2
    if ! [[ $bw =~ ^[0-9]+$ ]] || (( bw <= 0 )); then [[ $region == overseas || $region == global ]] && printf 64 || printf 16; return; fi
    if [[ $region == overseas || $region == global ]]; then
        case $bw in 100) printf 8;; 200) printf 16;; 300) printf 20;; 500) printf 32;; 700) printf 48;; 1000|1500|2000|2500) printf 64;; *) if ((bw<500)); then printf 16; elif ((bw<1000)); then printf 48; else printf 64; fi;; esac
    else
        case $bw in 100) printf 6;; 200) printf 8;; 300) printf 10;; 500) printf 12;; 700) printf 14;; 1000) printf 16;; 1500) printf 20;; 2000) printf 24;; 2500) printf 28;; *) if ((bw<500)); then printf 8; elif ((bw<1000)); then printf 12; elif ((bw<2000)); then printf 16; elif ((bw<5000)); then printf 24; elif ((bw<10000)); then printf 28; else printf 32; fi;; esac
    fi
}

tuning_choose_buffer() {
    local answer
    TUNING_BUFFER=$(tuning_buffer_value "$TUNING_BANDWIDTH" "$TUNING_REGION")
    if [[ ${TUNING_BUFFER_ACCEPT:-ask} == no ]]; then
        [[ $TUNING_REGION == overseas || $TUNING_REGION == global ]] && TUNING_BUFFER=32 || TUNING_BUFFER=16
        TUNING_BUFFER_SOURCE=REJECT_FALLBACK
        return
    elif tuning_is_interactive && [[ ${TUNING_BUFFER_ACCEPT:-ask} == ask ]]; then
        read -r -p "使用推荐 TCP Buffer ${TUNING_BUFFER} MiB？(Y/N) [Y]: " answer || answer=Y
        if [[ ! ${answer:-Y} =~ ^[Yy]$ ]]; then
            [[ $TUNING_REGION == overseas || $TUNING_REGION == global ]] && TUNING_BUFFER=32 || TUNING_BUFFER=16
            TUNING_BUFFER_SOURCE=REJECT_FALLBACK
            return
        fi
    fi
    TUNING_BUFFER_SOURCE=ORIGINAL_TABLE
}

tuning_low_memory_global_guard() {
    local memory answer
    [[ ${TUNING_REGION:-} == global ]] || return 0
    memory=${BBRV3_MEMORY_MB:-$(awk '/^MemTotal:/{printf "%d",$2/1024}' /proc/meminfo)}
    (( memory < 2048 )) || return 0
    printf '\n检测到当前内存低于 2 GiB。\n\n全球混合 / 代理节点模式会允许 TCP socket buffer\n在高带宽、高 RTT 活跃连接下增长到较高上限。\n\n注意：\n%s MiB 是单个 TCP socket 允许动态增长的上限，\n不是每个连接启动时立即占用 %s MiB。\n\n对于大量高吞吐并发连接，\n低内存 VPS 可能出现更高的内存压力。\n\n当前内存：%s MiB\n推荐 Buffer：%s MiB\n' "$TUNING_BUFFER" "$TUNING_BUFFER" "$memory" "$TUNING_BUFFER" >&2
    if ! tuning_is_interactive; then
        [[ ${TUNING_ACCEPT_LOW_MEMORY_GLOBAL:-NO} == YES ]] && return 0
        printf 'GLOBAL_LOW_MEMORY_CONFIRMATION_REQUIRED\n请显式使用 --accept-low-memory-global 授权，或选择 Asia / Overseas。\n' >&2
        return 3
    fi
    read -r -p '是否继续使用全球混合模式？[y/N]: ' answer || answer=N
    [[ ${answer:-N} =~ ^[Yy]$ ]]
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
    while :; do
        tuning_choose_region
        tuning_finalize_bandwidth
        tuning_choose_buffer
        if tuning_low_memory_global_guard; then break; fi
        if ! tuning_is_interactive || [[ -n ${TUNING_REQUESTED_REGION:-} ]]; then
            printf 'optimize=BLOCKED\nreason=GLOBAL_LOW_MEMORY_NOT_ACCEPTED\n' >&2
            return 3
        fi
        printf '\n已取消全球混合模式，请重新选择网络类型。\n' >&2
    done
}
