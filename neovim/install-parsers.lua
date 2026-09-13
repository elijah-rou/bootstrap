local lazy_config = require("lazy.core.config")
local lazy_plugin = require("lazy.core.plugin")
local plugin = assert(lazy_config.plugins["nvim-treesitter"], "nvim-treesitter is not configured")
local options = lazy_plugin.values(plugin, "opts", false) or {}
local languages = options.ensure_installed or {}
assert(type(languages) == "table" and #languages > 0, "effective parser set is empty")
local task = require("nvim-treesitter").install(languages)
task:wait(300000)
for _, language in ipairs(languages) do
  assert(vim.list_contains(require("nvim-treesitter").get_installed(), language), "parser not installed: " .. language)
end
vim.fn.writefile(languages, assert(vim.env.BOOTSTRAP_PARSER_SET_RECEIPT))
vim.cmd("qa!")
