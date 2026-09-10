local ok, failure = xpcall(function()
  local config = vim.fn.stdpath("config")
  vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")
  local lazy = require("lazy")
  local setup = lazy.setup
  local configured_lockfile
  lazy.setup = function(options)
    options.install = { missing = false }
    options.checker = { enabled = false }
    options.change_detection = { enabled = false }
    configured_lockfile = options.lockfile
    return setup(options)
  end

  dofile(config .. "/init.lua")
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
  assert(configured_lockfile == config .. "/lazy-lock.json", "plugin lock must stay in the writable runtime")
  assert(require("lazyvim.config").json.path == config .. "/lazyvim.json", "extras must use writable local state")
  local bundled_root = vim.fn.fnamemodify(vim.fn.resolve(config .. "/init.lua"), ":h")
  for _, name in ipairs({ "lazy-lock.json", "lazyvim.json", ".neoconf.json" }) do
    assert(vim.fn.filereadable(bundled_root .. "/" .. name) == 0, "seed JSON must stay outside the source runtime path")
  end
  assert(package.loaded["config.keymaps"], "bundled user keymaps were not loaded")
  assert(package.loaded["config.remote_clipboard"], "approved clipboard support was not loaded")
  assert(vim.fn.exists(":LeetcodeMode") == 2, "recovered LeetCode command is missing")
  local mapping = vim.fn.maparg("<Space><Space>", "n", false, true)
  assert(mapping.desc == "Find Files (Root Dir)")
  local picked
  local original_open = LazyVim.pick.picker.open
  LazyVim.pick.picker.open = function(command, options)
    picked = command
    assert(type(options.cwd) == "string", "file picker must retain root scope")
  end
  mapping.callback()
  LazyVim.pick.picker.open = original_open
  assert(picked == "files", "leader-space must invoke file search")
  local plugins = require("lazy.core.config").plugins
  if vim.g.bootstrap_neovim_profile == "bare" then
    assert(plugins["mason.nvim"] == nil, "bare must not activate Mason")
    assert(plugins["rustaceanvim"] == nil, "bare must retain PATH-based Rust LSP policy")
  else
    assert(plugins["mason.nvim"] ~= nil, "workstation must retain Mason policy")
  end
  print(
    "PASS managed " .. vim.g.bootstrap_neovim_profile .. " startup, recovered commands, writable lock, and file picker"
  )
  vim.cmd("qa!")
end, debug.traceback)
if not ok then
  print(failure)
  vim.cmd("cquit 1")
end
