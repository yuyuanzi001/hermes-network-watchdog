# Hermes Network Watchdog 🐕

Smart network proxy detection & auto-decision for CLI environments.  
智能网络代理检测与自动决策工具。

<p align="center">
  <b>netcheck → proxy on → done</b>
</p>

## What It Does | 功能

You're in WSL/Linux. Pip install hangs. GitHub clone times out. HuggingFace won't load.

```bash
$ netcheck https://huggingface.co
═══ netcheck: huggingface.co ═══
  代理: http://172.31.112.1:7897

  直连: ✗ 超时 (10s)
  代理: ✓ 连通 0.230s

→ 建议: 开启代理（直连不通，代理可用）
```

One command tells you: direct or proxy? Which is faster? What should you do?

## 30-Second Install | 30秒安装

```bash
curl -sL https://raw.githubusercontent.com/yuyuanzi001/hermes-network-watchdog/main/install.sh | bash
source ~/.bashrc
netcheck https://github.com
```

## 3-Layer Architecture | 三层架构

```
┌─────────────────────────────────────────────┐
│ L1: netcheck <url>                           │
│     Manual dual-path connectivity test       │
│     → Instant decision: direct or proxy      │
├─────────────────────────────────────────────┤
│ L2: spip / sgclone / swget / scurl           │
│     Auto-detect + auto-switch wrappers       │
│     → Never think about proxy again          │
├─────────────────────────────────────────────┤
│ L3: Hermes cron watchdog                     │
│     Silent background monitoring             │
│     → Alert only when things break           │
└─────────────────────────────────────────────┘
```

### L1: Manual Check | 手动检测

```bash
netcheck https://github.com
netcheck -t 5 https://huggingface.co/model.bin
netcheck -s https://huggingface.co/model.bin   # speed test
```

### L2: Smart Wrappers | 智能包装

```bash
spip install transformers     # auto-proxy if PyPI down
sgclone https://github.com/user/repo.git
swget https://example.com/file.tar.gz
scurl https://api.example.com/data
```

### L3: Hermes Integration | Hermes 集成

When the Hermes Agent hits a network error, it automatically calls `netcheck` to diagnose:

```
Agent: "Download failed. Let me check connectivity..."
       → netcheck tool returns: proxy needed
Agent: "Enabling proxy and retrying..."
       → proxy on && retry download
```

**Install Hermes tool:**
```bash
cp tools/netcheck.py ~/.hermes/tools/
```

**Cron watchdog (Hermes):**
```bash
hermes cronjob create \
  --name "Network Watchdog" \
  --schedule "*/15 * * * *" \
  --script "netcheck watchdog"
```

## Proxy Compatibility | 代理兼容

Any HTTP/SOCKS5 proxy — no vendor lock-in.  
支持所有 HTTP/SOCKS5 代理，不绑定任何软件。

| Proxy Software | Config |
|---------------|--------|
| Clash / Clash Verge | Default (port 7897) |
| v2rayN | `PROXY_PORT=10809 proxy on` |
| SSR / Shadowsocks | `PROXY_PORT=1080 proxy on` |
| Sing-box | `PROXY_PORT=2080 proxy on` |
| HTTP proxy | `PROXY_URL=http://host:port proxy on` |
| SOCKS5 proxy | `PROXY_URL=socks5://host:port proxy on` |

## Platform Support | 平台支持

| Environment | Auto-Detect | Notes |
|-------------|-------------|-------|
| WSL2 | ✓ Windows host IP | Default target |
| Linux | ✓ 127.0.0.1 | Set PROXY_HOST if needed |
| macOS | ✓ 127.0.0.1 | Set PROXY_HOST if needed |
| Docker | ✓ 127.0.0.1 | Use `host.docker.internal` |

## Use Cases Beyond China | 更多场景

- **Corporate VPN split-tunnel**: Auto-switch between direct and VPN routes
- **CI/CD pipelines**: Auto-proxy for geo-restricted dependencies
- **Multi-hop chains**: Test each proxy hop independently
- **Dev environments**: Never manually toggle proxy again

## Files | 文件

```
hermes-network-watchdog/
├── install.sh              # One-line installer
├── scripts/
│   ├── netcheck.sh         # Core connectivity test (bash)
│   └── smart_wrappers.sh   # spip/sgclone/swget/scurl wrappers
├── tools/
│   └── netcheck.py         # Hermes Agent tool integration
└── SKILL.md                # Full documentation (English)
```

## Requirements | 依赖

- `bash` (any version)
- `curl` (system default)
- `bc` (optional, for speed comparison — `apt install bc`)

No Python, no Node, no Docker. Pure shell. Zero bloat.

## License

MIT — do whatever you want.
