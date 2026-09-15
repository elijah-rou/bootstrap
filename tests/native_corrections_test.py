#!/usr/bin/env python3
"""Production native/runtime and cleanup entrypoints, with disposable CLI fixtures."""
import json
import os
import pathlib
import subprocess
import tempfile
import socket
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class CorrectionsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        self.home = pathlib.Path(self.temp.name) / 'home'
        self.home.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('BOOTSTRAP_', 'DOTFILES_', 'XDG_', 'PI_'))}
        self.env.update(HOME=str(self.home), XDG_STATE_HOME=str(self.home / '.local/state'))

    def shell(self, text, ok=True):
        result = subprocess.run(['bash', '-c', f'source "{ROOT}/install.sh"; source "{ROOT}/scripts/bare-env.sh"; set -e;\n' + text], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def test_version_boundaries(self):
        self.shell('''
for fixture_version in 22.19.0 22.19.1 22.20.0 23.0.0 24.0.0; do
  node() { if [[ "${1:-}" == -p ]]; then printf '%s\\n' "${fixture_version%%.*}"; else printf 'v%s\\n' "$fixture_version"; fi; }; install_upstream_tool() { return 99; }
  ensure_pi_node_version
done
for fixture_version in 22.18.9 22.19.0-rc.1 21.99.99 22.0.0 22.19 '' nonsense 0.26.nan; do
  node() { if [[ "${1:-}" == -p ]]; then printf '%s\\n' "${fixture_version%%.*}"; else printf 'v%s\\n' "$fixture_version"; fi; }; install_upstream_tool() { return 0; }
  if ensure_pi_node_version; then echo "accepted $fixture_version"; exit 1; fi
done
for fixture_version in 0.26.1 0.26.2 0.27.0 1.0.0; do
  version_at_least "$fixture_version" 0.26.1
done
for fixture_version in 0.26.0 0.25.99 '' malformed 0.26 0.26.1-rc.1; do
  if version_at_least "$fixture_version" 0.26.1; then exit 1; fi
done
''')

    def test_tree_sitter_fallback_rechecks(self):
        self.shell('''
node() { printf 'v24.0.0\\n'; }
nvim() { printf 'NVIM v0.12.5\\n'; }
for fixture_version in 0.26.1 0.27.0 1.0.0; do
  tree-sitter() { printf 'tree-sitter %s\\n' "$fixture_version"; }
  install_upstream_tool() { return 99; }
  ensure_runtime_versions
done
for fixture_version in 0.26.0 0.25.99 malformed ''; do
  tree-sitter() { printf 'tree-sitter %s\\n' "$fixture_version"; }
  install_upstream_tool() { return 0; }
  if ensure_runtime_versions; then exit 1; fi
  install_upstream_tool() { return 99; }
  if ensure_runtime_versions; then exit 1; fi
  install_upstream_tool() { [[ "$1" == tree-sitter ]]; fixture_version=0.26.1; }
  ensure_runtime_versions
done
''')

    def test_bun_placeholder_rejected_before_activation(self):
        self.shell('''
mkdir -p "$HOME/payload/package/bin" "$HOME/stage"
printf '#!/bin/sh\\nexit 1\\n' >"$HOME/payload/package/bin/bun"
chmod +x "$HOME/payload/package/bin/bun"
tar -czf "$HOME/placeholder.tgz" -C "$HOME/payload" package
bare_stage="$HOME/stage"
download_verified() { cp "$HOME/placeholder.tgz" "$3"; }
if install_upstream_tool bun; then exit 1; fi
[[ ! -e "$DOTFILES_BARE_ROOT/bin/bun" && ! -L "$DOTFILES_BARE_ROOT/bin/bun" ]]
''')

    def test_bootstrap_node_absent_npm_absent_and_hidden_keg(self):
        for backend, preexisting in [('apt', False), ('brew', True), ('brew', False)]:
            with self.subTest(backend=backend, preexisting=preexisting):
                self.shell('''
real_node="$(command -v node)"
mkdir -p "$HOME/system" "$HOME/keg/bin" "$BOOTSTRAP_STATE_ROOT"
for executable in bash uname mkdir chmod grep sed rm cat dirname basename ln readlink cp mv date awk find; do
  ln -sf "$(command -v "$executable")" "$HOME/system/$executable"
done
export PATH="$HOME/system"
export BOOTSTRAP_PACKAGE_BACKEND=FIXTURE_BACKEND
package_db="$HOME/package-db"; rm -f "$package_db"
PREEXIST
brew() {
  case "$1" in
    list) [[ ! -f "$package_db" ]] || printf 'node@24\\n'; return 0;;
    info) return 0;;
    --prefix) printf '%s\\n' "$HOME/keg";;
    install) ln -sf "$real_node" "$HOME/keg/bin/node"; touch_package;;
    *) return 99;;
  esac
}
touch_package() { printf installed >"$package_db"; }
dpkg-query() { [[ ! -f "$package_db" ]] || printf 'nodejs\\tinstall ok installed\\n'; return 0; }
apt-cache() { return 0; }
apt-get() { if [[ "$1" != --simulate ]]; then ln -sf "$real_node" "$HOME/system/node"; touch_package; fi; }
native_privileged() { "$@"; }
ensure_bootstrap_node
! command -v npm
version_at_least "$(node --version)" 22.19.0
initialize_bootstrap_component pi
adopt_bootstrap_node_journal
node -e 'const r=require(process.env.BOOTSTRAP_STATE_ROOT+"/install.json");if(r.packages[0].preexisting!==EXPECTED)process.exit(1)'
if [[ "$BOOTSTRAP_PACKAGE_BACKEND" == brew ]]; then [[ -x "$DOTFILES_BARE_ROOT/bin/node" ]]; fi
rm -rf "$HOME/system" "$HOME/keg" "$DOTFILES_BARE_ROOT" "$BOOTSTRAP_PRIVATE_ROOT" "$BOOTSTRAP_STATE_ROOT"
'''.replace('FIXTURE_BACKEND', backend).replace('PREEXIST', 'ln -sf "$real_node" "$HOME/keg/bin/node"; printf installed >"$package_db"' if preexisting else '').replace('EXPECTED', str(preexisting).lower()))

    def test_old_node_fallback_precedes_modern_helpers(self):
        self.shell('''
real_node="$(command -v node)"
mkdir -p "$HOME/old-bin" "$HOME/payload/node/bin" "$BOOTSTRAP_STATE_ROOT" "$HOME/stage"
printf '#!/bin/sh\\nif [ "$1" = --version ]; then echo v18.0.0; else echo forbidden >"$HOME/old-node-helper"; exit 99; fi\\n' >"$HOME/old-bin/node"
printf '#!/bin/sh\\nexec "%s" "$@"\\n' "$real_node" >"$HOME/payload/node/bin/node"
chmod +x "$HOME/old-bin/node" "$HOME/payload/node/bin/node"
tar -cJf "$HOME/node.tar.xz" -C "$HOME/payload" node
export PATH="$HOME/old-bin:$PATH"
bare_stage="$HOME/stage"
download_verified() { cp "$HOME/node.tar.xz" "$3"; }
ensure_bootstrap_node
initialize_bootstrap_component pi
adopt_bootstrap_node_journal
[[ ! -e "$HOME/old-node-helper" && -x "$DOTFILES_BARE_ROOT/bin/node" ]]
version_at_least "$("$DOTFILES_BARE_ROOT/bin/node" --version)" 22.19.0
''')

    def test_bookworm_eza_fallback(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
mkdir -p "$HOME/payload" "$HOME/stage"
printf '#!/bin/sh\\necho eza-v0.23.5\\n' >"$HOME/payload/eza"; chmod +x "$HOME/payload/eza"
tar -czf "$HOME/eza.tar.gz" -C "$HOME/payload" ./eza
bare_stage="$HOME/stage"
export BOOTSTRAP_PACKAGE_BACKEND=apt
bare_platform() { printf 'linux-64\\n'; }
command() { if [[ "$*" == '-v eza' ]]; then [[ -x "$DOTFILES_BARE_ROOT/bin/eza" ]]; else builtin command "$@"; fi; }
apt-cache() { return 100; }
download_verified() { [[ "$1" == https://github.com/eza-community/eza/releases/download/* ]] || return 1; cp "$HOME/eza.tar.gz" "$3"; }
install_native_keys eza
[[ "$("$DOTFILES_BARE_ROOT/bin/eza" --version)" == eza-v0.23.5 ]]
''')

    def test_selected_shell_extras_apply_and_login_is_reversible(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
printf 'export HOST_LOGIN_VALUE=preserved\\n' >"$HOME/.bash_login"
link_runtime_environment
link_bash_login_profile
install_native_keys() { return 0; }
install_bootstrap_selections tools starship
[[ -L "$HOME/.config/starship.toml" && ! -e "$HOME/.zshrc" ]]
install_bootstrap_selections tools zsh
[[ -L "$HOME/.zshrc" && -L "$HOME/.zprofile" ]]
mkdir -p "$DOTFILES_BARE_ROOT/bin"
ln -sf "$(command -v node)" "$DOTFILES_BARE_ROOT/bin/node"
ln -sf /usr/bin/true "$DOTFILES_BARE_ROOT/bin/nvim"
ln -sf /usr/bin/true "$DOTFILES_BARE_ROOT/bin/pi"
node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$DOTFILES_BARE_ROOT"
env -i HOME="$HOME" PATH=/usr/bin:/bin bash -lc '[[ "$HOST_LOGIN_VALUE" == preserved ]]; for executable in node pi nvim; do [[ "$(command -v "$executable")" == "$HOME/.local/share/bootstrap/tools/bin/$executable" ]] || exit 1; done'
ps() { return 0; }; export -f ps
uninstall_bare
[[ "$(cat "$HOME/.bash_login")" == 'export HOST_LOGIN_VALUE=preserved' ]]
''')

    def test_python_selection_requires_a_real_interpreter_without_lsp(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
real_python="$(command -v python3)"
install_native_keys() {
  [[ "$*" == 'uv python' ]] || return 99
  mkdir -p "$DOTFILES_BARE_ROOT/bin"
  ln -s "$real_python" "$DOTFILES_BARE_ROOT/bin/python3"
}
python3() { [[ -x "$DOTFILES_BARE_ROOT/bin/python3" ]] || return 127; "$DOTFILES_BARE_ROOT/bin/python3" "$@"; }
install_bootstrap_selections languages python
[[ "$(python3 -c 'print(6*7)')" == 42 ]]
[[ "$(node "$DOTFILES_DIR/scripts/state-helper.mjs" selections)" == $'languages\\tpython' ]]
[[ -x "$real_python" ]]
''')

    def test_go_telemetry_requires_fresh_or_explicitly_enrolled_location(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
case "$(uname -s)" in Darwin) telemetry="$HOME/Library/Application Support/go/telemetry";; Linux) telemetry="$HOME/.config/go/telemetry";; esac
enroll_go_telemetry
[[ -d "$telemetry" ]]
printf sensitive >"$telemetry/sentinel"
node "$DOTFILES_DIR/scripts/state-helper.mjs" uninstall --dry-run | grep -F "$telemetry"
enroll_go_telemetry
mv "$telemetry" "$telemetry.original"; mkdir "$telemetry"
if enroll_go_telemetry; then exit 1; fi
if node "$DOTFILES_DIR/scripts/state-helper.mjs" uninstall; then exit 1; fi
rmdir "$telemetry"; mv "$telemetry.original" "$telemetry"
ps() { return 0; }; export -f ps
uninstall_bare
[[ ! -e "$telemetry" ]]
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
mkdir -p "$telemetry"; printf unrelated >"$telemetry/sentinel"
if enroll_go_telemetry; then exit 1; fi
if install_bootstrap_selections languages go; then exit 1; fi
if install_lsp_selection gopls; then exit 1; fi
[[ -z "$(node "$DOTFILES_DIR/scripts/state-helper.mjs" selections)" && "$(cat "$telemetry/sentinel")" == unrelated ]]
rm -rf "$telemetry"; mkdir "$HOME/foreign-telemetry"; ln -s "$HOME/foreign-telemetry" "$telemetry"
if enroll_go_telemetry; then exit 1; fi
[[ -L "$telemetry" ]]
''')

    def test_documented_tool_cache_roots_are_enrolled_and_cleaned(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$DOTFILES_BARE_ROOT"
node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$BOOTSTRAP_PRIVATE_ROOT"
for variable in npm_config_cache UV_CACHE_DIR UV_PYTHON_INSTALL_DIR UV_PYTHON_BIN_DIR UV_TOOL_DIR UV_TOOL_BIN_DIR MIX_HOME MIX_INSTALL_DIR HEX_HOME GOCACHE GOMODCACHE; do
  directory="${!variable}"
  [[ "$directory" == "$DOTFILES_BARE_ROOT/"* || "$directory" == "$BOOTSTRAP_PRIVATE_ROOT/"* ]] || exit 1
  mkdir -p "$directory"; printf sensitive >"$directory/sentinel"
done
[[ "$GOENV" == "$BOOTSTRAP_PRIVATE_ROOT/"* ]]
mkdir -p "$(dirname "$GOENV")"; printf config >"$GOENV"
mkdir -p "$HOME/.npm" "$HOME/.mix" "$HOME/.hex" "$HOME/.cache/uv"; printf foreign >"$HOME/.npm/sentinel"
ps() { return 0; }; export -f ps
uninstall_bare
[[ ! -e "$BOOTSTRAP_PRIVATE_ROOT" && ! -e "$DOTFILES_BARE_ROOT" && "$(cat "$HOME/.npm/sentinel")" == foreign ]]
''')

    def test_existing_typescript_server_repairs_implementation_only(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
mkdir -p "$DOTFILES_BARE_ROOT/bin"
typescript-language-server() { return 0; }
bun() {
  [[ "$*" == 'install --global --exact typescript@6.0.2 typescript-language-server@5.3.0' ]] || return 99
  mkdir -p "$BUN_INSTALL/bin" "$BUN_INSTALL/install/global/node_modules/typescript/lib" "$BUN_INSTALL/install/global/node_modules/typescript-language-server"
  printf 'module.exports={};\\n' >"$BUN_INSTALL/install/global/node_modules/typescript/lib/tsserver.js"
  printf '#!/bin/sh\\nexit 0\\n' >"$BUN_INSTALL/bin/typescript-language-server"; chmod +x "$BUN_INSTALL/bin/typescript-language-server"
}
verify_selected_lsp() { [[ -f "$BUN_INSTALL/install/global/node_modules/typescript/lib/tsserver.js" ]]; }
install_lsp_selection typescript-language-server
[[ "$(node "$DOTFILES_DIR/scripts/state-helper.mjs" selections)" == $'lsp\\ttypescript-language-server' ]]
[[ -L "$DOTFILES_BARE_ROOT/bin/typescript-language-server" ]]
''')

    def test_core_reconciles_persisted_independent_selections(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
node "$DOTFILES_DIR/scripts/state-helper.mjs" select languages c
node "$DOTFILES_DIR/scripts/state-helper.mjs" select tools just
node "$DOTFILES_DIR/scripts/state-helper.mjs" select lsp basedpyright
bare_preflight() { :; }; ensure_runtime_versions() { :; }
install_pi_component() { :; }; install_herdr() { :; }; link_bare_config() { :; }
install_neovim_config() { :; }; install_neovim_parsers() { :; }; bare_doctor() { :; }
install_native_keys() { printf '%s\\n' "$*" >>"$HOME/native-keys"; }
command() {
  if [[ "$*" == '-v basedpyright-langserver' ]]; then [[ -x "$DOTFILES_BARE_ROOT/bin/basedpyright-langserver" ]]; else builtin command "$@"; fi
}
bun() {
  [[ "$*" == 'install --global --exact basedpyright@1.38.3' ]] || return 99
  mkdir -p "$DOTFILES_BARE_ROOT/bin"
  printf '#!/bin/sh\\nexit 0\\n' >"$DOTFILES_BARE_ROOT/bin/basedpyright-langserver"
  chmod +x "$DOTFILES_BARE_ROOT/bin/basedpyright-langserver"
}
verify_selected_lsp() {
  [[ "$1" == basedpyright && -x "$DOTFILES_BARE_ROOT/bin/basedpyright-langserver" && -f "$BOOTSTRAP_LSP_SELECTIONS" ]] || return 1
  printf verified >>"$HOME/readiness"
}
install_bare
[[ "$(cat "$HOME/readiness")" == verified ]]
grep -qx just "$HOME/native-keys"
[[ -z "$(node "$DOTFILES_DIR/scripts/state-helper.mjs" selections | grep typescript)" ]]
rm "$DOTFILES_BARE_ROOT/bin/basedpyright-langserver" "$BOOTSTRAP_LSP_SELECTIONS"
install_bare
[[ "$(cat "$HOME/readiness")" == verifiedverified ]]
verify_selected_lsp() { return 9; }
if install_bare; then exit 1; fi
''')

    def test_codex_selected_state_is_private(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
mkdir -p "$HOME/.codex" "$BOOTSTRAP_PRIVATE_ROOT"
printf foreign >"$HOME/.codex/auth.json"
link_bare_codex_config
printf owned >"$BOOTSTRAP_PRIVATE_ROOT/codex/auth.json"
printf session >"$BOOTSTRAP_PRIVATE_ROOT/codex/session.json"
[[ ! -e "$HOME/.codex/config.toml" ]]
ps() { return 0; }; export -f ps
uninstall_bare
[[ ! -e "$BOOTSTRAP_PRIVATE_ROOT/codex" && "$(cat "$HOME/.codex/auth.json")" == foreign ]]
''')

    def test_preview_is_read_only(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
mkdir -p "$TMUX_TMPDIR"
node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$BOOTSTRAP_PRIVATE_ROOT"
cp "$BOOTSTRAP_STATE_ROOT/install.json" "$HOME/before"
ps() { return 0; }
tmux() { echo forbidden >>"$HOME/effects"; }
bootstrap_lock_acquire() { echo forbidden >>"$HOME/effects"; return 1; }
uninstall_bare --dry-run
cmp "$HOME/before" "$BOOTSTRAP_STATE_ROOT/install.json"
[[ ! -e "$HOME/effects" ]]
[[ "$(ls -A "$BOOTSTRAP_STATE_ROOT")" == install.json ]]
''')

    def test_only_owned_multiplexer_sockets_are_controlled(self):
        private = self.home/'.local/share/bootstrap/private'
        owned = private/f'tmux/tmux-{os.getuid()}/default'
        foreign = self.home/'.config/herdr/herdr.sock'
        for path in [owned, foreign]:
            path.parent.mkdir(parents=True, exist_ok=True)
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(str(path))
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$BOOTSTRAP_PRIVATE_ROOT"
mkdir -p "$HOME/mock-bin"
printf '#!/bin/sh\\nprintf "%%s|%%s\\n" "${TMUX-unset}" "$*" >>"$HOME/server-calls"\\n[ "$1" = -S ] || exit 99\\nrm "$2"\\n' >"$HOME/mock-bin/tmux"
chmod +x "$HOME/mock-bin/tmux"
export PATH="$HOME/mock-bin:$PATH" TMUX="$HOME/foreign-tmux,1,0"
herdr() { echo forbidden >"$HOME/foreign-stopped"; return 99; }
ps() { return 0; }; export -f ps
uninstall_bare --dry-run
[[ ! -e "$HOME/server-calls" ]]
uninstall_bare
[[ "$(cat "$HOME/server-calls")" == "unset|-S $TMUX_TMPDIR/tmux-$(id -u)/default kill-server" ]]
[[ -S "$HOME/.config/herdr/herdr.sock" && ! -e "$HOME/foreign-stopped" ]]
''')

    def test_writer_identity_not_broad_process_name(self):
        self.shell('''
fixture_uid="$(id -u)"
ps() { if [[ "$1" == -axo ]]; then printf '%s 123 nvim nvim fixture\\n' "$fixture_uid"; else printf 'nvim BOOTSTRAP_PRIVATE_ROOT=/foreign/profile\\n'; fi; }
if bootstrap_live_writers; then exit 1; fi
ps() { if [[ "$1" == -axo ]]; then printf '%s 123 nvim nvim fixture\\n' "$fixture_uid"; else printf 'nvim BOOTSTRAP_PRIVATE_ROOT=%s\\n' "$BOOTSTRAP_PRIVATE_ROOT"; fi; }
bootstrap_live_writers
ps() { return 9; }
status=0; bootstrap_live_writers || status=$?; [[ "$status" == 2 ]]
''')

    def test_cleanup_conflict_retains_recovery_and_fails(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
printf original >"$HOME/.bashrc"
link_managed_file "$DOTFILES_DIR/bashrc" "$HOME/.bashrc"
rm "$HOME/.bashrc"; printf modified >"$HOME/.bashrc"
ps() { return 0; }
if uninstall_bare; then exit 1; fi
[[ -f "$BOOTSTRAP_STATE_ROOT/install.json" && -f "$BOOTSTRAP_STATE_ROOT/recovery/0.original" ]]
if node "$DOTFILES_DIR/scripts/state-helper.mjs" finish-uninstall; then exit 1; fi
[[ "$(cat "$HOME/.bashrc")" == modified ]]
''')

    def test_sole_runtime_cleanup(self):
        for backend in ('direct', 'apt'):
            with self.subTest(backend=backend):
                self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
mkdir -p "$DOTFILES_BARE_ROOT/bin"
real_node="$(command -v node)"
ln -s "$real_node" "$DOTFILES_BARE_ROOT/bin/node"
node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$DOTFILES_BARE_ROOT"
mkdir -p "$HOME/guard"
printf '#!/bin/sh\\necho unavailable >&2; exit 97\\n' >"$HOME/guard/node"; chmod +x "$HOME/guard/node"
export PATH="$DOTFILES_BARE_ROOT/bin:$HOME/guard:$PATH"
''' + ('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" package apt fixture-node 0 absent installed
mkdir -p "$HOME/native/bin"; mv "$DOTFILES_BARE_ROOT/bin/node" "$HOME/native/bin/node"
export PATH="$HOME/native/bin:$PATH"
export FIXTURE_NATIVE_NODE="$HOME/native/bin/node"
printf installed >"$HOME/package"
dpkg-query() { [[ ! -f "$HOME/package" ]] || printf 'fixture-node\\tinstall ok installed\\n'; }
apt-get() { [[ "$*" == '--simulate remove fixture-node' ]] || return 99; printf 'Remv fixture-node [1]\\n'; }
dpkg() { [[ "$*" == '--remove -- fixture-node' ]] || return 99; rm -f "$FIXTURE_NATIVE_NODE" "$HOME/package"; }
export -f dpkg-query apt-get dpkg
''' if backend == 'apt' else '') + '''
ps() { return 0; }; export -f ps
native_privileged() { "$@"; }; export -f native_privileged
uninstall_bare
[[ ! -e "$BOOTSTRAP_STATE_ROOT" && ! -e "$DOTFILES_BARE_ROOT" ]]
''')

    def test_finish_verifies_restored_files(self):
        self.shell('''
node "$DOTFILES_DIR/scripts/state-helper.mjs" init
printf original >"$HOME/.bashrc"; link_managed_file "$DOTFILES_DIR/bashrc" "$HOME/.bashrc"
node "$DOTFILES_DIR/scripts/state-helper.mjs" uninstall
printf changed >"$HOME/.bashrc"
if node "$DOTFILES_DIR/scripts/state-helper.mjs" finish-uninstall; then exit 1; fi
[[ -f "$BOOTSTRAP_STATE_ROOT/recovery/0.original" ]]
''')

if __name__ == '__main__':
    unittest.main()
