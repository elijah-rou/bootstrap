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
    mkdir -p "$PI_CODING_AGENT_DIR"
    for settings in '{}' '{"npmCommand":["npm"]}' '{"npmCommand":["bun"]}'; do
        printf '%s\n' "$settings" >"$PI_CODING_AGENT_DIR/settings.json"
        node "$ROOT/scripts/verify-pi-package-manager.mjs" || exit 1
        [[ "$(cat "$PI_CODING_AGENT_DIR/settings.json")" == "$settings" ]] || exit 1
    done
    [[ "$(env -i HOME="$HOME" PATH=/usr/bin:/bin "$HOME/.local/bin/pi" --version)" == "$PI_CLI_VERSION" ]]
    (
        cd "$fixture"
        env -i HOME="$HOME" PATH=/usr/bin:/bin "$HOME/.local/bin/pi" list --help > "$fixture/list-help"
        grep -q 'List installed packages' "$fixture/list-help"
        mkdir "$fixture/local-package"
        printf '{"name":"bootstrap-command-smoke","version":"1.0.0","pi":{"extensions":[],"skills":[]}}\n' > "$fixture/local-package/package.json"
        env -i HOME="$HOME" PATH=/usr/bin:/bin "$HOME/.local/bin/pi" install "$fixture/local-package"
        env -i HOME="$HOME" PATH=/usr/bin:/bin "$HOME/.local/bin/pi" list > "$fixture/packages"
        grep -Fq "$fixture/local-package" "$fixture/packages"
        env -i HOME="$HOME" PATH=/usr/bin:/bin "$HOME/.local/bin/pi" remove "$fixture/local-package"
        [[ -f "$fixture/local-package/package.json" ]]
    )
fi
if [[ "$(uname -s)" == Linux ]]; then
    install_upstream_tool eza
    "$DOTFILES_BARE_ROOT/bin/eza" --version
    "$DOTFILES_BARE_ROOT/bin/eza" "$HOME" >/dev/null
fi
printf 'PASS verified official binary artifacts execute on %s (no npm or package manager)\n' "$(bare_platform)"
