#!/usr/bin/env bash
# Exercise installed server dependencies through the production bundled configuration.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -le 1 ]] || exit 2
case "${1:-}" in ''|--elixirls) ;; *) exit 2 ;; esac
fixture="$(mktemp -d)"; fixture="$(cd "$fixture" && pwd -P)"
trap 'rm -rf "$fixture"' EXIT
unset DOTFILES_BARE_ROOT BOOTSTRAP_PRIVATE_ROOT BOOTSTRAP_STATE_ROOT
source "$ROOT/install.sh"
source "$ROOT/tests/bundled_neovim_fixture.sh"
prepare_bundled_neovim_fixture "$fixture"
source "$ROOT/scripts/bare-env.sh"
cd "$fixture"
bare_stage="$(mktemp -d "$BOOTSTRAP_STATE_ROOT/stage.XXXXXX")"
install_upstream_tool bun
install_lsp_selection typescript-language-server
printf 'PASS installed TypeScript server and implementation through bundled Neovim\n'
if [[ "${1:-}" == --elixirls ]]; then
    command -v elixir >/dev/null && command -v erl >/dev/null
    install_bare_elixir_ls
    install_lsp_selection elixirls
    printf 'PASS prepared ElixirLS through bundled Neovim within the existing attachment bound\n'
fi
node -e 'const r=JSON.parse(require("node:fs").readFileSync(process.argv[1])); if(r.selections.languages.length)throw Error("LSP installation selected a language bundle")' "$BOOTSTRAP_STATE_ROOT/install.json"
