#!/usr/bin/env bash
#
# Reproduce the terminal/editor toolchain on a Debian Trixie machine.
#
#   ./setup.sh            # everything
#   ./setup.sh --no-sudo  # skip the apt steps
#   ./setup.sh --stow     # only re-link the dotfiles
#
# Idempotent: safe to re-run. Nothing outside $HOME is modified except the
# apt operations.

set -euo pipefail

NVIM_VERSION=0.12.5
FONT_NAME='JetBrainsMono'
# Mono variant: every glyph (including Nerd Font icons) is forced to a single
# cell, which terminals need. The plain "Nerd Font" variant lets icons take
# their natural (often double) width, which misaligns and looks too spaced.
TERMINAL_FONT='JetBrainsMono Nerd Font Mono 11'
STOW_PACKAGES=(bash neovim git tmux)

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DO_SUDO=1
ONLY_STOW=0

for arg in "$@"; do
  case "$arg" in
    --no-sudo) DO_SUDO=0 ;;
    --stow)    ONLY_STOW=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# --- apt ---------------------------------------------------------------------
install_packages() {
  log "Installing apt packages from packages.txt"
  mapfile -t pkgs < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]*$//' "$TOOL_DIR/packages.txt")

  # xclip is only pulled in as a dependency of the neovim package; mark it
  # manual first so removing neovim below doesn't make it auto-removable.
  sudo apt-mark manual xclip >/dev/null 2>&1 || true

  sudo apt update
  sudo apt install -y "${pkgs[@]}"
}

remove_apt_neovim() {
  if dpkg -s neovim >/dev/null 2>&1; then
    log "Removing Debian's Neovim (replaced by the $NVIM_VERSION tarball)"
    sudo apt remove -y neovim neovim-runtime
    warn "Do not run 'apt autoremove' right now; it would sweep still-wanted libs."
  fi
}

# --- ~/.local/bin ------------------------------------------------------------
setup_local_bin() {
  log "Setting up ~/.local/bin shims"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/opt"
  # Debian renames these two to avoid filename clashes with other packages.
  ln -sfn /usr/bin/batcat "$HOME/.local/bin/bat"
  ln -sfn /usr/bin/fdfind "$HOME/.local/bin/fd"
}

# --- neovim ------------------------------------------------------------------
install_neovim() {
  local target="$HOME/.local/opt/nvim-$NVIM_VERSION"
  if [ -x "$target/bin/nvim" ]; then
    log "Neovim $NVIM_VERSION already present"
  else
    log "Installing Neovim $NVIM_VERSION to $target"
    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/nvim.tar.gz" \
      "https://github.com/neovim/neovim/releases/download/v$NVIM_VERSION/nvim-linux-x86_64.tar.gz"
    tar xzf "$tmp/nvim.tar.gz" -C "$tmp"
    rm -rf "$target"
    mv "$tmp/nvim-linux-x86_64" "$target"
    rm -rf "$tmp"
  fi
  ln -sfn "$target/bin/nvim" "$HOME/.local/bin/nvim"
}

# --- nerd font ---------------------------------------------------------------
install_font() {
  local dir="$HOME/.local/share/fonts/${FONT_NAME}NerdFont"
  if [ -f "$dir/${FONT_NAME}NerdFontMono-Regular.ttf" ]; then
    log "$FONT_NAME Nerd Font (Mono) already installed"
    return
  fi
  log "Installing $FONT_NAME Nerd Font Mono (regular/bold/italic/bolditalic only)"
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/font.zip" \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT_NAME}.zip"
  mkdir -p "$dir"
  unzip -o -j "$tmp/font.zip" \
    "${FONT_NAME}NerdFontMono-Regular.ttf" \
    "${FONT_NAME}NerdFontMono-Bold.ttf" \
    "${FONT_NAME}NerdFontMono-Italic.ttf" \
    "${FONT_NAME}NerdFontMono-BoldItalic.ttf" -d "$dir" >/dev/null
  rm -rf "$tmp"
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null
}

configure_terminal_font() {
  command -v gsettings >/dev/null 2>&1 || return 0
  local profile path
  profile="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d \"\'\")" || return 0
  [ -n "$profile" ] || return 0
  path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$profile/"
  log "Setting gnome-terminal font to $TERMINAL_FONT"
  gsettings set "$path" use-system-font false
  gsettings set "$path" font "$TERMINAL_FONT"
}

# --- git config shim ---------------------------------------------------------
# ~/.config/git/config stays a REAL file that includes the tracked one, because
# `git config --global` rewrites its target via lockfile+rename and would
# replace a stow symlink with a regular file.
setup_git_include() {
  local cfg="$HOME/.config/git/config"
  mkdir -p "$HOME/.config/git"
  if [ -L "$cfg" ]; then
    warn "$cfg is a symlink; replacing it with a real file containing an include"
    rm -f "$cfg"
  fi
  if ! [ -f "$cfg" ]; then
    log "Creating $cfg"
    cat > "$cfg" <<'EOF'
# Real file on purpose: `git config --global` rewrites this path via
# lockfile+rename, which would destroy a stow symlink. The tracked
# configuration lives in tracked.conf (stowed from the library repo).
# Machine-local overrides can go below the include.
[include]
	path = tracked.conf
EOF
  elif ! grep -q 'path *= *tracked.conf' "$cfg"; then
    log "Adding include of tracked.conf to $cfg"
    printf '\n[include]\n\tpath = tracked.conf\n' >> "$cfg"
  else
    log "$cfg already includes tracked.conf"
  fi
}

# --- stow --------------------------------------------------------------------
stow_packages() {
  command -v stow >/dev/null 2>&1 || { warn "stow not installed; skipping"; return; }
  log "Stowing: ${STOW_PACKAGES[*]}"

  # A pre-existing real ~/.bashrc would block the bash package.
  if [ -f "$HOME/.bashrc" ] && [ ! -L "$HOME/.bashrc" ]; then
    local bk
    bk="$HOME/.bashrc.pre-stow-$(date +%F-%H%M%S)"
    warn "Moving existing ~/.bashrc aside to $bk"
    mv "$HOME/.bashrc" "$bk"
  fi

  stow --dir "$TOOL_DIR" --target "$HOME" --restow "${STOW_PACKAGES[@]}"
}

# --- run ---------------------------------------------------------------------
if [ "$ONLY_STOW" -eq 1 ]; then
  stow_packages
  log "Done (stow only)."
  exit 0
fi

if [ "$DO_SUDO" -eq 1 ]; then
  install_packages
  remove_apt_neovim
else
  warn "Skipping apt steps (--no-sudo)"
fi

setup_local_bin
install_neovim
install_font
configure_terminal_font
setup_git_include
stow_packages

log "Done. Next steps:"
cat <<'EOF'

  1. exec bash                       # pick up the new shell config
  2. nvim                            # lazy.nvim bootstraps the plugins
  3. :MasonToolsInstall              # install language servers and formatters
  4. :checkhealth                    # confirm everything is wired up

  Then commit lazy-lock.json so the plugin set is pinned.
EOF
