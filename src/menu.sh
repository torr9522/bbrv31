#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=${BBRV3_UNIVERSAL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
PROJECT_ROOT=${BBRV3_MENU_PROJECT_ROOT:-/opt/bbrv3-universal}
FORMAL_KERNEL=6.18.54-x64v3-xanmod1

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_TITLE=$'\033[1;36m'; C_SECTION=$'\033[1;34m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'
else
    C_RESET= C_TITLE= C_SECTION= C_OK= C_WARN= C_ERR=
fi

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
    FALLBACK_KERNEL=$(dpkg-query -W -f='${Package}\n' 'linux-image-*' 2>/dev/null | grep -v "$FORMAL_KERNEL" | sed 's/^linux-image-//' | head -1 || true)
    CC_ACTIVE=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf unknown)
    CC_AVAILABLE=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf unknown)
    QDISC=$(tc qdisc show 2>/dev/null | awk '$1=="qdisc" && $6=="root" && $5!="lo" {print $2; exit}' || true)
    [[ -n $QDISC ]] || QDISC=unknown
    PROJECT_INSTALLED=NO
    [[ -x $PROJECT_ROOT/bbrv3-universal.sh ]] && PROJECT_INSTALLED=YES
    PROJECT_VERSION=未安装
    [[ -r $PROJECT_ROOT/VERSION ]] && PROJECT_VERSION=$(<"$PROJECT_ROOT/VERSION")
    PERSISTENCE=未启用
    [[ -e /var/lib/bbrv3-universal/persistence/enabled ]] && PERSISTENCE=已启用
    LATEST_VERSION=检查失败
    if command -v curl >/dev/null 2>&1; then
        latest=$(curl -fsSL --max-time 3 https://raw.githubusercontent.com/torr9522/bbrv31/master/LATEST_VERSION 2>/dev/null || true)
        if [[ $latest =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            LATEST_VERSION=$latest
        fi
    fi
}

kernel_status_text() {
    if [[ $FORMAL_KERNEL_RUNNING == YES ]]; then
        printf '%sBBRv3 Kernel：已安装并运行%s' "$C_OK" "$C_RESET"
    elif [[ $FORMAL_KERNEL_INSTALLED == YES ]]; then
        printf '%sBBRv3 Kernel：已安装，当前未运行%s' "$C_WARN" "$C_RESET"
    else
        printf '%sBBRv3 Kernel：未安装%s' "$C_WARN" "$C_RESET"
    fi
}

render() {
    detect_state
    clear 2>/dev/null || true
    printf '%sBBRv3 Universal 一键安装管理脚本 [v%s]%s\n' "$C_TITLE" "$(<"$ROOT/VERSION")" "$C_RESET"
    printf '%s当前支持：Debian 12 AMD64%s\n\n' "$C_SECTION" "$C_RESET"
    printf '%s---------------- BBRv3 安装 ----------------%s\n' "$C_SECTION" "$C_RESET"
    printf '  1. 安装 BBRv3 Kernel + AUTO 自动优化\n'
    printf '  2. 安装 / 修复 BBRv3 Kernel\n\n'
    printf '%s---------------- 优化与状态 ----------------%s\n' "$C_SECTION" "$C_RESET"
    printf '  3. AUTO 自动优化\n  4. 查看详细状态\n  5. 查看 Kernel 状态\n\n'
    printf '%s---------------- 恢复与维护 ----------------%s\n' "$C_SECTION" "$C_RESET"
    printf '  6. 回滚本项目优化\n  7. 强制恢复本项目基线\n  8. 高级设置\n  9. 更新 BBRv3 Universal\n 10. 卸载 BBRv3 Universal\n  0. 退出\n\n'
    printf '%s信息：%s | %s | %s | %s%s\n' "$C_TITLE" "$OS_NAME" "$VIRT" "$ARCH" "$RUNNING_KERNEL" "$C_RESET"
    printf '状态：'; kernel_status_text; printf '\n'
    printf '拥塞算法：%s\n队列算法：%s\n' "$CC_ACTIVE" "$QDISC"
    printf 'Fallback Kernel：%s\n' "${FALLBACK_KERNEL:-未识别} [已保留]"
    printf '项目：%s%s%s\n持久化：%s\n最新版本：%s\n\n' "$([[ $PROJECT_INSTALLED == YES ]] && printf 已安装 || printf 未安装)" "$([[ $PROJECT_INSTALLED == YES ]] && printf ' ' || true)" "$([[ $PROJECT_INSTALLED == YES ]] && printf "[$PROJECT_VERSION]" || true)" "$PERSISTENCE" "$LATEST_VERSION"
}

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
        status) "$ROOT/bbrv3-universal.sh" status-detail || rc=$?;;
        kernel) "$ROOT/bbrv3-universal.sh" kernel-status || rc=$?;;
        rollback) "$ROOT/bbrv3-universal.sh" rollback || rc=$?;;
        recover) "$ROOT/bbrv3-universal.sh" recover || rc=$?;;
        advanced) "$ROOT/bbrv3-universal.sh" advanced || rc=$?;;
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
            1) run_action install || [[ $? -eq 75 ]] && exit 75;;
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
main "$@"
