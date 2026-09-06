local specs = dofile(arg[1])
for i = 1, 4 do
  assert(specs[i].enabled == false, specs[i][1])
end
local configure = specs[5].opts
local original = vim.fn.executable
local available = {}
vim.fn.executable = function(command)
  return available[command] and 1 or 0
end
local callback = function() return "preserved" end
local function options()
  return { servers = { lua_ls = {}, vtsls = {}, ["*"] = { capabilities = {} } }, setup = { ts_ls = function() return true end, ruff = callback } }
end
local empty = options()
configure(nil, empty)
assert(empty.servers.lua_ls == nil and empty.servers.vtsls == nil)
assert(empty.servers["*"].capabilities)
assert(empty.setup.ruff == callback)
assert(empty.setup.ts_ls() == false and empty.setup.rust_analyzer() == false)
local expected = {
  basedpyright = "basedpyright-langserver", ruff = "ruff", ts_ls = "typescript-language-server",
  rust_analyzer = "rust-analyzer", gopls = "gopls", clangd = "clangd", elixirls = "elixir-ls",
  zls = "zls", bashls = "bash-language-server",
}
for server, command in pairs(expected) do
  available = { [command] = true }
  local opts = options()
  opts.servers[server] = { settings = { custom = true }, enabled = false }
  configure(nil, opts)
  assert(opts.servers[server].mason == false and opts.servers[server].enabled == true)
  assert(opts.servers[server].settings.custom)
  assert(opts.servers[server].cmd[1] == command)
  for name in pairs(opts.servers) do
    assert(name == server or name == "*", name)
  end
end
vim.fn.executable = original
print("Neovim PATH server consumer checks passed")

if arg[2] and vim.fn.isdirectory(arg[2]) == 1 then
  vim.opt.rtp:prepend(arg[2])
  local config = require("lazy.core.config")
  config.options = vim.deepcopy(config.defaults)
  local plugin = require("lazy.core.plugin")
  available = { ["typescript-language-server"] = true, ruff = true }
  vim.fn.executable = function(command) return available[command] and 1 or 0 end
  local merged = plugin.Spec.new({
    { "neovim/nvim-lspconfig", dependencies = { "mason-org/mason.nvim", "mason-org/mason-lspconfig.nvim" },
      opts = { servers = { vtsls = {}, ts_ls = { settings = { user_option = true } } },
        setup = { ts_ls = function() return true end, ruff = callback } } },
    { "mason-org/mason.nvim", opts = { ensure_installed = { "lua-language-server" } } },
    { "mrcjkb/rustaceanvim", opts = {} },
    specs,
  }, { pkg = false })
  assert(merged.plugins["mason.nvim"] == nil)
  assert(merged.plugins["mason-lspconfig.nvim"] == nil)
  assert(merged.plugins.rustaceanvim == nil)
  local opts = plugin.values(merged.plugins["nvim-lspconfig"], "opts", false)
  assert(opts.servers.ts_ls.settings.user_option)
  assert(opts.servers.ts_ls.enabled and opts.servers.ts_ls.mason == false)
  assert(opts.servers.vtsls == nil)
  assert(opts.setup.ts_ls() == false and opts.setup.ruff == callback)
  vim.fn.executable = original
  print("lazy.nvim merged specification consumer checks passed")
else
  print("SKIP: lazy.nvim specification merge check (set NVIM_LAZY_PATH)")
end
