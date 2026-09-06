-- Language profiles install servers on PATH; opening Neovim must not install them.
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "WhoIsSethDaniel/mason-tool-installer.nvim", enabled = false },
  -- Keep Rust on the same PATH-based lspconfig contract as the other profiles.
  { "mrcjkb/rustaceanvim", enabled = false },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local commands = {
        basedpyright = { "basedpyright-langserver", "--stdio" },
        ruff = { "ruff", "server" },
        ts_ls = { "typescript-language-server", "--stdio" },
        rust_analyzer = { "rust-analyzer" },
        gopls = { "gopls" },
        clangd = { "clangd" },
        elixirls = { "elixir-ls" },
        zls = { "zls" },
        bashls = { "bash-language-server", "start" },
      }
      opts.servers = { ["*"] = (opts.servers or {})["*"] }
      opts.setup = {}
      for server, cmd in pairs(commands) do
        if vim.fn.executable(cmd[1]) == 1 then
          opts.servers[server] = { mason = false, cmd = cmd }
        end
      end
    end,
  },
}
