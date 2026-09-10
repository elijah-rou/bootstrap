vim.g.mapleader = " "

local picked = nil
local scratch_calls = 0
_G.LazyVim = {
  pick = function(source)
    return function()
      picked = source
    end
  end,
}
vim.keymap.set("n", "<leader><space>", function()
  scratch_calls = scratch_calls + 1
end, { desc = "Toggle Scratch Buffer" })

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local keymaps = root .. "/lua/config/keymaps.lua"
if vim.fn.filereadable(keymaps) == 1 then
  dofile(keymaps)
end
local mapping = vim.fn.maparg("<Space><Space>", "n", false, true)
assert(mapping.desc == "Find Files (Root Dir)", vim.inspect(mapping))
assert(type(mapping.callback) == "function", "file picker callback is missing")
mapping.callback()
assert(picked == "files", "leader-space must invoke the configured file picker")
assert(scratch_calls == 0, "leader-space must not invoke scratch")
print("PASS leader-space overrides scratch with the file picker")
