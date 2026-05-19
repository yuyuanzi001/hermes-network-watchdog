---
name: network-proxy-watchdog
description: Smart network proxy detection & auto-decision. Compares direct vs proxy connectivity, auto-switches when sites are unreachable. Supports any HTTP/SOCKS5 proxy (Clash, v2ray, SSR, Sing-box, etc.)
category: devops
triggers:
  - download slow, download failed, network timeout
  - website/API unreachable
  - pip install / git clone / wget / curl failure
  - user asks "要不要开代理"、"网络不通"、"连不上", "should I enable proxy", "network down"
  - HuggingFace / GitHub / PyPI access issues
---

# Network Proxy Watchdog

3-layer architecture: manual detection → command wrappers → cron watchdog

## Quick Install (30 seconds)

```bash
# 1. Install bc (optional, for speed comparison)
sudo apt install bc -y   # Debian/Ubuntu
# brew install bc        # macOS

# 2. Download netcheck script
mkdir -p ~/.local/bin
curl -o ~/.local/bin/netcheck https://raw.githubusercontent.com/yuyuanzi001/hermes-network-watchdog/main/scripts/netcheck.sh
chmod +x ~/.local/bin/netcheck

# 3. Add to PATH (add to ~/.bashrc or ~/.zshrc)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 4. Test
netcheck https://github.com
```

## Proxy Configuration

All proxy settings are environment variables. **No hardcoded values.**

| Variable | Default | Description |
|----------|---------|-------------|
| `PROXY_URL` | (auto) | Full proxy URL, e.g. `http://127.0.0.1:7897` or `socks5://127.0.0.1:1080` |
| `PROXY_HOST` | Auto-detect | Proxy host (WSL: Windows host IP; others: 127.0.0.1) |
| `PROXY_PORT` | 7897 | Proxy port |
| `PROXY_PROTO` | http | Protocol: `http` or `socks5` |

**Supported proxy software** (any HTTP/SOCKS5-compatible):

| Software | Typical Config |
|----------|---------------|
| Clash / Clash Verge | `PROXY_PORT=7897` |
| v2rayN | `PROXY_PORT=10809` |
| SSR / Shadowsocks | `PROXY_PORT=1080` |
| Sing-box | `PROXY_PORT=2080` |
| Trojan | `PROXY_PORT=1080` |
| Any HTTP proxy | `PROXY_URL=http://host:port` |
| Any SOCKS5 proxy | `PROXY_URL=socks5://host:port` |

## L1: Manual Detection — `netcheck <url>`

```bash
# Basic usage
netcheck https://huggingface.co
netcheck https://github.com/user/repo/releases/download/v1.0/model.bin

# Custom timeout (default 10s)
netcheck -t 5 https://api.openai.com

# Speed comparison mode (downloads first 1MB)
netcheck -s https://huggingface.co/model.bin

# With custom proxy config
PROXY_PORT=1080 netcheck https://example.com
PROXY_URL=socks5://127.0.0.1:1080 netcheck -s https://huggingface.co/file.bin
```

Sample output:
```
═══ netcheck: huggingface.co ═══
  代理: http://172.31.112.1:7897

  直连: ✗ 超时 (10s)
  代理: ✓ 连通 0.230s

→ 建议: 开启代理（直连不通，代理可用）
  设置: export http_proxy=http://172.31.112.1:7897
```

Decision rules:

| Direct | Proxy | Action |
|--------|-------|--------|
| ✓ Fast | - | Keep direct |
| ✓ Slow | ✓ Faster | Switch to proxy |
| ✗ Down | ✓ OK | **Switch to proxy** |
| ✗ Down | ✗ Down | Both dead — troubleshoot |
| ✓ OK | ✗ Down | Direct OK, check proxy service |

## L2: Smart Command Wrappers

Add to `~/.bashrc` or `~/.bash_aliases`:

```bash
source <(curl -s https://raw.githubusercontent.com/yuyuanzi001/hermes-network-watchdog/main/scripts/smart_wrappers.sh)
```

Or copy manually — wrapper functions that auto-enable proxy when direct connection fails:

| Command | Replaces | Behavior |
|---------|----------|----------|
| `spip` | `pip install` | Checks pypi.org → proxy if needed |
| `sgclone` | `git clone` | Checks target host → proxy if needed |
| `swget` | `wget` | Checks target host → proxy if needed |
| `scurl` | `curl` | Checks target host → proxy if needed |
| `proxy on/off/status` | — | Toggle proxy on/off, show status |

## L3: Cron Watchdog (Hermes Agent only)

```bash
cronjob create \
  --name "Network Watchdog" \
  --schedule "*/15 * * * *" \
  --script "netcheck --cron" \
  --no_agent
```

Silently checks critical sites. Only notifies when connectivity changes.

## Architecture Notes

```
┌─────────────────────────────────────────────┐
│ L1: netcheck <url>                           │
│     Manual dual-path connectivity test       │
│     curl direct vs curl --proxy               │
│     → Prints decision + recommended action   │
├─────────────────────────────────────────────┤
│ L2: spip / sgclone / swget / scurl           │
│     Auto-detect target host connectivity      │
│     → proxy on if needed, then execute       │
├─────────────────────────────────────────────┤
│ L3: Cron watchdog                             │
│     Periodic silent check of critical sites  │
│     → Alert only when state changes          │
└─────────────────────────────────────────────┘
```

## Cross-Platform Support

| Environment | Auto-Detection | Notes |
|-------------|---------------|-------|
| WSL2 | ✓ Windows host IP via `ip route` | Default setup |
| Linux native | ✓ 127.0.0.1 | Set PROXY_HOST if different |
| macOS | ✓ 127.0.0.1 | Set PROXY_HOST if different |
| Docker | ✓ 127.0.0.1 | Use host.docker.internal if needed |
| Any shell | ✓ Via PROXY_URL env | Full manual control |

## Non-China Use Cases

This skill is useful whenever you need conditional proxy routing:

- **Corporate VPN**: Auto-detect if internal sites need direct access
- **Split-tunnel testing**: Compare latency between VPN and direct
- **Multi-hop proxy chains**: Test each hop independently
- **CI/CD pipelines**: Auto-switch proxy for geo-restricted dependencies
