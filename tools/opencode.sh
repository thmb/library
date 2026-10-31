#!/usr/bin/env bash
# opencode.sh - OpenCode binary (non-apt) and its configuration
#
# Usage: ./opencode.sh
#
# Idempotent and safe to re-run: installs anything that is missing and
# rewrites the configuration in place. sudo is requested only when an apt
# package actually needs installing; nothing outside $HOME is touched.
# Target: Debian Trixie or later.
set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# Install only the apt packages that are missing (one sudo round when needed).
apt_install() {
  local missing=() pkg
  for pkg in "$@"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  [ ${#missing[@]} -eq 0 ] && return 0
  log "apt: installing ${missing[*]}"
  sudo apt-get update
  sudo apt-get install -y "${missing[@]}"
}

# Replace the file at $path with content from a quoted heredoc. Safe for the
# backslash- and dollar-heavy content below. Any symlink on the path -- the
# file itself or an ancestor directory left by the old stow layout -- is
# replaced with a real file/directory, so nothing is written into a checkout.
write_file() {
  local path="$1" t; shift
  # The caller tilde-expands "~" already, so $1 is absolute.
  [ -L "$path" ] && rm -f "$path"
  t="$(dirname "$path")"
  while [ "$t" != "$HOME" ] && [ "$t" != "/" ]; do
    [ -L "$t" ] && rm -f "$t"
    t="$(dirname "$t")"
  done
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}


# Pin a release (e.g. 2.2.5) or leave this at "latest" to track upstream.
VERSION=latest

# --- install/update (non-apt): official installer --------------------------
# NOTE: opencode.ai/install is the OpenCode 1 installer; the /v2/ endpoint is
# the OpenCode 2 one (this config is V2). --no-modify-path keeps the installer
# from touching ~/.bashrc, which is owned by bash.sh and already puts
# ~/.opencode/bin on PATH.
install_args=(--no-modify-path)
[ "$VERSION" != "latest" ] && install_args+=(--version "$VERSION")
log "installing/updating opencode (${VERSION})"
curl -fsSL https://opencode.ai/v2/install | bash -s -- "${install_args[@]}"

# --- configuration (written in place each run) -----------------------------
write_file ~/.config/opencode/cli.json <<'EOF'
{
  "$schema": "https://opencode.ai/v2/cli.json",
  "session": {
    "sidebar": "hide"
  },
  "prompt": {
    "paste": "full"
  },
  "attention": {
    "notifications": true,
    "sound": true,
    "volume": 0.4
  }
}
EOF
write_file ~/.config/opencode/opencode.jsonc <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "openrouter/deepseek/deepseek-pro-latest",
  "small_model": "openrouter/deepseek/deepseek-chat",
  "permission": {
    "bash": {
      "*": "allow",
      "rm *": "ask",
      "git commit *": "ask",
      "git push *": "ask",
      "terraform apply *": "ask",
      "terraform destroy *": "ask",
      "alembic upgrade *": "ask",
      "alembic downgrade *": "ask"
    }
  },
  "plugin": ["opencode-terminal-bell-notifier@latest"]
}
EOF

# notify-send backs desktop notifications (optional; kept last so a missing
# sudo password still leaves the binary installed and the config written).
apt_install libnotify-bin
