-- Bootstrap lazy.nvim
local module_path = assert(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)))
local config_root = vim.fn.fnamemodify(module_path, ":h:h:h")
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local missing = not (vim.uv or vim.loop).fs_stat(lazypath)
if missing then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    if not vim.g.bootstrap_neovim_repair then vim.fn.getchar() end
    os.exit(1)
  end
end
if missing or vim.g.bootstrap_neovim_repair then
  local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
  if vim.fn.filereadable(lockfile) == 1 then
    local lock = vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
    local selected = lock["lazy.nvim"]
    if selected then
      assert(type(selected) == "table", "invalid lazy.nvim lock entry")
      assert(type(selected.commit) == "string", "missing lazy.nvim lock revision")
      assert(#selected.commit == 40 and selected.commit:match("^%x+$"), "invalid lazy.nvim lock revision")
      local out = vim.fn.system({ "git", "-C", lazypath, "checkout", "--detach", selected.commit })
      assert(vim.v.shell_error == 0, "Failed to restore lazy.nvim before loading it: " .. out)
    end
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
  install = { missing = not vim.g.bootstrap_neovim_repair },
  checker = { enabled = not vim.g.bootstrap_neovim_repair },
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
