local ok, failure = xpcall(function()
  local languages = vim.fn.readfile(assert(vim.env.BOOTSTRAP_PARSER_SET_RECEIPT))
  assert(#languages > 0, 'missing effective parser set')
  local receipt = {}
  for _, language in ipairs(languages) do
    local info = assert(require('nvim-treesitter.parsers')[language], 'unknown parser: ' .. language)
    if info.install_info then
      assert(vim.treesitter.language.add(language), 'parser did not load: ' .. language)
      local parser = assert(vim.treesitter.get_string_parser('', language))
      assert(parser:parse(true)[1], 'parser returned no tree: ' .. language)
    end
    -- Some injection-only grammars have no highlights; compile every shipped query.
    for _, kind in ipairs({ 'highlights', 'injections', 'folds', 'locals', 'indents' }) do
      if info.install_info then vim.treesitter.query.get(language, kind) end
    end
    receipt[#receipt + 1] = (info.install_info and 'parser=' or 'queries=') .. language
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(assert(vim.env.BOOTSTRAP_PARSER_FIXTURE)))
  vim.bo.filetype = 'lua'
  assert(vim.treesitter.get_parser(0, 'lua'):parse(true)[1])
  assert(vim.treesitter.query.get('lua', 'highlights'), 'Lua highlight query unavailable')
  vim.treesitter.start(0, 'lua')
  assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'highlighter did not start')
  vim.wo.foldmethod = 'expr'
  vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
  vim.cmd('normal! zx')
  assert(vim.fn.foldlevel(2) > 0, 'Tree-sitter fixture did not produce a fold')
  vim.list_extend(receipt, { 'highlight=true', 'fold=true' })
  vim.fn.writefile(receipt, assert(vim.env.BOOTSTRAP_PARSER_RECEIPT))
end, debug.traceback)
if not ok then print(failure); vim.cmd('cquit 1') end
vim.cmd('qa!')
