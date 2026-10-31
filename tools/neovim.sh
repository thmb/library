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


# Pin the release; bump this and re-run to upgrade. Neovim is NOT from apt:
# Debian ships 0.10.x but this config needs 0.12+ (vim.lsp.config/enable,
# 'autocomplete', 'winborder').
VERSION=0.12.5

apt_install make clangd clang-format shellcheck yamllint python3-venv \
  fzf fd-find ripgrep

# Remove Debian's older Neovim if the apt package is present; mark xclip manual
# first so it isn't swept by a later `apt autoremove`.
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

# --- configuration (written in place each run) -----------------------------
write_file ~/.config/nvim/init.lua <<'EOF'
-- ~/.config/nvim/init.lua
-- Managed by tools/neovim.sh
-- Requires Neovim >= 0.12 (uses vim.lsp.config/enable, 'autocomplete', 'winborder').

if vim.fn.has('nvim-0.12') == 0 then
  vim.notify('This config requires Neovim 0.12+', vim.log.levels.ERROR)
  return
end

require('config.options')
require('config.lazy')     -- bootstraps lazy.nvim and loads lua/plugins/*
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
o.cmdheight = 1
o.confirm = true -- prompt instead of failing on unsaved changes

-- Manual Configuration
vim.opt.wrap = true -- Enable line wrapping
vim.opt.linebreak = true -- Wrap lines at convenient points (like spaces) instead of mid-word
vim.opt.textwidth = 0 -- Prevent automatic physical line breaks

-- The 0.12 default statusline already reports diagnostics, LSP progress,
-- 'busy' and terminal exit codes, so no statusline plugin is needed. The one
-- thing it lacks is the git branch, which gitsigns exposes as b:gitsigns_head.
-- Extend the real default instead of hardcoding a copy of it.
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

-- Indentation (guess-indent was dropped; these are sane polyglot defaults and
-- editorconfig support is built in)
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
o.diffopt = "internal,filler,closeoff,indent-heuristic,inline:word,linematch:60,algorithm:histogram"

-- Project-local config. 0.12 searches parent directories too; files must be
-- explicitly trusted with :trust, so this is safe across /opt/github/*.
o.exrc = true

-- Wayland clipboard. wl-clipboard is installed; "+y / "+p talk to the desktop.
-- Left unset for `clipboard` on purpose: explicit "+ is less surprising than
-- silently routing every yank through the system clipboard.
vim.g.clipboard = nil

o.mouse = "a"
o.mousemoveevent = true

-- Fold with treesitter, but start fully open.
o.foldmethod = "expr"
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
o.foldlevel = 99
o.foldtext = ""
o.fillchars = "fold: ,foldopen:v,foldclose:>,foldsep: ,diff:/,eob: "

-- Filetype pinning ---------------------------------------------------------
-- Neovim's .tf detection is content-sensitive: a brand-new or comment-only
-- .tf file is classified as `tf` (TinyFugue, a MUD scripting language), which
-- means no terraformls and no formatter until real HCL is typed. This machine
-- runs OpenTofu, so pin the extension deterministically.
vim.filetype.add({
	extension = {
		tf = "terraform",
		tfvars = "terraform",
	},
})

-- Filetype pinning ---------------------------------------------------------
-- Neovim's .tf detection is content-sensitive: a brand-new or comment-only
-- .tf file is classified as `tf`, which is TinyFugue (a MUD scripting
-- language) rather than Terraform. That means no terraformls and no formatter
-- until real HCL is typed. This machine runs OpenTofu daily and nothing uses
-- TinyFugue, so pin the extension deterministically.
-- .tfvars is left alone: Neovim already gives it the dedicated
-- `terraform-vars` filetype, which conform maps below.
vim.filetype.add({
	extension = { tf = "terraform" },
})

-- Diagnostics: virtual_lines only for the current line keeps things quiet but
-- readable; virtual_text off avoids the wall-of-text effect.
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
write_file ~/.config/nvim/lua/config/lazy.lua <<'EOF'
-- lazy.nvim bootstrap. lazy-lock.json is committed, which is what makes this
-- config reproducible on another machine.

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local repo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system({ 'git', 'clone', '--filter=blob:none', '--branch=stable', repo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' }, { out, 'WarningMsg' } }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  spec = { { import = 'plugins' } },
  install = { colorscheme = { 'tokyonight' } },
  checker = { enabled = false },   -- no background update nagging
  change_detection = { notify = false },
  ui = { border = 'rounded' },
  performance = {
    rtp = {
      disabled_plugins = {
        'gzip', 'tarPlugin', 'zipPlugin', 'tohtml', 'tutor', 'netrwPlugin',
      },
    },
  },
})
EOF
write_file ~/.config/nvim/lua/config/keymaps.lua <<'EOF'
-- keymaps.lua
-- Plugin-specific maps live with their plugin spec; this file holds the rest.

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

-- Buffers and windows.
map('n', '<leader>w', '<cmd>write<cr>', { desc = 'Write buffer' })
map('n', '<leader>q', '<cmd>quit<cr>', { desc = 'Quit window' })
map('n', '<leader>bd', '<cmd>bdelete<cr>', { desc = 'Delete buffer' })
map('n', '<leader>bo', '<cmd>%bdelete|edit#|bdelete#<cr>', { desc = 'Delete other buffers' })
map('n', '[b', '<cmd>bprevious<cr>', { desc = 'Previous buffer' })
map('n', ']b', '<cmd>bnext<cr>', { desc = 'Next buffer' })

-- Splits.
map('n', '<leader>-', '<cmd>split<cr>', { desc = 'Split horizontal' })
map('n', '<leader>|', '<cmd>vsplit<cr>', { desc = 'Split vertical' })

-- Diagnostics.
map('n', '<leader>d', vim.diagnostic.open_float, { desc = 'Line diagnostics' })
map('n', '<leader>dq', vim.diagnostic.setqflist, { desc = 'Diagnostics to quickfix' })
-- 0.12 ships workspace diagnostics, so trouble.nvim is unnecessary.
map('n', '<leader>dw', function()
  if vim.lsp.buf.workspace_diagnostics then vim.lsp.buf.workspace_diagnostics() end
  vim.diagnostic.setqflist()
end, { desc = 'Workspace diagnostics' })

-- Quickfix.
map('n', '[q', '<cmd>cprevious<cr>', { desc = 'Previous quickfix' })
map('n', ']q', '<cmd>cnext<cr>', { desc = 'Next quickfix' })
map('n', '<leader>xq', '<cmd>copen<cr>', { desc = 'Open quickfix' })

-- Built-in 0.12 tooling that used to need plugins.
map('n', '<leader>u', '<cmd>Undotree<cr>', { desc = 'Undo tree (built-in)' })

-- Terminal escape.
map('t', '<C-\\><C-\\>', [[<C-\><C-n>]], { desc = 'Leave terminal mode' })

-- ---------------------------------------------------------------------------
-- Floating terminal, used for lazygit and opencode. Avoids a plugin for both.
-- ---------------------------------------------------------------------------
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

-- Don't autocomplete in prompts and telescope-style inputs.
vim.api.nvim_create_autocmd('FileType', {
  group = augroup('no_autocomplete'),
  pattern = { 'neo-tree', 'gitcommit', 'markdown', 'text' },
  callback = function() vim.bo.autocomplete = false end,
})
EOF
write_file ~/.config/nvim/lua/plugins/editor.lua <<'EOF'
-- plugins/editor.lua - colourscheme, picker, treesitter, files, motions, mini.

return {

  -- Colourscheme -----------------------------------------------------------
  {
    'folke/tokyonight.nvim',
    lazy = false,
    priority = 1000,
    opts = {
      style = 'night',
      styles = { comments = { italic = true } },
    },
    config = function(_, opts)
      require('tokyonight').setup(opts)
      vim.cmd.colorscheme('tokyonight-night')
    end,
  },

  -- mini.nvim: surround, textobjects, pairs, icons ------------------------
  -- One dependency covering four slots. mini.ai replaces
  -- nvim-treesitter-textobjects and avoids its main-branch churn.
  {
    'nvim-mini/mini.nvim',
    version = false,
    lazy = false,
    priority = 900,
    config = function()
      -- Icons first: neo-tree and fzf-lua both pick this up.
      require('mini.icons').setup()
      MiniIcons.mock_nvim_web_devicons()

      -- Surround on `gs` so leap keeps `s`/`S`.
      require('mini.surround').setup({
        mappings = {
          add = 'gsa',
          delete = 'gsd',
          find = 'gsf',
          find_left = 'gsF',
          highlight = 'gsh',
          replace = 'gsr',
          update_n_lines = 'gsn',
        },
      })

      -- Treesitter-aware a/i textobjects: daf, cif, vac, yio...
      -- The @function/@class captures come from nvim-treesitter-textobjects'
      -- query files (treesitter core ships none); mini.ai only reads them.
      -- `a` (argument) and `t` (tag) are left as mini.ai's query-free defaults.
      local ai = require('mini.ai')
      ai.setup({
        n_lines = 500,
        custom_textobjects = {
          f = ai.gen_spec.treesitter({ a = '@function.outer', i = '@function.inner' }),
          c = ai.gen_spec.treesitter({ a = '@class.outer', i = '@class.inner' }),
          o = ai.gen_spec.treesitter({
            a = { '@conditional.outer', '@loop.outer' },
            i = { '@conditional.inner', '@loop.inner' },
          }),
        },
      })

      require('mini.pairs').setup({
        modes = { insert = true, command = false, terminal = false },
      })
    end,
  },

  -- Picker: wraps the same fzf binary as bash ------------------------------
  {
    'ibhagwan/fzf-lua',
    cmd = 'FzfLua',
    keys = {
      { '<leader><space>', function() require('fzf-lua').files() end, desc = 'Find files' },
      { '<leader>ff', function() require('fzf-lua').files() end, desc = 'Find files' },
      { '<leader>/', function() require('fzf-lua').live_grep_native() end, desc = 'Live grep' },
      { '<leader>*', function() require('fzf-lua').grep_cword() end, desc = 'Grep word under cursor' },
      { '<leader>b', function() require('fzf-lua').buffers() end, desc = 'Buffers' },
      { '<leader>fr', function() require('fzf-lua').oldfiles() end, desc = 'Recent files' },
      { '<leader>fh', function() require('fzf-lua').helptags() end, desc = 'Help tags' },
      { '<leader>?', function() require('fzf-lua').keymaps() end, desc = 'Keymaps' },
      { '<leader>fl', function() require('fzf-lua').blines() end, desc = 'Lines in buffer' },
      { '<leader>fd', function() require('fzf-lua').diagnostics_document() end, desc = 'Document diagnostics' },
      { '<leader>fD', function() require('fzf-lua').diagnostics_workspace() end, desc = 'Workspace diagnostics' },
      { '<leader>fR', function() require('fzf-lua').resume() end, desc = 'Resume last picker' },
      -- Git pickers: the reason fzf-lua earns its place over mini.pick.
      { '<leader>gs', function() require('fzf-lua').git_status() end, desc = 'Git status' },
      { '<leader>gc', function() require('fzf-lua').git_commits() end, desc = 'Git commits (repo)' },
      { '<leader>gC', function() require('fzf-lua').git_bcommits() end, desc = 'Git commits (buffer)' },
      { '<leader>gB', function() require('fzf-lua').git_branches() end, desc = 'Git branches' },
      { '<leader>gt', function() require('fzf-lua').git_stash() end, desc = 'Git stash' },
    },
    opts = {
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
    },
    config = function(_, opts)
      local fzf = require('fzf-lua')
      fzf.setup(opts)
      -- Route vim.ui.select through fzf-lua (also used by opencode.nvim etc.)
      fzf.register_ui_select()
    end,
  },

  -- Treesitter -------------------------------------------------------------
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'master',
    lazy = false,
    build = ':TSUpdate',
    dependencies = {
      -- Query provider only: supplies the textobjects.scm files that mini.ai
      -- reads. No module setup, no keymaps of its own.
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'master' },
    },
    opts = {
      ensure_installed = {
        'bash', 'c', 'cpp', 'css', 'diff', 'dockerfile', 'git_config',
        'git_rebase', 'gitcommit', 'gitignore', 'go', 'hcl', 'html', 'javascript',
        'json', 'jsonc', 'lua', 'luadoc', 'make', 'markdown', 'markdown_inline',
        'python', 'query', 'regex', 'sql', 'terraform', 'toml', 'tsx',
        'typescript', 'vim', 'vimdoc', 'yaml',
      },
      highlight = { enable = true },
      indent = { enable = true },
      -- Incremental selection is native in 0.12 (v_an / v_in), so it's off here.
    },
    config = function(_, opts)
      -- Clone grammars over git rather than fetching release tarballs. The
      -- jsonc grammar is hosted on GitLab and its tarball endpoint returns
      -- non-gzip data, which aborts the whole install; git clone works.
      -- Costs a little extra time on first install only.
      require('nvim-treesitter.install').prefer_git = true
      require('nvim-treesitter.configs').setup(opts)
    end,
  },

  -- File explorer: neo-tree -----------------------------------------------
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    cmd = 'Neotree',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      -- nvim-web-devicons is supplied by mini.icons' mock_nvim_web_devicons().
    },
    -- Open the explorer at startup when no file was given.
    init = function()
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
    end,
    keys = {
      { '<leader>n', '<cmd>Neotree toggle<cr>', desc = 'File explorer (neo-tree)' },
      { '<leader>nf', '<cmd>Neotree filesystem<cr>', desc = 'File explorer (filesystem)' },
      { '<leader>nb', '<cmd>Neotree buffers<cr>', desc = 'Open buffers' },
      { '<leader>ng', '<cmd>Neotree git_status<cr>', desc = 'Git modified files' },
      { '<leader>nr', '<cmd>Neotree reveal<cr>', desc = 'Reveal current file' },
    },
    opts = {
      close_if_last_window = true,
      filesystem = {
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        filtered_items = { hide_dotfiles = false, hide_gitignored = false },
      },
      window = { width = 35 },
    },
  },

  -- Jump anywhere: leap keeps `s` / `S` -----------------------------------
  {
    'ggandor/leap.nvim',
    keys = {
      { 's', '<Plug>(leap-forward)', mode = { 'n', 'x', 'o' }, desc = 'Leap forward' },
      { 'S', '<Plug>(leap-backward)', mode = { 'n', 'x', 'o' }, desc = 'Leap backward' },
      { 'gS', '<Plug>(leap-from-window)', mode = { 'n', 'x', 'o' }, desc = 'Leap across windows' },
    },
    config = function()
      require('leap').opts.safe_labels = {}
    end,
  },

  -- Seamless pane/split movement with tmux, on Alt ------------------------
  {
    'christoomey/vim-tmux-navigator',
    lazy = false,
    cmd = {
      'TmuxNavigateLeft', 'TmuxNavigateDown',
      'TmuxNavigateUp', 'TmuxNavigateRight',
    },
    init = function()
      vim.g.tmux_navigator_no_mappings = 1
    end,
    keys = {
      { '<M-h>', '<cmd>TmuxNavigateLeft<cr>', desc = 'Pane/split left' },
      { '<M-j>', '<cmd>TmuxNavigateDown<cr>', desc = 'Pane/split down' },
      { '<M-k>', '<cmd>TmuxNavigateUp<cr>', desc = 'Pane/split up' },
      { '<M-l>', '<cmd>TmuxNavigateRight<cr>', desc = 'Pane/split right' },
    },
  },
}
EOF
write_file ~/.config/nvim/lua/plugins/git.lua <<'EOF'
-- plugins/git.lua
--
-- diffview.nvim was deliberately dropped (no commits since 2024-08). Branch
-- review is covered by lazygit (<leader>gg), fzf-lua's git_commits/git_bcommits,
-- gitsigns.diffthis, and Neovim 0.12's built-in :DiffTool.

return {
  {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
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

        -- Granular staging: the reason gitsigns is here rather than mini.diff.
        map('n', '<leader>hs', gs.stage_hunk, 'Stage hunk')
        map('n', '<leader>hr', gs.reset_hunk, 'Reset hunk')
        map('v', '<leader>hs', function() gs.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, 'Stage selected hunk')
        map('v', '<leader>hr', function() gs.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end, 'Reset selected hunk')
        map('n', '<leader>hS', gs.stage_buffer, 'Stage buffer')
        map('n', '<leader>hR', gs.reset_buffer, 'Reset buffer')
        map('n', '<leader>hu', gs.undo_stage_hunk, 'Undo stage hunk')
        map('n', '<leader>hp', gs.preview_hunk_inline, 'Preview hunk inline')
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
    },
  },
}
EOF
write_file ~/.config/nvim/lua/plugins/lsp.lua <<'EOF'
-- plugins/lsp.lua
--
-- Neovim 0.12 handles completion natively ('autocomplete' + vim.lsp.completion),
-- so there is no completion plugin. nvim-lspconfig is used purely as a library
-- of server definitions consumed by vim.lsp.enable().

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

return {

  -- Server / tool installer ------------------------------------------------
  {
    'mason-org/mason.nvim',
    cmd = { 'Mason', 'MasonUpdate' },
    opts = { ui = { border = 'rounded' } },
  },

  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    event = 'VeryLazy',
    dependencies = { 'mason-org/mason.nvim' },
    opts = {
      -- Declarative and committed: this list plus lazy-lock.json is what makes
      -- the editor reproducible on another machine.
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
        -- clangd from mason: 23.x versus apt's 19.x, a big difference for C/C++.
        -- clang-format, by contrast, comes from apt (installed by neovim.sh) because
        -- mason ships it as a PyPI wheel. The two need not match: both honour
        -- the project's .clang-format.
        'clangd',
        -- formatters
        'stylua',
        'prettierd',
        'shfmt',
        'sql-formatter',
      },
      run_on_start = false,   -- explicit :MasonToolsInstall, no startup surprises
    },
  },

  -- Server definitions + activation ---------------------------------------
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = { 'mason-org/mason.nvim' },
    config = function()
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

      -- Two 0.12 natives that replace whole plugins. Both are global and
      -- one-time, so they live here rather than in the per-buffer LspAttach
      -- handler below.
      --   document_color        -> inline colour swatches (nvim-colorizer)
      --   linked_editing_range  -> paired HTML tag rename (nvim-ts-autotag)
      --
      -- Note the asymmetry: requiring the document_color module *is* the
      -- enable call, because it self-enables globally on load, whereas
      -- linked_editing_range needs an explicit enable().
      pcall(require, 'vim.lsp.document_color')
      local ok_ler, ler = pcall(require, 'vim.lsp.linked_editing_range')
      if ok_ler then pcall(ler.enable, true) end

      -- Per-buffer: native completion plus the LSP keymaps. The 0.12 native
      -- document colour and linked editing are handled globally above.
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

          -- 0.12 already provides grn (rename), gra (code action),
          -- grr (references), gri (implementation), grt (type definition),
          -- grx (codelens) and K (hover). Bare `gr` is left unmapped so that
          -- whole prefix keeps working. These are additions, not replacements.
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
    end,
  },

  -- Formatting -------------------------------------------------------------
  {
    'stevearc/conform.nvim',
    event = 'BufWritePre',
    cmd = 'ConformInfo',
    keys = {
      {
        '<leader>f',
        function() require('conform').format({ async = true, lsp_format = 'fallback' }) end,
        mode = { 'n', 'v' },
        desc = 'Format buffer/selection',
      },
    },
    opts = {
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
        ['terraform-vars'] = { 'terraform_fmt' },
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
        -- conform's builtin hardcodes `terraform`, which isn't installed here;
        -- OpenTofu provides a CLI-compatible `tofu fmt`.
        terraform_fmt = { command = 'tofu' },
      },
    },
    init = function()
      -- Let :w respect conform, and allow disabling per-session.
      vim.api.nvim_create_user_command('FormatToggle', function()
        vim.g.disable_autoformat = not vim.g.disable_autoformat
        vim.notify('Autoformat ' .. (vim.g.disable_autoformat and 'disabled' or 'enabled'))
      end, { desc = 'Toggle format on save' })
    end,
  },
}
EOF
write_file ~/.config/nvim/lazy-lock.json <<'EOF'
{
  "conform.nvim": { "branch": "master", "commit": "016802de402556da54c36bd7359b441266b01cdd" },
  "fzf-lua": { "branch": "main", "commit": "02bc882f208f3481aa959dbbee8ce5edad2fd8b2" },
  "gitsigns.nvim": { "branch": "main", "commit": "8d79f2410c76e62b92e51c28c82e28c1c5a3daeb" },
  "lazy.nvim": { "branch": "main", "commit": "306a05526ada86a7b30af95c5cc81ffba93fef97" },
  "leap.nvim": { "branch": "main", "commit": "cbb7d3e4d9584d6b1ae47932f894eb4a16197a52" },
  "mason-tool-installer.nvim": { "branch": "main", "commit": "443f1ef8b5e6bf47045cb2217b6f748a223cf7dc" },
  "mason.nvim": { "branch": "main", "commit": "2a6940af80375532e5e9e7c1f2fc6319a1b7a69d" },
  "mini.nvim": { "branch": "main", "commit": "ac5dffcc52b8378fbb15efeb0497a83e57a0b01c" },
  "neo-tree.nvim": { "branch": "v3.x", "commit": "1a14083046d96e88e361d1da00761c40d45012f3" },
  "nui.nvim": { "branch": "main", "commit": "10fc361835c856ba4233ef5ea135b919bf3dce97" },
  "nvim-lspconfig": { "branch": "master", "commit": "ffd261c09c3dabd0bf1a438f47a8ae3b22f3c3ff" },
  "nvim-treesitter": { "branch": "master", "commit": "cf12346a3414fa1b06af75c79faebe7f76df080a" },
  "nvim-treesitter-textobjects": { "branch": "master", "commit": "5ca4aaa6efdcc59be46b95a3e876300cfead05ef" },
  "plenary.nvim": { "branch": "master", "commit": "74b06c6c75e4eeb3108ec01852001636d85a932b" },
  "tokyonight.nvim": { "branch": "main", "commit": "cdc07ac78467a233fd62c493de29a17e0cf2b2b6" },
  "vim-tmux-navigator": { "branch": "master", "commit": "e41c431a0c7b7388ae7ba341f01a0d217eb3a432" }
}
EOF

# First launch bootstraps lazy.nvim + plugins; run in nvim:
#   :MasonToolsInstall   (language servers + formatters)
#   :checkhealth
