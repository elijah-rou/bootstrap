vim.opt.runtimepath:prepend(vim.fn.getcwd())
local clipboard = require("config.remote_clipboard")
local emitted, copied, pasted = {}, {}, {}
local original = {
  readfile = vim.fn.readfile,
  executable = vim.fn.executable,
  system = vim.fn.system,
  systemlist = vim.fn.systemlist,
  getpid = vim.fn.getpid,
}
local wayland = false
local proc_reads = 0
local parent_is_herdr = false
vim.fn.getpid = function()
  return 10
end
vim.fn.readfile = function(path)
  proc_reads = proc_reads + 1
  if parent_is_herdr and path == "/proc/10/status" then
    return { "PPid:\t9" }
  end
  if parent_is_herdr and path == "/proc/9/comm" then
    return { "herdr" }
  end
  error("procfs is unavailable")
end
vim.fn.executable = function(command)
  return wayland and (command == "wl-copy" or command == "wl-paste") and 1 or 0
end
vim.fn.system = function(command, lines)
  copied[#copied + 1] = { command = command, lines = lines }
  return ""
end
vim.fn.systemlist = function(command)
  pasted[#pasted + 1] = command
  return { "local paste" }
end
package.loaded["vim.ui.clipboard.osc52"] = {
  copy = function(register)
    return function(lines)
      emitted[#emitted + 1] = { register = register, lines = lines }
    end
  end,
  paste = function(register)
    return function()
      return { "remote paste " .. register }
    end
  end,
}
for _, name in ipairs({ "TMUX", "SSH_TTY", "SSH_CONNECTION", "HERDR_PANE_ID", "WAYLAND_DISPLAY" }) do
  vim.env[name] = nil
end
vim.g.clipboard = "unchanged"
clipboard.setup()
assert(vim.g.clipboard == "unchanged", "local sessions must keep their existing clipboard")
assert(proc_reads <= 16, "ancestor detection must remain bounded without procfs")

for _, context in ipairs({ "TMUX", "SSH_TTY", "SSH_CONNECTION", "HERDR_PANE_ID" }) do
  vim.env[context] = "fixture"
  clipboard.setup()
  local provider = vim.g.clipboard
  local count = #emitted
  provider.copy["+"]({ "remote text" })
  assert(#emitted == count + 1)
  assert(emitted[#emitted].register == "+")
  assert(provider.paste["+"]()[1] == "remote paste +")
  vim.env[context] = nil
end
parent_is_herdr = true
clipboard.setup()
assert(type(vim.g.clipboard) == "table", "Herdr ancestors activate the remote clipboard")
parent_is_herdr = false

vim.env.TMUX = "fixture"
vim.env.WAYLAND_DISPLAY = "fixture"
wayland = true
clipboard.setup()
local provider = vim.g.clipboard
provider.copy["*"]({ "local and remote" })
assert(vim.deep_equal(copied[#copied].command, { "wl-copy", "--sensitive", "--type", "text/plain", "--primary" }))
assert(emitted[#emitted].register == "*")
assert(provider.paste["*"]()[1] == "local paste")
assert(vim.deep_equal(pasted[#pasted], { "wl-paste", "--no-newline", "--primary" }))
vim.g.omarchy_remote_clipboard_osc52 = false
local count = #emitted
provider.copy["+"]({ "local only" })
assert(#emitted == count, "explicit OSC 52 opt-out must be honored")
for name, callback in pairs(original) do
  vim.fn[name] = callback
end
print("PASS clipboard stays local by default and supports remote contexts with and without Wayland/procfs")
