# BBRv3 Universal

BBRv3 Universal 是面向 Debian 12 AMD64 VPS 的 BBRv3/XanMod 网络调优工具。它保留原版 BBRv3 的 sysctl、buffer、FQ、RPS/RFS、TCPMSS、Route IW、THP、nofile 和 swap 能力，并加入适用性检测、资源 ownership、transaction、持久化、漂移保护、回滚和显式恢复。

> **当前正式版本：`v0.2.0`**。本版新增 System Default TCP Buffer 模式；Asia、Overseas 和 Global 行为保持不变，Global 仍是默认选项。首次在重要服务器使用前，请确保有 VPS 控制台或 fallback/reinstall 能力。

## Quick Start

正式支持范围是 **Debian 12、AMD64/x86_64**，需要 root。普通用户推荐使用状态优先的固定菜单入口；它会先检测服务器并显示菜单，不会启动就自动安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/torr9522/bbrv31/master/bbrv3.sh)
```

宽窗口自动显示双列菜单，窄窗口显示单列；底部实时显示系统、内核、BBR、队列和版本状态。支持 `NO_COLOR`，无网络时仍可使用本地菜单。

菜单选择安装后才会部署到 `/opt/bbrv3-universal`。推荐流程：

1. 运行菜单，选择 `1. 安装 / 修复 BBRv3 内核`。
2. 内核安装检查全部通过后，服务器会显示倒计时并自动重启。
3. 重启后重新运行菜单，选择 `3. BBRv3 网络优化`。
4. 按提示完成真实测速、网络类型和 TCP Buffer 选择。

“安装内核”和“网络优化”是两个独立阶段。菜单 1 不会静默执行测速、地区选择或网络参数修改；菜单 3 只在 formal BBRv3 kernel 正在运行时执行完整调优。

内部 bootstrap 安装入口下载并校验固定的 `v0.2.0` Release payload 和 formal kernel package：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/torr9522/bbrv31/master/bootstrap.sh)
```

bootstrap 会检查 Debian 12 和 x86_64，下载 release archive、checksum 和 formal kernel package，验证 SHA256，使用 `zstd` 解压到 `/opt/bbrv3-universal`，最后执行 kernel-only 的 `bbrv3-universal.sh install`。它不会关闭 TLS 校验，也不会自动执行 `apt full-upgrade`。已有 `/opt/bbrv3-universal` 时会拒绝覆盖，避免破坏未知安装。

安装和优化需要 root。菜单 1 只处理 kernel、initramfs、GRUB、fallback 和 reboot lifecycle；菜单 3 才会修改 sysctl、qdisc、route、RPS/RFS、TCPMSS、THP、nofile、swap 和 tuning persistence。正式 Release payload 会通过 bootstrap 放入已校验的 XanMod `.deb`。自动重启前会显示逐项检查结果、SSH 断开说明和倒计时。

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

`status` 是只读状态摘要；`install` 只处理 formal kernel lifecycle；`optimize` 执行真实带宽检测、Swap 检查、网络类型选择、buffer 计算和完整调优，且不会安装 kernel；`apply` 保留为非交互兼容入口，应用固定的 Asia 1000 Mbps policy。重复执行 `optimize` 会重新测速和选择，不会重新安装 kernel。

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

## BBRv3 网络优化与高级能力

菜单 3 默认执行真实 Ookla Speedtest，也支持指定 Speedtest Server ID 和手工带宽。网络类型共有四种：

1. `Asia`：以亚太、低 RTT 连接为主，使用原版较小 Buffer ceiling 曲线。
2. `Overseas`：以欧美、跨洲高 RTT 连接为主，使用原版较大 Buffer ceiling 曲线。
3. `Global`：适合 Telegram、X/Twitter、TikTok、全球网页/App，以及亚洲和欧美混合目的地的通用代理节点。这是默认推荐选项。
4. `System`：BBRv3 Universal 不主动管理四项 TCP Buffer ceiling，适合希望保留系统/provider 设置，或担心小内存高并发 socket memory 压力的用户。

Global 的正式策略名为 `GLOBAL_MIXED_OVERSEAS_CURVE_V1`。自动测速和指定 Server ID 模式会读取 Download 与 Upload，并以两个有效结果中的较大值作为有效带宽；仅一侧有效时使用该侧，手工模式则直接把输入值作为有效带宽。Global 复用已经验收的 Overseas buffer 曲线，没有新增第三套经验数值表，也不执行自动多洲 RTT 探测。Asia 和 Overseas 仍按 v0.1.9 的 upload 输入与原版数值工作。

System 模式只释放 `net.core.rmem_max`、`net.core.wmem_max`、`net.ipv4.tcp_rmem` 和 `net.ipv4.tcp_wmem` 的项目管理权。首次接管前的真实值会保存为带校验的不可变 baseline；从 Asia、Overseas 或 Global 切换时，项目以事务方式恢复该 baseline，并从项目自有 sysctl 文件中删除这四项。找不到可信 baseline 时会安全阻止切换，不会猜测 Debian 或 Kernel 默认值，也不会修改系统、provider 或用户自己的 sysctl 文件。

System 模式不等于关闭 BBR、FQ 或其它优化。其余 27 项通用 sysctl、RPS/RFS、MSS、Route IW、THP、nofile、Swap、持久化、readback 和 recovery 仍会执行。Linux TCP autotuning 仍然存在；System 只是让这四项上限由系统/provider 管理。这是更保守的选择，不代表绝对不会发生 OOM，也不保证比 Global 更快。

内存低于 2 GiB 时，Global 会在任何网络或系统参数 apply 之前说明动态 socket buffer 的内存风险并要求明确确认；拒绝后返回网络类型选择，不会静默降低 Buffer 或继续应用。测速完全失败时仍会明确提供 1000 Mbps fallback 或手工输入。系统会根据 CPU、网卡 RX queues/RSS、内存、swap、默认 route、forwarding 和已有 qdisc 判断 APPLY、NOOP、SKIP 或 CONFLICT；单 CPU 会跳过 RPS，非 forwarding 主机会跳过 MSS。

正式调优路径包括 Asia/Overseas/Global 的 31 项 sysctl，或 System 的 27 项项目管理加 4 项明确 unmanaged 策略，以及 FQ、RPS/RFS、TCPMSS、IW 32/32、THP、nofile 524288、swap 和持久化 readback。原版 31 项功能审计保持不变；System 是用户明确选择的策略例外。CAKE 与本版要求的 FQ canonical path 冲突，因此只保留审计记录，不提供自动 mutation。原版临时 Reality profiles 含非核心应用调优或与持久 policy 冲突，已记录审计结论但不接入菜单 3。

固定的 `bbrv3.sh` 会进入数字交互菜单。菜单启动和每次返回时都会重新读取系统、虚拟化、运行 kernel、BBR、qdisc、fallback kernel、项目版本和 persistence 状态。原有命名 CLI 仍保留，适合脚本和高级用户。

菜单包含 kernel 安装/修复、BBRv3 网络优化、详细状态、kernel 状态、回滚、显式恢复、高级设置、更新和卸载项目等真实后端操作。菜单打开后输入 `0` 只退出，不会改变系统。

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

`v0.1.7` 保留了 RC1/v0.1.1/v0.1.2/v0.1.3/v0.1.4/v0.1.5/v0.1.6 已验收的功能、kernel、persistence、recovery 和 rollback，并修复已有自定义内核和显式 `GRUB_DEFAULT` 时 one-shot XanMod 启动没有转换为长期默认启动项的问题。成功启动 formal kernel 后，项目会保存原 GRUB 配置，将默认选择切换为已验证的 saved entry，并在失败时回滚。TcpQuality/NodeQuality 的部分第三方 endpoint 受外部限制，因此没有发布公网吞吐提升百分比，也没有把 benchmark 当成 runtime 依赖。

仍待扩展的 coverage 包括 native 512 MiB host、更多 nft-only provider 以及更多 RSS/IRQ layouts。这些不是当前正式版本的功能 blocker。0.x 版本仍建议重要服务器保持控制台或重装能力。

当前正式 Release：<https://github.com/torr9522/bbrv31/releases/tag/v0.2.0>

上一正式 Release（冻结且保留不变）：<https://github.com/torr9522/bbrv31/releases/tag/v0.1.10>

长期冻结基线：<https://github.com/torr9522/bbrv31/releases/tag/v0.1.9>

更早正式 Release（保留不变）：<https://github.com/torr9522/bbrv31/releases/tag/v0.1.8>

更早正式 Release（保留不变）：<https://github.com/torr9522/bbrv31/releases/tag/v0.1.7>

历史 RC1 Release（冻结，不再作为推荐安装版本）：<https://github.com/torr9522/bbrv31/releases/tag/v0.1.0-rc1>

## 高级源码安装

源码方式安装（高级用户）：

```bash
tmp=$(mktemp -d) && git clone --depth 1 --branch v0.2.0 https://github.com/torr9522/bbrv31.git "$tmp/bbrv31" && sudo bash "$tmp/bbrv31/bbrv3.sh"
```

固定安装入口位于 `master`，但默认 payload 始终是显式固定的正式 Release。以后版本升级只需更新 bootstrap 的默认版本；用户使用的 URL 不变。`v0.1.0-rc1` tag 和 release asset 永久保留且不被修改。

## 来源与许可

原版优化行为与映射信息保存在 `metadata/source-map.tsv`，项目保留对上游 `Eric86777/vps-tcp-tune` 相关行为的来源追踪。请在部署前按你的环境和上游许可要求进行审核；本仓库当前没有擅自添加新的许可证声明。
