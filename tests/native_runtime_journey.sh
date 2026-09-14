#!/usr/bin/env bash
# Destructive package journey: only explicitly disposable CI containers/VMs.
set -euo pipefail
[[ "${CI:-}" == true && "${BOOTSTRAP_NATIVE_DISPOSABLE:-}" == 1 ]] || { printf 'Refusing native package mutation outside disposable CI\n' >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/install.sh"
install_bare_pi
source "$ROOT/scripts/bare-env.sh"
[[ "$("$HOME/.local/bin/pi" --version)" == "$PI_CLI_VERSION" ]]
(
    bootstrap_lock_acquire
    bare_stage="$(mktemp -d "$BOOTSTRAP_STATE_ROOT/native-journey.XXXXXX")"
    trap 'rm -rf "$bare_stage"; bootstrap_lock_release' EXIT
    install_native_keys eza
    eza --version
    link_runtime_environment
    link_bash_login_profile
)
printf token >"$PI_CODING_AGENT_DIR/auth.json"
printf session >"$PI_CODING_AGENT_SESSION_DIR/sentinel"
# No inherited bootstrap variables are available to the login shell.
env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin bash -lc 'command -v node; command -v pi; pi --version'
uninstall_bare --dry-run
[[ -f "$PI_CODING_AGENT_DIR/auth.json" ]]
uninstall_bare
[[ ! -e "$BOOTSTRAP_STATE_ROOT" && ! -e "$BOOTSTRAP_PRIVATE_ROOT" && ! -e "$DOTFILES_BARE_ROOT" ]]
printf 'PASS real native Node/Bun/Pi/eza install, Bash login, and complete cleanup\n'
