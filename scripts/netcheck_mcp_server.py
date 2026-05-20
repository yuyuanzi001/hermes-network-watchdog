#!/usr/bin/env python3
"""
netcheck MCP Server — exposes netcheck as a Hermes Agent tool via MCP stdio.

Registered in ~/.hermes/config.yaml under mcp_servers.
Once registered, the agent gets an mcp_netcheck_netcheck tool it can call
before any download/network operation.

Usage as MCP server (called by Hermes, not manually):
  python netcheck_mcp_server.py
"""

import json
import subprocess
import os
import sys
import asyncio
from pathlib import Path

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

NETCHECK_BIN = os.path.expanduser(
    os.environ.get("HOME", f"/home/{os.environ.get('USER', 'unknown')}") + "/.local/bin/netcheck"
)

server = Server("netcheck")


def run_netcheck(url: str, timeout: int = 10) -> dict:
    """Execute netcheck.sh and parse structured result."""
    if not os.path.exists(NETCHECK_BIN):
        return {
            "error": "netcheck not installed",
            "recommendation": "install_netcheck",
        }

    try:
        result = subprocess.run(
            [NETCHECK_BIN, "-t", str(min(timeout, 30)), url],
            capture_output=True,
            text=True,
            timeout=min(timeout, 30) + 5,
            env={**os.environ, "LC_ALL": "C"},
        )
    except subprocess.TimeoutExpired:
        return {
            "error": "netcheck timed out",
            "recommendation": "timeout",
        }

    output = result.stdout
    # Check both Chinese and English output (netcheck uses Chinese by default)
    direct_ok = "直连: ✓" in output or "direct: OK" in output.lower()
    proxy_ok = "代理: ✓" in output or "proxy: OK" in output.lower()

    # Extract proxy URL
    proxy_url = "unknown"
    for line in output.split("\n"):
        if "代理:" in line and "://" in line:
            proxy_url = line.strip()
            break

    # Extract timing
    direct_time = 0.0
    proxy_time = 0.0
    for line in output.split("\n"):
        if "直连:" in line and "✓" in line:
            parts = line.split()
            for p in parts:
                if p.endswith("s") and p[:-1].replace(".", "").isdigit():
                    direct_time = float(p[:-1])
        if "代理:" in line and "✓" in line:
            parts = line.split()
            for p in parts:
                if p.endswith("s") and p[:-1].replace(".", "").isdigit():
                    proxy_time = float(p[:-1])

    # Determine recommendation
    if direct_ok and not proxy_ok:
        recommendation = "direct"
        action = "No proxy needed. Direct connection works."
    elif not direct_ok and proxy_ok:
        recommendation = "proxy"
        action = f"Direct FAILED. Use proxy. Run: proxy on  (proxy at {proxy_url})"
    elif direct_ok and proxy_ok:
        recommendation = "direct_preferred"
        action = "Both routes work. Direct preferred (lower latency)."
    else:
        recommendation = "both_dead"
        action = "Both routes FAILED. Check: 1) proxy service running? 2) site down? 3) DNS?"

    return {
        "url": url,
        "direct_ok": direct_ok,
        "proxy_ok": proxy_ok,
        "direct_time_s": direct_time,
        "proxy_time_s": proxy_time,
        "recommendation": recommendation,
        "action": action,
        "proxy_url": proxy_url,
    }


@server.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="netcheck",
            description=(
                "Test if a URL/domain is reachable directly or requires a proxy. "
                "Compares direct vs proxy connectivity and returns a recommendation. "
                "ALWAYS call this BEFORE any download, API call, git clone, pip install, "
                "or browser navigation to external sites. If recommendation is 'proxy', "
                "run 'proxy on' in terminal before proceeding."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "url": {
                        "type": "string",
                        "description": "URL or domain to test (e.g. 'https://github.com', 'huggingface.co')",
                    },
                    "timeout": {
                        "type": "integer",
                        "description": "Max seconds per test (default: 10, max: 30)",
                        "default": 10,
                    },
                },
                "required": ["url"],
            },
        )
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    if name != "netcheck":
        return [TextContent(type="text", text=f"Unknown tool: {name}")]

    url = arguments.get("url", "")
    timeout = arguments.get("timeout", 10)

    if not url:
        return [TextContent(type="text", text="Error: url is required")]

    result = run_netcheck(url, timeout)
    return [TextContent(type="text", text=json.dumps(result, indent=2, ensure_ascii=False))]


async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
