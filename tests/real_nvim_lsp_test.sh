#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v nvim >/dev/null || { printf 'Neovim is required\n' >&2; exit 1; }
command -v basedpyright-langserver >/dev/null || { printf 'BasedPyright is required\n' >&2; exit 1; }
temporary="$(mktemp -d)"; trap 'rm -rf "$temporary"' EXIT
export HOME="$temporary/home"; export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"; unset NVIM_APPNAME
mkdir -p "$HOME" "$XDG_CONFIG_HOME/nvim" "$temporary/project/bin"
printf 'value: int = 1\n' >"$temporary/project/main.py"
printf '#!/bin/sh\ntouch "$UNSELECTED_MARKER"\nexit 99\n' >"$temporary/project/bin/clangd"; chmod +x "$temporary/project/bin/clangd"
cat >"$temporary/selection.json" <<'JSON'
{"schemaVersion":1,"servers":{"basedpyright":{"selector":"basedpyright","cmd":["basedpyright-langserver","--stdio"],"filetypes":["python"]}}}
JSON
cat >"$XDG_CONFIG_HOME/nvim/init.lua" <<'LUA'
local value = vim.json.decode(table.concat(vim.fn.readfile(assert(vim.env.BOOTSTRAP_LSP_SELECTIONS)), "\n"))
for server, selection in pairs(value.servers) do
  vim.api.nvim_create_autocmd("FileType", { pattern = selection.filetypes, callback = function()
    vim.lsp.start({ name = server, cmd = selection.cmd, root_dir = vim.fs.root(0, { ".git" }) or vim.fn.getcwd() })
  end })
end
LUA
export PATH="$temporary/project/bin:$PATH" BOOTSTRAP_LSP_SELECTIONS="$temporary/selection.json" BOOTSTRAP_EXPECTED_LSP=basedpyright BOOTSTRAP_LSP_RECEIPT="$temporary/receipt.json" UNSELECTED_MARKER="$temporary/unselected"
node "$ROOT/scripts/run-bounded.mjs" 40 nvim --headless -i NONE -u "$XDG_CONFIG_HOME/nvim/init.lua" "$temporary/project/main.py" '+set filetype=python' -l "$ROOT/neovim/verify-lsp.lua"
node -e 'const v=JSON.parse(require("node:fs").readFileSync(process.argv[1]));if(!v.initialized||!v.attached||!v.request)process.exit(1)' "$temporary/receipt.json"
[[ ! -e "$temporary/unselected" ]]
printf 'PASS real Neovim selected LSP initialized, attached, answered; unselected executable stayed inactive\n'
