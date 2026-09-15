#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"
export XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache" XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME"; source "$ROOT/install.sh"; source "$ROOT/scripts/bare-env.sh"; node "$ROOT/scripts/state-helper.mjs" init; node "$ROOT/scripts/state-helper.mjs" ready
install_native_keys() { printf '%s\n' "$*" >>"$HOME/native"; }
bun() { printf '%s\n' "$*" >"$HOME/bun"; }
link_bare_codex_config() { touch "$HOME/codex-linked"; }
install_bare_optional tools zsh starship just codex
for value in zsh starship just codex; do node "$ROOT/scripts/state-helper.mjs" selections | grep -qx $'tools\t'"$value"; done
grep -q '^zsh$' "$HOME/native"; grep -q '^starship$' "$HOME/native"; grep -q '@openai/codex@0.153.4' "$HOME/bun"; [[ -f "$HOME/codex-linked" ]]
echo 'PASS tools remain explicit independent selections'
