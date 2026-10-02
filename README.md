# BBRv3 Universal

BBRv3 Universal 是面向 Debian 12 AMD64 VPS 的 BBRv3/XanMod 网络调优工具。它保留原版 BBRv3 的 sysctl、buffer、FQ、RPS/RFS、TCPMSS、Route IW、THP、nofile 和 swap 能力，并加入适用性检测、资源 ownership、transaction、持久化、漂移保护、回滚和显式恢复。

> **当前正式版本：`v0.1.6`**。这是加入状态优先交互菜单、修正菜单安装返回行为并兼容已安装旧 payload 后的 Debian 12 AMD64 正式版本。首次在重要服务器使用前，请确保有 VPS 控制台或 fallback/reinstall 能力。

## Quick Start

正式支持范围是 **Debian 12、AMD64/x86_64**，需要 root。普通用户推荐使用状态优先的固定菜单入口；它会先检测服务器并显示菜单，不会启动就自动安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/torr9522/bbrv31/master/bbrv3.sh)
```

菜单选择安装后才会部署到 `/opt/bbrv3-universal`。内部 bootstrap 安装入口仍会下载并校验固定的 `v0.1.6` Release payload 和 formal kernel package：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/torr9522/bbrv31/master/bootstrap.sh)
```

bootstrap 会检查 Debian 12 和 x86_64，下载 release archive、checksum 和 formal kernel package，验证 SHA256，使用 `zstd` 解压到 `/opt/bbrv3-universal`，最后执行 `bbrv3-universal.sh install`。它不会关闭 TLS 校验，也不会自动执行 `apt full-upgrade`。已有 `/opt/bbrv3-universal` 时会拒绝覆盖，避免破坏未知安装。

安装需要 root，并可能修改 sysctl、qdisc、route、RPS/RFS、TCPMSS、THP、nofile、swap 和 systemd persistence。正式 Release payload 会通过 bootstrap 放入已校验的 XanMod `.deb`。安装内核或执行 one-shot boot 时 SSH 可能暂时断开；resume/persistence 设计用于重启后继续。

## 支持范围

| 项目 | 当前正式支持范围 |
| --- | --- |
| OS | Debian 12 |
| Architecture | AMD64 / x86_64 |
| Formal kernel baseline | `6.18.54-x64v3-xanmod1` |
| CPU path | x86-64-v1/v2/v3/v4 policy detection；当前 formal verified artifact 为 x64v3 |
| Memory | 约 1 GiB 已真实覆盖；native 512 MiB 属于 future coverage |
| Boot | BIOS、UEFI 已覆盖 |
| Other OS/arch | Debian 11、Debian 13、Ubuntu、ARM64 不属于当前正式支持范围 |

真实验收覆盖了多个 Debian 12 AMD64 VPS，包含 1/2 CPU、约 1 GiB 内存以及不同虚拟化环境。它不代表所有 provider 或网卡拓扑都已认证。

## 安装后操作

所有正式命令都通过 `bbrv3-universal.sh --help` 查看。常用命令：

```bash
/opt/bbrv3-universal/bbrv3-universal.sh status
/opt/bbrv3-universal/bbrv3-universal.sh optimize
/opt/bbrv3-universal/bbrv3-universal.sh apply
/opt/bbrv3-universal/bbrv3-universal.sh rollback
/opt/bbrv3-universal/bbrv3-universal.sh recover
/opt/bbrv3-universal/bbrv3-universal.sh advanced
/opt/bbrv3-universal/bbrv3-universal.sh --help
```

`status` 是只读状态摘要；`optimize` 重新检测并应用当前 policy，已满足的资源会变成 NOOP，不会因为重复执行而重新安装 kernel；`apply` 应用当前 sysctl、network 和 system-resource plans。

当前 CLI 的公共入口是 `install`、`optimize`、`apply`、`status`、`rollback`、`recover`、`reboot`、`uninstall`、`one-click`、`advanced`、`detect` 和 `dry-run`。底层的 `plan/apply/verify/rollback/recover-{sysctl,network,resources}` 以及 `kernel-plan`、`kernel-status`、`kernel-install`、`kernel-update`、`kernel-uninstall` 也保留给高级用户。

## Kernel 行为

默认情况下，项目不会删除系统已有的 Debian kernel；安装流程会先记录 fallback kernel，并保护 fallback。kernel install/update 需要一个本地 `.deb`：

```bash
/opt/bbrv3-universal/bbrv3-universal.sh kernel-plan
/opt/bbrv3-universal/bbrv3-universal.sh kernel-install /path/to/linux-image-xanmod.deb
/opt/bbrv3-universal/bbrv3-universal.sh kernel-status
```

`kernel-uninstall <package>` 只有在当前没有运行该 XanMod kernel、且存在非 XanMod fallback 时才会继续；它不会盲目删除正在运行的 kernel。kernel uninstall 与网络 tuning rollback 是两件不同的事。当前 CLI 没有伪造的 `kernel-fallback` 命令；fallback 会由 lifecycle/GRUB protection 记录，必要时使用 provider console 选择 Debian fallback 或执行 provider recovery。

## 回滚、恢复与卸载

### 普通回滚

```bash
/opt/bbrv3-universal/bbrv3-universal.sh rollback
```

普通 rollback 只处理本项目 owned 的 network/system resources，并保留 drift protection。发现运行时值、route identity、qdisc 或第三方资源发生外部变化时，会安全阻止覆盖并报告原因。

### 显式恢复

```bash
/opt/bbrv3-universal/bbrv3-universal.sh recover
```

`recover` 是明确的 owned-baseline recovery，使用 transaction 中记录的 baseline 和 ownership。它不会扫描系统猜测默认值，也不会 flush 整个 sysctl、route 或 firewall。只有确认要覆盖本项目记录的 drift 时才使用。

### 项目卸载

```bash
/opt/bbrv3-universal/bbrv3-universal.sh uninstall
```

项目卸载会尝试安全回滚 owned tuning，移除本项目 persistence unit、wrapper 和 enabled marker。它不等同于 kernel uninstall，也不会默认删除 Debian fallback kernel。若普通 rollback 被 drift 阻止，应先检查 `status`，再按需使用 `recover`。

## AUTO、兼容模式与高级能力

AUTO 会根据 CPU、网卡 RX queues/RSS、内存、swap、默认 route、forwarding 和已有 qdisc 判断 APPLY、NOOP、SKIP、DEFER 或 CONFLICT。它不会为了“启用更多功能”强行改动不适用的 provider topology，例如单 CPU 的 RPS 或非 forwarding 主机的 MSS。

`COMPAT_ORIGINAL` 用于尽量保持原版行为，包括 31 项 sysctl、Asia/Overseas buffer 分支、FQ、RPS/RFS、TCPMSS、IW 32/32、THP、nofile 524288 和 swap 行为。`advanced` 可查看 profiles、FQ/qdisc、CAKE、RPS/RFS、MSS、Route IW、THP、nofile、swap 和 kernel capability；CAKE 是高级能力，不代表默认启用。

固定的 `bbrv3.sh` 会进入数字交互菜单。菜单启动和每次返回时都会重新读取系统、虚拟化、运行 kernel、BBR、qdisc、fallback kernel、项目版本和 persistence 状态。原有命名 CLI 仍保留，适合脚本和高级用户。

菜单包含安装/AUTO、详细状态、kernel 状态、回滚、显式恢复、高级设置、更新和卸载项目等真实后端操作。菜单打开后输入 `0` 只退出，不会改变系统。

## 安全与故障处理

项目会记录 baseline、ownership 和 transaction，并在 apply 后 read-back verify。持久化由 owned reconcile unit 管理。内核切换期间 SSH 断开是预期现象；若长时间无法恢复，请使用 VPS console 检查 fallback boot 或 provider recovery，不要首先手工覆盖 GRUB。

建议排查顺序：

```bash
/opt/bbrv3-universal/bbrv3-universal.sh status
/opt/bbrv3-universal/bbrv3-universal.sh status-detail
/opt/bbrv3-universal/bbrv3-universal.sh kernel-status
/opt/bbrv3-universal/bbrv3-universal.sh rollback
# 只有确认要恢复本项目 baseline 时：
/opt/bbrv3-universal/bbrv3-universal.sh recover
```

## 正式版本注意事项

`v0.1.6` 保留了 RC1/v0.1.1/v0.1.2/v0.1.3/v0.1.4/v0.1.5 已验收的功能、kernel、persistence、recovery 和 rollback，并修正已安装旧 payload 重新打开公开菜单时的兼容性。菜单的最新版检查使用缓存规避参数，避免 raw GitHub CDN 延迟造成错误版本显示。TcpQuality/NodeQuality 的部分第三方 endpoint 受外部限制，因此没有发布公网吞吐提升百分比，也没有把 benchmark 当成 runtime 依赖。

仍待扩展的 coverage 包括 native 512 MiB host、更多 nft-only provider 以及更多 RSS/IRQ layouts。这些不是当前正式版本的功能 blocker。0.x 版本仍建议重要服务器保持控制台或重装能力。

当前正式 Release：<https://github.com/torr9522/bbrv31/releases/tag/v0.1.6>

上一正式 Release（保留不变）：<https://github.com/torr9522/bbrv31/releases/tag/v0.1.5>

历史 RC1 Release（冻结，不再作为推荐安装版本）：<https://github.com/torr9522/bbrv31/releases/tag/v0.1.0-rc1>

## 高级源码安装

源码方式安装（高级用户）：

```bash
tmp=$(mktemp -d) && git clone --depth 1 --branch v0.1.6 https://github.com/torr9522/bbrv31.git "$tmp/bbrv31" && sudo bash "$tmp/bbrv31/bbrv3.sh"
```

固定安装入口位于 `master`，但默认 payload 始终是显式固定的正式 Release。以后版本升级只需更新 bootstrap 的默认版本；用户使用的 URL 不变。`v0.1.0-rc1` tag 和 release asset 永久保留且不被修改。

## 来源与许可

原版优化行为与映射信息保存在 `metadata/source-map.tsv`，项目保留对上游 `Eric86777/vps-tcp-tune` 相关行为的来源追踪。请在部署前按你的环境和上游许可要求进行审核；本仓库当前没有擅自添加新的许可证声明。
