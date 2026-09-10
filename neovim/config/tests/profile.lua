local root = vim.fn.getcwd()
for _, path in ipairs(vim.fn.globpath(root, "**/*.lua", false, true)) do
  local chunk, error_message = loadfile(path)
  assert(chunk, error_message)
end
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local original_stdpath = vim.fn.stdpath
vim.fn.stdpath = function(kind)
  if kind == "config" then
    return temporary
  end
  return original_stdpath(kind)
end
package.preload["config.lazy"] = function()
  return {}
end
vim.env.NVIM_LEETCODE_MODE = "0"
assert(not pcall(dofile, root .. "/init.lua"), "missing profile must not silently enable workstation behavior")
for _, profile in ipairs({ "bare", "workstation" }) do
  vim.fn.writefile({ vim.json.encode({ version = 1, profile = profile }) }, temporary .. "/bootstrap-profile.json")
  dofile(root .. "/init.lua")
  assert(vim.g.bootstrap_neovim_profile == profile)
end
for _, contents in ipairs({
  "null",
  "[]",
  "{}",
  "{invalid",
  '{"version":true,"profile":"bare"}',
  '{"version":2,"profile":"bare"}',
  '{"version":1,"profile":"unknown"}',
  '{"version":1,"profile":"bare","extra":true}',
}) do
  vim.fn.writefile({ contents }, temporary .. "/bootstrap-profile.json")
  assert(not pcall(dofile, root .. "/init.lua"), "invalid runtime profile was accepted: " .. contents)
end
vim.fn.stdpath = original_stdpath
vim.fn.delete(temporary, "rf")
print("PASS bundled entrypoint validates profiles before loading plugins")
