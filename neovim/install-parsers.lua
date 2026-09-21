local ok, failure = xpcall(function()
  vim.g.bootstrap_neovim_repair = true
  vim.opt.loadplugins = true
  dofile(assert(vim.env.BOOTSTRAP_NVIM_INIT))
  local lazy_config = require('lazy.core.config')
  local plugin = assert(lazy_config.plugins['nvim-treesitter'], 'nvim-treesitter is not configured')
  local options = require('lazy.core.plugin').values(plugin, 'opts', false) or {}
  local configured = options._bootstrap_ensure_installed or options.ensure_installed or {}
  assert(type(configured) == 'table' and #configured > 0, 'effective parser set is empty')
  local config = require('nvim-treesitter.config')
  local languages = config.norm_languages(configured)
  assert(#languages > 0, 'no supported parsers configured')
  local ts = require('nvim-treesitter')
  local parsers = require('nvim-treesitter.parsers')
  local missing = {}
  for _, language in ipairs(languages) do
    assert(parsers[language], 'unknown configured parser: ' .. language)
    if parsers[language].install_info and vim.fn.filereadable(config.get_install_dir('parser') .. '/' .. language .. '.so') == 0 then
      missing[#missing + 1] = language
    end
  end
  -- Upstream's installed set includes query directories even if the library is missing.
  if #missing > 0 then assert(ts.install(missing, { force = true, max_jobs = 2 }):wait(300000), 'missing parser installation failed') end
  assert(ts.install(languages, { max_jobs = 2 }):wait(300000), 'parser installation failed')
  assert(ts.update(languages, { max_jobs = 2 }):wait(300000), 'parser revision reconciliation failed')
  parsers = require('nvim-treesitter.parsers')
  for _, language in ipairs(languages) do
    local info = parsers[language].install_info
    if info and info.revision then
      local revision = table.concat(vim.fn.readfile(config.get_install_dir('parser-info') .. '/' .. language .. '.revision'), '\n')
      assert(revision == info.revision, 'parser revision mismatch: ' .. language)
    end
    if info then
      -- Runtime lookup can cache the absent site directory during first startup.
      -- The separate fresh-process verifier checks ordinary runtime discovery.
      local library = { path = config.get_install_dir('parser') .. '/' .. language .. '.so' }
      local loaded, result = pcall(vim.treesitter.language.add, language, library)
      if not loaded or not result then
        assert(ts.install({ language }, { force = true, max_jobs = 2 }):wait(300000), 'incompatible parser repair failed: ' .. language)
        assert(vim.treesitter.language.add(language, library), 'parser did not load after repair: ' .. language)
      end
    end
  end
  table.sort(languages)
  vim.fn.writefile(languages, assert(vim.env.BOOTSTRAP_PARSER_SET_RECEIPT))
end, debug.traceback)
if not ok then io.stderr:write(tostring(failure), '\n'); vim.cmd('cquit 1') end
vim.cmd('qa!')
