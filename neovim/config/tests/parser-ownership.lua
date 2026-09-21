local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.env.BOOTSTRAP_LSP_SELECTIONS = vim.fn.tempname()
local function treesitter_policy(repair)
  vim.g.bootstrap_neovim_repair = repair
  for _, spec in ipairs(dofile(root .. "/bootstrap.lua")) do
    if spec[1] == "nvim-treesitter/nvim-treesitter" then return spec end
  end
  error("parser ownership policy is missing")
end
local ordinary = treesitter_policy(false)
assert(ordinary.build == nil and ordinary.opts == nil, "ordinary editor behavior must remain unchanged")
local repair = treesitter_policy(true)
assert(repair.build == false, "plugin repair must not launch parser builds")
local languages = { "lua", "bash", "python" }
local options = { ensure_installed = languages, highlight = { enable = true } }
repair.opts(nil, options)
assert(#options.ensure_installed == 0, "LazyVim must not start a second parser installer")
assert(vim.deep_equal(options._bootstrap_ensure_installed, languages), "the explicit installer must retain the effective parser set")
assert(options.highlight.enable, "unrelated options must survive")
print("PASS repair has one parser writer and preserves ordinary editor options")
