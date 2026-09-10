if vim.g.bootstrap_neovim_profile ~= "bare" then
  return {}
end

local module_path = assert(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)))
local root = vim.fn.fnamemodify(module_path, ":h:h:h:h")
return dofile(root .. "/bootstrap.lua")
