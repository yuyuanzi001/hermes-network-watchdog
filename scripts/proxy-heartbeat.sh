#!/usr/bin/env bash
# proxy-heartbeat.sh — 代理存活心跳检测 (v3)
# 用法: proxy-heartbeat.sh --once
# 输出: JSON
set -euo pipefail

STATE_FILE="$HOME/.hermes/.proxy_state"
HEARTBEAT_FILE="$HOME/.hermes/.proxy_heartbeat"
PROXY_HOST="${PROXY_HOST:-}"
PROXY_PORT="${PROXY_PORT:-7897}"

detect_proxy() {
  # 从任意代理环境变量获取地址（检查全部四种写法）
  local proxy_url=""
  for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
    if [ -n "${!var:-}" ]; then
      proxy_url="${!var}"
      break
    fi
  done
  if [ -n "$proxy_url" ]; then
    # 剥离协议前缀和凭据 (user:pass@host:port → host:port)
    # 用 ## 最长匹配处理密码中可能含 @ 的边界情况
    local url="${proxy_url#*://}"
    url="${url##*@}"  # 剥离 user:pass@ （最长匹配）
    PROXY_HOST="${url%:*}"
    PROXY_PORT="${url##*:}"
    return 0
  fi
  # 从状态文件判断是否配置了代理，并尝试从常见端口推断
  if [ -f "$STATE_FILE" ] && grep -q "on" "$STATE_FILE" 2>/dev/null; then
    # 尝试自动检测 Windows 宿主机 IP（WSL 环境）
    if [ -z "$PROXY_HOST" ]; then
      PROXY_HOST=$(ip route show default 2>/dev/null | awk '{print $3; exit}')
      [ -z "$PROXY_HOST" ] && PROXY_HOST="127.0.0.1"
    fi
    return 0
  fi
  return 1
}

ping_proxy() {
  local host="${1:-$PROXY_HOST}"
  local port="${2:-$PROXY_PORT}"
  export TCP_HOST="$host" TCP_PORT="$port"
  timeout 2 bash -c 'echo >/dev/tcp/"$TCP_HOST"/"$TCP_PORT"' 2>/dev/null && return 0
  return 1
}

if ! detect_proxy; then
  echo '{"status":"no_proxy","message":"代理未配置或已关闭"}'
  exit 0
fi

if ping_proxy "$PROXY_HOST" "$PROXY_PORT"; then
  date -Iseconds > "$HEARTBEAT_FILE" 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z > "$HEARTBEAT_FILE"
  echo "{\"status\":\"alive\",\"host\":\"$PROXY_HOST\",\"port\":$PROXY_PORT}"
else
  echo "{\"status\":\"dead\",\"host\":\"$PROXY_HOST\",\"port\":$PROXY_PORT,\"message\":\"代理端口不可达，代理进程可能已崩溃\"}"
  exit 1
fi
