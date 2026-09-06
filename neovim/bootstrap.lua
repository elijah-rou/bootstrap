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
      local existing = opts.servers or {}
      opts.servers = { ["*"] = existing["*"] }
      opts.setup = opts.setup or {}
      -- LazyVim extras defer these servers to plugins disabled by this overlay.
      opts.setup.ts_ls = function() return false end
      opts.setup.rust_analyzer = function() return false end
      for server, cmd in pairs(commands) do
        if vim.fn.executable(cmd[1]) == 1 then
          local settings = type(existing[server]) == "table" and existing[server] or {}
          settings.enabled = true
          settings.mason = false
          settings.cmd = cmd
          opts.servers[server] = settings
        end
      end
    end,
  },
}
