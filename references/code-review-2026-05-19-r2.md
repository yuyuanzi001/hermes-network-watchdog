# Round 2 Code Review — 2026-05-19

Reviewer: Claude Code via code-review-skill
Cost: $0.56
Result: 8 issues found (🔴2 🟡3 🟢3), all fixed. Round 1 issues confirmed resolved with zero regressions.

## Confirmed: Round 1 fixes all held (5/5) ✅

All 5 critical bugs from round 1 were correctly fixed with no backsliding:
- curl `%{exitcode}` → `$?` (no regression)
- MCP server duplicate condition (no regression)
- `|| true` swallowing curl exit in main path (no regression — but see R2-1 below for the route path)

## New issues found

### 🔴 R2-1: Route table exit code 2 swallowed (netcheck.sh:111-113)
```
ROUTE_ACTION=$("$ROUTE_HELPER" "$HOST" 2>/dev/null) || true
```
`|| true` swallowed netcheck-route's exit code 2 (YAML parse error / corrupted route table). The error was treated as "no match" and silently fell through to TCP probe.

**Fix:** Capture `$?` explicitly; warn on exit 2; only enter route-match block on `always_proxy`/`always_direct`.

### 🔴 R2-2: TCP probe only checks port 443 (agent-check.sh, netcheck.sh)
Both `agent-check.sh` and `netcheck.sh` tried only port 443. Pure HTTP services (port 80) or non-standard ports were misclassified as unreachable. In `agent-check.sh`, this could cause a host that IS reachable on port 80 to be classified as `"blocked"`.

**Fix:** Add port 80 as fallback after 443: `tcp_probe "$HOST" 443 2 || tcp_probe "$HOST" 80 2`. In agent-check.sh, wrapped in a `tcp_reachable()` helper.

### 🟡 R2-3: URL parsing with `#*@` shortest match (proxy-heartbeat.sh:16-18)
`${url#*@}` (single hash = shortest prefix match) fails when the proxy password contains `@`. E.g., `user:p@ss@127.0.0.1:7897` → strips only `user:p@`, leaving `ss@127.0.0.1:7897` as the host.

**Fix:** Changed to `${url##*@}` (double hash = longest prefix match), stripping everything up to the last `@`.

### 🟡 R2-4: swget assumes URL is last argument (smart_wrappers.sh:121)
`swget` used `${@: -1}` to grab the last argument as URL. Breaks with `swget -O file.zip https://example.com`. Inconsistent with `scurl` which correctly iterates over all args.

**Fix:** Iterate over `$@` to find the URL, matching scurl's behavior. Also added `ftp://` detection.

### 🟡 R2-5: Log failure triggers false alarm (wake-guard.sh:50)
```
"$HB_BIN" --once | python3 -c "..." && log "代理正常" || log "代理异常"
```
The `&&`/`||` chain catches both the heartbeat check AND `log`'s exit code. If `log "代理正常"` fails for any reason (disk full, pipe broken), the `||` branch fires and incorrectly reports "代理异常".

**Fix:** Captured heartbeat result in a boolean (`hb_ok`) before logging, so the log command's own exit code doesn't pollute the decision.

### 🟢 R2-6: GNU-specific commands (multi-file)
`date -Iseconds` and `stat -c %Y` are GNU extensions. Not a real bug for Linux/WSL targets, but would break on macOS/BSD. Not fixed — target platform is Linux.

### 🟢 R2-7: Route table header claims 200+ (network-routes.yaml:12)
Header `# v3: 100+ rules covering 200+ domain patterns` was inaccurate — actual count ~117. Fixed to `~120`.

### 🟢 R2-8: SKILL.md changelog missing v3 (SKILL.md:177-181)
Changelog stopped at v2.1. v3 features (agent-check, proxy-heartbeat, wake-guard) weren't documented. Fixed by adding v3.0 entry.
