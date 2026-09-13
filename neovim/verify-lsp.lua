local expected = assert(vim.env.BOOTSTRAP_EXPECTED_LSP, "missing expected LSP")
local receipt = assert(vim.env.BOOTSTRAP_LSP_RECEIPT, "missing receipt path")
local detected = vim.filetype.match({ buf = 0, filename = vim.api.nvim_buf_get_name(0) })
if detected and vim.bo.filetype == "" then vim.bo.filetype = detected end
vim.cmd("doautocmd FileType")
local attached
local ok = vim.wait(20000, function()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.name == expected and client.initialized then attached = client; return true end
  end
  return false
end, 50)
if not ok or not attached then
  local path = vim.lsp.log.get_filename()
  local detail = vim.fn.filereadable(path) == 1 and table.concat(vim.fn.readfile(path), "\n") or "no LSP log"
  error("selected LSP did not initialize and attach: " .. expected .. "\n" .. detail)
end
local response_ok = false
attached:request("workspace/symbol", { query = "" }, function(error, _)
  assert(error == nil or type(error) == "table", "malformed LSP response")
  response_ok = true
end, 0)
assert(vim.wait(10000, function() return response_ok end, 50), "selected LSP did not answer a request")
vim.fn.writefile({ vim.json.encode({ server = expected, initialized = true, attached = true, request = true }) }, receipt)
vim.cmd("qa!")
