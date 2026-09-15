local specs = dofile(arg[1])
for i = 1, 4 do assert(specs[i].enabled == false, specs[i][1]) end
local configure = specs[5].opts
local original = vim.fn.executable
local available = { ["basedpyright-langserver"] = true, ["typescript-language-server"] = true, clangd = true, ["rust-analyzer"] = true }
vim.fn.executable = function(command) return available[command] and 1 or 0 end
local callback = function() return "preserved" end
local opts = { servers = { basedpyright = { settings = { custom = true } }, clangd = {}, lua_ls = {}, ["*"] = { capabilities = {} } }, setup = { ruff = callback } }
configure(nil, opts)
assert(opts.servers["*"].capabilities)
assert(opts.servers.basedpyright.enabled and opts.servers.basedpyright.mason == false)
assert(opts.servers.basedpyright.settings.custom)
assert(opts.servers.basedpyright.cmd[1] == "basedpyright-langserver")
assert(opts.servers.ts_ls.enabled and opts.servers.ts_ls.cmd[1] == "typescript-language-server")
assert(opts.servers.clangd == nil, "unselected executable was activated")
assert(opts.servers.lua_ls == nil)
assert(opts.setup.ruff == callback)
assert(opts.setup.ts_ls() == false and opts.setup.rust_analyzer() == false)
local project = vim.fn.tempname()
vim.fn.mkdir(project .. "/src", "p")
project = assert(vim.uv.fs_realpath(project))
vim.fn.writefile({ "[package]", 'name = "fixture"', 'version = "0.1.0"' }, project .. "/Cargo.toml")
vim.cmd("edit " .. vim.fn.fnameescape(project .. "/src/main.rs"))
vim.bo.filetype = "rust"
local root
opts.servers.rust_analyzer.root_dir(0, function(value) root = value end)
assert(root == project, "standalone Rust must honor project markers without invoking a toolchain")
local params = {}
local rust_config = { settings = { ["rust-analyzer"] = { custom = true } } }
opts.servers.rust_analyzer.before_init(params, rust_config)
assert(params.initializationOptions.custom)
assert(params.initializationOptions.detachedFiles[1] == project .. "/src/main.rs")
assert(params.initializationOptions.cargo.sysroot == vim.NIL)
assert(params.initializationOptions.checkOnSave == false)
assert(params.initializationOptions.procMacro.enable == false)
vim.fn.delete(project, "rf")
opts.servers.rust_analyzer.root_dir(0, function(value) root = value end)
assert(root == project .. "/src", "unmarked standalone Rust must use the file directory")
available.rustc, available.cargo = true, true
local workspace_root = function() return "workspace" end
local workspace_opts = { servers = { rust_analyzer = { root_dir = workspace_root } } }
configure(nil, workspace_opts)
assert(workspace_opts.servers.rust_analyzer.root_dir == workspace_root, "toolchain-enabled workspace policy must survive")
available.rustc, available.cargo = nil, nil
vim.fn.executable = original
print("Neovim explicit LSP selection and standalone/workspace Rust policy checks passed")

if arg[2] and vim.fn.isdirectory(arg[2]) == 1 then
  vim.opt.rtp:prepend(arg[2])
  local config = require("lazy.core.config")
  config.options = vim.deepcopy(config.defaults)
  local plugin = require("lazy.core.plugin")
  vim.fn.executable = function(command) return available[command] and 1 or 0 end
  local merged = plugin.Spec.new({
    { "neovim/nvim-lspconfig", dependencies = { "mason-org/mason.nvim", "mason-org/mason-lspconfig.nvim" }, opts = { servers = { basedpyright = { settings = { user_option = true } }, clangd = {} } } },
    { "mason-org/mason.nvim", opts = { ensure_installed = { "lua-language-server" } } },
    { "mrcjkb/rustaceanvim", opts = {} }, specs,
  }, { pkg = false })
  assert(merged.plugins["mason.nvim"] == nil and merged.plugins["mason-lspconfig.nvim"] == nil and merged.plugins.rustaceanvim == nil)
  local merged_opts = plugin.values(merged.plugins["nvim-lspconfig"], "opts", false)
  assert(merged_opts.servers.basedpyright.settings.user_option and merged_opts.servers.basedpyright.enabled)
  assert(merged_opts.servers.clangd == nil)
  vim.fn.executable = original
  print("lazy.nvim selected-server merge checks passed")
else print("SKIP: lazy.nvim specification merge check") end
