-- Mason is disabled. Only explicitly persisted and ready servers are configured.
local selection_path = vim.env.BOOTSTRAP_LSP_SELECTIONS
local selected = {}
if selection_path and vim.fn.filereadable(selection_path) == 1 then
  local value = vim.json.decode(table.concat(vim.fn.readfile(selection_path), "\n"))
  assert(type(value) == "table" and value.schemaVersion == 1 and type(value.servers) == "table", "invalid bootstrap LSP selections")
  selected = value.servers
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
          opts.servers[server] = settings
        end
      end
    end,
  },
}
