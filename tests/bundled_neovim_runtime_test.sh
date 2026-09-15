#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT/tests/bundled_neovim_repair_test.sh"
temporary="$(mktemp -d)"
temporary="$(cd "$temporary" && pwd -P)"
trap 'rm -rf "$temporary"' EXIT
source "$ROOT/tests/bundled_neovim_fixture.sh"
prepare_bundled_neovim_fixture "$temporary"
mkdir -p "$XDG_DATA_HOME/nvim"
ln -s "$XDG_DATA_HOME/bootstrap-nvim/lazy" "$XDG_DATA_HOME/nvim/lazy"
[[ ! -d "$XDG_DATA_HOME/bootstrap-nvim/site" ]] || ln -s "$XDG_DATA_HOME/bootstrap-nvim/site" "$XDG_DATA_HOME/nvim/site"
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
