#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
PROJECT_ROOT=${BBRV3_MENU_PROJECT_ROOT:-/opt/bbrv3-universal}
FORMAL_KERNEL=6.18.54-x64v3-xanmod1

source "$ROOT/src/menu-ui.sh"
ui_init

say() { printf '%s\n' "$*"; }
pause() { [[ -t 0 ]] || return 0; printf '\n按 Enter 返回主菜单...'; read -r _ || true; }
trap 'printf "\n已退出。\n"; exit 130' INT TERM

detect_state() {
    . /etc/os-release
    OS_NAME=${PRETTY_NAME:-${NAME:-unknown}}
    OS_VERSION=${VERSION_ID:-unknown}
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    VIRT=$(systemd-detect-virt 2>/dev/null || printf unknown)
    RUNNING_KERNEL=$(uname -r)
    FORMAL_KERNEL_INSTALLED=NO
    dpkg-query -W -f='${Status}' "linux-image-$FORMAL_KERNEL" 2>/dev/null | grep -q 'install ok installed' && FORMAL_KERNEL_INSTALLED=YES || true
    FORMAL_KERNEL_RUNNING=NO
    [[ $RUNNING_KERNEL == "$FORMAL_KERNEL" ]] && FORMAL_KERNEL_RUNNING=YES
    FALLBACK_KERNELS=$(dpkg-query -W -f='${Package}\n' 'linux-image-*' 2>/dev/null | grep -v "$FORMAL_KERNEL" | sed 's/^linux-image-//' | grep -E '^[0-9]' | sort -u || true)
    FALLBACK_KERNEL=$(printf '%s\n' "$FALLBACK_KERNELS" | head -1)
    FALLBACK_COUNT=$(printf '%s\n' "$FALLBACK_KERNELS" | awk 'NF {n++} END {print n+0}')
    CC_ACTIVE=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf unknown)
    CC_AVAILABLE=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf unknown)
    QDISC=$(tc qdisc show 2>/dev/null | awk '
        $1=="qdisc" && $5!="lo" { if ($6=="root") root=$2; else if ($6=="parent") leaf[$2]=1 }
        END { if (root=="mq" && leaf["fq"]) print "fq (mq)"; else print root }' || true)
    [[ -n $QDISC ]] || QDISC=unknown
    PROJECT_INSTALLED=NO
    [[ -x $PROJECT_ROOT/bbrv3-universal.sh ]] && PROJECT_INSTALLED=YES
    PROJECT_VERSION=未安装
    [[ -r $PROJECT_ROOT/VERSION ]] && PROJECT_VERSION=$(<"$PROJECT_ROOT/VERSION")
    PERSISTENCE=未启用
    [[ -e /var/lib/bbrv3-universal/persistence/enabled ]] && PERSISTENCE=已启用
    LATEST_VERSION=检查失败
    if command -v curl >/dev/null 2>&1; then
        latest=$(curl -fsSL --max-time 3 "https://raw.githubusercontent.com/torr9522/bbrv31/master/LATEST_VERSION?cache=$(date +%s)" 2>/dev/null || true)
        if [[ $latest =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            LATEST_VERSION=$latest
        fi
    fi
}

kernel_status_text() {
    if [[ $FORMAL_KERNEL_RUNNING == YES ]]; then
        printf '%sBBRv3 内核已安装并运行%s' "$C_GREEN" "$C_RESET"
    elif [[ $FORMAL_KERNEL_INSTALLED == YES ]]; then
        printf '%sBBRv3 内核已安装，当前未运行%s' "$C_YELLOW" "$C_RESET"
    else
        printf '%sBBRv3 内核未安装（当前运行其他内核）%s' "$C_YELLOW" "$C_RESET"
    fi
}

render_ui() {
    ui_layout
    [[ -t 1 && -n ${TERM:-} && $TERM != dumb ]] && clear 2>/dev/null || true
    printf '%sBBRv3 Universal 一键安装管理脚本%s %s[v%s]%s\n' "$C_CYAN" "$C_RESET" "$C_RED" "$(<"$ROOT/VERSION")" "$C_RESET"
    printf '%s当前支持：%s%sDebian 12 AMD64%s\n' "$C_BLUE" "$C_RESET" "$C_WHITE" "$C_RESET"
    ui_section 'BBRv3 安装'
    ui_pair 1 '安装 BBRv3 内核 + AUTO' 2 '安装 / 修复 BBRv3 内核'
    ui_section '优化与状态'
    ui_pair 3 'AUTO 自动优化' 4 '查看详细状态'
    ui_pair 5 '查看内核状态'
    ui_section '恢复与维护'
    ui_pair 6 '回滚本项目优化' 7 '强制恢复本项目基线'
    ui_pair 8 '高级设置' 9 '更新 BBRv3 Universal'
    ui_item 10 '卸载 BBRv3 Universal' "$C_YELLOW"; printf '\n'
    ui_item 0 '退出'; printf '\n'
    ui_separator
    case $VIRT in kvm) display_virt=KVM;; microsoft) display_virt=Microsoft;; amazon) display_virt=Amazon;; none) display_virt=物理机;; *) display_virt=$VIRT;; esac
    printf '%s信息：%s%s | %s | %s | %s\n' "$C_CYAN" "$C_RESET" "$OS_NAME" "$display_virt" "$ARCH" "$RUNNING_KERNEL"
    printf '%s状态：%s' "$C_CYAN" "$C_RESET"; kernel_status_text
    if (( FALLBACK_COUNT > 0 )); then
        printf ' | %s原系统内核已保留（%s个）%s\n' "$C_GREEN" "$FALLBACK_COUNT" "$C_RESET"
    else
        printf ' | %s原系统内核未识别%s\n' "$C_YELLOW" "$C_RESET"
    fi
    printf '%s网络：%s%s%s | %s%s\n' "$C_CYAN" "$C_RESET" "$C_GREEN" "$CC_ACTIVE" "$QDISC" "$C_RESET"
    local project_text=未安装 project_color=$C_YELLOW persistence_color=$C_YELLOW latest_color=$C_YELLOW
    [[ $PROJECT_INSTALLED == YES ]] && { project_text="v$PROJECT_VERSION"; project_color=$C_GREEN; }
    [[ $PERSISTENCE == 已启用 ]] && persistence_color=$C_GREEN
    [[ $LATEST_VERSION == "$PROJECT_VERSION" ]] && latest_color=$C_GREEN
    local latest_text=$LATEST_VERSION
    [[ $LATEST_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && latest_text="v$LATEST_VERSION"
    printf '%s项目：%s%s%s%s | 持久化 %s%s%s | 最新 %s%s%s\n' "$C_CYAN" "$C_RESET" "$project_color" "$project_text" "$C_RESET" "$persistence_color" "$PERSISTENCE" "$C_RESET" "$latest_color" "$latest_text" "$C_RESET"
    ui_separator
}
render() { detect_state; render_ui; }

require_root() { [[ $EUID -eq 0 ]] || { printf '%s需要 root 权限。%s\n' "$C_ERR" "$C_RESET"; pause; return 1; }; }
payload_install_if_needed() {
    [[ ${BBRV3_MENU_PAYLOAD_ROOT:-} ]] || return 0
    [[ ! -e $PROJECT_ROOT ]] || { printf '%s安装目录已存在，停止覆盖。%s\n' "$C_ERR" "$C_RESET"; return 1; }
    install -d -m 755 "$PROJECT_ROOT"
    cp -a "$BBRV3_MENU_PAYLOAD_ROOT/." "$PROJECT_ROOT/"
    ROOT=$PROJECT_ROOT
}

run_action() {
    local action=$1 rc=0
    require_root || return 0
    payload_install_if_needed || return 0
    case $action in
        install) "$ROOT/bbrv3-universal.sh" install || rc=$?;;
        optimize) "$ROOT/bbrv3-universal.sh" optimize || rc=$?;;
        status) ui_section "详细状态"; "$ROOT/bbrv3-universal.sh" status-detail || rc=$?;;
        kernel) ui_section "内核状态"; "$ROOT/bbrv3-universal.sh" kernel-status || rc=$?;;
        rollback) "$ROOT/bbrv3-universal.sh" rollback || rc=$?;;
        recover) "$ROOT/bbrv3-universal.sh" recover || rc=$?;;
        advanced) ui_section "高级设置"; "$ROOT/bbrv3-universal.sh" advanced || rc=$?;;
        uninstall) "$ROOT/bbrv3-universal.sh" uninstall || rc=$?;;
        update) "$ROOT/bbrv3.sh" --update || rc=$?;;
    esac
    [[ $rc -eq 75 ]] && return 75
    (( rc == 0 )) || printf '%s操作失败，返回码=%s%s\n' "$C_ERR" "$rc" "$C_RESET"
    pause
}

main() {
    while :; do
        render
        printf '请输入数字：'
        read -r choice || exit 0
        case $choice in
            1)
                if run_action install; then
                    :
                else
                    rc=$?
                    [[ $rc -eq 75 ]] && exit 75
                    return "$rc"
                fi
                ;;
            2) run_action install;;
            3) run_action optimize;;
            4) run_action status;;
            5) run_action kernel;;
            6) run_action rollback;;
            7) run_action recover;;
            8) run_action advanced;;
            9) run_action update;;
            10) run_action uninstall;;
            0) say '已退出。'; exit 0;;
            *) printf '%s无效选项，请重新输入。%s\n' "$C_WARN" "$C_RESET"; pause;;
        esac
    done
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
