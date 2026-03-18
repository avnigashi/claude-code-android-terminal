# Claude Code — Android & ARM Linux Installer

> One-line installer for [Claude Code](https://claude.ai/code) that works on Android (Termux/proot), ARM Linux servers, and standard x86 Linux — fixing all the pitfalls the official installer misses.

```bash
curl -fsSL https://raw.githubusercontent.com/avnigashi/claude-code-android-terminal/main/install.sh | bash
```

---

## Why this exists

The official `curl -fsSL https://claude.ai/install.sh | bash` fails on ARM and Android environments with errors like:

```
Illegal instruction
EACCES: permission denied, mkdir '/usr/local/lib/node_modules'
```

This installer handles all of that automatically.

---

## What it does

| Step | What happens |
|------|-------------|
| 🔍 Detect environment | Identifies arch (ARM64/x86), Termux, and root status |
| ⚡ Native installer | Tries the official installer first on x86_64 — skips it on ARM/Termux |
| 📦 Node.js | Installs Node 18+ if missing (`pkg`, `apt`, or `nvm` as fallback) |
| 🔐 Fix EACCES | Switches npm prefix to `~/.npm-global` — no `sudo` needed |
| 🛣️ Fix PATH | Adds npm bin to your current session and `.bashrc`/`.zshrc` |
| 🤖 Fix Termux `/tmp` | Sets `TMPDIR` to the correct Android path so Claude doesn't crash |
| ✅ Install & verify | Installs `@anthropic-ai/claude-code` via npm and confirms it works |

---

## Compatibility

| Platform | Status |
|----------|--------|
| Android — Termux | ✅ |
| Android — proot/chroot (Debian/Ubuntu) | ✅ |
| ARM64 Linux (servers, SBCs) | ✅ |
| x86_64 Linux | ✅ |
| macOS | ⚠️ Use the [official installer](https://claude.ai/code) |
| Windows | ⚠️ Use the [official installer](https://claude.ai/code) |

---

## After installing

Run `claude` in any project directory and authenticate:

```bash
claude
```

You'll be prompted to log in with your Claude.ai account (Pro, Max, Teams, or Enterprise required).

---

## Requirements

- A [Claude Pro, Max, Teams, or Enterprise](https://claude.ai) account — the free plan does not include Claude Code
- Internet connection
- `curl` and `bash`

---

## Troubleshooting

**`command not found: claude` after install**
```bash
source ~/.bashrc
```

**Still failing on Termux**
```bash
export TMPDIR=$PREFIX/tmp
pkg install nodejs
npm install -g @anthropic-ai/claude-code
```

**Node.js version too old**
```bash
# Termux
pkg install nodejs-lts

# apt
sudo apt-get install -y nodejs npm
```

---

## Related issues

- [Hardcoded `/tmp` paths break on Termux](https://github.com/anthropics/claude-code/issues/15637)
- [EACCES on `/tmp/claude` on Android](https://github.com/anthropics/claude-code/issues/17366)
- [Startup hang in Termux with Node v24](https://github.com/anthropics/claude-code/issues/23665)

---

## License

MIT
