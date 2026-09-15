#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fixture="$(mktemp -d)"; fixture="$(cd "$fixture" && pwd -P)"; trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"; export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"; mkdir -p "$HOME"
source "$ROOT/install.sh"; source "$ROOT/scripts/bare-env.sh"
node "$ROOT/scripts/state-helper.mjs" init
original="$HOME/.bashrc"; printf 'original\n' >"$original"; link_managed_file "$ROOT/bashrc" "$original"
mkdir -p "$BOOTSTRAP_PRIVATE_ROOT/credentials"; printf secret >"$BOOTSTRAP_PRIVATE_ROOT/credentials/auth.json"; node "$ROOT/scripts/state-helper.mjs" enroll "$BOOTSTRAP_PRIVATE_ROOT"
node "$ROOT/scripts/state-helper.mjs" package apt bootstrap-added 0 absent installed; node "$ROOT/scripts/state-helper.mjs" component-begin core; node "$ROOT/scripts/state-helper.mjs" component-ready core; node "$ROOT/scripts/state-helper.mjs" ready
printf installed >"$HOME/package-present"
dpkg-query() { [[ ! -f "$HOME/package-present" ]] || printf 'bootstrap-added\tinstall ok installed\n'; return 0; }
apt-get() { [[ "$*" == '--simulate remove bootstrap-added' ]] || return 99; printf 'Remv bootstrap-added [1]\n'; }
dpkg() { [[ "$*" == '--remove -- bootstrap-added' ]] || return 99; printf 'apt bootstrap-added\n' >>"$HOME/removed"; rm "$HOME/package-present"; }
native_privileged() { "$@"; }
ps() { return 0; }
export -f dpkg-query apt-get dpkg ps
uninstall_bare --dry-run >/dev/null
[[ -f "$BOOTSTRAP_PRIVATE_ROOT/credentials/auth.json" && -L "$original" && ! -e "$HOME/removed" ]]
uninstall_bare
[[ ! -e "$BOOTSTRAP_PRIVATE_ROOT" && ! -L "$original" && "$(cat "$original")" == original ]]
[[ -z "$(find "$HOME" -name '*.bak.*' -print)" ]]
[[ "$(cat "$HOME/removed")" == 'apt bootstrap-added' && ! -e "$BOOTSTRAP_STATE_ROOT" ]]
uninstall_bare
[[ "$(wc -l <"$HOME/removed" | tr -d ' ')" == 1 ]]
echo 'PASS uninstall preview, cleanup, restoration, package removal, and retry'

export HOME="$fixture/legacy-home"; export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
unset DOTFILES_BARE_ROOT BOOTSTRAP_PRIVATE_ROOT BOOTSTRAP_STATE_ROOT CARGO_HOME RUSTUP_HOME BUN_INSTALL npm_config_prefix GOPATH GOBIN PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR GH_CONFIG_DIR NVIM_APPNAME BOOTSTRAP_LSP_SELECTIONS
mkdir -p "$HOME/.config/dotfiles" "$HOME/.pi/agent/sessions" "$HOME/.local/share/dotfiles/bare"
ln -s "$ROOT/scripts/bare-env.sh" "$HOME/.config/dotfiles/bare-env.sh"
printf secret >"$HOME/.pi/agent/auth.json"; printf session >"$HOME/.pi/agent/sessions/one"; printf unrelated >"$HOME/.local/share/dotfiles/bare/user-addition"
bootstrap_migration prepare >/dev/null
bootstrap_migration transfer --yes >/dev/null
bootstrap_migration activate --yes >/dev/null
bootstrap_migration verify >/dev/null
[[ "$(cat "$HOME/.local/share/bootstrap/private/pi/agent/auth.json")" == secret ]]
bootstrap_migration retire --yes >/dev/null
[[ ! -e "$HOME/.pi/agent" && -e "$HOME/.local/share/bootstrap/private/pi/agent/auth.json" && -L "$HOME/.config/dotfiles/bare-env.sh" ]]
[[ "$(cat "$HOME/.local/share/dotfiles/bare/user-addition")" == unrelated ]]
echo 'PASS explicit legacy migration preserves sensitive state and unrelated old tool additions'
