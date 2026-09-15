#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"
export XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache" XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME"; source "$ROOT/install.sh"; source "$ROOT/scripts/bare-env.sh"; node "$ROOT/scripts/state-helper.mjs" init; node "$ROOT/scripts/state-helper.mjs" ready
install_native_keys() { printf '%s\n' "$*" >>"$HOME/native"; }
install_bare_rust() { touch "$HOME/rust"; }
bun() { printf '%s\n' "$*" >>"$HOME/bun"; }
install_bare_optional languages c rust typescript
node "$ROOT/scripts/state-helper.mjs" selections | grep -qx $'languages\tc'
node "$ROOT/scripts/state-helper.mjs" selections | grep -qx $'languages\trust'
node "$ROOT/scripts/state-helper.mjs" selections | grep -qx $'languages\ttypescript'
[[ -f "$HOME/rust" ]] && grep -q 'compiler make pkg-config' "$HOME/native" && grep -q 'typescript@6.0.2' "$HOME/bun"
if node "$ROOT/scripts/state-helper.mjs" selections | grep -q '^lsp'; then exit 1; fi
install_bare_optional languages python
if node "$ROOT/scripts/state-helper.mjs" selections | grep -q basedpyright; then exit 1; fi
echo 'PASS languages persist independently without LSP selection'
