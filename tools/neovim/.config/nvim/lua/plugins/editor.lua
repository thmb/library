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
