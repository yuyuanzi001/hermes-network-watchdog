#!/bin/bash
# Smart wrapper functions for network-proxy-watchdog
# Source this file in ~/.bashrc or ~/.bash_aliases
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/yuyuanzi001/hermes-network-watchdog/main/scripts/smart_wrappers.sh | bash
#   source ~/.bashrc

# ===== Proxy Address Resolution =====
__proxy_get_url() {
    if [[ -n "${PROXY_URL:-}" ]]; then
        echo "$PROXY_URL"
        return
    fi
    local proto="${PROXY_PROTO:-http}"
    local host="${PROXY_HOST:-}"
    if [[ -z "$host" ]]; then
        host=$(ip route show default 2>/dev/null | awk '{print $3; exit}')
        [[ -z "$host" ]] && host="127.0.0.1"
    fi
    local port="${PROXY_PORT:-7897}"
    echo "${proto}://${host}:${port}"
}

# ===== Proxy Toggle =====
proxy() {
    local PROXY_URL=$(__proxy_get_url)
    case "${1:-}" in
        on)
            export http_proxy="$PROXY_URL"
            export https_proxy="$PROXY_URL"
            export HTTP_PROXY="$PROXY_URL"
            export HTTPS_PROXY="$PROXY_URL"
            export all_proxy="$PROXY_URL"
            export ALL_PROXY="$PROXY_URL"
            export no_proxy="localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
            export NO_PROXY="$no_proxy"
            echo "Proxy ON → ${PROXY_URL}"
            ;;
        off)
            unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
            echo "Proxy OFF"
            ;;
        status|"")
            if [ -n "${http_proxy:-}" ]; then
                echo "Proxy ON → $http_proxy"
            else
                echo "Proxy OFF"
            fi
            ;;
        *) echo "Usage: proxy {on|off|status}"; return 1 ;;
    esac
}

# ===== Connectivity Check =====
__check_host() {
    curl -s --max-time 3 "https://$1" > /dev/null 2>&1
}

# ===== Smart Wrappers =====
spip() {
    __check_host "pypi.org" || { echo "[spip] Proxy needed for PyPI"; proxy on; }
    pip "$@"
}

sgclone() {
    local host=$(echo "${1:-}" | sed 's|.*://||;s|/.*||')
    [[ -n "$host" ]] && __check_host "$host" || { echo "[sgclone] Proxy needed for $host"; proxy on; }
    git clone "$@"
}

swget() {
    local last="${@: -1}"
    local host=$(echo "$last" | sed 's|.*://||;s|/.*||')
    [[ -n "$host" ]] && __check_host "$host" || { echo "[swget] Proxy needed for $host"; proxy on; }
    wget "$@"
}

scurl() {
    for arg in "$@"; do
        [[ "$arg" =~ ^https?:// ]] && { local host=$(echo "$arg" | sed 's|.*://||;s|/.*||'); __check_host "$host" || { echo "[scurl] Proxy needed for $host"; proxy on; }; break; }
    done
    curl "$@"
}

echo "Smart wrappers loaded: proxy, spip, sgclone, swget, scurl"
