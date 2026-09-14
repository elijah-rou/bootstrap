local ok, failure = xpcall(function()
  -- Repair uses the effective lock as input, never as generated update output.
  vim.g.bootstrap_neovim_repair = true
  vim.opt.loadplugins = true
  dofile(assert(vim.env.BOOTSTRAP_NVIM_INIT))
  local config = require('lazy.core.config')
  local lockfile = config.options.lockfile
  local bytes = table.concat(vim.fn.readfile(lockfile, 'b'), '\n')
  local lock = vim.json.decode(bytes)
  assert(type(lock) == 'table', 'invalid effective plugin lock')
  require('lazy.manage.lock').update = function() end
  local manager = require('lazy.manage')
  manager.install({ wait = true, show = false, lockfile = true })
  for name, plugin in pairs(config.plugins) do
    for _, task in ipairs(plugin._.tasks or {}) do
      assert(not task:has_errors(), 'plugin installation failed: ' .. name)
    end
  end
  local locked_plugins = {}
  for name in pairs(config.plugins) do
    if lock[name] then locked_plugins[#locked_plugins + 1] = name end
  end
  manager.restore({ wait = true, show = false, plugins = locked_plugins })
  for name, plugin in pairs(config.plugins) do
    for _, task in ipairs(plugin._.tasks or {}) do
      assert(not task:has_errors(), 'plugin repair failed: ' .. name)
    end
    assert(plugin._.installed, 'plugin missing: ' .. name)
    if lock[name] and not plugin._.is_local then
      local info = assert(require('lazy.manage.git').info(plugin.dir))
      assert(info.commit == lock[name].commit, 'plugin revision mismatch: ' .. name)
    end
  end
  assert(bytes == table.concat(vim.fn.readfile(lockfile, 'b'), '\n'), 'repair changed the effective lock')
  vim.fn.writefile({ 'plugins=restored' }, assert(vim.env.BOOTSTRAP_PLUGIN_RECEIPT))
end, debug.traceback)
if not ok then print(failure); vim.cmd('cquit 1') end
vim.cmd('qa!')
