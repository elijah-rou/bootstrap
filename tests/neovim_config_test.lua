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
local function options()
  return { servers = { lua_ls = {}, vtsls = {}, ["*"] = { capabilities = {} } }, setup = { ts_ls = function() end } }
end
local empty = options()
configure(nil, empty)
assert(empty.servers.lua_ls == nil and empty.servers.vtsls == nil)
assert(empty.servers["*"].capabilities)
assert(next(empty.setup) == nil)
local expected = {
  basedpyright = "basedpyright-langserver", ruff = "ruff", ts_ls = "typescript-language-server",
  rust_analyzer = "rust-analyzer", gopls = "gopls", clangd = "clangd", elixirls = "elixir-ls",
  zls = "zls", bashls = "bash-language-server",
}
for server, command in pairs(expected) do
  available = { [command] = true }
  local opts = options()
  configure(nil, opts)
  assert(opts.servers[server].mason == false)
  assert(opts.servers[server].cmd[1] == command)
  for name in pairs(opts.servers) do
    assert(name == server or name == "*", name)
  end
end
vim.fn.executable = original
print("Neovim PATH server consumer checks passed")
