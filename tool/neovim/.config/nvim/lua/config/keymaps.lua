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
