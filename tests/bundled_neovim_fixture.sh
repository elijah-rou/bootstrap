#!/usr/bin/env bash
# Call before changing HOME. All plugin and parser writes stay in the disposable copy.
prepare_bundled_neovim_fixture() {
    local temporary="$1" plugin_root="${NVIM_PLUGIN_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy}" site_root="${NVIM_SITE_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site}"
    [[ -d "$plugin_root/lazy.nvim" && -d "$plugin_root/LazyVim" ]] || { printf 'Installed LazyVim plugin cache required\n' >&2; return 1; }
    export HOME="$temporary/home" NVIM_APPNAME=bootstrap-nvim NVIM_LEETCODE_MODE=0
    export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
    export DOTFILES_DIR="$ROOT" BOOTSTRAP_PRIVATE_ROOT="$XDG_DATA_HOME/bootstrap/private" BOOTSTRAP_STATE_ROOT="$XDG_STATE_HOME/bootstrap"
    unset NVIM_CONFIG_REPO_URL NVIM_CONFIG_CHECKOUT_DIR BOOTSTRAP_LSP_SELECTIONS BOOTSTRAP_NEOVIM_PROFILE
    mkdir -p "$XDG_DATA_HOME/bootstrap-nvim/lazy" "$BOOTSTRAP_STATE_ROOT"
    cp -R "$plugin_root/." "$XDG_DATA_HOME/bootstrap-nvim/lazy/"
    if [[ -d "$site_root" ]]; then
        mkdir -p "$XDG_DATA_HOME/bootstrap-nvim/site"
        cp -R "$site_root/." "$XDG_DATA_HOME/bootstrap-nvim/site/"
        for directory in parser parser-info; do
            [[ ! -d "$site_root/$directory" ]] || {
                rm -rf "$XDG_DATA_HOME/bootstrap-nvim/site/$directory"
                cp -RL "$site_root/$directory" "$XDG_DATA_HOME/bootstrap-nvim/site/$directory"
            }
        done
    fi
    node - "$XDG_DATA_HOME/bootstrap-nvim" <<'JS'
const fs = require('node:fs'); const path = require('node:path'); const root = process.argv[2];
const queries = `${root}/site/queries`;
if (fs.existsSync(queries)) for (const name of fs.readdirSync(queries)) {
  const file = path.join(queries, name);
  if (!fs.lstatSync(file).isSymbolicLink()) continue;
  const target = fs.readlinkSync(file); const marker = '/nvim-treesitter/runtime/queries/';
  if (target.includes(marker)) {
    fs.unlinkSync(file); fs.symlinkSync(`${root}/lazy/nvim-treesitter/runtime/queries/${target.split(marker)[1]}`, file);
  }
}
JS
    node - "$ROOT/neovim/defaults/lazy-lock.json" "$XDG_DATA_HOME/bootstrap-nvim/lazy" <<'JS'
const fs = require('node:fs'); const cp = require('node:child_process');
const [lock, root] = process.argv.slice(2);
for (const [name, value] of Object.entries(JSON.parse(fs.readFileSync(lock)))) {
  if (!fs.existsSync(`${root}/${name}/.git`)) continue;
  cp.execFileSync('git', ['-C', `${root}/${name}`, 'checkout', '--detach', value.commit], {stdio:'pipe'});
}
JS
    bash "$ROOT/configure.sh" neovim
}
