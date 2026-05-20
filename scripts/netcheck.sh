#!/usr/bin/env bash
# netcheck — 网络连通性智能检测（对比直连 vs 代理）
# 用法: netcheck [选项] <url>
#
# 代理配置（环境变量，均可选）：
#   PROXY_URL      — 完整代理地址，如 http://127.0.0.1:7897 或 socks5://127.0.0.1:1080
#   PROXY_HOST     — 代理主机（默认：自动检测 WSL 网关 或 127.0.0.1）
#   PROXY_PORT     — 代理端口（默认：7897）
#   PROXY_PROTO    — 代理协议（默认：http，可选 socks5）
#
# 自动检测：WSL 环境下自动获取 Windows 主机 IP 作为默认 PROXY_HOST。
# 非 WSL 环境默认 127.0.0.1。
#
# 依赖: curl, bc（可选，用于速度对比）
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'

# ===== 代理地址推导 =====
detect_proxy() {
    # 1. 如果用户已设置完整 PROXY_URL，直接使用
    if [[ -n "${PROXY_URL:-}" ]]; then
        echo "$PROXY_URL"
        return
    fi

    # 2. 协议：PROXY_PROTO 或 http
    local proto="${PROXY_PROTO:-http}"

    # 3. 主机：自动检测 或 127.0.0.1
    local host="${PROXY_HOST:-}"
    if [[ -z "$host" ]]; then
        # WSL 环境：取 Windows 主机 IP
        host=$(ip route show default 2>/dev/null | awk '{print $3; exit}')
        # 非 WSL 或失败：回退到 127.0.0.1
        [[ -z "$host" ]] && host="127.0.0.1"
    fi

    # 4. 端口：PROXY_PORT 或默认 7897
    local port="${PROXY_PORT:-7897}"

    echo "${proto}://${host}:${port}"
}

PROXY_URL_DETECTED=$(detect_proxy)

# 提取代理类型用于 curl 参数
PROXY_PROTO="${PROXY_PROTO:-http}"
if [[ "$PROXY_URL_DETECTED" == socks5://* ]]; then
    CURL_PROXY_ARG="--socks5-hostname ${PROXY_URL_DETECTED#socks5://}"
elif [[ "$PROXY_URL_DETECTED" == socks4://* ]]; then
    CURL_PROXY_ARG="--socks4 ${PROXY_URL_DETECTED#socks4://}"
elif [[ "$PROXY_URL_DETECTED" == https://* ]]; then
    CURL_PROXY_ARG="--proxy-insecure --proxy $PROXY_URL_DETECTED"
else
    # http:// 或没有协议头
    CURL_PROXY_ARG="--proxy $PROXY_URL_DETECTED"
fi

TIMEOUT=10
URL=""
SPEED_TEST=false

usage() {
    cat <<EOF
用法: netcheck [选项] <url>

网络连通性智能检测 — 对比直连与代理的连通性和速度。

环境变量配置（均可选）:
  PROXY_URL    完整代理地址（如 http://127.0.0.1:7897 或 socks5://127.0.0.1:1080）
  PROXY_HOST   代理主机（默认: WSL 网关 或 127.0.0.1）
  PROXY_PORT   代理端口（默认: 7897）
  PROXY_PROTO  代理协议（默认: http，可选 socks5）

选项:
  -t <秒>    超时秒数（默认 10）
  -s         速度对比模式（下载前 1MB 测速）
  -h         帮助

示例:
  netcheck https://huggingface.co
  netcheck -t 5 https://github.com
  PROXY_PORT=1080 netcheck https://example.com
  PROXY_URL=socks5://127.0.0.1:1080 netcheck -s https://huggingface.co/file.bin
EOF
    exit 0
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) TIMEOUT="$2"; shift 2 ;;
        -s) SPEED_TEST=true; shift ;;
        -h|--help) usage ;;
        -*) echo "未知选项: $1"; usage ;;
        *)  URL="$1"; shift ;;
    esac
done

[[ -z "$URL" ]] && { echo -e "${RED}错误: 请提供 URL${RESET}"; usage; }

HOST=$(echo "$URL" | sed -E 's|^https?://([^/:]+).*|\1|')

# ===== B. 路由表优先（跳过检测）=====
ROUTE_HELPER="$HOME/.local/bin/netcheck-route"
if [[ -x "$ROUTE_HELPER" ]]; then
    ROUTE_ACTION=$("$ROUTE_HELPER" "$HOST" 2>/dev/null); route_exit=$?
    # Exit code 2 = route table parse error (corrupted YAML)
    if [[ $route_exit -eq 2 ]]; then
        echo -e "${YELLOW}⚠ 路由表解析错误，跳过路由检测，进行实时检测...${RESET}" >&2
    elif [[ "$ROUTE_ACTION" == "always_proxy" ]]; then
        echo ""
        echo -e "${CYAN}═══ netcheck: $HOST ═══${RESET}"
        echo -e "  路由: ${YELLOW}命中规则 → 始终代理${RESET}"
        echo -e "  代理: ${PROXY_URL_DETECTED}"
        echo ""
        echo -e "→ ${GREEN}建议: 开启代理${RESET}（路由表规则）"
        echo -e "  设置: ${CYAN}export http_proxy=$PROXY_URL_DETECTED${RESET}"
        echo ""
        exit 0
    elif [[ "$ROUTE_ACTION" == "always_direct" ]]; then
        echo ""
        echo -e "${CYAN}═══ netcheck: $HOST ═══${RESET}"
        echo -e "  路由: ${GREEN}命中规则 → 始终直连${RESET}"
        echo ""
        echo -e "→ ${GREEN}建议: 保持直连${RESET}（路由表规则）"
        echo ""
        exit 0
    fi
    # "auto" or no match → proceed with live check
fi

# ── TCP 端口连通性检测（v3: 快速回退，纯 TCP，非 HTTP）──
tcp_probe() {
    local host="$1"
    local port="${2:-443}"
    local timeout="${3:-2}"
    export TCP_HOST="$host" TCP_PORT="$port"
    timeout "$timeout" bash -c 'echo >/dev/tcp/"$TCP_HOST"/"$TCP_PORT"' 2>/dev/null && return 0
    python3 -c "
import socket, sys, os
s = socket.socket()
s.settimeout(${timeout})
try:
    s.connect((os.environ['TCP_HOST'], int(os.environ['TCP_PORT'])))
    s.close()
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
    return 1
}

# L1: TCP 端口探测（路由表未命中时快速判定）— 先443再80
if tcp_probe "$HOST" 443 2 || tcp_probe "$HOST" 80 2; then
    echo ""
    echo -e "${CYAN}═══ netcheck: $HOST ═══${RESET}"
    echo -e "  代理: ${PROXY_URL_DETECTED}"
    echo ""
    echo -e "  直连: ${GREEN}✓${RESET} TCP 可达"
    echo ""
    echo -e "→ ${GREEN}建议: 保持直连${RESET}（TCP 端口可达）"
    echo ""
    exit 0
fi

# ===== 单次检测 =====
check_url() {
    local url="$1"
    local proxy_arg="$2"
    local label="$3"

    local start_time end_time elapsed http_code curl_exit

    start_time=$(date +%s.%N)
    # Capture HTTP status via -w, exit code via $?
    # Use set +e to prevent premature exit, then capture curl's real exit code
    set +e
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$TIMEOUT" \
        --connect-timeout "$((TIMEOUT/2))" \
        -L \
        $proxy_arg \
        "$url" 2>/dev/null)
    curl_exit=$?
    set -e
    end_time=$(date +%s.%N)

    elapsed=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")

    # curl exit 0 = connected successfully (site is reachable)
    if [[ $curl_exit -eq 0 ]]; then
        echo "ok $elapsed"
    else
        local reason
        case $curl_exit in
            6)  reason="DNS 解析失败" ;;
            7)  reason="连接被拒绝" ;;
            28) reason="超时 (${TIMEOUT}s)" ;;
            35) reason="SSL/TLS 握手失败" ;;
            52) reason="无数据返回" ;;
            56) reason="接收数据失败" ;;
            *)  reason="curl 错误码 $curl_exit" ;;
        esac
        echo "fail $reason"
    fi
}

# ===== 速度测试 =====
speed_test() {
    local url="$1"
    local proxy_arg="$2"
    local label="$3"

    local speed_kbps curl_exit
    set +e
    speed_kbps=$(curl -s -o /dev/null -w "%{speed_download}" \
        --max-time "$TIMEOUT" \
        --connect-timeout "$((TIMEOUT/2))" \
        -L \
        --range 0-1048575 \
        $proxy_arg \
        "$url" 2>/dev/null)
    curl_exit=$?
    set -e

    if [[ $curl_exit -ne 0 ]]; then
        echo "0"
        return
    fi
    speed_kbps=$(echo "$speed_kbps / 1024" | bc 2>/dev/null || echo "0")
    echo "$speed_kbps"
}

# ===== 主流程 =====
echo ""
echo -e "${CYAN}═══ netcheck: $HOST ═══${RESET}"
echo -e "  代理: ${PROXY_URL_DETECTED}"
echo ""

# 1. 直连
DIRECT_RESULT=$(check_url "$URL" "" "直连")
DIRECT_STATUS=$(echo "$DIRECT_RESULT" | awk '{print $1}')
DIRECT_TIME=$(echo "$DIRECT_RESULT" | awk '{print $2}')

if [[ "$DIRECT_STATUS" == "ok" ]]; then
    echo -e "  直连: ${GREEN}✓${RESET} 连通 ${DIRECT_TIME}s"
else
    REASON=$(echo "$DIRECT_RESULT" | cut -d' ' -f2-)
    echo -e "  直连: ${RED}✗${RESET} $REASON"
fi

# 2. 代理
PROXY_RESULT=$(check_url "$URL" "$CURL_PROXY_ARG" "代理")
PROXY_STATUS=$(echo "$PROXY_RESULT" | awk '{print $1}')
PROXY_TIME=$(echo "$PROXY_RESULT" | awk '{print $2}')

if [[ "$PROXY_STATUS" == "ok" ]]; then
    echo -e "  代理: ${GREEN}✓${RESET} 连通 ${PROXY_TIME}s"
else
    REASON=$(echo "$PROXY_RESULT" | cut -d' ' -f2-)
    echo -e "  代理: ${RED}✗${RESET} $REASON"
fi

# 3. 速度对比
if $SPEED_TEST; then
    echo ""
    DIRECT_SPEED=$(speed_test "$URL" "" "直连")
    PROXY_SPEED=$(speed_test "$URL" "$CURL_PROXY_ARG" "代理")
    echo "  直连速度: ${DIRECT_SPEED} KB/s"
    echo "  代理速度: ${PROXY_SPEED} KB/s"
fi

# 4. 决策
echo ""
if [[ "$DIRECT_STATUS" == "ok" ]] && [[ "$PROXY_STATUS" == "fail" ]]; then
    echo -e "→ ${YELLOW}建议: 直连可用，代理不可用${RESET}（检查代理服务是否运行）"
elif [[ "$DIRECT_STATUS" == "fail" ]] && [[ "$PROXY_STATUS" == "ok" ]]; then
    echo -e "→ ${GREEN}建议: 开启代理${RESET}（直连不通，代理可用）"
    echo -e "  设置: ${CYAN}export http_proxy=$PROXY_URL_DETECTED${RESET}"
elif [[ "$DIRECT_STATUS" == "ok" ]] && [[ "$PROXY_STATUS" == "ok" ]]; then
    if command -v bc &>/dev/null; then
        DIRECT_FASTER=$(echo "$DIRECT_TIME < $PROXY_TIME" | bc -l)
        if [[ "$DIRECT_FASTER" == "1" ]]; then
            DIFF=$(echo "$PROXY_TIME - $DIRECT_TIME" | bc)
            echo -e "→ ${GREEN}建议: 保持直连${RESET}（快 ${DIFF}s）"
        else
            DIFF=$(echo "$DIRECT_TIME - $PROXY_TIME" | bc)
            echo -e "→ ${YELLOW}建议: 开启代理${RESET}（代理快 ${DIFF}s）"
        fi
    else
        echo -e "→ ${GREEN}建议: 直连可用${RESET}（代理也通，保持当前状态）"
    fi
else
    echo -e "→ ${RED}直连和代理都不可用${RESET}"
    echo -e "  ${YELLOW}排查:${RESET}"
    echo -e "    1. 代理服务是否运行？"
    echo -e "    2. 目标站点是否本身宕机？"
    echo -e "    3. PROXY_PORT 是否正确？当前检测地址: $PROXY_URL_DETECTED"
fi
echo ""
