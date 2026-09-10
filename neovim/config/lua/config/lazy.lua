-- Bootstrap lazy.nvim
local module_path = assert(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)))
local config_root = vim.fn.fnamemodify(module_path, ":h:h:h")
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false, -- always use the latest git commit
  },
  checker = { enabled = true }, -- automatically check for plugin updates
  performance = {
    cache = {
      enabled = true,
    },
    reset_packpath = true,
    rtp = {
      paths = { config_root },
      disabled_plugins = {},
    },
  },
})
