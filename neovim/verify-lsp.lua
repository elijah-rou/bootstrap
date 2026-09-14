local client, request_id
local ok, failure = xpcall(function()
  assert(vim.v.errmsg == '', 'Neovim startup error: ' .. vim.v.errmsg)
  local expected = assert(vim.env.BOOTSTRAP_EXPECTED_LSP, 'missing expected LSP')
  local receipt = assert(vim.env.BOOTSTRAP_LSP_RECEIPT, 'missing receipt path')
  local path = vim.env.BOOTSTRAP_LSP_SELECTIONS or (vim.fn.stdpath('config') .. '/lsp-selections.json')
  local selected = vim.json.decode(table.concat(vim.fn.readfile(path), '\n')).servers[expected]
  assert(selected and type(selected.verification) == 'table' and vim.tbl_count(selected.verification) == 1, 'invalid verification policy')
  local method = assert(selected.verification.method, 'missing verification policy')
  assert(method == 'textDocument/documentSymbol' or method == 'textDocument/diagnostic' or method == 'workspace/symbol', 'unsupported verification method')
  local detected = vim.filetype.match({ buf = 0, filename = vim.api.nvim_buf_get_name(0) })
  if detected and vim.bo.filetype == '' then vim.bo.filetype = detected end
  vim.cmd('doautocmd FileType')
  assert(vim.wait(20000, function()
    for _, attached in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
      if attached.name == expected and attached.initialized then client = attached; return true end
    end
    return false
  end, 50), 'selected LSP did not initialize and attach: ' .. expected)
  assert(client:supports_method(method, 0), 'selected LSP does not support ' .. method)
  local answered, response_error, result = false, nil, nil
  local sent
  local params = method == 'workspace/symbol' and { query = '' } or { textDocument = { uri = vim.uri_from_bufnr(0) } }
  if method == 'textDocument/diagnostic' then
    local provider = client.server_capabilities.diagnosticProvider
    if type(provider) == 'table' and provider.identifier then params.identifier = provider.identifier end
  end
  sent, request_id = client:request(method, params, function(err, response)
    response_error, result, answered = err, response, true
  end, 0)
  assert(sent, 'selected LSP refused request')
  assert(vim.wait(10000, function() return answered end, 50), 'selected LSP request timed out')
  assert(response_error == nil, 'selected LSP request failed: ' .. vim.inspect(response_error))
  if method == 'textDocument/diagnostic' then
    assert(type(result) == 'table' and result.kind == 'full' and type(result.items) == 'table', 'invalid diagnostic report')
  else
    assert(result == nil or result == vim.NIL or (type(result) == 'table' and vim.islist(result)), 'invalid document symbols')
  end
  vim.fn.writefile({ vim.json.encode({ server = expected, initialized = true, attached = true, request = true, method = method }) }, receipt)
end, debug.traceback)
if client then
  if not ok and request_id then client:cancel_request(request_id) end
  client:stop(true)
end
if not ok then print(failure); vim.cmd('cquit 1') end
vim.cmd('qa!')
