#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
lazy_path="${NVIM_LAZY_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim}"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state"
export DOTFILES_DIR="$ROOT" NVIM_CONFIG_CHECKOUT_DIR="$tmp/checkout"
mkdir -p "$HOME" "$tmp/upstream/lua/config"
printf 'return {}\n' > "$tmp/upstream/init.lua"
printf 'return {}\n' > "$tmp/upstream/lua/config/lazy.lua"
git -C "$tmp/upstream" init -q
git -C "$tmp/upstream" add .
git -C "$tmp/upstream" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
export NVIM_CONFIG_REPO_URL="$tmp/upstream"
info() { :; }
warn() { printf '%s\n' "$*" >&2; }
source "$ROOT/scripts/lib/install/managed-files.sh"
source "$ROOT/scripts/lib/install/configuration.sh"
setup_neovim_config
plugin="$NVIM_CONFIG_CHECKOUT_DIR/lua/plugins/zz-bootstrap-managed.lua"
[[ -L "$plugin" && -L "$XDG_CONFIG_HOME/nvim" ]]
[[ -z "$(git -C "$NVIM_CONFIG_CHECKOUT_DIR" status --porcelain)" ]]
setup_neovim_config
[[ "$(grep -cxF '/lua/plugins/zz-bootstrap-managed.lua' "$NVIM_CONFIG_CHECKOUT_DIR/.git/info/exclude")" == 1 ]]
# A new upstream commit must still fast-forward after materialization.
printf '\n' >> "$tmp/upstream/init.lua"
git -C "$tmp/upstream" -c user.name=Test -c user.email=test@example.invalid commit -qam update
setup_neovim_config
[[ "$(git -C "$NVIM_CONFIG_CHECKOUT_DIR" rev-parse HEAD)" == "$(git -C "$tmp/upstream" rev-parse HEAD)" ]]
rm "$plugin"
printf 'user configuration\n' > "$plugin"
DOTFILES_RELINK_ONLY=1 setup_neovim_config
[[ -L "$plugin" ]]
grep -qxF 'user configuration' "$XDG_STATE_HOME"/bootstrap/neovim-backups/*
[[ -z "$(git -C "$NVIM_CONFIG_CHECKOUT_DIR" status --porcelain)" ]]
# An ignored path tracked by the user is not installer-owned.
rm "$plugin"
printf 'tracked configuration\n' > "$plugin"
git -C "$NVIM_CONFIG_CHECKOUT_DIR" add -f "$plugin"
if DOTFILES_RELINK_ONLY=1 setup_neovim_config; then
    printf 'Tracked collision was accepted\n' >&2
    exit 1
fi
grep -qxF 'tracked configuration' "$plugin"
mkdir "$NVIM_CONFIG_CHECKOUT_DIR.install.lock"
if DOTFILES_RELINK_ONLY=1 setup_neovim_config; then
    printf 'Concurrent setup was accepted\n' >&2
    exit 1
fi
rmdir "$NVIM_CONFIG_CHECKOUT_DIR.install.lock"
if command -v nvim >/dev/null; then
    nvim --headless -u NONE -i NONE -l "$ROOT/tests/neovim_config_test.lua" "$ROOT/neovim/bootstrap.lua" "$lazy_path"
else
    printf 'SKIP: Neovim Lua consumer check (nvim unavailable)\n'
fi
printf 'Neovim configuration checks passed\n'
