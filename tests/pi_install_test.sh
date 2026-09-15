#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home" USER="${USER:-$(id -un)}"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
unset DOTFILES_BARE_ROOT BOOTSTRAP_PRIVATE_ROOT BOOTSTRAP_STATE_ROOT PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR NVIM_APPNAME BOOTSTRAP_LSP_SELECTIONS BUN_INSTALL npm_config_prefix CARGO_HOME RUSTUP_HOME GOPATH GOBIN GH_CONFIG_DIR TMUX_TMPDIR
mkdir -p "$HOME/.pi/agent"; printf unrelated >"$HOME/.pi/agent/sentinel"
source "$ROOT/install.sh"

bare_preflight() { :; }
install_native_keys() { printf '%s\n' "$*" >>"$HOME/native-components"; }
ensure_pi_node_version() { :; }
bun() {
    if [[ "$*" == --version ]]; then printf '1.4.0\n'; return; fi
    [[ "$*" == "install --global --exact $PI_CLI_PACKAGE@$PI_CLI_VERSION" ]]
    printf 'pi-cli\n' >>"$HOME/bun-installs";
    mkdir -p "$BUN_INSTALL/install/global/node_modules/@earendil-works/pi-coding-agent/dist"
    printf 'console.log("%s");\n' "$PI_CLI_VERSION" >"$BUN_INSTALL/install/global/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
}

pi() {
    if [[ "${1:-}" == --version ]]; then printf '%s\n' "$PI_CLI_VERSION"; return; fi
    [[ "${1:-}" == install && -n "${2:-}" ]] || return 97
    printf '%s\n' "$2" >>"$HOME/pi-packages"
}
check_pi_subagents_revision() { :; }
install_herdr() { printf forbidden-herdr >"$HOME/forbidden"; return 98; }
install_neovim_config() { printf forbidden-neovim >"$HOME/forbidden"; return 98; }
install_neovim_parsers() { printf forbidden-parser >"$HOME/forbidden"; return 98; }
link_terminal_config() { printf forbidden-terminal >"$HOME/forbidden"; return 98; }

if install_bare_pi; then exit 1; fi
[[ ! -e "$HOME/native-components" && ! -e "$HOME/.local/bin/pi" ]]
bootstrap_migration prepare >/dev/null
bootstrap_migration transfer --yes >/dev/null
bootstrap_migration activate --yes >/dev/null
bootstrap_migration verify >/dev/null
install_bare_pi
private="$HOME/.local/share/bootstrap/private"
[[ "$(cat "$HOME/.pi/agent/sentinel")" == unrelated && ! -e "$HOME/.pi/agent/settings.json" ]]
[[ "$(cat "$private/pi/agent/sentinel")" == unrelated ]]
[[ -f "$private/pi/agent/settings.json" && -L "$private/pi/agent/AGENTS.md" ]]
[[ -L "$private/pi/agent/extensions/subagent/config.json" && -L "$private/pi/agent/skills/blast-radius" ]]
[[ -L "$HOME/.local/bin/pi-workspace" && -L "$HOME/.local/bin/pi-headroom" ]]
[[ ! -e "$HOME/.config/bootstrap-nvim" && ! -e "$HOME/.bashrc" && ! -e "$HOME/.config/herdr" && ! -e "$HOME/forbidden" ]]
[[ "$(cat "$HOME/native-components")" == 'node bun' ]]
node - <<'NODE'
const record=require(process.env.HOME+'/.local/state/bootstrap/install.json');
if(record.status!=='partial'||record.components.pi!=='ready'||record.components.core)process.exit(1);
NODE
first_packages="$(cat "$HOME/pi-packages")"
install_bare_pi
[[ "$(cat "$HOME/bun-installs")" == $'pi-cli\npi-cli' && "$(cat "$HOME/pi-packages")" == "$first_packages"$'\n'"$first_packages" ]]
[[ -z "$(find "$HOME" -name '*.bak.*' -print)" ]]
# Installed entrypoints must ignore a foreign Pi even without shell configuration.
mkdir -p "$HOME/foreign" "$HOME/.local/share/bootstrap/tools/bin"
ln -sf "$(command -v node)" "$HOME/.local/share/bootstrap/tools/bin/node"
printf '#!/bin/sh\necho foreign >"$HOME/foreign-used"; exit 99\n' >"$HOME/foreign/pi"
chmod +x "$HOME/foreign/pi"
[[ "$(env -i HOME="$HOME" PATH="$HOME/foreign:/usr/bin:/bin" "$HOME/.local/bin/pi" --version)" == "$PI_CLI_VERSION" ]]
[[ "$(env -i HOME="$HOME" PATH="$HOME/foreign:/usr/bin:/bin" "$HOME/.local/bin/piw" --main -- --version)" == "$PI_CLI_VERSION" ]]
[[ ! -e "$HOME/foreign-used" ]]
printf secret >"$private/pi/agent/auth.json"; printf session >"$private/pi/sessions/one"; printf history >"$private/bash/history"
printf dotfiles-only >"$HOME/.pi/agent/dotfiles-only"
bootstrap_live_writers() { return 1; }
uninstall_bare --dry-run >/dev/null
uninstall_bare
[[ ! -e "$private" && ! -e "$HOME/.local/share/bootstrap/tools" ]]
[[ "$(cat "$HOME/.pi/agent/sentinel")" == unrelated && "$(cat "$HOME/.pi/agent/dotfiles-only")" == dotfiles-only ]]
[[ ! -e "$HOME/.local/bin/pi-workspace" && ! -e "$HOME/.local/bin/pi-headroom" ]]
mv "$HOME/.pi/agent" "$HOME/legacy-pi-agent"
mkdir -p "$private/pi/agent"; printf unowned >"$private/pi/agent/auth.json"
if install_bare_pi; then exit 1; fi
[[ "$(cat "$private/pi/agent/auth.json")" == unowned && ! -f "$HOME/.local/state/bootstrap/install.json" ]]
rm -rf "$private"; mkdir -p "$private/pi/agent/extensions"
ln -s "$ROOT/pi/extensions/notify.ts" "$private/pi/agent/extensions/notify.ts"
install_bare_pi
[[ "$(readlink "$private/pi/agent/extensions/notify.ts")" == "$ROOT/pi/extensions/notify.ts" ]]
uninstall_bare
mv "$HOME/legacy-pi-agent" "$HOME/.pi/agent"
[[ ! -e "$private" && "$(cat "$HOME/.pi/agent/sentinel")" == unrelated ]]
echo 'PASS targeted Pi install owns only Pi runtime/configuration, retries, guarded adoption, and sensitive cleanup'
