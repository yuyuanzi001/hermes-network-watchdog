# Hermes Network Watchdog 🐕 v3.3

Smart network proxy detection & auto-decision for CLI and AI agents.  
智能网络代理检测与自动决策工具 — 5 层架构，0ms-2s 决策。

<p align="center">
  <b>agent-check → proxy on → done</b>
</p>

## What It Does | 功能

You're in WSL/Linux behind the GFW. GitHub clone times out. HuggingFace won't load. Pip install hangs.

```bash
$ agent-check github.com
{"domain":"github.com","layer":"route","decision":"proxy","reason":"routing rule"}

$ netcheck huggingface.co
═══ netcheck: huggingface.co ═══
  路由表命中: always_proxy (0ms)
→ 建议: 开启代理
```

One command. Instant decision. No waiting.

## 30-Second Install | 30秒安装

```bash
curl -sL https://raw.githubusercontent.com/yuyuanzi001/hermes-network-watchdog/master/install.sh | bash
source ~/.bashrc
agent-check github.com   # 0ms route table lookup
```

## 5-Layer Architecture | 五层架构

```
┌──────────────────────────────────────────────────┐
│ L0: Route Table        (~110 domain patterns)     │  0ms
│     netcheck-route → always_proxy/direct/auto     │
├──────────────────────────────────────────────────┤
│ L1: TCP Probe          443→80 cascade             │  <2s
│     agent-check / netcheck                        │
├──────────────────────────────────────────────────┤
│ L2: HTTP Fallback      Full connectivity test     │  <10s
│     (reserved for edge cases)                     │
├──────────────────────────────────────────────────┤
│ L3: Smart Wrappers     Push/pop safe              │
│     spip / sgclone / swget / scurl                │
├──────────────────────────────────────────────────┤
│ L4: Heartbeat + Guard  Automated monitoring       │
│     proxy-heartbeat (30s) + wake-guard            │
├──────────────────────────────────────────────────┤
│ L5: MCP Tool           Agent-native integration   │
│     mcp_netcheck_netcheck(url)                    │
└──────────────────────────────────────────────────┘
```

### L0: Route Table (0ms)
~110 domain patterns with instant routing. Blocked sites → always_proxy. Domestic sites → always_direct. Everything else → auto (live check).

### L1: Agent Protocol (v3)
```bash
agent-check <domain>     # JSON decision: direct | proxy | blocked
agent-check github.com   # {"decision":"proxy","layer":"route"}
```

### L2: Manual Check
```bash
netcheck huggingface.co              # instant (route table)
netcheck -t 5 unknown.xyz            # live test with timeout
netcheck -s large.bin                # speed comparison
```

### L3: Smart Wrappers (push/pop safe)
```bash
spip install torch                  # auto-proxy if needed → restores state
sgclone https://github.com/user/repo.git
swget https://example.com/file.tar.gz
scurl https://api.example.com/data
proxy on|off|status|push|pop        # manual control
```

### L4: Health Monitoring
```bash
proxy-heartbeat                     # check proxy alive
wake-guard                          # recover from sleep/hibernate
```

### L5: MCP Tool (Hermes Agent)
```python
mcp_netcheck_netcheck(url="github.com")
# → {"recommendation": "proxy", "action": "Run: proxy on"}
```

## Proxy Compatibility | 代理兼容

Any HTTP/SOCKS5 proxy. Clash Verge tested on port 7897.

| Software | Default |
|----------|---------|
| Clash / Clash Verge | port 7897 |
| v2rayN | `PROXY_PORT=10809` |
| SSR | `PROXY_PORT=1080` |
| Sing-box | `PROXY_PORT=2080` |

## Platform Support

| Environment | Auto-Detect |
|-------------|-------------|
| WSL2 | ✓ Windows host IP |
| Linux | ✓ 127.0.0.1 |
| macOS | ✓ 127.0.0.1 |

## Files

```
├── install.sh                    # One-line installer
├── SKILL.md                      # Full documentation
├── scripts/
│   ├── agent-check.sh            # Agent 3-way decision (v3)
│   ├── netcheck.sh               # CLI connectivity test
│   ├── netcheck-route            # L0 route table lookup
│   ├── smart_wrappers.sh         # spip/sgclone/swget/scurl
│   ├── proxy-heartbeat.sh        # L4 heartbeat monitor
│   ├── wake-guard.sh             # Wake-from-sleep recovery
│   ├── netcheck_mcp_server.py    # L5 MCP stdio server
│   ├── netcheck_tool.py          # Standalone Python wrapper
│   └── hermes_tool.py            # Hermes integration
├── templates/
│   └── network-routes.yaml       # Default route table
├── references/
│   ├── code-review-round2-*.md   # Review history (R1→R4)
│   └── compatibility.md          # Test results
└── docs/
    └── plans/                    # Architecture plans
```

## Pitfalls | 踩坑

- **git push 必须用 SOCKS5**：`ALL_PROXY=socks5://172.31.112.1:7897`，HTTP 代理会导致 GnuTLS 断连
- **路由表损坏静默吞错**：永远不要用 `|| true` / `|| echo "auto"` 包裹 `netcheck-route`，捕获 `$?` 显式处理
- **TCP 探测只查 443**：会漏 HTTP-only 站点，务必 443→80 级联回退
- **`source` 脚本不能加 `set -e`**：会导致父 shell 异常退出

## Requirements | 依赖

- `bash` + `curl` + `python3` (MCP tool only)
- No Docker, no Node. Pure shell at core.

## Changelog

**v3.3**: 4-round code review — ALL CLEAN ✅ 18/18 fixes, zero regressions  
**v3.2**: Round 3 fixes — agent-check regression, route dedup, docs  
**v3.1**: Round 2 fixes — 5 bugs squashed (route codes, TCP, URL parsing, etc.)  
**v3.0**: Agent protocol, heartbeat, wake-guard, 5-layer architecture  
**v2.x**: Initial release — netcheck + smart wrappers

## License

MIT
