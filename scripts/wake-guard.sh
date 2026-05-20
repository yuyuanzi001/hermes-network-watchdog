#!/usr/bin/env bash
# wake-guard.sh — 休眠唤醒检测 & 自动恢复 (v3)
# 环境变量: WAKEGUARD_TEST_DOMAIN (默认 google.com)
set -euo pipefail

# cron 环境下补充 PATH
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

STAMP_FILE="$HOME/.hermes/.wake_stamp"
GUARD_LOG="$HOME/.hermes/logs/wake-guard.log"
TEST_DOMAIN="${WAKEGUARD_TEST_DOMAIN:-google.com}"
SLEEP_THRESHOLD=120
MAX_LOG_SIZE=$((512 * 1024))  # 512KB max

mkdir -p "$(dirname "$GUARD_LOG")"

# 日志轮转
if [ -f "$GUARD_LOG" ]; then
  LOG_SIZE=$(stat -c %s "$GUARD_LOG" 2>/dev/null || stat -f %z "$GUARD_LOG" 2>/dev/null || echo 0)
  if [ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]; then
    mv "$GUARD_LOG" "${GUARD_LOG}.old" 2>/dev/null || true
  fi
fi

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$GUARD_LOG"; }

# 首次运行
if [ ! -f "$STAMP_FILE" ]; then
  touch "$STAMP_FILE"
  exit 0
fi

NOW=$(date +%s)
LAST=$(stat -c %Y "$STAMP_FILE" 2>/dev/null || stat -f %m "$STAMP_FILE" 2>/dev/null || echo "$NOW")
GAP=$((NOW - LAST))
touch "$STAMP_FILE"

if [ "$GAP" -le "$SLEEP_THRESHOLD" ]; then
  exit 0
fi

log "疑似休眠唤醒 (间隔 ${GAP}s)，开始恢复..."

# 1. DNS 可达性 (python3 优先，回退 getent)
dns_ok=false
for i in $(seq 1 6); do
  export WAKEGUARD_TEST_DOMAIN="$TEST_DOMAIN"
  if python3 -c "
import socket, os
d = os.environ.get('WAKEGUARD_TEST_DOMAIN', 'google.com')
socket.getaddrinfo(d, 443)
" 2>/dev/null; then
    dns_ok=true; break
  elif getent hosts "$TEST_DOMAIN" >/dev/null 2>&1; then
    dns_ok=true; break
  fi
  sleep 3
done
$dns_ok && log "DNS 已恢复" || log "DNS 未恢复 ⚠"

# 2. 代理心跳 (绝对路径)
HB_BIN="$HOME/.local/bin/proxy-heartbeat"
if [ -x "$HB_BIN" ]; then
  hb_ok=false
  if "$HB_BIN" --once 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('status')=='alive' else 1)" 2>/dev/null; then
    hb_ok=true
  fi
  $hb_ok && log "代理正常" || log "代理异常"
fi

# 3. Gateway
pgrep -f "hermes gateway" >/dev/null 2>&1 && log "Gateway 存活" || log "Gateway 未运行"

log "恢复流程完成"
