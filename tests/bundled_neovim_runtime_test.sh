#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_root="${NVIM_PLUGIN_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy}"
site_root="${NVIM_SITE_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site}"
[[ -d "$plugin_root/lazy.nvim" && -d "$plugin_root/LazyVim" ]] || { printf 'Installed LazyVim plugins are required\n' >&2; exit 1; }
temporary="$(mktemp -d)"
temporary="$(cd "$temporary" && pwd -P)"
trap 'rm -rf "$temporary"' EXIT
export HOME="$temporary/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state"
unset NVIM_CONFIG_REPO_URL NVIM_CONFIG_CHECKOUT_DIR
export NVIM_LEETCODE_MODE=0
mkdir -p "$HOME" "$XDG_DATA_HOME/nvim" "$XDG_DATA_HOME/bootstrap-nvim"
ln -s "$plugin_root" "$XDG_DATA_HOME/nvim/lazy"
ln -s "$plugin_root" "$XDG_DATA_HOME/bootstrap-nvim/lazy"
[[ ! -d "$site_root" ]] || { ln -s "$site_root" "$XDG_DATA_HOME/nvim/site"; ln -s "$site_root" "$XDG_DATA_HOME/bootstrap-nvim/site"; }
cp "$ROOT/neovim/defaults/lazy-lock.json" "$temporary/source-lock"
cp "$ROOT/neovim/defaults/lazyvim.json" "$temporary/source-extras"
export NVIM_APPNAME=bootstrap-nvim
for profile in workstation bare; do
    if [[ "$profile" == workstation ]]; then
        bash "$ROOT/configure.sh" neovim
    else
        bash "$ROOT/install.sh" link
    fi
    nvim --headless -i NONE -u "$ROOT/neovim/config/tests/managed-startup.lua"
done
cmp "$temporary/source-lock" "$ROOT/neovim/defaults/lazy-lock.json"
cmp "$temporary/source-extras" "$ROOT/neovim/defaults/lazyvim.json"
unset NVIM_APPNAME
export TMPDIR="$temporary/tmp"; mkdir -p "$TMPDIR"
cd "$ROOT/neovim/config"
NVIM_BUNDLED_RUNTIME=1 nvim --headless -u NONE -i NONE -l tests/leetcode_mode.lua
