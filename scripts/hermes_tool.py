# Hermes Agent tool — netcheck integration
# Copy to ~/.hermes/tools/netcheck.py to register as a tool.
# When Agent encounters network failures (curl/pip/git timeout),
# it auto-calls netcheck to diagnose direct vs proxy connectivity.
#
# Installation:
#   cp scripts/hermes_tool.py ~/.hermes/tools/netcheck.py
#
# Usage in Agent context:
#   Agent: "Download failed. Let me check connectivity..."
#   -> netcheck(url="https://huggingface.co")
#   <- "Direct FAILED. Must use proxy: http://172.31.112.1:7897"
#   Agent: "Enabling proxy and retrying..."

import json
import subprocess
import os
import sys


TOOL_SCHEMA = {
    "type": "function",
    "function": {
        "name": "netcheck",
        "description": "Test if a URL is reachable directly or requires proxy. Compares direct vs proxy connectivity and returns a recommendation. Use when downloads fail, sites are unreachable, or user asks about network/proxy.",
        "parameters": {
            "type": "object",
            "properties": {
                "url": {
                    "type": "string",
                    "description": "The URL or domain to test (e.g. 'https://github.com', 'huggingface.co')",
                },
                "timeout": {
                    "type": "integer",
                    "description": "Max seconds per test (default: 10, max: 30)",
                    "default": 10,
                },
            },
            "required": ["url"],
        },
    },
}


def handler(url: str, timeout: int = 10) -> str:
    """Called by Hermes Agent when netcheck tool is invoked."""
    netcheck_bin = os.path.expanduser("~/.local/bin/netcheck")

    if not os.path.exists(netcheck_bin):
        return (
            "netcheck script not found. Install with:\n"
            "curl -sL https://github.com/USER/hermes-network-watchdog/raw/main/install.sh | bash"
        )

    timeout = min(timeout or 10, 30)

    try:
        r = subprocess.run(
            [netcheck_bin, "-t", str(timeout), url],
            capture_output=True, text=True, timeout=timeout + 5,
            env={**os.environ, "LC_ALL": "C"},
        )
    except subprocess.TimeoutExpired:
        return "netcheck timed out — both routes unreachable."

    output = r.stdout
    direct_ok = "直连:" in output and "✓" in output
    proxy_ok = "代理:" in output and "✓" in output

    proxy_url = "unknown"
    for line in output.split("\n"):
        if "代理:" in line and "://" in line:
            for p in line.split():
                if "://" in p:
                    proxy_url = p
                    break

    if direct_ok and proxy_ok:
        return f"Both routes reachable for {url}. Direct preferred."
    elif direct_ok and not proxy_ok:
        return f"Direct OK for {url}. Proxy seems down — check proxy service."
    elif not direct_ok and proxy_ok:
        return f"Direct FAILED for {url}. Use proxy: {proxy_url}\nTo enable: proxy on"
    else:
        return (
            f"Both routes FAILED for {url}.\n"
            f"Troubleshooting: 1) proxy service running? 2) site down? 3) DNS?\n"
            f"Manual: PROXY_PORT=1080 proxy on"
        )
