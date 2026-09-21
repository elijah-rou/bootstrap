-- Mason is disabled. Only explicitly persisted and ready servers are configured.
local selection_path = vim.env.BOOTSTRAP_LSP_SELECTIONS
if not selection_path or selection_path == "" then
  selection_path = vim.fn.stdpath("config") .. "/lsp-selections.json"
end
local selected = {}
if selection_path and vim.fn.filereadable(selection_path) == 1 then
  local value = vim.json.decode(table.concat(vim.fn.readfile(selection_path), "\n"))
  assert(type(value) == "table" and value.schemaVersion == 1 and type(value.servers) == "table", "invalid bootstrap LSP selections")
  selected = value.servers
end

local treesitter = { "nvim-treesitter/nvim-treesitter", optional = true }
if vim.g.bootstrap_neovim_repair then
  -- Parser installation has one explicit writer, separate from plugin repair and editor startup.
  treesitter.build = false
  treesitter.opts = function(_, opts)
    opts._bootstrap_ensure_installed = opts.ensure_installed
    opts.ensure_installed = {}
  end
end

return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "WhoIsSethDaniel/mason-tool-installer.nvim", enabled = false },
  { "mrcjkb/rustaceanvim", enabled = false },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local existing = opts.servers or {}
      opts.servers = { ["*"] = existing["*"] }
      opts.setup = opts.setup or {}
      opts.setup.ts_ls = function() return false end
      opts.setup.rust_analyzer = function() return false end
      for server, selection in pairs(selected) do
        assert(type(selection.cmd) == "table" and type(selection.cmd[1]) == "string", "invalid selected LSP command")
        if vim.fn.executable(selection.cmd[1]) == 1 then
          local settings = type(existing[server]) == "table" and vim.deepcopy(existing[server]) or {}
          settings.enabled = true
          settings.mason = false
          settings.cmd = selection.cmd
          settings.filetypes = selection.filetypes
          if selection.root_markers then
            assert(type(selection.root_markers) == "table" and #selection.root_markers > 0 and #selection.root_markers <= 16, "invalid root markers")
            for _, marker in ipairs(selection.root_markers) do
              assert(type(marker) == "string" and #marker > 0 and #marker <= 128 and not marker:find("[/\\%z]"), "invalid root marker")
            end
            settings.root_markers = selection.root_markers
          end
          if selection.root_policy then
            assert(selection.root_policy == "rust-standalone" and server == "rust_analyzer", "unknown root policy")
            assert(selection.root_markers, "Rust root policy requires explicit markers")
            if vim.fn.executable("rustc") == 0 or vim.fn.executable("cargo") == 0 then
              -- The pinned upstream root finder invokes rustc before checking markers.
              settings.root_dir = function(bufnr, on_dir)
                local filename = vim.api.nvim_buf_get_name(bufnr)
                on_dir(vim.fs.root(filename, selection.root_markers) or vim.fs.dirname(filename))
              end
              settings.before_init = function(params, config)
                local rust = vim.deepcopy((config.settings or {})["rust-analyzer"] or {})
                rust.linkedProjects = {}
                local buffers = vim.api.nvim_list_bufs()
                rust.detachedFiles = {}
                for _, bufnr in ipairs(buffers) do
                  if vim.bo[bufnr].filetype == "rust" then
                    table.insert(rust.detachedFiles, vim.api.nvim_buf_get_name(bufnr))
                  end
                end
                rust.cargo = vim.tbl_deep_extend("force", rust.cargo or {}, { sysroot = vim.NIL, buildScripts = { enable = false } })
                rust.procMacro = { enable = false }
                rust.checkOnSave = false
                config.settings = config.settings or {}
                config.settings["rust-analyzer"] = rust
                params.initializationOptions = rust
              end
            end
          end
          opts.servers[server] = settings
        end
      end
    end,
  },
  treesitter,
}
