#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_CLI_PACKAGE="@earendil-works/pi-coding-agent"
PI_CLI_VERSION="0.84.4"
HERDR_INSTALLER_SHA256="bf83668c944cff30b3365eee5a4fe15ff61a4b749ab0c73b98e7a203f70893dd"
install_failures=()
INSTALL_FAILURE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install-failures.log"

info() { printf '[INFO] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1" >&2; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }

# shellcheck source=scripts/lib/install/downloads.sh
source "$DOTFILES_DIR/scripts/lib/install/downloads.sh"
# shellcheck source=scripts/lib/install/managed-files.sh
source "$DOTFILES_DIR/scripts/lib/install/managed-files.sh"
# shellcheck source=scripts/lib/install/agents.sh
source "$DOTFILES_DIR/scripts/lib/install/agents.sh"
# shellcheck source=scripts/lib/install/configuration.sh
source "$DOTFILES_DIR/scripts/lib/install/configuration.sh"
# shellcheck source=scripts/lib/install/bare.sh
source "$DOTFILES_DIR/scripts/lib/install/bare.sh"

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

case "${1:-install}" in
    install|bare|preflight|bare-preflight|doctor|bare-doctor|link|codex-link|neovim|pi-packages|pi-version|pi-check|--help|-h)
        [[ $# -le 1 ]] || { printf 'This command accepts no additional arguments\n' >&2; exit 2; }
        ;;
    --languages|-l)
        shift
        install_bare_optional languages "$@"
        exit $?
        ;;
    --tools|-t)
        shift
        install_bare_optional tools "$@"
        exit $?
        ;;
    *) printf 'Unknown command: %s\n' "$1" >&2; exit 2 ;;
esac

case "${1:-install}" in
    install|bare) install_bare ;;
    preflight|bare-preflight) bare_preflight ;;
    doctor|bare-doctor) bare_doctor ;;
    link) DOTFILES_RELINK_ONLY=1 link_bare_config; DOTFILES_RELINK_ONLY=1 setup_neovim_config ;;
    codex-link) link_codex_assets ;;
    neovim) BOOTSTRAP_WORKSTATION=1 NVIM_CONFIG_REPO_URL="${NVIM_CONFIG_REPO_URL:-https://github.com/elijah-rou/lazyvim-config.git}" setup_neovim_config ;;
    pi-packages) install_pi_packages "$HOME/.pi/agent/settings.json" ;;
    pi-version) printf '%s\n' "$PI_CLI_VERSION" ;;
    pi-check) check_pi_subagents_revision ;;
    --help|-h)
        printf '%s\n' 'Usage: ./install.sh [install|preflight|doctor|link|codex-link|neovim|pi-packages|pi-version|pi-check]' \
            '       ./install.sh (--languages|-l) LANGUAGE...' \
            '       ./install.sh (--tools|-t) TOOL...' \
            'Tools: codex just wget unzip (requires base install).' \
            'Languages: c cpp rust go python typescript bash elixir zig (requires base install).' \
            'Default: user-local terminal tools, Neovim, Pi, Herdr.' \
            'Language toolchains and LSPs are opt-in; Node and Python are tool dependencies.'
        ;;
esac
