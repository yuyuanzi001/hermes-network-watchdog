---
name: network-proxy-watchdog
description: Smart network proxy detection & auto-decision. Compares direct vs proxy connectivity, auto-switches when sites are unreachable. Supports any HTTP/SOCKS5 proxy (Clash, v2ray, SSR, Sing-box, etc.)
category: devops
metadata:
  hermes:
    tags: [proxy, network, connectivity, download, wsl, china-gfw]
    related_skills: [hermes-agent-skill-authoring]
triggers:
  - download slow, download failed, network timeout
  - website/API unreachable
  - pip install / git clone / wget / curl failure
  - user asks "要不要开代理"、"网络不通"、"连不上", "should I enable proxy", "network down"
  - HuggingFace / GitHub / PyPI access issues
---

# Network Proxy Watchdog

Smart proxy detection & auto-decision. 5-layer architecture that gets faster with each layer.

## ⚡ One-Click Install

**From local skill directory:**
```bash
bash ~/.hermes/skills/devops/network-proxy-watchdog/install.sh
source ~/.bash_aliases
```

**From GitHub (fresh install):**
```bash
git clone https://github.com/yuyuanzi001/hermes-network-watchdog /tmp/nwd
bash /tmp/nwd/install.sh
source ~/.bash_aliases
```

This installs everything: `netcheck` CLI, route table, bash functions (proxy/spip/sgclone/…), and the MCP server. See the printed instructions for optional MCP registration.

After install, restart Hermes if you want the MCP tool (`mcp_netcheck_netcheck`).

---

## ⚡ Agent Network Protocol (MANDATORY — v3)

**You MUST call `agent-check <domain>` before ANY external network operation.**

### Decision Flow
```
agent-check <domain> → JSON decision (0ms-2s):
  "direct"  → proceed normally
  "proxy"   → proxy on → execute → proxy pop (restore original state)
  "blocked" → TELL USER: "需要代理访问 <domain>，请先 proxy on"
```

### Triggers
ANY of these operations trigger the protocol:
- `terminal` running `curl`, `wget`, `git clone/pull`, `pip install`, `npm install`, `apt install`
- `browser_navigate` to external URL
- Any HTTP request to non-localhost domains

### Post-Failure Recovery
If a network operation FAILS:
1. Run `agent-check <domain>` on the failed domain
2. If "blocked" → tell user to enable proxy, then retry
3. If "direct" but still fails → report error to user
4. NEVER retry same operation without changing proxy state

### NEVER skip this protocol. No exceptions.

### Proxy State
Agent can read proxy status: `cat ~/.hermes/.proxy_state` → `"on"` or `"off"`
Recent heartbeat: check `~/.hermes/.proxy_heartbeat` timestamp (within 120s = alive)

---

## Architecture (v3 — agent-aware, 0ms-2s decision)

```
L0: Route Table (~110 domain patterns) → ~/.hermes/network-routes.yaml  (0ms)
L1: TCP Probe                        → agent-check / netcheck          (<2s)
L2: HTTP Fallback                    → full HTTP connectivity test     (<10s, reserved)
L3: Smart Wrappers                   → spip/sgclone/swget/scurl        (push/pop safe)
L4: Proxy Heartbeat + Wake Guard     → automated health monitoring     (30s cron)
L5: MCP Tool                         → mcp_netcheck_netcheck           (agent native)
```

---

## L0: Route Table

File: `~/.hermes/network-routes.yaml`

Domains matched here are decided instantly — no 10s wait.

| Category | Examples | Action |
|----------|----------|--------|
| Blocked (CN) | huggingface.co, *.hf.co, raw.githubusercontent.com, *.gradio.live, arxiv.org | `always_proxy` |
| Domestic | *.cn, baidu.com, *.aliyun.com, *.bilibili.com | `always_direct` |
| Local | 127.*, 192.168.*, 10.*, localhost | `always_direct` |
| Everything else | github.com, pypi.org, ... | `auto` (live check) |

Query from CLI: `netcheck-route <domain>`

Edit the file to add domains you discover. Cache at `~/.hermes/cache/netcheck/` (10min TTL).

---

## L5: MCP Tool

After `install.sh` + config.yaml registration + Hermes restart:

```
mcp_netcheck_netcheck(url="github.com")
→ {"recommendation": "proxy", "action": "Direct FAILED. Use proxy. Run: proxy on"}
```

Without MCP, the agent falls back to `terminal` + `netcheck`. Both work.

---

## L2: CLI

```bash
netcheck huggingface.co   # instant (route table)
netcheck -t 5 unknown.xyz # 10s live test
netcheck -s large.bin     # speed comparison mode
```

---

## L3: Smart Wrappers (push/pop safe)

Available after `source ~/.bash_aliases`:

```bash
spip install torch        # auto-detects pypi.org → proxy if needed → restores state
sgclone https://github.com/user/repo.git
swget https://example.com/file.tar.gz
scurl https://api.example.com/data
proxy on|off|status|push|pop
```

Push/pop ensures: even if a wrapper enables proxy for a download, your next command uses whatever proxy state you had before. No pollution.

---

## Proxy Configuration

All via environment variables. No hardcoded values.

| Variable | Default | Description |
|----------|---------|-------------|
| `PROXY_URL` | (auto) | Full proxy URL |
| `PROXY_HOST` | Auto-detect | WSL: Windows host IP; others: 127.0.0.1 |
| `PROXY_PORT` | 7897 | Proxy port |
| `PROXY_PROTO` | http | http or socks5 |

Supports Clash, v2rayN, SSR, Sing-box, or any HTTP/SOCKS5 proxy.

---

## File Index (inside skill directory)

| File | Purpose |
|------|---------|
| `install.sh` | One-click deployment |
| `scripts/netcheck.sh` | CLI connectivity checker → installed to ~/.local/bin/netcheck |
| `scripts/netcheck-route` | Route table lookup → installed to ~/.local/bin/netcheck-route |
| `scripts/netcheck_mcp_server.py` | MCP stdio server → installed to ~/.hermes/tools/ |
| `scripts/netcheck_tool.py` | Standalone Python wrapper |
| `scripts/agent-check.sh` | Agent auto-detection protocol (v3) → installed to ~/.local/bin/agent-check |
| `scripts/proxy-heartbeat.sh` | Proxy health monitor (v3) → installed to ~/.local/bin/proxy-heartbeat |
| `scripts/wake-guard.sh` | Sleep-wake recovery guard (v3) → installed to ~/.local/bin/wake-guard |
| `scripts/smart_wrappers.sh` | Standalone bash wrappers (alternative to install.sh embed) |
| `scripts/hermes_tool.py` | Hermes MCP tool adapter |
| `templates/network-routes.yaml` | Default route table → installed to ~/.hermes/ |
| `references/compatibility.md` | Test results and known quirks |
| `references/code-review-2026-05-19.md` | Initial code review report (v2, round 1) |
| `references/code-review-2026-05-19-r2.md` | Round 2 code review — v3 hardening details |
| `references/code-review-round2-2026-05-19.md` | Cumulative review history — R1→R4 findings, all fixes & repair records |

---

## Changelog

**v3.3 (2026-05-20):** Round 4 code review — ALL CLEAN ✅ 18/18 fixes verified, zero regressions. Minor: merged duplicate File Index entry in SKILL.md.

**v3.2 (2026-05-20):** Round 3 code review — fixed R2 regression in agent-check.sh route exit code handling, removed duplicate entries from network-routes.yaml, documented `set -uo` design for source scripts. See `references/code-review-round2-2026-05-19.md`.

**v3.1 (2026-05-19):** Round 2 code review fixes — route table exit code handling, TCP fallback to port 80, proxy URL `##*@` parsing, swget URL arg detection, wake-guard log isolation. See `references/code-review-2026-05-19-r2.md`.

**v3.0 (2026-05-19):** Agent auto-detection protocol (`agent-check`), proxy heartbeat monitoring (`proxy-heartbeat`), wake-from-sleep recovery (`wake-guard`), push/pop-safe smart wrappers, 5-layer architecture (L0-L5), MCP tool integration.

**v2.1 (2026-05-19):** Fixed curl exitcode bug (`$?` instead of fake `%{exitcode}`). Cleaned duplicate condition in MCP server parser. Added English output fallback.

**v2.0 (2026-05-19):** Route table (L0), MCP tool (L1), push/pop wrappers (L3), self-contained install.sh, 5-layer architecture.

---

## Pitfalls (lessons from code review)

These were real bugs found by Claude Code review. Avoid reintroducing them.

### Route table exit codes
`netcheck-route` returns exit code 2 when the YAML is corrupted. **Never** use `|| true` after the route lookup — it silently turns parse errors into "no match" fallthroughs. Capture `$?` explicitly:
```bash
ROUTE_ACTION=$(netcheck-route "$HOST" 2>/dev/null); route_exit=$?
if [[ $route_exit -eq 2 ]]; then
    echo "⚠ Route table parse error, falling through to live check" >&2
elif [[ "$ROUTE_ACTION" == "always_proxy" ]]; then ...
```

### TCP probe must try port 80
443-only probing misses HTTP-only sites (e.g., plain HTTP APIs, dev servers). Always fall back to port 80:
```bash
tcp_probe "$HOST" 443 2 || tcp_probe "$HOST" 80 2
```

### URL parsing: use `##*@` (longest match), not `#*@`
If a proxy password contains `@` (e.g., `user:p@ss@host:port`), `${url#*@}` only strips up to the first `@`, leaving part of the password in the host string. Use `${url##*@}` to strip everything up to the LAST `@`.

### Smart wrapper URL detection
`swget` must iterate all arguments to find the URL, not assume it's the last one. `-O` flag reorders arguments. Follow the same pattern as `scurl`:
```bash
for arg in "$@"; do
    [[ "$arg" =~ ^https?:// ]] && { url="$arg"; break; }
done
```

### Log statements in `&&`/`||` chains
Never chain `command && log "ok" || log "fail"` — if `log "ok"` itself fails (disk full), it triggers the "fail" branch. Capture the result first:
```bash
hb_ok=false
if check_heartbeat; then hb_ok=true; fi
$hb_ok && log "ok" || log "fail"
```

### Route table header
Don't claim specific domain counts in YAML headers — they get stale. Use approximate language ("~110 unique domain patterns") and validate periodically.

### `set -euo pipefail` only for executable scripts
Scripts that are `source`d (like `smart_wrappers.sh`) must NOT use `set -e` — it would cause the sourcing shell to exit on any wrapper error, breaking the interactive session. Use `set -uo pipefail` for source scripts, and `set -euo pipefail` only for scripts that run independently in their own subshell.

---

## Troubleshooting

**"netcheck: command not found"** — `source ~/.bash_aliases` or check `~/.local/bin` is in PATH.

**MCP tool not appearing** — Restart Hermes after adding the config block. Check `pip install mcp` succeeded.

**"curl error 28" on both routes** — Both direct and proxy are down. Check: 1) proxy service running? 2) site itself down? 3) DNS?

**Proxy stays on after spip/sgclone** — Update your wrappers. v2 uses push/pop. Re-run `install.sh`.
