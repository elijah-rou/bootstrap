#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"; fixture="$(cd "$fixture" && pwd -P)"; trap 'rm -rf "$fixture"' EXIT
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
    cat >"$BUN_INSTALL/install/global/node_modules/@earendil-works/pi-coding-agent/dist/config.js" <<'JS'
export const PACKAGE_NAME = '@earendil-works/pi-coding-agent';
export const detectInstallMethod = () => 'bun';
export const getSelfUpdateCommand = () => ({ command: 'bun', args: ['install', '-g', PACKAGE_NAME] });
JS
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
[[ ! -e "$HOME/native-components" && ! -e "$HOME/.local/bin/pi" ]] || exit 1
# Pi-only cases select a fresh profile; migration's shell/editor activation has its own suite.
export BOOTSTRAP_LEGACY_PI_ROOT="$HOME/empty-legacy"
install_bare_pi
private="$HOME/.local/share/bootstrap/private"
[[ "$(cat "$HOME/.pi/agent/sentinel")" == unrelated && ! -e "$HOME/.pi/agent/settings.json" ]] || exit 1
[[ ! -e "$private/pi/agent/sentinel" ]] || exit 1
[[ -f "$private/pi/agent/settings.json" && -L "$private/pi/agent/AGENTS.md" ]] || exit 1
[[ -L "$private/pi/agent/extensions/subagent/config.json" && -L "$private/pi/agent/skills/blast-radius" ]] || exit 1
[[ -L "$HOME/.local/bin/pi-workspace" && -L "$HOME/.local/bin/pi-headroom" ]] || exit 1
[[ ! -e "$HOME/.config/bootstrap-nvim" && ! -e "$HOME/.bashrc" && ! -e "$HOME/.config/herdr" && ! -e "$HOME/forbidden" ]] || exit 1
[[ "$(cat "$HOME/native-components")" == 'node bun' ]] || exit 1
node - <<'NODE'
const record=require(process.env.HOME+'/.local/state/bootstrap/install.json');
if(record.status!=='partial'||record.components.pi!=='ready'||record.components.core)process.exit(1);
NODE
first_packages="$(cat "$HOME/pi-packages")"
install_bare_pi
[[ "$(cat "$HOME/bun-installs")" == $'pi-cli\npi-cli' && "$(cat "$HOME/pi-packages")" == "$first_packages"$'\n'"$first_packages" ]] || exit 1
[[ -z "$(find "$HOME" -name '*.bak.*' -print)" ]] || exit 1
# Installed entrypoints must ignore a foreign Pi even without shell configuration.
mkdir -p "$HOME/foreign" "$HOME/.local/share/bootstrap/tools/bin"
ln -sf "$(command -v node)" "$HOME/.local/share/bootstrap/tools/bin/node"
printf '#!/bin/sh\necho foreign >"$HOME/foreign-used"; exit 99\n' >"$HOME/foreign/pi"
chmod +x "$HOME/foreign/pi"
[[ "$(env -i HOME="$HOME" PATH="$HOME/foreign:/usr/bin:/bin" "$HOME/.local/bin/pi" --version)" == "$PI_CLI_VERSION" ]] || exit 1
[[ "$(env -i HOME="$HOME" PATH="$HOME/foreign:/usr/bin:/bin" "$HOME/.local/bin/piw" --main -- --version)" == "$PI_CLI_VERSION" ]] || exit 1
[[ ! -e "$HOME/foreign-used" ]] || exit 1
printf secret >"$private/pi/agent/auth.json"; printf session >"$private/pi/sessions/one"; printf history >"$private/bash/history"
printf dotfiles-only >"$HOME/.pi/agent/dotfiles-only"
bootstrap_live_writers() { return 1; }
uninstall_bare --dry-run >/dev/null
uninstall_bare
[[ ! -e "$private" && ! -e "$HOME/.local/share/bootstrap/tools" ]] || exit 1
[[ "$(cat "$HOME/.pi/agent/sentinel")" == unrelated && "$(cat "$HOME/.pi/agent/dotfiles-only")" == dotfiles-only ]] || exit 1
[[ ! -e "$HOME/.local/bin/pi-workspace" && ! -e "$HOME/.local/bin/pi-headroom" ]] || exit 1
mv "$HOME/.pi/agent" "$HOME/legacy-pi-agent"
mkdir -p "$private/pi/agent"; printf unowned >"$private/pi/agent/auth.json"
if install_bare_pi; then exit 1; fi
[[ "$(cat "$private/pi/agent/auth.json")" == unowned && ! -f "$HOME/.local/state/bootstrap/install.json" ]] || exit 1
rm -rf "$private"; mkdir -p "$private/pi/agent/extensions"
ln -s "$ROOT/pi/extensions/notify.ts" "$private/pi/agent/extensions/notify.ts"
install_bare_pi
[[ "$(readlink "$private/pi/agent/extensions/notify.ts")" == "$ROOT/pi/extensions/notify.ts" ]] || exit 1
uninstall_bare
mv "$HOME/legacy-pi-agent" "$HOME/.pi/agent"
[[ ! -e "$private" && "$(cat "$HOME/.pi/agent/sentinel")" == unrelated ]] || exit 1
echo 'PASS targeted Pi install owns only Pi runtime/configuration, retries, guarded adoption, and sensitive cleanup'
