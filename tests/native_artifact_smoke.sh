#!/usr/bin/env bash
# Networked binary smoke only. No host packages or user configuration are touched.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home" XDG_STATE_HOME="$fixture/home/.local/state"
unset DOTFILES_BARE_ROOT BOOTSTRAP_PRIVATE_ROOT BOOTSTRAP_STATE_ROOT
mkdir -p "$HOME"
source "$ROOT/install.sh"; source "$ROOT/scripts/bare-env.sh"
bare_stage="$fixture/stage"; mkdir "$bare_stage"
npm() { echo 'Bun must not require npm' >&2; return 99; }
install_upstream_tool bun
[[ "$("$DOTFILES_BARE_ROOT/bin/bun" --version)" == 1.4.0 ]]
[[ "$("$DOTFILES_BARE_ROOT/bin/bun" -e 'console.log(6*7)')" == 42 ]]
if [[ "${1:-}" == --node || "${1:-}" == --pi ]]; then
    install_upstream_tool node
    [[ "$("$DOTFILES_BARE_ROOT/bin/node" --version)" == v24.18.0 ]]
fi
if [[ "${1:-}" == --pi ]]; then
    bun install --global --exact "$PI_CLI_PACKAGE@$PI_CLI_VERSION"
    link_pi_launchers
    [[ "$(env -i HOME="$HOME" PATH=/usr/bin:/bin "$HOME/.local/bin/pi" --version)" == "$PI_CLI_VERSION" ]]
fi
if [[ "$(uname -s)" == Linux ]]; then
    install_upstream_tool eza
    "$DOTFILES_BARE_ROOT/bin/eza" --version
    "$DOTFILES_BARE_ROOT/bin/eza" "$HOME" >/dev/null
fi
printf 'PASS verified official binary artifacts execute on %s (no npm or package manager)\n' "$(bare_platform)"
