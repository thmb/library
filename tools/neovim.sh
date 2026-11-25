#!/usr/bin/env bash
# neovim.sh - Neovim (tarball, not apt) and editor configuration
#
# Usage: ./neovim.sh
#
# Idempotent and safe to re-run: installs anything that is missing and
# rewrites the configuration in place. sudo is requested only when an apt
# package actually needs installing; nothing outside $HOME is touched.
# Target: Debian Trixie or later.
set -euo pipefail

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
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

# Replace the file at $path with content from a quoted heredoc. Any symlink on
# the path (left by the old stow layout) becomes a real file, so nothing is
# ever written into a checkout.
write_file() {
  local path="$1" t
  shift
  # The caller tilde-expands "~" already, so $1 is absolute.
  [ -L "$path" ] && rm -f "$path"
  t="$(dirname "$path")"
  while [ "$t" != "$HOME" ] && [ "$t" != "/" ]; do
    [ -L "$t" ] && rm -f "$t"
    t="$(dirname "$t")"
  done
  mkdir -p "$(dirname "$path")"
  cat >"$path"
}

# Pin the release; bump and re-run to upgrade. Not from apt: Debian ships
# 0.10.x, this config needs 0.12+ (vim.lsp.config, 'autocomplete', vim.pack).
VERSION=0.12.6

# wl-clipboard is only for Neovim's "+ paste reads; yanks go out over OSC 52.
apt_install make gcc clangd clang-format shellcheck yamllint python3-venv \
  fzf fd-find ripgrep wl-clipboard

# Replace Debian's older Neovim; mark xclip manual first so a later
# `apt autoremove` doesn't sweep it.
if dpkg -s neovim >/dev/null 2>&1; then
  log "removing apt neovim (replaced by the pinned tarball)"
  sudo apt-mark manual xclip >/dev/null 2>&1 || true
  sudo apt-get remove -y neovim neovim-runtime
  warn "avoid 'apt autoremove' right now; it would sweep still-wanted libs"
fi

# --- install (non-apt): Neovim tarball -------------------------------------
target="$HOME/.local/opt/nvim-$VERSION"
if [ -x "$target/bin/nvim" ]; then
  log "Neovim $VERSION already installed"
else
  log "installing Neovim $VERSION (GitHub release tarball)"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/nvim.tar.gz" \
    "https://github.com/neovim/neovim/releases/download/v$VERSION/nvim-linux-x86_64.tar.gz"
  tar xzf "$tmp/nvim.tar.gz" -C "$tmp"
  rm -rf "$target"
  mv "$tmp/nvim-linux-x86_64" "$target"
  rm -rf "$tmp"
fi
mkdir -p "$HOME/.local/bin"
ln -sfn "$target/bin/nvim" "$HOME/.local/bin/nvim"

# --- install (non-apt): tree-sitter CLI ------------------------------------
# nvim-treesitter main needs tree-sitter-cli >= 0.26.1 (Debian ships 0.22.6);
# pinned standalone binary, installed like the Neovim tarball above.
TS_VERSION=0.27.2
ts_target="$HOME/.local/opt/tree-sitter-$TS_VERSION"
if [ -x "$ts_target/tree-sitter" ]; then
  log "tree-sitter CLI $TS_VERSION already installed"
else
  log "installing tree-sitter CLI $TS_VERSION (GitHub release binary)"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/tree-sitter.gz" \
    "https://github.com/tree-sitter/tree-sitter/releases/download/v$TS_VERSION/tree-sitter-linux-x64.gz"
  mkdir -p "$ts_target"
  gunzip -c "$tmp/tree-sitter.gz" >"$ts_target/tree-sitter"
  chmod +x "$ts_target/tree-sitter"
  rm -rf "$tmp"
fi
ln -sfn "$ts_target/tree-sitter" "$HOME/.local/bin/tree-sitter"

# --- install (non-apt): jsonc grammar (pinned local checkout) --------------
# tree-sitter-jsonc is GitLab-only and its tarball endpoint returns non-gzip
# data, breaking nvim-treesitter's curl-based installer. Keep a pinned local
# checkout; its registration lives in plugins/editor.lua.
JSONC_REV=f7890ba894d885d1b2b721cfae759b07d53c8886
jsonc_dir="$HOME/.local/opt/grammars/tree-sitter-jsonc"
if [ -d "$jsonc_dir/.git" ] && git -C "$jsonc_dir" cat-file -e "$JSONC_REV^{commit}" 2>/dev/null; then
  log "jsonc grammar: pinned revision present"
  git -C "$jsonc_dir" checkout --quiet "$JSONC_REV"
elif [ -d "$jsonc_dir/.git" ]; then
  log "jsonc grammar: fetching pinned revision"
  git -C "$jsonc_dir" fetch --quiet origin
  git -C "$jsonc_dir" checkout --quiet "$JSONC_REV"
else
  log "cloning tree-sitter-jsonc ($JSONC_REV)"
  mkdir -p "$(dirname "$jsonc_dir")"
  git clone --quiet https://gitlab.com/WhyNotHugo/tree-sitter-jsonc.git "$jsonc_dir"
  git -C "$jsonc_dir" checkout --quiet "$JSONC_REV"
fi

# --- configuration (written in place each run) -----------------------------
write_file ~/.config/nvim/init.lua <<'EOF'
-- ~/.config/nvim/init.lua -- managed by tools/neovim.sh. Needs Neovim 0.12+.

if vim.fn.has('nvim-0.12') == 0 then
  vim.notify('This config requires Neovim 0.12+', vim.log.levels.ERROR)
  return
end

require('config.options')
require('config.plugins')  -- vim.pack manifest + lua/plugins/* configuration
require('config.keymaps')
require('config.autocmds')
EOF
write_file ~/.config/nvim/lua/config/options.lua <<'EOF'
-- options.lua

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local o = vim.o

-- UI
o.number = true
o.relativenumber = true -- makes 12j / d5k practical
o.signcolumn = "yes" -- stop the text shifting when signs appear
o.cursorline = true
o.termguicolors = true
o.showmode = false -- the statusline already says it
o.winborder = "rounded" -- 0.12: one global float border, no per-plugin config
o.pumborder = "rounded"
o.pummaxwidth = 60
o.scrolloff = 6
o.sidescrolloff = 8
o.list = true
o.listchars = "tab:> ,trail:.,nbsp:+,extends:>,precedes:<"
o.splitbelow = true
o.splitright = true
o.splitkeep = "screen" -- don't scroll the current window when splitting
o.laststatus = 3 -- one global statusline
o.showtabline = 2 -- the tabline lists buffers, not just tab pages: always show it
o.cmdheight = 1
o.confirm = true -- prompt instead of failing on unsaved changes

-- Wrapping
o.wrap = true
o.linebreak = true -- wrap at word boundaries, not mid-word
o.textwidth = 0

-- Statusline: extend the 0.12 default (it lacks only the git branch) instead
-- of hardcoding a copy of it.
do
	local default_stl = vim.api.nvim_get_option_info2("statusline", {}).default
	local branch = [[%{% get(b:, 'gitsigns_head', '') !=# '' ? ' ' .. b:gitsigns_head .. ' ' : '' %}]]
	local anchor = "%<%f %h%w%m%r "
	if default_stl:sub(1, #anchor) == anchor then
		o.statusline = anchor .. branch .. default_stl:sub(#anchor + 1)
	else
		o.statusline = default_stl .. branch
	end
end

-- Indentation: sane polyglot defaults; editorconfig support is built in.
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.softtabstop = 4
o.smartindent = true
o.shiftround = true

-- Search
o.ignorecase = true
o.smartcase = true -- an uppercase letter makes the search sensitive
o.hlsearch = true
o.incsearch = true
o.inccommand = "split" -- live preview for :s

-- Files / persistence
o.undofile = true -- persistent undo across sessions
o.undolevels = 10000
o.swapfile = false
o.backup = false
o.writebackup = false
o.autoread = true
o.updatetime = 250
o.timeoutlen = 400

-- Completion: native 0.12 autocompletion, no completion plugin.
o.autocomplete = true
o.completeopt = "menu,menuone,popup,noselect,fuzzy,nearest"
o.pumheight = 12
o.wildmode = "longest:full,full"
o.wildoptions = "pum,fuzzy"

-- Diff: 0.12 defaults are already good; add word-level inline and linematch.
-- `vertical` keeps every diff (gitsigns diffthis, :diffsplit, :DiffTool)
-- side-by-side like VSCode; gitsigns derives its split from 'diffopt'.
o.diffopt = "internal,filler,closeoff,vertical,indent-heuristic,inline:word,linematch:60,algorithm:histogram"

-- Project-local config. 0.12 searches parent directories too; files must be
-- explicitly trusted with :trust, so this is safe across /opt/github/*.
o.exrc = true

-- Clipboard: "+ yanks reach the desktop over OSC 52 (works through tmux and
-- over SSH). "+ paste reads the desktop clipboard with wl-paste/xclip,
-- because OSC 52 reads do not round-trip through tmux: the read query never
-- reaches the terminal and the built-in osc52 paste hangs. `clipboard` stays
-- unset on purpose: explicit beats surprising.
local function desktop_paste(sel)
  local cmds = sel == "*" and {
    { "wl-paste", "--primary", "-n" },
    { "xclip", "-selection", "primary", "-o" },
  } or {
    { "wl-paste", "-n" },
    { "xclip", "-selection", "clipboard", "-o" },
  }
  return function()
    for _, cmd in ipairs(cmds) do
      if vim.fn.executable(cmd[1]) == 1 then
        -- Timeout: a dead Wayland socket would otherwise hang the UI.
        local out = vim.system(cmd, { text = true, timeout = 2000 }):wait()
        if out.code == 0 then
          return vim.split((out.stdout:gsub("\n$", "")), "\n", { plain = true })
        end
      end
    end
    return {}
  end
end

vim.g.clipboard = {
  name = "osc52+desktop",
  copy = {
    ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
    ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
  },
  paste = {
    ["+"] = desktop_paste("+"),
    ["*"] = desktop_paste("*"),
  },
}

o.mouse = "a"
o.mousemoveevent = true

-- Fold with treesitter, but start fully open.
o.foldmethod = "expr"
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
o.foldlevel = 99
o.foldtext = ""
o.fillchars = "fold: ,foldopen:v,foldclose:>,foldsep: ,diff:/,eob: "

-- Filetype pinning: Neovim's .tf detection is content-sensitive (a new or
-- comment-only file classifies as `tf` = TinyFugue), so terraformls would not
-- attach until real HCL is typed. Pin both extensions to `terraform` for
-- uniform tooling (native .tfvars is `terraform-vars`, which has no parser).
vim.filetype.add({ extension = { tf = "terraform", tfvars = "terraform" } })

-- Diagnostics: virtual_lines on the current line only; virtual_text off.
vim.diagnostic.config({
	severity_sort = true,
	underline = true,
	update_in_insert = false,
	virtual_text = false,
	virtual_lines = { current_line = true },
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = "E",
			[vim.diagnostic.severity.WARN] = "W",
			[vim.diagnostic.severity.INFO] = "I",
			[vim.diagnostic.severity.HINT] = "H",
		},
	},
	float = { border = "rounded", source = true },
})
EOF
write_file ~/.config/nvim/lua/config/plugins.lua <<'EOF'
-- config/plugins.lua -- vim.pack, Neovim 0.12's built-in plugin manager.
-- Deliberately eager: everything loads at startup. Pins are the commit hashes
-- below. To upgrade: bump a hash, re-run tools/neovim.sh, restart, then
-- :packupdate and confirm. Nvim owns nvim-pack-lock.json; never hand-edit it.

-- Barbar's plugin/ file self-calls setup() at load; disable that (the real
-- setup lives in plugins/ui.lua).
vim.g.barbar_auto_setup = false

-- Run :TSUpdate after nvim-treesitter installs/updates. Registered before the
-- add() below because PackChanged fires during it (:h vim.pack-events).
vim.api.nvim_create_autocmd('PackChanged', {
  group = vim.api.nvim_create_augroup('thmb_pack_build', { clear = true }),
  desc = 'Refresh treesitter parsers after install/update',
  callback = function(ev)
    if ev.data.spec.name == 'nvim-treesitter'
      and (ev.data.kind == 'install' or ev.data.kind == 'update') then
      pcall(vim.cmd.packadd, 'nvim-treesitter') -- make :TSUpdate exist
      pcall(vim.cmd, 'TSUpdate')
    end
  end,
})

-- Install anything missing at its pinned revision; load lua/ + plugin/
-- before the setup() calls below.
vim.pack.add({
  { src = 'https://github.com/folke/tokyonight.nvim', name = 'tokyonight.nvim', version = 'cdc07ac78467a233fd62c493de29a17e0cf2b2b6' },
  { src = 'https://github.com/nvim-mini/mini.nvim', name = 'mini.nvim', version = '4d32e018f7cfcc0ba95357465516be615c542fef' },
  { src = 'https://github.com/ibhagwan/fzf-lua', name = 'fzf-lua', version = 'ded1c96d3d9d74634287d722431c26690968a4bf' },
  { src = 'https://github.com/nvim-treesitter/nvim-treesitter', name = 'nvim-treesitter', version = '60c0f468de3e636fa660a419d537e8033aca4e39' },
  { src = 'https://github.com/nvim-neo-tree/neo-tree.nvim', name = 'neo-tree.nvim', version = '1a14083046d96e88e361d1da00761c40d45012f3' },
  { src = 'https://github.com/MunifTanjim/nui.nvim', name = 'nui.nvim', version = '10fc361835c856ba4233ef5ea135b919bf3dce97' },
  { src = 'https://github.com/nvim-lua/plenary.nvim', name = 'plenary.nvim', version = '74b06c6c75e4eeb3108ec01852001636d85a932b' },
  { src = 'https://github.com/lewis6991/gitsigns.nvim', name = 'gitsigns.nvim', version = '7c33a797a5c0923e346cbedebe37bdea8f7ea160' },
  { src = 'https://github.com/mason-org/mason.nvim', name = 'mason.nvim', version = '2a6940af80375532e5e9e7c1f2fc6319a1b7a69d' },
  { src = 'https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim', name = 'mason-tool-installer.nvim', version = '443f1ef8b5e6bf47045cb2217b6f748a223cf7dc' },
  { src = 'https://github.com/neovim/nvim-lspconfig', name = 'nvim-lspconfig', version = '443d92c6bea761ab54cdde46fb197a2b4d614bdd' },
  { src = 'https://github.com/stevearc/conform.nvim', name = 'conform.nvim', version = '016802de402556da54c36bd7359b441266b01cdd' },
  { src = 'https://github.com/romgrk/barbar.nvim', name = 'barbar.nvim', version = '337ecfadb8bf005050990bf2f624dc4fc828dabd' },
}, { load = true })

-- :Undotree ships as a bundled opt package; load it for the <leader>u map.
vim.cmd.packadd('nvim.undotree')

-- :DiffTool ships as a bundled opt package; load it for side-by-side diffs.
vim.cmd.packadd('nvim.difftool')

-- Disable unused runtime plugins.
vim.g.loaded_gzip = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_tutor = 1
vim.g.loaded_netrwPlugin = 1

-- Order matters: colourscheme first, icons before their consumers, the
-- tabline last (it reads gitsigns state).
for _, m in ipairs({ 'editor', 'git', 'lsp', 'ui' }) do
  require('plugins.' .. m)
end
EOF
write_file ~/.config/nvim/lua/config/keymaps.lua <<'EOF'
-- keymaps.lua -- global maps; plugin-specific ones live in plugins/*.lua.

local map = vim.keymap.set

-- Escape clears search highlight too.
map('n', '<Esc>', '<cmd>nohlsearch<cr>', { desc = 'Clear search highlight' })

-- Keep the cursor centred when jumping around.
map('n', '<C-d>', '<C-d>zz')
map('n', '<C-u>', '<C-u>zz')
map('n', 'n', 'nzzzv')
map('n', 'N', 'Nzzzv')

-- Move visual selections and keep indentation sane.
map('v', 'J', ":m '>+1<cr>gv=gv", { desc = 'Move selection down' })
map('v', 'K', ":m '<-2<cr>gv=gv", { desc = 'Move selection up' })
map('v', '<', '<gv')
map('v', '>', '>gv')

-- Paste over a selection without losing the register.
map('x', 'p', [["_dP]], { desc = 'Paste without yanking' })

-- System clipboard, explicit.
map({ 'n', 'v' }, '<leader>y', [["+y]], { desc = 'Yank to system clipboard' })
map('n', '<leader>Y', [["+Y]], { desc = 'Yank line to system clipboard' })
map({ 'n', 'v' }, '<leader>p', [["+p]], { desc = 'Paste from system clipboard' })

-- Buffers and windows. Buffer-tab maps ([b ]b <leader>bd ...) live in
-- plugins/ui.lua (they follow barbar's tab order).
map('n', '<leader>w', '<cmd>write<cr>', { desc = 'Write buffer' })
map('n', '<leader>q', '<cmd>quit<cr>', { desc = 'Quit window' })

-- Splits.
map('n', '<leader>-', '<cmd>split<cr>', { desc = 'Split horizontal' })
map('n', '<leader>|', '<cmd>vsplit<cr>', { desc = 'Split vertical' })

-- Diagnostics.
map('n', '<leader>d', vim.diagnostic.open_float, { desc = 'Line diagnostics' })
map('n', '<leader>dq', vim.diagnostic.setqflist, { desc = 'Diagnostics to quickfix' })
-- Workspace diagnostics: native in 0.12.
map('n', '<leader>dw', function()
  if vim.lsp.buf.workspace_diagnostics then vim.lsp.buf.workspace_diagnostics() end
  vim.diagnostic.setqflist()
end, { desc = 'Workspace diagnostics' })

-- Quickfix.
map('n', '[q', '<cmd>cprevious<cr>', { desc = 'Previous quickfix' })
map('n', ']q', '<cmd>cnext<cr>', { desc = 'Next quickfix' })
map('n', '<leader>xq', '<cmd>copen<cr>', { desc = 'Open quickfix' })

-- Undo tree (:Undotree is packadd'ed in plugins.lua).
map('n', '<leader>u', '<cmd>Undotree<cr>', { desc = 'Undo tree (built-in)' })

-- Terminal escape.
map('t', '<C-\\><C-\\>', [[<C-\><C-n>]], { desc = 'Leave terminal mode' })

-- Floating terminal for lazygit/opencode/shell (avoids plugins for all three).
local floats = {}

local function float_term(name, cmd)
  local state = floats[name] or {}
  floats[name] = state

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
    return
  end

  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
  end

  local w = math.floor(vim.o.columns * 0.9)
  local h = math.floor(vim.o.lines * 0.9)
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    width = w,
    height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. name .. ' ',
    title_pos = 'center',
  })
  vim.wo[state.win].winhighlight = 'NormalFloat:Normal'

  if not state.job then
    state.job = vim.fn.jobstart(cmd, {
      term = true,
      cwd = vim.fn.getcwd(),
      on_exit = function()
        state.job = nil
        if state.win and vim.api.nvim_win_is_valid(state.win) then
          vim.api.nvim_win_close(state.win, true)
        end
        if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
          vim.api.nvim_buf_delete(state.buf, { force = true })
        end
        state.buf = nil
        state.win = nil
        -- Files changed outside Neovim (commits, AI edits) get picked up.
        vim.cmd('checktime')
      end,
    })
  end

  vim.cmd('startinsert')
  vim.keymap.set('t', '<Esc><Esc>', function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
      state.win = nil
    end
  end, { buffer = state.buf, desc = 'Hide float' })
end

map('n', '<leader>gg', function() float_term('lazygit', 'lazygit') end, { desc = 'Lazygit' })
map('n', '<leader>ga', function() float_term('opencode', 'opencode') end, { desc = 'opencode' })
map('n', '<leader>tt', function() float_term('shell', vim.o.shell) end, { desc = 'Floating shell' })
EOF
write_file ~/.config/nvim/lua/config/autocmds.lua <<'EOF'
-- autocmds.lua

local function augroup(name)
  return vim.api.nvim_create_augroup('thmb_' .. name, { clear = true })
end

-- Briefly highlight yanked text.
vim.api.nvim_create_autocmd('TextYankPost', {
  group = augroup('highlight_yank'),
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})

-- Return to the last cursor position when reopening a file.
vim.api.nvim_create_autocmd('BufReadPost', {
  group = augroup('last_loc'),
  callback = function(ev)
    if vim.bo[ev.buf].filetype == 'gitcommit' then return end
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    local lines = vim.api.nvim_buf_line_count(ev.buf)
    if mark[1] > 0 and mark[1] <= lines then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Create missing parent directories on save.
vim.api.nvim_create_autocmd('BufWritePre', {
  group = augroup('mkdir'),
  callback = function(ev)
    if ev.match:match('^%w%w+://') then return end
    vim.fn.mkdir(vim.fn.fnamemodify(ev.match, ':p:h'), 'p')
  end,
})

-- Trim trailing whitespace on save, preserving the cursor.
vim.api.nvim_create_autocmd('BufWritePre', {
  group = augroup('trim_ws'),
  callback = function()
    local save = vim.fn.winsaveview()
    vim.cmd([[silent! %s/\s\+$//e]])
    vim.fn.winrestview(save)
  end,
})

-- q closes throwaway windows.
vim.api.nvim_create_autocmd('FileType', {
  group = augroup('close_with_q'),
  pattern = { 'help', 'qf', 'man', 'checkhealth', 'lspinfo', 'query', 'notify' },
  callback = function(ev)
    vim.bo[ev.buf].buflisted = false
    vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = ev.buf, silent = true })
  end,
})

-- Two-space indentation for languages where four is unusual.
vim.api.nvim_create_autocmd('FileType', {
  group = augroup('indent_two'),
  pattern = {
    'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'json',
    'jsonc', 'yaml', 'html', 'css', 'scss', 'lua', 'terraform', 'hcl',
    'markdown', 'sh', 'bash',
  },
  callback = function()
    vim.bo.shiftwidth = 2
    vim.bo.tabstop = 2
    vim.bo.softtabstop = 2
  end,
})

-- Makefiles genuinely need real tabs.
vim.api.nvim_create_autocmd('FileType', {
  group = augroup('make_tabs'),
  pattern = { 'make', 'go' },
  callback = function() vim.bo.expandtab = false end,
})

-- Don't autocomplete in prompts and pickers.
vim.api.nvim_create_autocmd('FileType', {
  group = augroup('no_autocomplete'),
  pattern = { 'neo-tree', 'gitcommit', 'markdown', 'text' },
  callback = function() vim.bo.autocomplete = false end,
})
EOF
write_file ~/.config/nvim/lua/plugins/editor.lua <<'EOF'
-- plugins/editor.lua - colourscheme, icons, picker, treesitter, files.

-- Colourscheme -------------------------------------------------------------
require('tokyonight').setup({
  style = 'night',
  styles = { comments = { italic = true } },
})
vim.cmd.colorscheme('tokyonight-night')

-- mini.nvim: icons ---------------------------------------------------------
-- neo-tree, fzf-lua and barbar all consume the mocked nvim-web-devicons.
require('mini.icons').setup()
MiniIcons.mock_nvim_web_devicons()

-- Picker: fzf-lua, wrapping the same fzf binary as bash ----------------------
local fzf = require('fzf-lua')
fzf.setup({
  'default-title',
  winopts = {
    height = 0.85,
    width = 0.85,
    preview = { layout = 'flex', scrollbar = false },
  },
  files = {
    -- Debian ships fd as fdfind.
    cmd = 'fdfind --type f --hidden --follow --exclude .git',
  },
  grep = { rg_glob = true },
  fzf_opts = { ['--cycle'] = true },
})
-- Route vim.ui.select through fzf-lua.
fzf.register_ui_select()

local map = vim.keymap.set
map('n', '<leader><space>', fzf.files, { desc = 'Find files' })
map('n', '<leader>ff', fzf.files, { desc = 'Find files' })
map('n', '<leader>/', fzf.live_grep_native, { desc = 'Live grep' })
map('n', '<leader>*', fzf.grep_cword, { desc = 'Grep word under cursor' })
map('n', '<leader>b', fzf.buffers, { desc = 'Buffers' })
map('n', '<leader>fr', fzf.oldfiles, { desc = 'Recent files' })
map('n', '<leader>fh', fzf.helptags, { desc = 'Help tags' })
map('n', '<leader>?', fzf.keymaps, { desc = 'Keymaps' })
map('n', '<leader>fl', fzf.blines, { desc = 'Lines in buffer' })
map('n', '<leader>fd', fzf.diagnostics_document, { desc = 'Document diagnostics' })
map('n', '<leader>fD', fzf.diagnostics_workspace, { desc = 'Workspace diagnostics' })
map('n', '<leader>fR', fzf.resume, { desc = 'Resume last picker' })
-- Git pickers: why fzf-lua over mini.pick.
map('n', '<leader>gs', fzf.git_status, { desc = 'Git status' })
map('n', '<leader>gc', fzf.git_commits, { desc = 'Git commits (repo)' })
map('n', '<leader>gC', fzf.git_bcommits, { desc = 'Git commits (buffer)' })
map('n', '<leader>gB', fzf.git_branches, { desc = 'Git branches' })
map('n', '<leader>gt', fzf.git_stash, { desc = 'Git stash' })

-- Treesitter ----------------------------------------------------------------
-- nvim-treesitter on its maintained main branch (master is frozen and its
-- queries crash on 0.12). Highlight and folds are core; indent is opt-in.
-- Upgrades: bump the pin in config/plugins.lua, then :packupdate + :TSUpdate.
require('nvim-treesitter').setup({
  install_dir = vim.fn.stdpath('data') .. '/site', -- parsers and queries; prepended to 'rtp'
})

-- jsonc: missing from main's parser list and its GitLab tarball endpoint is
-- broken, so neovim.sh keeps a pinned local checkout to compile from.
vim.api.nvim_create_autocmd('User', {
  group = vim.api.nvim_create_augroup('thmb_ts_custom', { clear = true }),
  pattern = 'TSUpdate',
  desc = 'Register custom treesitter parsers',
  callback = function()
    require('nvim-treesitter.parsers').jsonc = {
      install_info = {
        path = vim.fn.expand('~/.local/opt/grammars/tree-sitter-jsonc'),
      },
    }
  end,
})

-- The parser set (no-op when installed; fetches in the background otherwise).
require('nvim-treesitter').install({
  'bash', 'c', 'cpp', 'css', 'diff', 'dockerfile', 'git_config',
  'git_rebase', 'gitcommit', 'gitignore', 'go', 'hcl', 'html', 'javascript',
  'json', 'jsonc', 'lua', 'luadoc', 'make', 'markdown', 'markdown_inline',
  'python', 'query', 'regex', 'sql', 'terraform', 'toml', 'tsx',
  'typescript', 'vim', 'vimdoc', 'yaml',
})

-- Highlight + indent per buffer when a parser exists, silent otherwise.
-- (jsonc queries live in ~/.config/nvim/queries/jsonc/, written by neovim.sh.)
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('thmb_treesitter', { clear = true }),
  desc = 'Treesitter highlight + indent for filetypes with a parser',
  callback = function(ev)
    if not pcall(vim.treesitter.start, ev.buf) then return end
    vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end,
})

-- File explorer: neo-tree ---------------------------------------------------
require('neo-tree').setup({
  close_if_last_window = true,
  filesystem = {
    follow_current_file = { enabled = true },
    use_libuv_file_watcher = true,
    filtered_items = { hide_dotfiles = false, hide_gitignored = false },
  },
  window = { width = 35 },
})

-- Open the explorer at startup when no file was given.
vim.api.nvim_create_autocmd('VimEnter', {
  group = vim.api.nvim_create_augroup('thmb_neo_tree_startup', { clear = true }),
  desc = 'Open neo-tree on startup when no file was given',
  callback = function()
    -- Piped input lands in a nameless buffer with content; skip that too.
    if vim.fn.argc() > 0 or vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= '' then
      return
    end
    vim.cmd('Neotree show')
  end,
})

map('n', '<leader>n', '<cmd>Neotree toggle<cr>', { desc = 'File explorer (neo-tree)' })
map('n', '<leader>nf', '<cmd>Neotree filesystem<cr>', { desc = 'File explorer (filesystem)' })
-- No <leader>nb: the barbar tabline, <leader>bp and <leader>b cover buffers.
map('n', '<leader>ng', '<cmd>Neotree git_status<cr>', { desc = 'Git modified files' })
map('n', '<leader>nr', '<cmd>Neotree reveal<cr>', { desc = 'Reveal current file' })
EOF
write_file ~/.config/nvim/lua/plugins/ui.lua <<'EOF'
-- plugins/ui.lua - tabline: two state layers per tab, so "what have I altered"
-- and "what needs saving" are answered at a glance:
--   + / ~ / -   git added / changed / deleted vs HEAD (via gitsigns)
--   ●           modified but not yet written
-- barbar over bufferline (no git layer) or mini.tabline (no state at all);
-- vim.g.barbar_auto_setup is set in config/plugins.lua.

require('barbar').setup({
  icons = {
    gitsigns = {
      added = { enabled = true, icon = '+' },
      changed = { enabled = true, icon = '~' },
      deleted = { enabled = true, icon = '-' },
    },
    button = '×',
    modified = { button = '●' }, -- clicking it writes the buffer
    -- Errors and warnings only; INFO/HINT in every tab is noise.
    diagnostics = {
      [vim.diagnostic.severity.ERROR] = { enabled = true, icon = 'E' },
      [vim.diagnostic.severity.WARN] = { enabled = true, icon = 'W' },
      [vim.diagnostic.severity.INFO] = { enabled = false },
      [vim.diagnostic.severity.HINT] = { enabled = false },
    },
    separator = { left = '▎', right = '' },
  },
  -- neo-tree opens at startup (editor.lua); the tabline steps around it.
  sidebar_filetypes = {
    ['neo-tree'] = { text = 'Files', align = 'center' },
  },
})

local map = vim.keymap.set
-- Movement follows the visual tab order, pinned buffers included.
map('n', '[b', '<cmd>BufferPrevious<cr>', { desc = 'Previous buffer' })
map('n', ']b', '<cmd>BufferNext<cr>', { desc = 'Next buffer' })
map('n', '<leader>b<', '<cmd>BufferMovePrevious<cr>', { desc = 'Move buffer left' })
map('n', '<leader>b>', '<cmd>BufferMoveNext<cr>', { desc = 'Move buffer right' })
-- bbye semantics: closing keeps the window layout intact.
map('n', '<leader>bd', '<cmd>BufferClose<cr>', { desc = 'Delete buffer' })
map('n', '<leader>bo', '<cmd>BufferCloseAllButCurrentOrPinned<cr>', { desc = 'Delete other buffers' })
-- Pick by letter (stable per buffer); pin keeps it at the left.
map('n', '<leader>bp', '<cmd>BufferPick<cr>', { desc = 'Pick buffer' })
map('n', '<leader>bP', '<cmd>BufferPin<cr>', { desc = 'Pin/unpin buffer' })
EOF
write_file ~/.config/nvim/lua/plugins/git.lua <<'EOF'
-- plugins/git.lua - gitsigns. No diff-view plugin: lazygit (<leader>gg),
-- gitsigns.diff / diffthis and :DiffTool cover branch review.

require('gitsigns').setup({
  signs = {
    add = { text = '+' },
    change = { text = '~' },
    delete = { text = '_' },
    topdelete = { text = '^' },
    changedelete = { text = '~' },
    untracked = { text = '|' },
  },
  signs_staged_enable = true,
  current_line_blame = false,        -- toggled on demand with <leader>gB
  current_line_blame_opts = { delay = 300, virt_text_pos = 'eol' },
  preview_config = { border = 'rounded' },
  on_attach = function(bufnr)
    local gs = require('gitsigns')
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
    end

    -- Hunk navigation; works inside diff mode too.
    map('n', ']c', function()
      if vim.wo.diff then vim.cmd.normal({ ']c', bang = true })
      else gs.nav_hunk('next') end
    end, 'Next hunk')

    map('n', '[c', function()
      if vim.wo.diff then vim.cmd.normal({ '[c', bang = true })
      else gs.nav_hunk('prev') end
    end, 'Previous hunk')

    -- Granular staging (why gitsigns over mini.diff).
    map('n', '<leader>hs', gs.stage_hunk, 'Stage hunk')
    map('n', '<leader>hr', gs.reset_hunk, 'Reset hunk')
    map('v', '<leader>hs', function() gs.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, 'Stage selected hunk')
    map('v', '<leader>hr', function() gs.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, 'Reset selected hunk')
    map('n', '<leader>hS', gs.stage_buffer, 'Stage buffer')
    map('n', '<leader>hR', gs.reset_buffer, 'Reset buffer')
    map('n', '<leader>hu', gs.undo_stage_hunk, 'Undo stage hunk')
    map('n', '<leader>hp', gs.preview_hunk_inline, 'Preview hunk inline')
    map('n', '<leader>gd', gs.diff, 'Diff file tree (HEAD vs worktree)')
    map('n', '<leader>hd', gs.diffthis, 'Diff against index')
    map('n', '<leader>hD', function() gs.diffthis('~') end, 'Diff against last commit')
    map('n', '<leader>hm', function() gs.diffthis('main') end, 'Diff against main')
    map('n', '<leader>hq', gs.setqflist, 'Hunks to quickfix')

    -- Blame.
    map('n', '<leader>gb', function() gs.blame_line({ full = true }) end, 'Blame line')
    map('n', '<leader>gB', gs.toggle_current_line_blame, 'Toggle inline blame')
    map('n', '<leader>gw', gs.blame, 'Blame whole file')

    -- Hunk as a textobject: dih / vih
    map({ 'o', 'x' }, 'ih', gs.select_hunk, 'Select hunk')
  end,
})
EOF
write_file ~/.config/nvim/lua/plugins/lsp.lua <<'EOF'
-- plugins/lsp.lua - mason, servers, conform. Completion is native 0.12;
-- nvim-lspconfig is just server definitions consumed by vim.lsp.enable().

local servers = {
  'lua_ls',
  'basedpyright',
  'ruff',
  'vtsls',
  'bashls',
  'terraformls',
  'yamlls',
  'jsonls',
  'html',
  'cssls',
  'clangd',
}

-- Server / tool installer ---------------------------------------------------
require('mason').setup({ ui = { border = 'rounded' } })
require('mason-tool-installer').setup({
  -- Reproducible: this list plus the commit pins in config/plugins.lua.
  ensure_installed = {
    -- language servers
    'lua-language-server',
    'basedpyright',
    'ruff',
    'vtsls',
    'bash-language-server',
    'terraform-ls',
    'yaml-language-server',
    'json-lsp',
    'html-lsp',
    'css-lsp',
    -- clangd from mason (23.x vs apt's 19.x); clang-format from apt because
    -- mason ships it as a PyPI wheel. Both honour the project's .clang-format.
    'clangd',
    -- formatters
    'stylua',
    'prettierd',
    'shfmt',
    'sql-formatter',
  },
  run_on_start = false,   -- explicit :MasonToolsInstall, no startup surprises
})

-- Server definitions + activation -------------------------------------------
-- Shared defaults for every server.
vim.lsp.config('*', {
  capabilities = vim.lsp.protocol.make_client_capabilities(),
})

-- Per-server overrides; everything else uses lspconfig's defaults.
vim.lsp.config('lua_ls', {
  settings = {
    Lua = {
      runtime = { version = 'LuaJIT' },
      workspace = { checkThirdParty = false },
      diagnostics = { globals = { 'vim', 'MiniIcons' } },
      telemetry = { enable = false },
      hint = { enable = true },
    },
  },
})

vim.lsp.config('basedpyright', {
  settings = {
    basedpyright = {
      analysis = {
        typeCheckingMode = 'standard',
        diagnosticMode = 'openFilesOnly',
      },
    },
  },
})

vim.lsp.config('yamlls', {
  settings = {
    yaml = {
      keyOrdering = false,
      schemaStore = { enable = true },
    },
  },
})

vim.lsp.enable(servers)

-- Two 0.12 natives replacing plugins: document_color (colour swatches,
-- nvim-colorizer) and linked_editing_range (paired HTML tag rename). The
-- first self-enables on require; the second needs an explicit enable().
pcall(require, 'vim.lsp.document_color')
local ok_ler, ler = pcall(require, 'vim.lsp.linked_editing_range')
if ok_ler then pcall(ler.enable, true) end

-- Per-buffer: native completion plus LSP keymaps.
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('thmb_lsp_attach', { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client then return end
    local buf = ev.buf

    -- Native LSP completion feeding the built-in 'autocomplete'.
    if client:supports_method('textDocument/completion') then
      vim.lsp.completion.enable(true, client.id, buf, { autotrigger = true })
    end

    local function map(lhs, rhs, desc, mode)
      vim.keymap.set(mode or 'n', lhs, rhs, { buffer = buf, desc = 'LSP: ' .. desc })
    end

    -- 0.12 ships grn/gra/grr/gri/grt/grx and K; these add to them. Bare `gr`
    -- stays unmapped so the whole prefix keeps working.
    map('gd', vim.lsp.buf.definition, 'Definition')
    map('gD', vim.lsp.buf.declaration, 'Declaration')
    map('<leader>rn', vim.lsp.buf.rename, 'Rename')
    map('<leader>ca', vim.lsp.buf.code_action, 'Code action', { 'n', 'v' })
    map('<leader>ls', vim.lsp.buf.document_symbol, 'Document symbols')

    if client:supports_method('textDocument/inlayHint') then
      map('<leader>th', function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
      end, 'Toggle inlay hints')
    end
  end,
})

-- Formatting ----------------------------------------------------------------
local map = vim.keymap.set
map({ 'n', 'v' }, '<leader>f', function()
  require('conform').format({ async = true, lsp_format = 'fallback' })
end, { desc = 'Format buffer/selection' })

require('conform').setup({
  formatters_by_ft = {
    lua = { 'stylua' },
    python = { 'ruff_fix', 'ruff_format' },
    javascript = { 'prettierd' },
    javascriptreact = { 'prettierd' },
    typescript = { 'prettierd' },
    typescriptreact = { 'prettierd' },
    json = { 'prettierd' },
    jsonc = { 'prettierd' },
    yaml = { 'prettierd' },
    html = { 'prettierd' },
    css = { 'prettierd' },
    scss = { 'prettierd' },
    markdown = { 'prettierd' },
    sh = { 'shfmt' },
    bash = { 'shfmt' },
    c = { 'clang-format' },
    cpp = { 'clang-format' },
    sql = { 'sql_formatter' },
    terraform = { 'terraform_fmt' },
    hcl = { 'terraform_fmt' },
    ['_'] = { 'trim_whitespace' },
  },
  -- Function form so that :FormatToggle actually takes effect.
  format_on_save = function(bufnr)
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return nil
    end
    return { timeout_ms = 1000, lsp_format = 'fallback' }
  end,
  formatters = {
    shfmt = { prepend_args = { '-i', '2', '-ci' } },
    -- conform's builtin hardcodes `terraform`; this machine runs OpenTofu.
    terraform_fmt = { command = 'tofu' },
  },
})

-- Let :w respect conform, and allow disabling per-session.
vim.api.nvim_create_user_command('FormatToggle', function()
  vim.g.disable_autoformat = not vim.g.disable_autoformat
  vim.notify('Autoformat ' .. (vim.g.disable_autoformat and 'disabled' or 'enabled'))
end, { desc = 'Toggle format on save' })
EOF

# --- jsonc treesitter queries (adapted from nvim-treesitter, Apache-2.0) ----
# main ships none and the grammar has none; `; inherits: json` pulls json's.
write_file ~/.config/nvim/queries/jsonc/highlights.scm <<'EOF'
; inherits: json

(comment) @comment @spell
EOF
write_file ~/.config/nvim/queries/jsonc/injections.scm <<'EOF'
((comment) @injection.content
  (#set! injection.language "comment"))
EOF
write_file ~/.config/nvim/queries/jsonc/indents.scm <<'EOF'
; inherits: json

(comment) @indent.ignore
EOF
write_file ~/.config/nvim/queries/jsonc/folds.scm <<'EOF'
; inherits: json
EOF
write_file ~/.config/nvim/queries/jsonc/locals.scm <<'EOF'
; inherits: json
EOF

# --- migration cleanup: lazy.nvim is gone (vim.pack replaced it) -----------
rm -f "$HOME/.config/nvim/lazy-lock.json" "$HOME/.config/nvim/lua/config/lazy.lua"
rm -rf "$HOME/.local/share/nvim/lazy"

# First launch installs the plugins at their pinned revisions (vim.pack);
# run in nvim:
#   :MasonToolsInstall   (language servers + formatters)
#   :checkhealth
