#!/usr/bin/env bash
# Claude Code installer
# Works on: Android Termux, proot/chroot Debian, ARM64, x86_64, macOS
# Usage: curl -fsSL https://raw.githubusercontent.com/avnigashi/claude-code-android-terminal/main/install.sh | bash

# ── Force bash even if called via sh ─────────────────────────────────────────
if [ -z "$BASH_VERSION" ]; then
    if command -v bash > /dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "[!] bash not found, trying to install it..."
        if command -v apt-get > /dev/null 2>&1; then
            apt-get install -y bash 2>/dev/null || sudo apt-get install -y bash
            exec bash "$0" "$@"
        fi
        echo "[x] Could not get bash. Please run: bash install.sh"
        exit 1
    fi
fi

set -euo pipefail

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

# ── 1. Detect environment ─────────────────────────────────────────────────────

ARCH=$(uname -m)
IS_TERMUX=false
IS_PROOT=false
IS_ROOT=false
HAS_PKG=false

[[ "$(id -u)" -eq 0 ]] && IS_ROOT=true
command -v pkg > /dev/null 2>&1 && HAS_PKG=true

if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
    IS_TERMUX=true
    $HAS_PKG || IS_PROOT=true
fi

info "Detected arch: $ARCH"
if $IS_PROOT; then
    info "proot/chroot environment inside Termux detected"
elif $IS_TERMUX; then
    info "Native Termux environment detected"
fi

# ── Helper: run with or without sudo ─────────────────────────────────────────

run_privileged() {
    if $IS_ROOT; then "$@"; else sudo "$@"; fi
}

# ── 2. Try native installer first (x86_64 non-Termux only) ───────────────────

if [[ "$ARCH" == "x86_64" ]] && ! $IS_TERMUX; then
    info "Attempting official native installer..."
    if curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
        success "Native installer succeeded!"
        echo ""
        echo -e "${GREEN}Run: ${BOLD}claude${NC}"
        exit 0
    else
        warn "Native installer failed, falling back to npm..."
    fi
else
    warn "Skipping native installer (ARM or Termux/proot — using npm)"
fi

# ── 3. Ensure Node.js 18+ is available ───────────────────────────────────────

node_version_ok() {
    command -v node > /dev/null 2>&1 || return 1
    node -e "process.exit(parseInt(process.versions.node) < 18 ? 1 : 0)" 2>/dev/null
}

install_node_nvm() {
    info "Installing Node.js 20 via nvm..."
    export NVM_DIR="$HOME/.nvm"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm use 20
    nvm alias default 20
}

install_node_nodesource() {
    info "Installing Node.js 20 via NodeSource..."
    run_privileged apt-get update -qq
    run_privileged apt-get install -y ca-certificates curl gnupg
    curl -fsSL https://deb.nodesource.com/setup_20.x | run_privileged bash
    run_privileged apt-get install -y nodejs
}

install_node() {
    # Native Termux (pkg available, no libcrypto issues)
    if $IS_TERMUX && $HAS_PKG; then
        info "Installing Node.js via pkg..."
        pkg install -y nodejs-lts
        return
    fi

    # apt-based (Debian/Ubuntu, proot)
    if command -v apt-get > /dev/null 2>&1; then
        if install_node_nodesource; then
            return
        fi
        warn "NodeSource failed, falling back to nvm..."
        install_node_nvm
        return
    fi

    # dnf (Fedora/RHEL)
    if command -v dnf > /dev/null 2>&1; then
        info "Installing Node.js via dnf..."
        run_privileged dnf install -y nodejs npm
        return
    fi

    # yum (CentOS/older RHEL)
    if command -v yum > /dev/null 2>&1; then
        info "Installing Node.js via yum..."
        run_privileged yum install -y nodejs npm
        return
    fi

    # pacman (Arch)
    if command -v pacman > /dev/null 2>&1; then
        info "Installing Node.js via pacman..."
        run_privileged pacman -Sy --noconfirm nodejs npm
        return
    fi

    # apk (Alpine)
    if command -v apk > /dev/null 2>&1; then
        info "Installing Node.js via apk..."
        run_privileged apk add nodejs npm
        return
    fi

    # brew (macOS)
    if command -v brew > /dev/null 2>&1; then
        info "Installing Node.js via brew..."
        brew install node
        return
    fi

    # Last resort: nvm
    install_node_nvm
}

if node_version_ok; then
    success "Node.js $(node --version) OK"
else
    if command -v node > /dev/null 2>&1; then
        NODE_RAW=$(node --version 2>/dev/null || echo "unknown")
        warn "Node.js $NODE_RAW is unusable (too old or missing libs), upgrading..."
    else
        warn "Node.js not found"
    fi
    install_node
fi

# Source nvm if node still not in PATH
if ! node_version_ok; then
    [[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh"
fi

node_version_ok || error "Node.js 18+ could not be installed. Please install it manually and re-run."
success "Node.js $(node --version) ready"

# ── 4. Configure user-level npm prefix (avoids EACCES) ───────────────────────

NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "")

if [[ "$NPM_PREFIX" == "/usr"* ]] || [[ "$NPM_PREFIX" == "/usr/local"* ]]; then
    warn "npm prefix is system-wide ($NPM_PREFIX), switching to ~/.npm-global..."
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    NPM_BIN="$HOME/.npm-global/bin"
else
    NPM_BIN="$(npm config get prefix)/bin"
fi

# ── 5. Add npm bin to PATH ────────────────────────────────────────────────────

export PATH="$NPM_BIN:$PATH"

if [[ -n "${ZSH_VERSION:-}" ]]; then
    RCFILE="$HOME/.zshrc"
elif [[ -n "${BASH_VERSION:-}" ]]; then
    RCFILE="$HOME/.bashrc"
else
    RCFILE="$HOME/.profile"
fi

PATH_LINE="export PATH=\"$NPM_BIN:\$PATH\""
if ! grep -qF "$NPM_BIN" "$RCFILE" 2>/dev/null; then
    echo "" >> "$RCFILE"
    echo "# Added by Claude Code installer" >> "$RCFILE"
    echo "$PATH_LINE" >> "$RCFILE"
    info "Added PATH entry to $RCFILE"
fi

# ── 6. Fix TMPDIR for Android environments ────────────────────────────────────

if $IS_TERMUX || $IS_PROOT; then
    if [[ -n "${PREFIX:-}" ]]; then
        ANDROID_TMPDIR="$PREFIX/tmp"
    elif [[ -d "/data/data/com.termux/files/usr/tmp" ]]; then
        ANDROID_TMPDIR="/data/data/com.termux/files/usr/tmp"
    else
        ANDROID_TMPDIR="$HOME/tmp"
    fi

    mkdir -p "$ANDROID_TMPDIR"
    export TMPDIR="$ANDROID_TMPDIR"

    if ! grep -q "TMPDIR" "$RCFILE" 2>/dev/null; then
        echo "export TMPDIR=\"$ANDROID_TMPDIR\"" >> "$RCFILE"
        info "Set TMPDIR=$ANDROID_TMPDIR for Android compatibility"
    fi
fi

# ── 7. Install Claude Code ────────────────────────────────────────────────────

info "Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# ── 8. Verify ─────────────────────────────────────────────────────────────────

if command -v claude > /dev/null 2>&1; then
    success "Claude Code installed!"
elif [[ -x "$NPM_BIN/claude" ]]; then
    success "Claude Code installed at $NPM_BIN/claude"
    warn "Open a new terminal or run: source $RCFILE"
else
    error "Installation may have failed. Check: npm list -g @anthropic-ai/claude-code"
fi

echo ""
echo -e "${GREEN}${BOLD}All done! Run: claude${NC}"
echo ""
