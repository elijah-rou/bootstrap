#!/usr/bin/env bash
# Real tool writes stay in a disposable HOME; no native package manager is used.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d /tmp/bootstrap-toolchain.XXXXXX)"; trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/home/.config" XDG_STATE_HOME="$fixture/home/.local/state" XDG_DATA_HOME="$fixture/home/.local/share" XDG_CACHE_HOME="$fixture/home/.cache"
unset DOTFILES_BARE_ROOT BOOTSTRAP_PRIVATE_ROOT BOOTSTRAP_STATE_ROOT
mkdir -p "$HOME"
source "$ROOT/install.sh"; source "$ROOT/scripts/bare-env.sh"
bare_stage="$fixture/stage"; mkdir "$bare_stage"
node "$ROOT/scripts/state-helper.mjs" init
node "$ROOT/scripts/state-helper.mjs" enroll "$DOTFILES_BARE_ROOT"
node "$ROOT/scripts/state-helper.mjs" enroll "$BOOTSTRAP_PRIVATE_ROOT"
mkdir -p "$DOTFILES_BARE_ROOT/bin" "$BOOTSTRAP_PRIVATE_ROOT"
command -v uv >/dev/null || install_upstream_tool uv
install_upstream_tool python
[[ "$("$DOTFILES_BARE_ROOT/bin/python3" -c 'print(6*7)')" == 42 ]]
[[ "$(uv cache dir)" == "$UV_CACHE_DIR" && "$(uv tool dir)" == "$UV_TOOL_DIR" ]]
if command -v npm >/dev/null; then
    npm cache add is-number@7.0.0 --ignore-scripts --no-audit --no-fund
    [[ -d "$npm_config_cache/_cacache" ]]
fi
if command -v go >/dev/null; then
    enroll_go_telemetry
    [[ "$(go env GOCACHE)" == "$GOCACHE" && "$(go env GOMODCACHE)" == "$GOMODCACHE" && "$(go env GOENV)" == "$GOENV" ]]
    go env -w GOPRIVATE=fixture.invalid
    printf 'package main\nfunc main() {}\n' >"$fixture/main.go"
    GO111MODULE=off go build -o "$fixture/hello" "$fixture/main.go"
    [[ -f "$GOENV" && -d "$GOCACHE" ]]
    printf 'Go telemetry location: %s\n' "$(go env GOTELEMETRYDIR)"
fi
if [[ "${1:-}" == --elixirls ]]; then
    command -v elixir >/dev/null && command -v nvim >/dev/null
    started="$(date +%s)"
    install_bare_elixir_ls
    printf 'ElixirLS cold preparation: %ss\n' "$(( $(date +%s) - started ))"
    [[ -d "$MIX_HOME" && -d "$MIX_INSTALL_DIR" && -d "$HEX_HOME" ]]
    mix hex.config api_url https://hex.pm
    printf 'defmodule Main do\nend\n' >"$fixture/main.ex"
    cat >"$fixture/attach.lua" <<'LUA'
local started = vim.uv.hrtime()
local id = vim.lsp.start({ name = 'elixirls', cmd = { 'elixir-ls' }, root_dir = vim.fn.getcwd() })
assert(id, 'client did not start')
assert(vim.wait(20000, function()
  local client = vim.lsp.get_client_by_id(id)
  return client and client.initialized and vim.lsp.buf_is_attached(0, id)
end, 20), 'prepared ElixirLS did not attach within 20s')
local elapsed = (vim.uv.hrtime() - started) / 1e6
local client = assert(vim.lsp.get_client_by_id(id))
local response = client:request_sync('textDocument/documentSymbol', { textDocument = { uri = vim.uri_from_bufnr(0) } }, 5000)
assert(response and not response.err, 'documentSymbol failed')
print(string.format('ElixirLS prepared initialize/attach: %.0fms; documentSymbol answered', elapsed))
client:stop(true)
vim.cmd('qa!')
LUA
    (cd "$fixture"; node "$ROOT/scripts/run-bounded.mjs" 35 nvim --headless -u NONE -i NONE main.ex -l "$fixture/attach.lua")
fi
# Confirm known cache roots disappear and unrelated state remains.
for directory in "$npm_config_cache" "$UV_CACHE_DIR" "$MIX_HOME" "$MIX_INSTALL_DIR" "$HEX_HOME" "$GOCACHE" "$GOMODCACHE"; do
    mkdir -p "$directory"; printf sensitive >"$directory/sentinel"
done
printf unrelated >"$HOME/unrelated"
uninstall_bare --dry-run
uninstall_bare
[[ ! -e "$BOOTSTRAP_STATE_ROOT" && ! -e "$BOOTSTRAP_PRIVATE_ROOT" && ! -e "$DOTFILES_BARE_ROOT" && "$(cat "$HOME/unrelated")" == unrelated ]]
printf 'PASS real Python, npm/uv/Go cache writes and enrolled tool-state cleanup\n'
