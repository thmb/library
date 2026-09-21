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
        -- clang-format, by contrast, comes from apt (see packages.txt) because
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
