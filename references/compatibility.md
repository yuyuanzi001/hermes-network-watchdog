# Proxy Compatibility Test Results (2026-05-19, updated 2026-05-19 v2.1)

## Test Environment
- WSL2 Ubuntu 24.04
- Clash Verge on Windows host (172.31.112.1:7897)

## v2.1 Changelog (May 2026)
- Fixed curl exitcode detection: use `$?` instead of fake `%{exitcode}` format variable
- Cleaned duplicate condition in MCP server output parser
- Added English fallback for netcheck output parsing

```
L0: Route Table      → ~/.hermes/network-routes.yaml
L1: MCP Tool         → mcp_netcheck_netcheck (Hermes native tool)
L2: netcheck CLI     → ~/.local/bin/netcheck (+ route table integration)
L3: Smart Wrappers   → spip/sgclone/swget/scurl (push/pop safe)
L4: Cron Watchdog    → (TBD)
```

## Test Matrix

| Config | Result | Notes |
|--------|--------|-------|
| `PROXY_PORT=7897` (default) | ✓ Works | Clash Verge http |
| `PROXY_PORT=10809` | ✓ Detects correctly | v2rayN default |
| `PROXY_PROTO=socks5 PROXY_PORT=1080` | ✓ Detects correctly | SSR/SS default |
| `PROXY_URL=http://custom:port` | ✓ Overrides all | Full manual control |
| `PROXY_URL=socks5://custom:port` | ✓ Works | SOCKS5 via curl --socks5-hostname |

## Route Table Performance

| Domain | Without route table | With route table | Savings |
|--------|--------------------|--------------------|---------|
| huggingface.co | ~10s (timeout) | 0s | 10s |
| baidu.com | ~1s | 0s | 1s |
| github.com | ~3s (proxy) | ~3s (auto, lives check) | 0s |

## proxy push/pop Behavior

```
proxy off        → 代理已关闭
proxy push       → (saves "off" to stack)
proxy on         → 代理已开启
spip install x   → push → check → (already on) → pip → pop → restores "off"
proxy status     → 代理已关闭 (restored by pop)
```

## MCP Server Notes

- Server: `~/.hermes/tools/netcheck_mcp_server.py`
- Transport: stdio (subprocess spawned by Hermes)
- Registered in: `~/.hermes/config.yaml` → `mcp_servers.netcheck`
- Tool name: `mcp_netcheck_netcheck`
- Dependencies: `pip install mcp` (done), `~/.local/bin/netcheck` (must exist)
- The server calls netcheck.sh as a subprocess — same behavior as CLI

## Known Quirks

### Git Push Through HTTP Proxy (TLS Conflict)
Git HTTPS operations through Clash HTTP proxy may fail with:
```
error: RPC failed; curl 56 GnuTLS recv error (-110): The TLS connection was non-properly terminated.
```
**Workaround:**
```bash
GIT_SSL_NO_VERIFY=1 git -c http.sslVerify=false push
```
Or use SSH (`git@github.com:...`) if your SSH key is configured on GitHub. SSH bypasses the HTTP proxy entirely.

### Route Table Parser
- Simple YAML parser in `netcheck-route` — no PyYAML dependency
- Handles inline comments (`# ...`) correctly
- Only matches top-level keys by checking raw line indentation
- `default_action: auto` is the fallback for unmatched domains

### MCP Tool Limitations
- Timeout capped at 30 seconds
- If netcheck binary is missing, returns `recommendation: install_netcheck`
- No caching at MCP level (caching is in route table + netcheck.sh)

### WSL-specific
1. Windows host IP detected via `ip route show default | awk '{print $3}'`
2. MySQL on Windows cannot be reached from WSL via localhost — use Windows binary mysql.exe directly
3. Maven on Windows must be invoked via `cmd.exe /c build.bat` from WSL

### MySQL GUI Tools
1. Navicat-like GUI tools strip `*` from SQL (COUNT(*) → COUNT(), SELECT * FROM → SELECT FROM)
2. Workaround: use `COUNT(1)` instead of `COUNT(*)`, list column names explicitly

### Cron Job Pitfalls

## Git Push + Proxy TLS Conflicts

When pushing to GitHub through an HTTP proxy (Clash, v2ray, etc.), `git push` may fail with:

```
error: RPC failed; curl 56 GnuTLS recv error (-110): The TLS connection was non-properly terminated.
```

This happens because the proxy interferes with git's HTTPS TLS handshake. 

**Workaround (in order of preference):**

1. **Skip SSL verification** (quick but no MITM protection):
   ```bash
   GIT_SSL_NO_VERIFY=1 git -c http.sslVerify=false push
   ```

2. **Use SSH instead of HTTPS** (best if SSH key is configured on GitHub):
   ```bash
   git remote set-url origin git@github.com:user/repo.git
   git push origin master
   ```

3. **Push without proxy** (if direct connection works intermittently):
   ```bash
   unset http_proxy https_proxy && git push
   ```

**Root cause:** HTTP proxies tunnel HTTPS traffic, but some proxy implementations (especially Clash) strip or mangle TLS headers, causing GnuTLS on the client side to reject the connection. The `GIT_SSL_NO_VERIFY` flag bypasses the client-side certificate check while keeping the proxy tunnel intact.
1. Windows mysql.exe adds `\r` to output — pipe through `tr -d '\r'`
2. `no_agent: true` cron jobs use `deliver: local` — check docs for current behavior
