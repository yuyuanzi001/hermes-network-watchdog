# Code Review Report — hermes-network-watchdog v2 (2026-05-19)

## Methodology

Used `software-development/requesting-code-review` pipeline. Manual review due to diff size (62KB).

## Critical Issues Found & Fixed

### 1. `netcheck.sh` — Fake `curl -w "%{exitcode}"` format variable
**Root cause:** `curl -w` supports `%{http_code}` but NOT `%{exitcode}`. The old code used a non-existent format specifier. When curl timed out, the `|| echo "28"` fallback accidentally worked. When curl returned HTTP errors (403, 404), the empty string from `-w` was treated as "connected."

**Fix (v2.1):** Capture `$?` after curl runs using `set +e`/`set -e` guard. Same fix applied to `speed_test()`.

```bash
# BEFORE (broken):
curl_exit=$(curl ... -w "%{exitcode}" ... 2>/dev/null || echo "28")

# AFTER (fixed):
set +e
http_code=$(curl ... -w "%{http_code}" ... 2>/dev/null)
curl_exit=$?
set -e
```

### 2. `netcheck_mcp_server.py` — Duplicate condition, dead code
```python
# BEFORE: same Chinese string checked twice
direct_ok = "直连: ✓" in output or "直连: ✓" in output

# AFTER: English fallback
direct_ok = "直连: ✓" in output or "direct: OK" in output.lower()
```

## Important Issues Found & Fixed

### 3. `netcheck-route` YAML parser fragility
No parse warnings for invalid actions, missing action lines, empty routes. Added validation warnings to stderr and `--help` flag.

### 4. Duplicate code in `install.sh` vs `smart_wrappers.sh`
80 lines of bash functions were embedded in install.sh while the same logic existed in smart_wrappers.sh. Fixed: install.sh now copies smart_wrappers.sh to `~/.local/bin/` and bash_aliases sources it.

### 5. `__proxy_check` HTTPS-only assumption
Always used `https://` prefix, failing for HTTP-only sites. Fixed: try HTTPS first, fall back to HTTP.

## Nit Fixes Applied

- `smart_wrappers.sh`: Added `set -uo pipefail`
- `netcheck_mcp_server.py`: Handle missing `$HOME`
- `netcheck-route`: Added `--help`
- `install.sh`: pip cross-platform already handled by fallback

## Regression Caught in Re-Review

The `|| true` used to suppress `set -e` failures ALSO swallowed curl's exit code. Replaced with `set +e`/`set -e` pair which preserves `$?`.

## Bash Pattern Learned

```bash
# ❌ WRONG with set -e: swallows exit code
result=$(command) || true
rc=$?  # rc is ALWAYS 0 from true

# ✅ CORRECT with set -e: preserves exit code
set +e
result=$(command)
rc=$?
set -e
```
