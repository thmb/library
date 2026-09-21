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
