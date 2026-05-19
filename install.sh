#!/bin/bash
# Hermes Network Watchdog — One-line installer
# curl -sL https://raw.githubusercontent.com/yuyuanzi001/hermes-network-watchdog/main/install.sh | bash

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
REPO="https://raw.githubusercontent.com/yuyuanzi001/hermes-network-watchdog/main"

echo -e "${CYAN}═══ Hermes Network Watchdog Installer ═══${RESET}"
echo ""

# 1. Install netcheck script
echo "→ Installing netcheck..."
mkdir -p ~/.local/bin
curl -sL "$REPO/scripts/netcheck.sh" -o ~/.local/bin/netcheck
chmod +x ~/.local/bin/netcheck

# Add to PATH if not already
if ! echo "$PATH" | grep -q ".local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
fi

# 2. Install smart wrappers
echo "→ Installing smart wrappers..."
WRAPPERS_LINE='source <(curl -sL '"$REPO/scripts/smart_wrappers.sh"')'
if ! grep -q "smart_wrappers" ~/.bashrc 2>/dev/null; then
    echo "$WRAPPERS_LINE" >> ~/.bashrc
fi

# 3. Install Hermes tool (if Hermes exists)
if command -v hermes &>/dev/null; then
    echo "→ Installing Hermes Agent tool..."
    mkdir -p ~/.hermes/tools
    curl -sL "$REPO/tools/netcheck.py" -o ~/.hermes/tools/netcheck.py
fi

echo ""
echo -e "${GREEN}✓ Installation complete!${RESET}"
echo ""
echo "Quick start:"
echo "  source ~/.bashrc"
echo "  netcheck https://github.com"
echo "  proxy on"
echo "  spip install transformers"
echo ""
echo "Configure proxy (if not using default Clash on 7897):"
echo "  PROXY_PORT=1080 proxy on        # v2ray / SSR"
echo "  PROXY_URL=socks5://127.0.0.1:1080 proxy on   # SOCKS5"
echo -e "  ${CYAN}See README:${RESET} $REPO/README.md"
