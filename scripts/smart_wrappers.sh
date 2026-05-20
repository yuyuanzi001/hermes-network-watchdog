#!/bin/bash
# Smart wrapper functions for network-proxy-watchdog (v2 — push/pop safe)
# Source this file in ~/.bashrc or ~/.bash_aliases
#
# Usage:
#   source ~/.hermes/skills/devops/network-proxy-watchdog/scripts/smart_wrappers.sh
set -uo pipefail

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

# ===== Proxy Toggle (v2 — with push/pop) =====
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
            mkdir -p "$HOME/.hermes"
            echo "on" > "$HOME/.hermes/.proxy_state"
            echo "Proxy ON → ${PROXY_URL}"
            ;;
        off)
            unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
            mkdir -p "$HOME/.hermes"
            echo "off" > "$HOME/.hermes/.proxy_state"
            echo "Proxy OFF"
            ;;
        push)
            if [ -n "${http_proxy:-}" ]; then
                export __PROXY_STACK="${__PROXY_STACK:+$__PROXY_STACK:}on"
            else
                export __PROXY_STACK="${__PROXY_STACK:+$__PROXY_STACK:}off"
            fi
            ;;
        pop)
            if [ -z "${__PROXY_STACK:-}" ]; then
                echo "proxy: stack empty, keeping current state"
                return 0
            fi
            local state="${__PROXY_STACK##*:}"
            if [[ "$__PROXY_STACK" == *:* ]]; then
                export __PROXY_STACK="${__PROXY_STACK%:*}"
            else
                unset __PROXY_STACK
            fi
            if [ "$state" = "on" ]; then
                export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL"
                export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL"
                export all_proxy="$PROXY_URL" ALL_PROXY="$PROXY_URL"
            else
                unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
            fi
            ;;
        status|"")
            if [ -n "${http_proxy:-}" ]; then
                echo "Proxy ON → $http_proxy"
            else
                echo "Proxy OFF"
            fi
            ;;
        *) echo "Usage: proxy {on|off|status|push|pop}"; return 1 ;;
    esac
}

# ===== Connectivity Check =====
__proxy_check() {
    # Try HTTPS first (most sites), fall back to HTTP for HTTP-only sites
    curl -s --max-time 3 "https://$1" > /dev/null 2>&1 || \
    curl -s --max-time 3 "http://$1" > /dev/null 2>&1
}

# ===== Smart Wrappers (push/pop — auto-restore proxy state) =====
spip() {
    proxy push
    if ! __proxy_check "pypi.org"; then
        echo "[spip] PyPI unreachable, enabling proxy..."
        proxy on
    fi
    pip "$@"
    local _rc=$?
    proxy pop
    return $_rc
}

sgclone() {
    local url=""
    for arg in "$@"; do
        [[ "$arg" =~ ^https?:// ]] && { url="$arg"; break; }
        [[ "$arg" =~ ^git@ ]] && { url="$arg"; break; }
    done
    if [[ -z "$url" ]]; then
        git clone "$@"
        return $?
    fi
    local host=$(echo "$url" | sed 's|.*://||;s|/.*||;s|.*@||;s|:.*||')
    proxy push
    if ! __proxy_check "$host"; then
        echo "[sgclone] $host unreachable, enabling proxy..."
        proxy on
    fi
    git clone "$@"
    local _rc=$?
    proxy pop
    return $_rc
}

swget() {
    local url=""
    for arg in "$@"; do
        [[ "$arg" =~ ^https?:// ]] && { url="$arg"; break; }
        [[ "$arg" =~ ^ftp:// ]] && { url="$arg"; break; }
    done
    proxy push
    if [[ -n "$url" ]]; then
        local host=$(echo "$url" | sed 's|.*://||;s|/.*||')
        if ! __proxy_check "$host"; then
            echo "[swget] $host unreachable, enabling proxy..."
            proxy on
        fi
    fi
    wget "$@"
    local _rc=$?
    proxy pop
    return $_rc
}

scurl() {
    local url=""
    for arg in "$@"; do
        [[ "$arg" =~ ^https?:// ]] && { url="$arg"; break; }
    done
    proxy push
    if [[ -n "$url" ]]; then
        local host=$(echo "$url" | sed 's|.*://||;s|/.*||')
        if ! __proxy_check "$host"; then
            echo "[scurl] $host unreachable, enabling proxy..."
            proxy on
        fi
    fi
    curl "$@"
    local _rc=$?
    proxy pop
    return $_rc
}

echo "Smart wrappers loaded (v2 push/pop): proxy, spip, sgclone, swget, scurl"
