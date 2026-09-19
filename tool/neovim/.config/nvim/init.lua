-- ~/.config/nvim/init.lua
-- Managed in /opt/github/thmb/library/tool/neovim
-- Requires Neovim >= 0.12 (uses vim.lsp.config/enable, 'autocomplete', 'winborder').

if vim.fn.has('nvim-0.12') == 0 then
  vim.notify('This config requires Neovim 0.12+', vim.log.levels.ERROR)
  return
end

require('config.options')
require('config.lazy')     -- bootstraps lazy.nvim and loads lua/plugins/*
require('config.keymaps')
require('config.autocmds')
