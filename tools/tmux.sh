#!/usr/bin/env bash
# tmux.sh - tmux + session persistence and its configuration
#
# Usage: ./tmux.sh
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

# Clone the first time, fast-forward on re-runs (keeps non-apt tools updated).
clone_or_update() {
  local dir="$1" url="$2"
  if [ -d "$dir/.git" ]; then
    log "updating $(basename "$dir")"
    git -C "$dir" pull --ff-only
  else
    log "cloning $(basename "$dir")"
    mkdir -p "$(dirname "$dir")"
    git clone --depth 1 "$url" "$dir"
  fi
}

apt_install tmux

# --- plugins (non-apt): TPM + tmux-resurrect ------------------------------
clone_or_update "$HOME/.tmux/plugins/tpm" https://github.com/tmux-plugins/tpm
clone_or_update "$HOME/.tmux/plugins/tmux-resurrect" https://github.com/tmux-plugins/tmux-resurrect

# --- configuration (written in place each run) -----------------------------
write_file ~/.tmux.conf <<'EOF'
# ~/.tmux.conf - deliberately small.

# --- prefix ----------------------------------------------------------------
# C-Space costs only readline's set-mark. The default C-b would steal
# backward-char in bash and shadow <C-b> page-up in nvim.
unbind C-b
set -g prefix C-Space
bind C-Space send-prefix          # prefix twice to send a literal C-Space

# --- terminal / colours ----------------------------------------------------
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc,xterm-256color:Tc"
set -g escape-time 10             # don't mistake <Esc> for a meta sequence
set -g focus-events on            # required for nvim's autoread/autosave
set -g history-limit 50000
set -g display-time 2000

# --- behaviour -------------------------------------------------------------
set -g mouse on
set -g base-index 1               # windows start at 1, not 0
setw -g pane-base-index 1
set -g renumber-windows on
setw -g mode-keys vi
setw -g automatic-rename on

# New panes/windows inherit the current directory.
bind '"' split-window -h -c "#{pane_current_path}"
bind '%' split-window -v -c "#{pane_current_path}"
bind c   new-window      -c "#{pane_current_path}"

# --- pane navigation: M-hjkl ----------------------------------------------
# Alt rather than Ctrl: Alt+h/j/k are unbound in readline and Alt+l is only
# downcase-word, whereas C-h is backspace and C-l is clear-screen. These
# always move tmux panes; inside nvim, <C-w>hjkl moves splits.
bind-key -n 'M-h' select-pane -L
bind-key -n 'M-j' select-pane -D
bind-key -n 'M-k' select-pane -U
bind-key -n 'M-l' select-pane -R
bind-key -T copy-mode-vi 'M-h' select-pane -L
bind-key -T copy-mode-vi 'M-j' select-pane -D
bind-key -T copy-mode-vi 'M-k' select-pane -U
bind-key -T copy-mode-vi 'M-l' select-pane -R

# Resize with prefix + HJKL (repeatable).
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# --- copy mode / clipboard --------------------------------------------------
# No clipboard tools involved: every copy lands in a tmux buffer and, via
# OSC 52, on the desktop clipboard of the terminal emulator (Alacritty
# accepts OSC 52 copies out of the box, terminal.osc52 = "OnlyCopy").
# Double/triple click and Enter keep the default copy-selection* commands
# and follow the same path.
set -g set-clipboard on           # yanks set the terminal clipboard
set -g allow-passthrough on       # let panes bypass tmux via ESC Ptmux;...:
                                  # OpenCode's TUI wraps its OSC 52 clipboard
                                  # writes that way and tmux silently drops
                                  # them otherwise (off by default since 3.3)
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-selection-and-cancel               # yank -> clipboard
bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-selection-and-cancel # select -> already copied
bind -T copy-mode-vi Escape send -X cancel

# prefix+v: paste the last tmux buffer with bracketed paste (so vim and
# shells don't mangle it). The desktop clipboard is pasted with the
# terminal's own paste key (Ctrl+Shift+V in Alacritty), which never goes
# through tmux.
bind v paste-buffer -p

# --- session list / new session ---------------------------------------------
# Native tmux session tree (the default `s` binding). Enter switches to the
# selected session; x kills the selected session/window/pane.
bind s choose-tree -Zs

# Prefix+S: create a new session, prompting for its name.
bind S command-prompt -p "session name:" "new-session -s '%%'"

# Reload config.
bind r source-file ~/.tmux.conf \; display-message "tmux.conf reloaded"

# --- status line: minimal --------------------------------------------------
set -g status-position bottom
set -g status-style 'bg=default fg=colour245'
set -g status-left  ' #[fg=colour39,bold]#S#[default] '
set -g status-right '#[fg=colour245]%Y-%m-%d %H:%M '
set -g status-left-length 30
set -g status-right-length 30
set -g window-status-format '#I:#W'
set -g window-status-current-format '#[fg=colour39,bold]#I:#W#[default]'
set -g window-status-separator '  '
set -g pane-border-style 'fg=colour238'
set -g pane-active-border-style 'fg=colour39'
set -g message-style 'bg=colour39 fg=black'

# --- status line: attention flag --------------------------------------------
# opencode-terminal-bell-notifier emits BEL when opencode needs attention
# (done / question / permission). tmux turns that into a highlighted window
# name in the status bar; bell-action none stops the terminal from also
# ringing (the sound comes from opencode itself). The current window is never
# flagged -- you are already looking at it.
setw -g monitor-bell on
set -g bell-action none
setw -g window-status-bell-style 'fg=colour214,bold'

# --- session persistence (tmux-resurrect) ------------------------------------
# Save with prefix+C-s, restore with prefix+C-r. TPM installs the plugins
# (tmux.sh installs them); a systemd user unit restores at
# login and saves at logout -- see tools/tmux/.config/systemd/user/.
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @resurrect-capture-pane-contents 'on'   # keep pane scrollback (opencode transcripts)
run '~/.tmux/plugins/tpm/tpm'
EOF

write_file ~/.config/systemd/user/tmux-persist.service <<'EOF'
[Unit]
Description=Restore tmux sessions at login and save them at logout
Documentation=man:tmux(1) https://github.com/tmux-plugins/tmux-resurrect

[Service]
Type=oneshot
RemainAfterExit=yes

# The tmux server forked below stays in this unit's cgroup. systemd runs
# ExecStop *before* killing leftover processes, so logout = save then kill.

# A bare `tmux start-server` exits immediately with no session, so create one
# detached session to keep the server alive, then run resurrect's restore
# inside it. run-shell exports $TMUX, so restore.sh talks to the right socket.
# restore.sh is idempotent: with its single empty pane it does the documented
# "restore from scratch"; anything already running is left untouched.
ExecStart=/usr/bin/tmux new-session -d
ExecStart=/usr/bin/tmux run-shell %h/.tmux/plugins/tmux-resurrect/scripts/restore.sh
# A missing save file (first ever boot) makes restore.sh a harmless no-op, but
# keep the unit active regardless so ExecStop keeps running at later logouts.
ExecStart=/usr/bin/true

# Snapshot everything at logout/shutdown, but only while the server is still
# alive -- a dead server must not overwrite the last good snapshot with empty.
ExecStop=/bin/sh -c 'tmux has-session 2>/dev/null && tmux run-shell %h/.tmux/plugins/tmux-resurrect/scripts/save.sh quiet'

[Install]
WantedBy=default.target
EOF

# Enable the login-restore/logout-save unit (no-op harmlessly without a user
# manager, e.g. first login over plain SSH).
if systemctl --user daemon-reload 2>/dev/null; then
  systemctl --user enable tmux-persist.service 2>/dev/null || true
  log "tmux-persist.service enabled (applies at next login)"
else
  warn "systemd user manager unavailable; unit installed but not enabled"
fi

# Reload a running server's config if one exists (bindings take effect now).
tmux source-file "$HOME/.tmux.conf" 2>/dev/null || true
