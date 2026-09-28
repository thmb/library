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
