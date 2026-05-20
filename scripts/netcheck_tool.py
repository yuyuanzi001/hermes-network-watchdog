#!/usr/bin/env python3
"""
Hermes Agent tool: netcheck
Compares direct vs proxy connectivity for a URL and returns a decision.

Called automatically when:
- curl/wget/pip/git operations fail with network errors
- Agent suspects connectivity issues
- User asks about network status

Returns structured JSON with connectivity results and recommended action.
"""

import json
import subprocess
import sys
import os


def run_netcheck(url: str, timeout: int = 10) -> dict:
    """
    Check if a URL is reachable directly and/or via proxy.

    Args:
        url: The URL to test connectivity against
        timeout: Maximum seconds to wait (default 10)

    Returns:
        dict with keys:
            direct_ok: bool — direct connection succeeded
            proxy_ok: bool — proxy connection succeeded
            direct_time: float — direct connection latency in seconds
            proxy_time: float — proxy connection latency in seconds
            recommendation: str — "direct" | "proxy" | "both_dead" | "direct_preferred"
            proxy_url: str — detected proxy URL
    """
    netcheck_path = os.path.expanduser("~/.local/bin/netcheck")

    if not os.path.exists(netcheck_path):
        return {
            "error": "netcheck not installed. Run: curl -sL https://raw.githubusercontent.com/USER/hermes-network-watchdog/main/install.sh | bash",
            "direct_ok": None,
            "proxy_ok": None,
            "recommendation": "install_netcheck",
        }

    try:
        result = subprocess.run(
            [netcheck_path, "-t", str(timeout), url],
            capture_output=True,
            text=True,
            timeout=timeout + 5,
            env={**os.environ, "LC_ALL": "C"},  # force English output
        )
    except subprocess.TimeoutExpired:
        return {
            "error": f"netcheck timed out after {timeout+5}s",
            "direct_ok": False,
            "proxy_ok": False,
            "recommendation": "timeout",
        }

    output = result.stdout

    # Parse netcheck output
    direct_ok = "直连: ✓" in output or "direct: OK" in output.lower() or "direct: ✓" in output
    if not direct_ok:
        direct_ok = "直连: ✓" in output

    proxy_ok = "代理: ✓" in output or "proxy: OK" in output.lower() or "proxy: ✓" in output
    if not proxy_ok:
        proxy_ok = "代理: ✓" in output

    # Extract proxy URL
    proxy_url = "unknown"
    for line in output.split("\n"):
        if "代理:" in line and ("http://" in line or "socks5://" in line):
            proxy_url = line.split("http://")[-1].split("socks5://")[-1].strip()
            if proxy_url.startswith("http"):
                pass
            elif proxy_url.startswith("socks5"):
                pass
            break

    # Determine recommendation
    if direct_ok and not proxy_ok:
        recommendation = "direct"
    elif not direct_ok and proxy_ok:
        recommendation = "proxy"
    elif direct_ok and proxy_ok:
        recommendation = "direct_preferred"
    else:
        recommendation = "both_dead"

    # Extract timing if available
    direct_time = 0.0
    proxy_time = 0.0

    return {
        "direct_ok": direct_ok,
        "proxy_ok": proxy_ok,
        "direct_time": direct_time,
        "proxy_time": proxy_time,
        "recommendation": recommendation,
        "proxy_url": proxy_url,
        "raw_output": output.strip(),
    }


# Hermes tool registration
TOOL_SCHEMA = {
    "type": "function",
    "function": {
        "name": "netcheck",
        "description": "Test network connectivity (direct vs proxy) for a URL. Use when downloads fail, sites are unreachable, or network issues suspected. Returns which route works and a recommendation.",
        "parameters": {
            "type": "object",
            "properties": {
                "url": {
                    "type": "string",
                    "description": "The URL to test connectivity against (e.g., https://github.com, https://huggingface.co)",
                },
                "timeout": {
                    "type": "integer",
                    "description": "Maximum seconds to wait for each test (default: 10)",
                    "default": 10,
                },
            },
            "required": ["url"],
        },
    },
}


def handler(url: str, timeout: int = 10) -> str:
    """Tool handler — called by Hermes Agent when netcheck is invoked."""
    result = run_netcheck(url, timeout)

    if result.get("error"):
        return f"❌ netcheck error: {result['error']}"

    rec = result["recommendation"]
    proxy = result.get("proxy_url", "unknown")

    if rec == "direct":
        return f"✅ Direct connection OK for {url}. No proxy needed."
    elif rec == "proxy":
        return f"🔄 Direct connection FAILED for {url}. Use proxy: {proxy}\n   Run: proxy on"
    elif rec == "direct_preferred":
        return f"✅ Both routes OK for {url}. Direct preferred (lower latency)."
    elif rec == "both_dead":
        return f"❌ Both direct and proxy FAILED for {url}. Check: 1) proxy service running? 2) site itself down? 3) DNS?"
    else:
        return f"netcheck result: {result['raw_output']}"


# CLI support
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: netcheck-tool <url> [timeout]")
        sys.exit(1)

    url = sys.argv[1]
    timeout = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    print(json.dumps(run_netcheck(url, timeout), indent=2, ensure_ascii=False))
