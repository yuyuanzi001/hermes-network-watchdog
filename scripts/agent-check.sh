#!/usr/bin/env bash
# agent-check.sh — Agent 专用网络三段式决策 (v3)
# 用法: agent-check.sh <domain>
# 输出: JSON
# 退出码: 0=直连可用, 1=需要代理, 2=被墙且代理未开, 3=用法错误
set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo '{"error":"missing domain argument"}' >&2
  exit 3
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Layer 0: 路由表 (0ms) ──
ROUTE=$("$SCRIPT_DIR/netcheck-route" "$DOMAIN" 2>/dev/null); route_exit=$?
if [ $route_exit -eq 2 ]; then
  echo "{\"warning\":\"route table parse error, falling back to live check\"}" >&2
  ROUTE="auto"
fi
if [ "$ROUTE" = "always_proxy" ]; then
  echo "{\"domain\":\"$DOMAIN\",\"layer\":\"route\",\"decision\":\"proxy\",\"reason\":\"routing rule\"}"
  exit 1
elif [ "$ROUTE" = "always_direct" ]; then
  echo "{\"domain\":\"$DOMAIN\",\"layer\":\"route\",\"decision\":\"direct\",\"reason\":\"routing rule\"}"
  exit 0
fi

# ── Layer 1: TCP 端口探测 (<2s) ── 先443再80
tcp_reachable() {
    TCP_HOST="$DOMAIN" TCP_PORT=443 timeout 2 bash -c 'echo >/dev/tcp/"$TCP_HOST"/"$TCP_PORT"' 2>/dev/null && return 0
    TCP_HOST="$DOMAIN" TCP_PORT=80  timeout 2 bash -c 'echo >/dev/tcp/"$TCP_HOST"/"$TCP_PORT"' 2>/dev/null && return 0
    return 1
}
if tcp_reachable; then
  echo "{\"domain\":\"$DOMAIN\",\"layer\":\"tcp\",\"decision\":\"direct\",\"reason\":\"TCP reachable\"}"
  exit 0
fi

# ── Layer 2: 代理状态判断 ──
PROXY_ALIVE=false
if [ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}" ]; then
  PROXY_ALIVE=true
fi
if [ -f "$HOME/.hermes/.proxy_heartbeat" ]; then
  HB_AGE=$(($(date +%s) - $(stat -c %Y "$HOME/.hermes/.proxy_heartbeat" 2>/dev/null || stat -f %m "$HOME/.hermes/.proxy_heartbeat" 2>/dev/null || echo 0)))
  [ "$HB_AGE" -lt 120 ] && PROXY_ALIVE=true
fi

if $PROXY_ALIVE; then
  echo "{\"domain\":\"$DOMAIN\",\"layer\":\"tcp\",\"decision\":\"proxy\",\"reason\":\"TCP unreachable, proxy available\"}"
  exit 1
else
  echo "{\"domain\":\"$DOMAIN\",\"layer\":\"tcp\",\"decision\":\"blocked\",\"reason\":\"TCP unreachable, proxy NOT enabled\"}"
  exit 2
fi
