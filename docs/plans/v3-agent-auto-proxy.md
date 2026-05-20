# Network Proxy Watchdog v3 — Agent 无感代理 整合评审与实施计划

> **评审日期:** 2026-05-19
> **来源:** v3-agent-auto-proxy.md (9 tasks) + wsl2-proxy-pain-points-research.md (14 痛点)

---

## 一、痛点覆盖分析

### 1.1 已覆盖的痛点（7/14）

| # | 痛点 | 覆盖 Task | 覆盖程度 |
|---|------|-----------|----------|
| #2 | 代理守护进程默默崩溃 | Task 0 (心跳检测) | 完整 |
| #11 | 休眠唤醒后代理失效 | Task 0 + Task 8 | 完整 |
| #9 | Git/pip/npm 等工具挂起超时 | Task 1 + Task 2 + Task 3 | 完整（通过三段式决策避免超时） |
| #10 | 分流路由失败（国内慢/国外不通） | Task 1 (路由表 200+) | 完整 |
| #6 | TUN vs system proxy 混乱 | Task 4 (状态文件) | 间接（提供地面真相状态） |
| #13 | GUI 代理状态与实际不一致 | Task 4 (状态文件) | 间接 |
| #1 | WSL2 IP 重启后变化 | Task 8 (wake-guard) | 部分（仅处理休眠唤醒，未处理重启后 IP 自动检测） |

### 1.2 未覆盖的痛点（7/14）

| # | 痛点 | 原因 | 建议 |
|---|------|------|------|
| #3 | 代理端口变化后配置过期 | 需要端口扫描能力 | v3.1 考虑：扫描常见代理端口并自动更新 |
| #4 | DNS 泄漏/GFW DNS 投毒 | 需要 DNS 对比检测 | v3.1 考虑：代理 vs 直连 DNS 解析对比 |
| #5 | 企业 VPN + WSL2 + 代理三重冲突 | 太复杂，需要单独的项目 | 不做。建议用户手动处理或用 wsl-vpnkit |
| #7 | Docker 容器绕过代理 | Docker 独立网络栈 | 不做。属于 Docker 配置问题，非 watchdog 职责 |
| #8 | VSCode Remote-WSL 断开 | VSCode 自身问题 | 不做。确保 localhost 不被代理即可（路由表已覆盖） |
| #12 | PortProxy 自环 | LOW 优先级，边缘场景 | 不做。影响面太小 |
| #14 | GFW 主动探测断流 | 无法程序化解决 | 不做。属于协议层面问题，非 watchdog 能干预 |

### 1.3 不值得做的痛点

- **#5 (VPN 冲突):** 需要内核级网络栈操作，超出 watchdog 范围。现有 wsl-vpnkit (2,887★) 已有成熟方案。
- **#8 (VSCode 断开):** 这是 VSCode Remote-WSL 扩展的 bug，不是代理问题。
- **#12 (PortProxy 自环):** 极少数用户会遇到，且已有文档化 workaround。
- **#14 (GFW 断流):** 无程序化解决方案，协议选择属于用户决策。

---

## 二、Task 优先级与依赖关系评估

### 2.1 原计划问题

原计划 Task 顺序为 0→1→2→3→4→5→6→7→8，存在以下依赖冲突：

| 问题 | 详情 |
|------|------|
| Task 0 依赖 Task 4 | 心跳脚本读取 `~/.hermes/.proxy_state`，但状态文件在 Task 4 才创建 |
| Task 3 依赖 Task 1, 2, 4 | agent-check 需要路由表、TCP 探测函数、状态文件三者就绪 |
| Task 5 依赖 Task 3 | SKILL.md 引用的 `agent-check` 命令在 Task 3 才存在 |
| Task 8 依赖 Task 0 | wake-guard 调用 `proxy-heartbeat --once` |

### 2.2 修正后的依赖链

```
Task 1 (路由表) ─┐
                  ├─→ Task 3 (agent-check) ─→ Task 5 (SKILL.md)
Task 2 (TCP检测) ─┤
                  │
Task 4 (状态文件)─┴─→ Task 0 (心跳) ─→ Task 8 (唤醒恢复)
                                           │
Task 6 (集成测试) ←─────────────────────────┘
  ↓
Task 7 (安装+发布)
```

### 2.3 建议执行顺序

| 顺序 | Task | 依赖 | 理由 |
|------|------|------|------|
| 1 | **Task 1** 路由表扩展 | 无 | 纯数据，无代码依赖，先扩展域名覆盖 |
| 2 | **Task 4** 代理状态文件 | 无 | 轻量改动，Task 0 和 Task 3 都需要 |
| 3 | **Task 2** TCP 端口检测 | Task 1 (共用路由概念) | 改 netcheck.sh，与路由表配合 |
| 4 | **Task 0** 代理心跳 | Task 4 (状态文件) | 心跳依赖 `.proxy_state` |
| 5 | **Task 3** agent-check | Task 1, 2, 4 | 聚合三层决策的入口命令 |
| 6 | **Task 5** SKILL.md 重写 | Task 3 | 文档引用 agent-check 命令 |
| 7 | **Task 8** 休眠唤醒恢复 | Task 0 (心跳) | wake-guard 调用 heartbeat |
| 8 | **Task 6** 集成测试 | 以上所有 | 端到端验证 |
| 9 | **Task 7** 安装+发布 | Task 6 通过 | 测试通过后发布 |

---

## 三、过度设计分析

### 3.1 可砍掉的部分

| 位置 | 内容 | 理由 |
|------|------|------|
| Task 0 Step 4 | cron 心跳守护 + 脚本内循环守护 **二选一** | 当前设计：cron 每分钟触发 + 脚本内 30s 循环 + PID 防重叠。过度防御。保留 cron（每分钟调 `--once`），去掉脚本内循环模式。 |
| Task 2 | `tcp_latency()` 延迟测量函数 | 决策只需 pass/fail，不需要毫秒级延迟。如果未来需要延迟分级（<500ms 直连，>500ms 走代理），再加。当前版本可去掉。 |
| Task 3 | TTY 人类可读模式 | agent 不读彩色输出。保留 JSON 输出即可。如需人类调试，加 `--pretty` 可选参数。 |
| Task 3 Step 2 | 递归调用自身解析 JSON | 用 `$0` 重调自己来美化输出，实现丑陋且易出错。如需美化，用 Python 一行搞定。 |
| Task 8 | wake-guard 中的 `api.sgroup.qq.com` DNS 检测 | 硬编码特定域名，不通用。改为可配置的 `WATCHDOG_TEST_DOMAIN` 环境变量，默认 `google.com`。 |
| Task 8 | 12 次重试 DNS（每次 5s = 60s） | 等待 60 秒太长。改为 6 次 x 3 秒 = 18 秒即可。 |

### 3.2 架构多余层

当前设计有 6 层架构 (L0-L5)，实际运行时：
- **L2 (HTTP Fallback):** 在 agent 场景中几乎不会被触发（路由表覆盖 95% + TCP 探测覆盖剩余 5%）。保留代码但不在 agent-check 中调用。
- **L4 (MCP Tool):** 计划说明"不碰"，但存在感弱。建议 v3 先不实现，如果 agent 需要原生 MCP 调用再补。
- **L5 (Cron Watchdog):** 与 Task 0 心跳守护功能重叠。合并。

---

## 四、整合后完整计划

### Task 1: 路由表扩展至 200+ 域名

**目的:** 让 95%+ 的域名请求在 0ms 内命中路由规则，无需 TCP 探测或 HTTP 回退。

**文件:**
- 修改: `templates/network-routes.yaml`

**关键接口:**
- 规则分为 `always_proxy`（国外/AI/被墙）和 `always_direct`（国内/本地/Hermes API）
- 覆盖类别：AI/ML、代码托管、学术、包仓库、容器、Google 服务、Cloudflare、社交媒体、国内站点、本地地址
- 统计命令: `grep -c '^\s\+-' templates/network-routes.yaml` 验证规则数

**变更简述:** 从 30+ 规则扩展到 200+ 规则。调研来源：shell history 域名提取、agent 日志域名提取、已知开发域名清单。

---

### Task 4: 代理状态文件（提前至 Task 1 之后）

**目的:** 为 agent 和其他脚本提供统一的代理状态查询入口，消除 GUI 状态与实际不一致的问题。

**文件:**
- 修改: `scripts/smart_wrappers.sh`
- 涉及: `~/.bash_aliases` (需同步更新)

**关键接口:**
- `proxy_on()` 写入 `echo "on" > ~/.hermes/.proxy_state`
- `proxy_off()` 写入 `echo "off" > ~/.hermes/.proxy_state`
- agent 读取: `cat ~/.hermes/.proxy_state` → `"on"` 或 `"off"`

**变更简述:** 在 proxy on/off 函数中增加状态文件写入。确保 bash_aliases 中的别名指向 smart_wrappers.sh 的统一实现。

---

### Task 2: TCP 端口快速检测

**目的:** 替代完整 HTTP 请求作为路由表未命中时的回退方案，将决策延迟从 10s+ 降到 <2s。

**文件:**
- 修改: `scripts/netcheck.sh`

**关键接口:**
- `tcp_probe(host, port=443, timeout=2)` → 返回 0(连通) / 1(超时) / 2(拒绝)
- `netcheck <domain>` 主流程改为三层：路由表 → TCP probe → 代理决策
- **砍掉:** `tcp_latency()` 延迟测量（v3 不需要毫秒分级）

**变更简述:** 用 bash `/dev/tcp` 或 Python socket 做 TCP connect，2 秒超时。替代原有的 HTTP 请求检测作为 L1 回退。

---

### Task 0: 代理存活心跳检测

**目的:** 检测代理守护进程是否存活，崩溃或休眠后及时告警。

**文件:**
- 新建: `scripts/proxy-heartbeat.sh`
- 修改: `install.sh`

**关键接口:**
- `proxy-heartbeat --once` → JSON `{"status":"alive"|"dead"|"no_proxy", "host":"...", "port":...}`
- 心跳时间戳写入 `~/.hermes/.proxy_heartbeat`
- agent-check 读取心跳文件：若最近 120 秒内有心跳则认为代理存活

**砍掉:** 脚本内循环守护模式（`run_daemon()`）。改为 cron 每分钟调用 `--once`，更简单可靠。

**变更简述:** 单文件脚本，TCP ping 代理端口。通过 cron 每分钟触发。状态变化时输出告警。

---

### Task 3: agent 专用 agent-check 命令

**目的:** agent 只需调用一个命令即可获得网络决策结果，输出结构化 JSON，退出码明确语义。

**文件:**
- 新建: `scripts/agent-check.sh`
- 修改: `install.sh`

**关键接口:**
```
输入:  agent-check <domain>
输出:  {"domain":"...","layer":"route"|"tcp","decision":"direct"|"proxy"|"blocked","reason":"...","latency_ms":0|null}
退出码: 0=直连可用, 1=需要代理, 2=被墙且代理未开（需提醒用户）
```

**三层决策逻辑:**
1. 查路由表 (0ms) → always_proxy / always_direct → 直接返回
2. TCP 探测 (<2s) → 连通则直连
3. 检查代理状态 → 已开则走代理 / 未开则 blocked 告警

**砍掉:** TTY 人类可读模式。如调试需要，追加 `--pretty` 选项用 Python 一行格式化 JSON。

**变更简述:** 聚合 Task 1 (路由表) + Task 2 (TCP 探测) + Task 4 (状态文件) 为单一命令。agent 行为协议的唯一入口。

---

### Task 5: 重写 SKILL.md — 强制三段式协议

**目的:** 将 agent 行为从"建议"升级为"强制协议"，确保 agent 在任何外网操作前都调用 agent-check。

**文件:**
- 重写: `SKILL.md`

**关键内容:**
- 强制三段式决策协议（MANDATORY 标记）
- 触发条件清单：curl, wget, git, pip, npm, apt, browser_navigate 等
- 失败恢复协议：操作失败后的标准恢复流程
- 更新架构图：标注 L0-L5 六层（合并 cron + heartbeat 为 L4）

**变更简述:** 将现有 SKILL.md 从"建议"模式改写为"协议"模式。增加 MANDATORY 标记和明确的不得跳过的声明。

---

### Task 8: 休眠唤醒恢复

**目的:** 检测电脑休眠/唤醒周期，自动恢复代理连接和 DNS 解析。

**文件:**
- 新建: `scripts/wake-guard.sh`
- 修改: `install.sh`

**关键接口:**
- 检测原理：文件时间戳心跳，间隔 > 120 秒判定为疑似休眠
- 恢复流程：DNS 可达性检查 → 代理心跳验证 → Hermes gateway 验证
- 环境变量 `WAKEGUARD_TEST_DOMAIN` (默认 `google.com`) 替代硬编码域名
- DNS 重试：6 次 × 3 秒 = 18 秒超时（原设计 12 次 × 5 秒 = 60 秒太浪费）

**变更简述:** 通过 cron 每分钟触发，检测心跳间隔判断是否休眠唤醒。唤醒后自动验证 DNS、代理、Hermes gateway 三项。

---

### Task 6: 端到端集成测试

**目的:** 验证所有组件协同工作，路由表覆盖率达标，agent 协议场景正确。

**测试场景:**
1. 路由表覆盖率：收集 agent 24h 内访问的所有域名，验证 95%+ 命中路由表
2. 协议场景验证：
   - `agent-check github.com` → proxy (路由表命中)
   - `agent-check baidu.com` → direct (路由表命中)
   - `proxy off && agent-check huggingface.co` → blocked (退出码 2)
   - `proxy on && agent-check huggingface.co` → proxy (退出码 1)
3. 心跳检测：关闭代理 → `proxy-heartbeat --once` 返回 dead
4. 唤醒模拟：删除时间戳 → 等待检测 → 验证恢复日志

**变更简述:** 编写测试脚本和手动测试 check list。不做自动化 CI（WSL2 环境无 CI）。

---

### Task 7: 安装脚本更新 + 发布

**目的:** 将所有新建脚本部署到位，更新 bash_aliases，推送发布。

**文件:**
- 修改: `install.sh`
- 涉及: `~/.bash_aliases` 追加段

**部署清单:**
| 文件 | 安装路径 |
|------|----------|
| `agent-check.sh` | `~/.local/bin/agent-check` |
| `proxy-heartbeat.sh` | `~/.local/bin/proxy-heartbeat` |
| `wake-guard.sh` | `~/.local/bin/wake-guard` |

**新别名:**
- `proxy-watch='proxy-heartbeat'`
- `proxy-ping='proxy-heartbeat --once'`
- `wake-guard='wake-guard'`

**发布步骤:**
1. `bash install.sh` 验证安装
2. `source ~/.bash_aliases` 验证别名
3. `agent-check github.com` 冒烟验证
4. git commit + tag v3.0 + push

---

## 五、改动文件总览

| 文件 | 操作 | Task |
|------|------|------|
| `templates/network-routes.yaml` | 大幅扩展 (30→200+ 规则) | Task 1 |
| `scripts/smart_wrappers.sh` | 增加状态文件写入 | Task 4 |
| `scripts/netcheck.sh` | 增加 TCP 探测，重写主流程 | Task 2 |
| `scripts/agent-check.sh` | **新建** — agent 三段式决策入口 | Task 3 |
| `scripts/proxy-heartbeat.sh` | **新建** — 代理存活心跳 | Task 0 |
| `scripts/wake-guard.sh` | **新建** — 休眠唤醒恢复 | Task 8 |
| `SKILL.md` | 重写为强制协议 | Task 5 |
| `install.sh` | 增加 3 个新脚本部署 + 新别名 | Task 0,3,7,8 |

**不碰的文件:** MCP server、L3 smart_wrappers（仅 Task 4 小幅改动）、cron 配置（手动设置，不进仓库）。

---

## 六、v3.1 候选（本次不做）

| 痛点 | 功能 | 理由 |
|------|------|------|
| #3 端口变化 | 扫描常见代理端口，自动更新配置 | 需要端口探测 + 自动修改 env var |
| #4 DNS 泄漏 | DNS 代理 vs 直连对比检测 | 需要可靠的 DNS 对比逻辑 |
| #1 IP 自动检测 | 重启后自动获取 Windows 主机 IP | wake-guard 只处理休眠，重启场景需额外方案 |
| #7 Docker 代理检查 | 检查 Docker daemon 代理配置 | 独立网络栈，不属于 agent 网络路径 |
