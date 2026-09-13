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
bun() { [[ "$*" == "install --global --exact $PI_CLI_PACKAGE@$PI_CLI_VERSION" ]]; }
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
