# Hermes Agent — netcheck 工具集成
#
# 将此文件放到 ~/.hermes/tools/netcheck.py，Hermes 自动发现为工具。
# 安装: cp scripts/netcheck_tool.py ~/.hermes/tools/netcheck.py
#
# Agent 使用方式：
#   1. 自动触发：curl/pip/git 失败时，Agent 知道可以调 netcheck 判断
#   2. 手动触发：用户说"检测网络"或"试试代理"

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
            "netcheck script not found at ~/.local/bin/netcheck\n"
            "Install: curl -sL https://raw.githubusercontent.com/yuyuanzi001/hermes-network-watchdog/main/install.sh | bash"
        )

    timeout = min(timeout or 10, 30)

    try:
        r = subprocess.run(
            [netcheck_bin, "-t", str(timeout), url],
            capture_output=True, text=True, timeout=timeout + 5,
            env={**os.environ, "LC_ALL": "C"},
        )
    except subprocess.TimeoutExpired:
        return "netcheck timed out — both direct and proxy unreachable within time limit."

    output = r.stdout

    # Parse results
    direct_ok = "直连:" in output and "✓" in output
    proxy_ok = "代理:" in output and "✓" in output

    # Extract proxy URL for display
    proxy_url = "unknown"
    for line in output.split("\n"):
        if "代理:" in line and "://" in line:
            parts = line.split()
            for p in parts:
                if "://" in p:
                    proxy_url = p
                    break

    if direct_ok and proxy_ok:
        return f"Both routes reachable for {url}. Direct preferred (lower latency typically)."
    elif direct_ok and not proxy_ok:
        return f"Direct connection OK for {url}. No proxy needed. Proxy seems down — check proxy service."
    elif not direct_ok and proxy_ok:
        return (
            f"Direct connection FAILED for {url}. Must use proxy: {proxy_url}\n"
            f"To enable proxy: proxy on"
        )
    else:
        return (
            f"Both direct and proxy FAILED for {url}.\n"
            f"Troubleshooting:\n"
            f"  1. Is the proxy service running?\n"
            f"  2. Is {url} itself down? Try a different site.\n"
            f"  3. DNS issue? Try: nslookup {url}\n"
            f"  4. Set proxy manually: PROXY_PORT=1080 proxy on"
        )
