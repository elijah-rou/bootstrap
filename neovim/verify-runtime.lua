local ok, failure = xpcall(function()
  assert(vim.v.errmsg == '', 'startup error: ' .. vim.v.errmsg)
  local expected = assert(vim.env.BOOTSTRAP_EXPECTED_NVIM_PROFILE)
  if expected ~= 'external' then
    assert(vim.g.bootstrap_neovim_profile == expected, 'wrong or absent bundled profile')
    assert(package.loaded['config.lazy'], 'bundled LazyVim configuration did not load')
    assert(require('lazy.core.config').plugins['LazyVim'], 'LazyVim is not configured')
    vim.api.nvim_exec_autocmds('User', { pattern = 'VeryLazy' })
    assert(package.loaded['config.keymaps'], 'bundled keymaps did not load')
    assert(vim.fn.exists(':LeetcodeMode') == 2, 'bundled command missing')
  end
  assert(vim.v.errmsg == '', 'configuration error: ' .. vim.v.errmsg)
  vim.fn.writefile({ expected }, assert(vim.env.BOOTSTRAP_NVIM_RECEIPT))
end, debug.traceback)
if not ok then print(failure); vim.cmd('cquit 1') end
vim.cmd('qa!')
