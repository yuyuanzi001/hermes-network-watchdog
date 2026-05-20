# Hermes Network Watchdog 🐕 v3.3

Smart proxy detection & auto-decision. 0ms-2s, 5-layer architecture.

```bash
$ agent-check github.com
{"decision":"proxy","layer":"route"}    # 0ms, route table hit

$ netcheck huggingface.co
路由表命中: always_proxy → 建议开启代理
```

## Install

```bash
curl -sL https://raw.githubusercontent.com/yuyuanzi001/hermes-network-watchdog/master/install.sh | bash
source ~/.bashrc
```

## Usage

| Command | What it does |
|---------|-------------|
| `agent-check <domain>` | JSON decision: direct / proxy / blocked (0ms-2s) |
| `netcheck <url>` | Dual-path connectivity test with recommendation |
| `spip install <pkg>` | pip with auto-proxy fallback |
| `sgclone <url>` | git clone with auto-proxy |
| `swget / scurl` | wget/curl with auto-proxy |
| `proxy on\|off\|status` | Manual proxy control (push/pop safe) |

## Architecture

```
L0: Route Table (~110 domains)  →  0ms
L1: TCP Probe (443→80 cascade)  →  <2s
L2: HTTP Fallback               →  <10s (reserved)
L3: Smart Wrappers              →  push/pop safe
L4: Health Monitor              →  heartbeat + wake-guard
L5: MCP Tool                    →  mcp_netcheck_netcheck()
```

## Proxy Support

Works with any HTTP/SOCKS5 proxy. Tested: Clash Verge (7897), v2rayN, SSR, Sing-box.

| Platform | Auto-Detect |
|----------|-------------|
| WSL2 | ✓ Windows host IP |
| Linux / macOS | ✓ 127.0.0.1 |

## Requirements

`bash` + `curl`. Python only needed for MCP tool. Zero bloat.

## License

MIT
