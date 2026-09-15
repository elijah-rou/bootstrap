#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for command in nvim node basedpyright-langserver; do command -v "$command" >/dev/null || { printf '%s is required\n' "$command" >&2; exit 1; }; done
rust_analyzer="${RUST_ANALYZER_TEST_BIN:-$(command -v rust-analyzer || true)}"
[[ -x "$rust_analyzer" ]] || { printf 'Standalone rust-analyzer required (RUST_ANALYZER_TEST_BIN)\n' >&2; exit 1; }
node_bin="$(command -v node)"; nvim_bin="$(command -v nvim)"; basedpyright_bin="$(command -v basedpyright-langserver)"; fd_bin="$(command -v fd || command -v fdfind || true)"
[[ -n "$fd_bin" ]] || { printf 'fd is required\n' >&2; exit 1; }
temporary="$(mktemp -d)"; temporary="$(cd "$temporary" && pwd -P)"; trap 'rm -rf "$temporary"' EXIT
source "$ROOT/tests/bundled_neovim_fixture.sh"
prepare_bundled_neovim_fixture "$temporary"
info() { printf '%s\n' "$*"; }; warn() { printf '%s\n' "$*" >&2; }
source "$ROOT/scripts/lib/install/neovim.sh"
catalog_query() { node -e 'console.log(JSON.stringify(require(process.argv[1])[process.argv[2]][process.argv[3]]))' "$ROOT/packages/catalog.json" "$1" "$2"; }
for selection in basedpyright rust-analyzer; do node "$ROOT/scripts/state-helper.mjs" select lsp "$selection"; done
write_neovim_lsp_selections
# This is production-generated policy, not a substitute LSP configuration.
node -e 'const v=require(process.argv[1]).servers; if(v.rust_analyzer.root_policy!=="rust-standalone" || !v.basedpyright.verification) throw Error("Production lsp-output is missing root/verification metadata")' "$BOOTSTRAP_PRIVATE_ROOT/neovim/config/lsp-selections.json"
mkdir "$temporary/bin"
ln -s "$node_bin" "$temporary/bin/node"; ln -s "$nvim_bin" "$temporary/bin/nvim"
ln -s "$basedpyright_bin" "$temporary/bin/basedpyright-langserver"; ln -s "$rust_analyzer" "$temporary/bin/rust-analyzer"; ln -s "$fd_bin" "$temporary/bin/fd"
for command in clangd lua-language-server rustup; do
    printf '#!/bin/sh\nprintf forbidden >> "$UNSELECTED_MARKER"\nexit 99\n' >"$temporary/bin/$command"; chmod +x "$temporary/bin/$command"
done
export UNSELECTED_MARKER="$temporary/unselected"
# No rustc/Cargo entry or shim, including in the system PATH.
export PATH="$temporary/bin:/usr/bin:/bin"
! command -v rustc; ! command -v cargo
verify_selected_lsp rust-analyzer
verify_selected_lsp basedpyright
mkdir -p "$temporary/rust-project/src"
printf '[package]\nname="fixture"\nversion="0.1.0"\n' >"$temporary/rust-project/Cargo.toml"
printf 'fn main() {}\n' >"$temporary/rust-project/src/main.rs"
BOOTSTRAP_EXPECTED_LSP=rust_analyzer BOOTSTRAP_LSP_RECEIPT="$temporary/rust-project/receipt" node "$ROOT/scripts/run-bounded.mjs" 40 nvim --headless -i NONE -u "$XDG_CONFIG_HOME/bootstrap-nvim/init.lua" "$temporary/rust-project/src/main.rs" -l "$ROOT/neovim/verify-lsp.lua"
[[ -s "$temporary/rust-project/receipt" ]]
[[ ! -e "$UNSELECTED_MARKER" ]]
printf 'PASS R8 real bundled standalone rust-analyzer and BasedPyright initialized, attached and answered; rustc/Cargo absent\n'
# Start an unselected C buffer through ordinary bundled startup as well.
printf 'int main(void) { return 0; }\n' >"$temporary/unselected.c"
BOOTSTRAP_EXPECTED_NVIM_PROFILE=workstation BOOTSTRAP_NVIM_RECEIPT="$temporary/startup" node "$ROOT/scripts/run-bounded.mjs" 30 nvim --headless -i NONE "$temporary/unselected.c" "+lua dofile(vim.env.DOTFILES_DIR .. '/neovim/verify-runtime.lua')"
[[ ! -e "$UNSELECTED_MARKER" && -s "$temporary/startup" ]]
# Keep the production selection/config; only replace the selected executable with a protocol fixture.
rm "$temporary/bin/basedpyright-langserver"
printf '#!/bin/sh\nexec "%s" "%s"\n' "$node_bin" "$ROOT/tests/neovim_lsp_server.mjs" >"$temporary/bin/basedpyright-langserver"
chmod +x "$temporary/bin/basedpyright-langserver"
export LSP_FIXTURE_PID="$temporary/server.pid"
for mode in success method-not-found internal-error unsupported malformed timeout initialize-timeout; do
    export LSP_FIXTURE_MODE="$mode"
    if verify_selected_lsp basedpyright >"$temporary/$mode.log" 2>&1; then
        [[ "$mode" == success ]] || { cat "$temporary/$mode.log"; exit 1; }
    else
        [[ "$mode" != success ]] || { cat "$temporary/$mode.log"; exit 1; }
        case "$mode" in
            method-not-found|internal-error) grep -q 'selected LSP request failed' "$temporary/$mode.log" ;;
            unsupported) grep -q 'does not support' "$temporary/$mode.log" ;;
            malformed) grep -q 'invalid document symbols' "$temporary/$mode.log" ;;
            timeout) grep -q 'request timed out' "$temporary/$mode.log" ;;
            initialize-timeout) grep -q 'did not initialize and attach' "$temporary/$mode.log" ;;
        esac
    fi
    node - "$LSP_FIXTURE_PID" <<'JS'
const fs=require('node:fs');const pid=Number(fs.readFileSync(process.argv[2]));
setTimeout(()=>{try {process.kill(pid,0); console.error('LSP fixture leaked');process.exitCode=1;} catch(e){if(e.code!=='ESRCH')throw e;}},200);
JS
    [[ -z "$(find "$BOOTSTRAP_STATE_ROOT" -maxdepth 1 -name 'lsp.*' -print)" ]]
done
printf 'PASS R14 bundled selected-server protocol success, method/internal errors, unsupported capability, malformed result, request/init timeouts and process cleanup\n'
