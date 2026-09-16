#!/usr/bin/env bash
# Cold runtime fixture. Native packages must already exist; only the disposable HOME is writable.
set -eo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 1 && "$1" == /* && ! -e "$1" && ! -L "$1" ]] || { printf 'Usage: %s ABSENT_FIXTURE_DIRECTORY\n' "$0" >&2; exit 2; }
source "$ROOT/install.sh"
if [[ "${BOOTSTRAP_NATIVE_DISPOSABLE:-0}" == 1 ]]; then
    [[ "${GITHUB_ACTIONS:-}" == true ]] || { printf 'Native fixture provisioning requires disposable CI\n' >&2; exit 2; }
else
while IFS= read -r executable; do
    command -v "$executable" >/dev/null || { printf 'Preinstall required fixture command: %s\n' "$executable" >&2; exit 1; }
done < <(node -e 'const c=require(process.argv[1]);for(const k of c.core)console.log(c.packages[k].executable)' "$ROOT/packages/catalog.json")
command -v herdr >/dev/null || { printf 'Preinstall Herdr before building the fixture\n' >&2; exit 1; }
version_at_least "$(node --version)" 22.19.0
read -r _ version _ <<<"$(nvim --version)"; version_at_least "$version" 0.12.0
read -r _ version _ <<<"$(tree-sitter --version)"; version_at_least "$version" 0.26.1
fi
mkdir -m 0700 "$1"
fixture="$(cd "$1" && pwd -P)"
export HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/home/.config" XDG_DATA_HOME="$fixture/home/.data"
export XDG_STATE_HOME="$fixture/home/.state" XDG_CACHE_HOME="$fixture/home/.cache"
export DOTFILES_BARE_ROOT="$fixture/home/tools" BOOTSTRAP_PRIVATE_ROOT="$fixture/home/private" BOOTSTRAP_STATE_ROOT="$fixture/home/state/bootstrap"
unset GH_CONFIG_DIR BOOTSTRAP_LEGACY_GH_ROOT BOOTSTRAP_LEGACY_PI_ROOT NVIM_CONFIG_CHECKOUT_DIR NVIM_CONFIG_REPO_URL BOOTSTRAP_NEOVIM_PROFILE
mkdir -p "$HOME/.pi/agent"
printf '{"packages":[]}\n' >"$HOME/.pi/agent/settings.json"
# The command and version preconditions keep native transactions empty.
bash "$ROOT/install.sh" migration prepare
if [[ "${BOOTSTRAP_NATIVE_DISPOSABLE:-0}" != 1 ]]; then
    node -e 'const r=require(process.argv[1]);if(r.packages.length)throw Error("Fixture unexpectedly installed native packages")' "$BOOTSTRAP_STATE_ROOT/install.json"
fi
printf 'Real migration runtime fixture prepared: %s\n' "$fixture"
