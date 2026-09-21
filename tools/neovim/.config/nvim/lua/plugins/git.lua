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
