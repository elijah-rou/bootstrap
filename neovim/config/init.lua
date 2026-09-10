local entrypoint = assert(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)))
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(entrypoint, ":h"))

local profile_path = vim.fn.stdpath("config") .. "/bootstrap-profile.json"
assert(vim.fn.filereadable(profile_path) == 1, "Missing bootstrap Neovim profile; rerun configuration")
local profile = vim.json.decode(table.concat(vim.fn.readfile(profile_path), "\n"))
assert(type(profile) == "table" and vim.tbl_count(profile) == 2, "Invalid bootstrap Neovim profile fields")
assert(profile.version == 1, "Invalid bootstrap Neovim profile version")
assert(profile.profile == "bare" or profile.profile == "workstation", "Unknown bootstrap Neovim profile")
vim.g.bootstrap_neovim_profile = profile.profile

local leetcode = require("config.leetcode")

if leetcode.enabled() then
  vim.opt.loadplugins = false
  leetcode.setup()
else
  leetcode.register_command()
  require("config.lazy")
end
