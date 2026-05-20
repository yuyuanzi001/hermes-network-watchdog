#!/usr/bin/env bash
# network-proxy-watchdog — one-click install
# Run from the skill directory or any path:
#   bash ~/.hermes/skills/devops/network-proxy-watchdog/install.sh
# Or directly:
#   curl -sL <url>/install.sh | bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
HERMES_DIR="$HOME/.hermes"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════${RESET}"
echo -e "${CYAN}  network-proxy-watchdog installer${RESET}"
echo -e "${CYAN}═══════════════════════════════════════${RESET}"
echo ""

# ── Step 1: Install executables ──
echo -e "${YELLOW}[1/4] Installing netcheck executables...${RESET}"
mkdir -p "$BIN_DIR"

# netcheck — check if already a symlink to our script
SRC_NETCHECK="$SKILL_DIR/scripts/netcheck.sh"
DST_NETCHECK="$BIN_DIR/netcheck"
if [[ -L "$DST_NETCHECK" ]] && [[ "$(readlink -f "$DST_NETCHECK")" == "$(readlink -f "$SRC_NETCHECK")" ]]; then
    echo -e "  ${GREEN}✓${RESET} netcheck already linked to skill dir"
else
    cp "$SRC_NETCHECK" "$DST_NETCHECK"
    chmod +x "$DST_NETCHECK"
    echo -e "  ${GREEN}✓${RESET} netcheck installed"
fi

# netcheck-route
cp "$SKILL_DIR/scripts/netcheck-route" "$BIN_DIR/netcheck-route"
chmod +x "$BIN_DIR/netcheck-route"
echo -e "  ${GREEN}✓${RESET} netcheck-route installed"

# v3: agent-check
cp "$SKILL_DIR/scripts/agent-check.sh" "$BIN_DIR/agent-check"
chmod +x "$BIN_DIR/agent-check"
echo -e "  ${GREEN}✓${RESET} agent-check installed"

# v3: proxy-heartbeat
cp "$SKILL_DIR/scripts/proxy-heartbeat.sh" "$BIN_DIR/proxy-heartbeat"
chmod +x "$BIN_DIR/proxy-heartbeat"
echo -e "  ${GREEN}✓${RESET} proxy-heartbeat installed"

# v3: wake-guard
cp "$SKILL_DIR/scripts/wake-guard.sh" "$BIN_DIR/wake-guard"
chmod +x "$BIN_DIR/wake-guard"
echo -e "  ${GREEN}✓${RESET} wake-guard installed"

# Ensure BIN_DIR in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
    export PATH="$BIN_DIR:$PATH"
    echo -e "  ${GREEN}✓${RESET} Added $BIN_DIR to PATH"
fi
echo -e "  ${GREEN}✓${RESET} netcheck + netcheck-route installed"

# ── Step 2: Route table ──
echo -e "${YELLOW}[2/4] Installing route table...${RESET}"
ROUTES_FILE="$HERMES_DIR/network-routes.yaml"
if [[ -f "$ROUTES_FILE" ]]; then
    echo -e "  ${YELLOW}⚠${RESET}  $ROUTES_FILE already exists, skipping"
    echo "     (delete it first if you want a fresh copy)"
else
    cp "$SKILL_DIR/templates/network-routes.yaml" "$ROUTES_FILE"
    echo -e "  ${GREEN}✓${RESET} Route table installed: $ROUTES_FILE"
fi

# ── Step 3: MCP server (optional) ──
echo -e "${YELLOW}[3/4] MCP server setup...${RESET}"
MCP_SRC="$SKILL_DIR/scripts/netcheck_mcp_server.py"
MCP_DST="$HERMES_DIR/tools/netcheck_mcp_server.py"

mkdir -p "$HERMES_DIR/tools"
cp "$MCP_SRC" "$MCP_DST"
chmod +x "$MCP_DST"
echo -e "  ${GREEN}✓${RESET} MCP server: $MCP_DST"

# Check if mcp package is installed
if ! python3 -c "import mcp" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠${RESET}  Python 'mcp' package not found, installing..."
    pip install mcp --break-system-packages 2>/dev/null || pip install mcp 2>/dev/null || {
        echo -e "  ${YELLOW}⚠${RESET}  Could not install 'mcp'. MCP tool won't work."
        echo "     Install manually: pip install mcp"
    }
fi

# Check if MCP server already registered in config.yaml
CONFIG_FILE="$HERMES_DIR/config.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
    if grep -q "netcheck_mcp_server" "$CONFIG_FILE" 2>/dev/null; then
        echo -e "  ${YELLOW}⚠${RESET}  MCP server already in config.yaml, skipping"
    else
        echo ""
        echo -e "  ${YELLOW}To register the MCP tool, add this to ~/.hermes/config.yaml:${RESET}"
        echo ""
        echo "    mcp_servers:"
        echo "      netcheck:"
        echo '        command: "python3"'
        echo '        args: ["'"$MCP_DST"'"]'
        echo "        timeout: 30"
        echo "        connect_timeout: 10"
        echo ""
        echo -e "  Then restart Hermes. Without MCP, the agent can still use"
        echo -e "  'terminal' to run 'netcheck <domain>' directly."
    fi
else
    echo -e "  ${YELLOW}⚠${RESET}  No config.yaml found. Create one with 'hermes setup' first."
fi

# ── Step 4: Bash functions ──
echo -e "${YELLOW}[4/4] Installing bash functions...${RESET}"
BASH_ALIASES="$HOME/.bash_aliases"
INSTALL_MARKER="# >>> network-proxy-watchdog (auto-installed)"

# Install the standalone wrapper script so bash_aliases just sources it
SMART_WRAPPERS_DST="$BIN_DIR/smart_wrappers.sh"
cp "$SKILL_DIR/scripts/smart_wrappers.sh" "$SMART_WRAPPERS_DST"
chmod +x "$SMART_WRAPPERS_DST"

if [[ -f "$BASH_ALIASES" ]] && grep -qF "$INSTALL_MARKER" "$BASH_ALIASES" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠${RESET}  Functions already in ~/.bash_aliases, skipping"
else
    cat >> "$BASH_ALIASES" << BASHEOF

# >>> network-proxy-watchdog (auto-installed)
source "$SMART_WRAPPERS_DST"
alias netcheck='PATH="\$HOME/.local/bin:\$PATH" netcheck'
alias proxy-ping='proxy-heartbeat --once'
# <<< network-proxy-watchdog
BASHEOF
    echo -e "  ${GREEN}✓${RESET} Added source line to ~/.bash_aliases"
    echo -e "  ${YELLOW}  Run 'source ~/.bash_aliases' to activate now${RESET}"
fi

# ── Done ──
echo ""
echo -e "${GREEN}═══════════════════════════════════════${RESET}"
echo -e "${GREEN}  Installation complete!${RESET}"
echo ""
echo "  Quick test:"
echo "    source ~/.bash_aliases"
echo "    netcheck huggingface.co"
echo ""
echo "  For Hermes MCP integration, add the config block"
echo "  shown above and restart Hermes."
echo -e "${GREEN}═══════════════════════════════════════${RESET}"
