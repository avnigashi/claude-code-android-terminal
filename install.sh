#!/usr/bin/env bash
set -euo pipefail

# Claude Code installer
# Works on ARM Linux, Android (Termux/proot), and standard x86 Linux
# Usage: curl -fsSL https://mygiturl/install.sh | bash

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BOLD}[•] $1${NC}"; }
success() { echo -e "${GREEN}[✓] $1${NC}"; }
warn()    { echo -e "${YELLOW}[!] $1${NC}"; }
error()   { echo -e "${RED}[✗] $1${NC}"; exit 1; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Claude Code Installer        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════╝${NC}"
echo ""

# ── 1. Detect environment ────────────────────────────────────────────────────

ARCH=$(uname -m)
IS_TERMUX=false
IS_ROOT=false

[[ -n "${TERMUX_VERSION:-}" || -d "/data/data/com.termux" ]] && IS_TERMUX=true
[[ "$(id -u)" -eq 0 ]] && IS_ROOT=true

info "Detected arch: $ARCH"
$IS_TERMUX && info "Termux environment detected"

# ── 2. Try native installer first (x86_64 non-Termux only) ──────────────────

if [[ "$ARCH" == "x86_64" ]] && ! $IS_TERMUX; then
    info "Attempting native installer..."
    if curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
        success "Native installer succeeded!"
        echo ""
        echo -e "${GREEN}Run: ${BOLD}claude${NC}"
        exit 0
    else
        warn "Native installer failed, falling back to npm..."
    fi
else
    warn "Skipping native installer (ARM or Termux — using npm instead)"
fi

# ── 3. Ensure Node.js is available ──────────────────────────────────────────

install_node_apt() {
    info "Installing Node.js via apt..."
    if $IS_ROOT; then
        apt-get update -qq && apt-get install -y nodejs npm
    else
        sudo apt-get update -qq && sudo apt-get install -y nodejs npm
    fi
}

install_node_termux() {
    info "Installing Node.js via pkg..."
    pkg install -y nodejs npm
}

install_node_nvm() {
    info "Installing Node.js via nvm..."
    export NVM_DIR="$HOME/.nvm"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
}

if ! command -v node &>/dev/null; then
    warn "Node.js not found"
    if $IS_TERMUX; then
        install_node_termux
    elif command -v apt-get &>/dev/null; then
        install_node_apt
    else
        install_node_nvm
    fi
else
    NODE_VER=$(node -e "process.exit(parseInt(process.versions.node) < 18 ? 1 : 0)" 2>/dev/null && echo ok || echo old)
    if [[ "$NODE_VER" == "old" ]]; then
        warn "Node.js $(node --version) is too old (need 18+), upgrading..."
        if $IS_TERMUX; then
            install_node_termux
        elif command -v apt-get &>/dev/null; then
            install_node_apt
        else
            install_node_nvm
        fi
    else
        success "Node.js $(node --version) OK"
    fi
fi

# ── 4. Configure user-level npm prefix (avoids EACCES) ──────────────────────

NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "")

if [[ "$NPM_PREFIX" == "/usr"* || "$NPM_PREFIX" == "/usr/local"* ]]; then
    warn "npm prefix is system-wide ($NPM_PREFIX), switching to user-local..."
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    NPM_BIN="$HOME/.npm-global/bin"
else
    NPM_BIN="$(npm config get prefix)/bin"
fi

# ── 5. Add npm bin to PATH (current session + shell rc file) ─────────────────

add_to_path() {
    local line='export PATH="'"$NPM_BIN"':$PATH"'

    # Current session
    export PATH="$NPM_BIN:$PATH"

    # Detect shell rc file
    local rcfile=""
    if [[ -n "${BASH_VERSION:-}" ]]; then
        rcfile="$HOME/.bashrc"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        rcfile="$HOME/.zshrc"
    else
        rcfile="$HOME/.profile"
    fi

    if [[ -f "$rcfile" ]] && grep -qF "$NPM_BIN" "$rcfile" 2>/dev/null; then
        : # Already present
    else
        echo "" >> "$rcfile"
        echo "# Added by Claude Code installer" >> "$rcfile"
        echo "$line" >> "$rcfile"
        info "Added PATH entry to $rcfile"
    fi
}

add_to_path

# ── 6. Set TMPDIR for Android/Termux ────────────────────────────────────────

if $IS_TERMUX; then
    TERMUX_TMPDIR="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    mkdir -p "$TERMUX_TMPDIR"
    export TMPDIR="$TERMUX_TMPDIR"

    # Persist it
    RCFILE="$HOME/.bashrc"
    if ! grep -q "TMPDIR" "$RCFILE" 2>/dev/null; then
        echo "" >> "$RCFILE"
        echo "# Fix for Claude Code on Termux" >> "$RCFILE"
        echo "export TMPDIR=\"$TERMUX_TMPDIR\"" >> "$RCFILE"
        info "Set TMPDIR for Termux compatibility"
    fi
fi

# ── 7. Install Claude Code ───────────────────────────────────────────────────

info "Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# ── 8. Verify ────────────────────────────────────────────────────────────────

if command -v claude &>/dev/null; then
    success "Claude Code $(claude --version 2>/dev/null || echo '') installed!"
elif [[ -x "$NPM_BIN/claude" ]]; then
    success "Claude Code installed at $NPM_BIN/claude"
    warn "Restart your shell or run: source ~/.bashrc"
else
    error "Installation may have failed. Check npm logs."
fi

echo ""
echo -e "${GREEN}${BOLD}All done! Run: claude${NC}"
echo ""
