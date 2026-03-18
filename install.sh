#!/bin/sh
# Claude Code installer
# Works on ARM Linux, Android (Termux/proot/chroot), and standard x86 Linux
# POSIX sh compatible — works under bash, dash, ash, busybox sh
# Usage: curl -fsSL https://raw.githubusercontent.com/avnigashi/claude-code-android-terminal/main/install.sh | sh

set -e

info()    { printf '[*] %s\n' "$1"; }
success() { printf '[+] %s\n' "$1"; }
warn()    { printf '[!] %s\n' "$1"; }
error()   { printf '[X] %s\n' "$1" >&2; exit 1; }

printf '\n================================\n    Claude Code Installer\n================================\n\n'

# ── 1. Detect environment ────────────────────────────────────────────────────

ARCH=$(uname -m)
IS_TERMUX=0
IS_ROOT=0

if [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ]; then
    IS_TERMUX=1
fi
if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=1
fi

info "Detected arch: $ARCH"
if [ "$IS_TERMUX" = "1" ]; then
    info "Android/Termux environment detected"
fi

# ── 2. Helpers ───────────────────────────────────────────────────────────────

apt_get() {
    if [ "$IS_ROOT" = "1" ]; then
        apt-get "$@"
    else
        sudo apt-get "$@"
    fi
}

run_as_root() {
    if [ "$IS_ROOT" = "1" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Check node exists AND actually executes (catches libcrypto-style failures)
node_runs() {
    command -v node > /dev/null 2>&1 && node --version > /dev/null 2>&1
}

node_version_ok() {
    node_runs || return 1
    _ver=$(node -e "process.exit(parseInt(process.versions.node) < 18 ? 1 : 0)" 2>/dev/null && echo ok || echo old)
    [ "$_ver" = "ok" ]
}

# ── 3. Try native installer (x86_64, non-Android only) ───────────────────────

if [ "$ARCH" = "x86_64" ] && [ "$IS_TERMUX" = "0" ]; then
    info "Attempting official native installer..."
    if curl -fsSL https://claude.ai/install.sh | sh 2>/dev/null; then
        success "Native installer succeeded!"
        printf '\nRun: claude\n\n'
        exit 0
    else
        warn "Native installer failed, falling back to npm..."
    fi
else
    warn "Skipping native installer (ARM or Android — using npm instead)"
fi

# ── 4. Install Node.js ───────────────────────────────────────────────────────

install_node_via_nvm() {
    info "Installing Node.js via nvm (self-contained, no system lib deps)..."
    NVM_DIR="$HOME/.nvm"
    export NVM_DIR
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | sh
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
        nvm install --lts
        nvm use --lts
    else
        error "nvm install failed — please install Node.js 18+ manually and re-run."
    fi
}

install_node_via_nodesource() {
    info "Installing Node.js 20 via NodeSource..."
    apt_get update -qq
    apt_get install -y ca-certificates curl gnupg
    curl -fsSL https://deb.nodesource.com/setup_20.x | run_as_root sh
    apt_get install -y nodejs
}

install_node() {
    # --- Termux native pkg (only if pkg is Termux's real pkg, not apt's) ---
    if [ "$IS_TERMUX" = "1" ] && command -v pkg > /dev/null 2>&1 && [ -n "${PREFIX:-}" ]; then
        info "Trying pkg (native Termux)..."
        pkg install -y openssl-tool nodejs npm 2>/dev/null || pkg install -y nodejs npm 2>/dev/null || true
        if node_runs; then
            return
        fi
        warn "pkg Node.js failed to run (libcrypto missing in proot?), trying nvm..."
        install_node_via_nvm
        return
    fi

    # --- apt (Debian/Ubuntu/proot) ---
    if command -v apt-get > /dev/null 2>&1; then
        # Try NodeSource first for a modern Node 20
        if install_node_via_nodesource 2>/dev/null && node_runs; then
            return
        fi
        warn "NodeSource failed or node won't run, trying nvm..."
        install_node_via_nvm
        return
    fi

    # --- dnf (Fedora/RHEL) ---
    if command -v dnf > /dev/null 2>&1; then
        info "Installing Node.js via dnf..."
        run_as_root dnf install -y nodejs npm
        node_runs && return
        warn "dnf Node.js won't run, trying nvm..."
        install_node_via_nvm
        return
    fi

    # --- yum (CentOS/older RHEL) ---
    if command -v yum > /dev/null 2>&1; then
        info "Installing Node.js via yum..."
        run_as_root yum install -y nodejs npm
        node_runs && return
        install_node_via_nvm
        return
    fi

    # --- pacman (Arch) ---
    if command -v pacman > /dev/null 2>&1; then
        info "Installing Node.js via pacman..."
        run_as_root pacman -Sy --noconfirm nodejs npm
        node_runs && return
        install_node_via_nvm
        return
    fi

    # --- apk (Alpine) ---
    if command -v apk > /dev/null 2>&1; then
        info "Installing Node.js via apk..."
        run_as_root apk add nodejs npm
        node_runs && return
        install_node_via_nvm
        return
    fi

    # --- last resort ---
    install_node_via_nvm
}

if node_version_ok; then
    success "Node.js $(node --version) OK"
else
    if command -v node > /dev/null 2>&1 && ! node_runs; then
        warn "Node.js is installed but won't execute (library missing?) — using nvm instead"
        install_node_via_nvm
    elif command -v node > /dev/null 2>&1; then
        warn "Node.js $(node --version) is too old (need 18+), upgrading..."
        install_node
    else
        warn "Node.js not found, installing..."
        install_node
    fi
fi

# Re-source nvm if node still not in PATH
if ! node_version_ok; then
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        . "$HOME/.nvm/nvm.sh"
    fi
fi

if ! node_version_ok; then
    error "Node.js 18+ could not be installed. Please install it manually and re-run."
fi

success "Node.js $(node --version) ready"

# ── 5. Configure user-level npm prefix (avoids EACCES) ──────────────────────

NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "")

case "$NPM_PREFIX" in
    /usr*|/usr/local*)
        warn "npm prefix is system-wide ($NPM_PREFIX), switching to ~/.npm-global..."
        mkdir -p "$HOME/.npm-global"
        npm config set prefix "$HOME/.npm-global"
        NPM_BIN="$HOME/.npm-global/bin"
        ;;
    *)
        NPM_BIN="$(npm config get prefix)/bin"
        ;;
esac

# ── 6. Add npm bin to PATH ────────────────────────────────────────────────────

export PATH="$NPM_BIN:$PATH"

if [ -n "${BASH_VERSION:-}" ]; then
    RC_FILE="$HOME/.bashrc"
elif [ -n "${ZSH_VERSION:-}" ]; then
    RC_FILE="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    RC_FILE="$HOME/.bashrc"
else
    RC_FILE="$HOME/.profile"
fi

if ! grep -qF "$NPM_BIN" "$RC_FILE" 2>/dev/null; then
    printf '\n# Added by Claude Code installer\nexport PATH="%s:$PATH"\n' "$NPM_BIN" >> "$RC_FILE"
    info "Added PATH entry to $RC_FILE"
fi

# ── 7. Fix TMPDIR for Android/Termux ─────────────────────────────────────────

if [ "$IS_TERMUX" = "1" ]; then
    TERMUX_TMPDIR="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
    mkdir -p "$TERMUX_TMPDIR"
    export TMPDIR="$TERMUX_TMPDIR"
    if ! grep -q "TMPDIR" "$RC_FILE" 2>/dev/null; then
        printf '\n# Fix for Claude Code on Android/Termux\nexport TMPDIR="%s"\n' "$TERMUX_TMPDIR" >> "$RC_FILE"
        info "Set TMPDIR=$TERMUX_TMPDIR for Android compatibility"
    fi
fi

# ── 8. Install Claude Code ───────────────────────────────────────────────────

info "Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# ── 9. Verify ────────────────────────────────────────────────────────────────

if command -v claude > /dev/null 2>&1; then
    success "Claude Code installed successfully!"
elif [ -x "$NPM_BIN/claude" ]; then
    success "Claude Code installed at $NPM_BIN/claude"
    warn "Open a new shell or run: . $RC_FILE"
else
    error "Installation may have failed. Check npm error logs above."
fi

printf '\nAll done! Run: claude\n\n'
