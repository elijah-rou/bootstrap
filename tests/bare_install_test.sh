#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$HOME"
source "$ROOT_DIR/install.sh"

# Core journey uses native dispatch and records ownership without selecting extras.
bare_preflight() { :; }
catalog_query() { [[ "$1" == core ]] && printf 'git\nnode\nbun\n'; }
install_native_keys() { printf '%s\n' "$*" >>"$HOME/native-keys"; }
ensure_runtime_versions() { :; }
ensure_pi_node_version() { :; }
bun() {
    if [[ "$*" == --version ]]; then printf '1.4.0\n'; return; fi
    [[ "$*" == "install --global --exact $PI_CLI_PACKAGE@$PI_CLI_VERSION" ]]

    mkdir -p "$BUN_INSTALL/install/global/node_modules/@earendil-works/pi-coding-agent/dist"
    printf 'console.log("%s");\n' "$PI_CLI_VERSION" >"$BUN_INSTALL/install/global/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
}

pi() { [[ "${1:-}" == --version ]] && printf '%s\n' "$PI_CLI_VERSION" || :; }
install_herdr() { :; }
link_bare_config() { :; }
install_neovim_config() { :; }
install_pi_packages() { [[ "$1" == "$PI_CODING_AGENT_DIR/settings.json" ]]; }
pi_doctor() { :; }
install_neovim_parsers() { :; }
report_install_failures() { :; }
bare_doctor() { :; }
install_bare
[[ "$(cat "$HOME/native-keys")" == $'git node bun\nnode bun' ]]
[[ -z "$(node "$ROOT_DIR/scripts/state-helper.mjs" selections)" ]]
[[ ! -e "$HOME/.zshrc" && ! -e "$HOME/.config/starship.toml" ]]
node "$ROOT_DIR/scripts/state-helper.mjs" validate >/dev/null
install_bare
[[ "$(cat "$HOME/native-keys")" == $'git node bun\nnode bun\ngit node bun\nnode bun' ]]
[[ ! -d "$XDG_STATE_HOME/bootstrap/mutate.lock" ]]
echo 'PASS native core install and retry record no implicit extras'

# Locks are never stolen based on PID guesses.
mkdir "$XDG_STATE_HOME/bootstrap/mutate.lock"
if install_bare; then exit 1; fi
[[ -d "$XDG_STATE_HOME/bootstrap/mutate.lock" ]]
rmdir "$XDG_STATE_HOME/bootstrap/mutate.lock"
echo 'PASS ownership-aware lock rejects overlap'

# Unsupported and malformed CLI inputs stop before mutation.
for args in '--languages' '--lsp unknown' '--tools nope' 'uninstall --bad'; do
  status=0
  # shellcheck disable=SC2086
  HOME="$fixture/reject" bash "$ROOT_DIR/install.sh" $args >/dev/null 2>&1 || status=$?
  [[ $status -eq 2 && ! -e "$fixture/reject" ]]
done
echo 'PASS selectors reject before mutation'

readiness_home="$fixture/readiness"
mkdir -p "$readiness_home"
readiness_env=(HOME="$readiness_home" XDG_STATE_HOME="$readiness_home/.state")
env "${readiness_env[@]}" node "$ROOT_DIR/scripts/state-helper.mjs" init
if env "${readiness_env[@]}" node "$ROOT_DIR/scripts/state-helper.mjs" ready >/dev/null 2>&1; then exit 1; fi
env "${readiness_env[@]}" node "$ROOT_DIR/scripts/state-helper.mjs" component-begin core
env "${readiness_env[@]}" node "$ROOT_DIR/scripts/state-helper.mjs" component-ready core
env "${readiness_env[@]}" node "$ROOT_DIR/scripts/state-helper.mjs" component-begin pi
if env "${readiness_env[@]}" node "$ROOT_DIR/scripts/state-helper.mjs" ready >/dev/null 2>&1; then exit 1; fi
node -e 'const r=require(process.argv[1]);if(r.status!=="partial")process.exit(1)' "$readiness_home/.state/bootstrap/install.json"
echo 'PASS readiness is derived from verified component state'

(
    export HOME="$fixture/herdr-conflict" XDG_CONFIG_HOME="$fixture/herdr-conflict/.config" XDG_STATE_HOME="$fixture/herdr-conflict/.state"
    export XDG_DATA_HOME="$fixture/herdr-conflict/.data" XDG_CACHE_HOME="$fixture/herdr-conflict/.cache"
    unset DOTFILES_BARE_ROOT BOOTSTRAP_PRIVATE_ROOT BOOTSTRAP_STATE_ROOT
    mkdir -p "$XDG_CONFIG_HOME/herdr"
    printf personal >"$XDG_CONFIG_HOME/herdr/personal.db"
    source "$ROOT_DIR/install.sh"
    bare_preflight() { :; }
    install_native_keys() { printf effect >"$HOME/effect"; }
    if install_bare; then exit 1; fi
    [[ ! -e "$HOME/effect" && ! -e "$XDG_STATE_HOME/bootstrap" ]]
)
echo 'PASS Herdr conflicts stop before installer effects'
