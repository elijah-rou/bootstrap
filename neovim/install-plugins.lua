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
  -- Loading a newly installed spec can reveal another layer of dependencies.
  for pass = 1, 8 do
    manager.install({ wait = true, show = false, lockfile = true })
    local locked_plugins = {}
    for name, plugin in pairs(config.plugins) do
      for _, task in ipairs(plugin._.tasks or {}) do
        assert(not task:has_errors(), 'plugin installation failed: ' .. name)
      end
      if lock[name] and plugin._.installed then locked_plugins[#locked_plugins + 1] = name end
    end
    manager.restore({ wait = true, show = false, plugins = locked_plugins })
    local missing = {}
    for name, plugin in pairs(config.plugins) do
      for _, task in ipairs(plugin._.tasks or {}) do
        assert(not task:has_errors(), 'plugin repair failed: ' .. name)
      end
      if not plugin._.installed then
        missing[#missing + 1] = name
      elseif lock[name] and not plugin._.is_local then
        local info = assert(require('lazy.manage.git').info(plugin.dir))
        assert(info.commit == lock[name].commit, 'plugin revision mismatch: ' .. name)
      end
    end
    if #missing == 0 then break end
    assert(pass < 8, 'plugin dependency discovery did not converge: ' .. table.concat(missing, ', '))
  end
  assert(bytes == table.concat(vim.fn.readfile(lockfile, 'b'), '\n'), 'repair changed the effective lock')
  vim.fn.writefile({ 'plugins=restored' }, assert(vim.env.BOOTSTRAP_PLUGIN_RECEIPT))
end, debug.traceback)
if not ok then print(failure); vim.cmd('cquit 1') end
vim.cmd('qa!')
