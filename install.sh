#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_CLI_PACKAGE="@earendil-works/pi-coding-agent"
PI_CLI_VERSION="0.87.0"
HERDR_INSTALLER_SHA256="bf83668c944cff30b3365eee5a4fe15ff61a4b749ab0c73b98e7a203f70893dd"
install_failures=()
INSTALL_FAILURE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap/install-failures.log"

info() { printf '[INFO] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1" >&2; }
error() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }

source "$DOTFILES_DIR/scripts/lib/install/downloads.sh"
source "$DOTFILES_DIR/scripts/lib/install/managed-files.sh"
source "$DOTFILES_DIR/scripts/lib/install/agents.sh"
source "$DOTFILES_DIR/scripts/lib/install/configuration.sh"
source "$DOTFILES_DIR/scripts/lib/install/neovim.sh"
source "$DOTFILES_DIR/scripts/lib/install/native.sh"
source "$DOTFILES_DIR/scripts/lib/install/bare.sh"

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

usage() {
    printf '%s\n' 'Usage: ./install.sh [install|pi|preflight|doctor|link|codex-link|neovim|herdr|pi-packages|pi-version|pi-check]' \
        '       ./install.sh (--languages|-l) LANGUAGE...' \
        '       ./install.sh (--lsp|-s) SERVER...' \
        '       ./install.sh (--tools|-t) TOOL...' \
        '       ./install.sh uninstall [--dry-run|--yes]' \
        '       ./install.sh migration <inspect|prepare|readiness|transfer|activate|verify|rollback|retire> [--yes]' \
        '       ./install.sh enroll-project ABS_DIR --yes' \
        '       ./install.sh migrate-legacy --yes  # compatibility notice only' \
        'Languages: c cpp rust go python typescript elixir zig.' \
        'LSPs: clangd rust-analyzer gopls basedpyright ruff typescript-language-server bash-language-server elixirls zls.' \
        'Tools: zsh starship codex just wget unzip shellcheck ruff headroom.' \
        'Core is native Bash, Pi 0.87.0, Herdr, Neovim, compiler and Tree-sitter CLI. Python, Zsh and Starship are not core.'
}

case "${1:-install}" in
    migration)
        shift
        bootstrap_migration "$@"; exit $?
        ;;
    enroll-project)
        [[ $# -eq 3 && "$2" == /* && "$3" == --yes ]] || { usage >&2; exit 2; }
        enroll_bootstrap_project "$2"; exit $?
        ;;
    migrate-legacy)
        [[ $# -eq 2 && "$2" == --yes ]] || { usage >&2; exit 2; }
        migrate_legacy_bootstrap; exit $?
        ;;
    --languages|-l|--lsp|-s|--tools|-t)
        command_name="$1"; shift
        case "$command_name" in --languages|-l) group=languages ;; --lsp|-s) group=lsp ;; *) group=tools ;; esac
        install_bare_optional "$group" "$@"
        exit $?
        ;;
    uninstall)
        shift
        case "${1:-}" in
            --dry-run) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; uninstall_bare --dry-run ;;
            --yes) [[ $# -eq 1 ]] || { usage >&2; exit 2; }; uninstall_bare --dry-run; uninstall_bare ;;
            '')
                [[ -t 0 ]] || { warn 'Uninstall requires --dry-run or explicit --yes when non-interactive'; exit 2; }
                ./install.sh uninstall --dry-run
                printf 'Delete enrolled personal state and eligible bootstrap-added packages? [y/N] ' >&2
                read -r answer; [[ "$answer" == y || "$answer" == Y ]] || exit 1
                uninstall_bare
                ;;
            *) usage >&2; exit 2 ;;
        esac
        exit $?
        ;;
    install|bare|pi|preflight|bare-preflight|doctor|bare-doctor|link|codex-link|neovim|herdr|pi-packages|pi-version|pi-check|--help|-h)
        [[ $# -le 1 ]] || { warn 'This command accepts no additional arguments'; exit 2; } ;;
    *) warn "Unknown command: $1"; exit 2 ;;
esac

case "${1:-install}" in
    install|bare) install_bare ;;
    pi) install_bare_pi ;;
    preflight|bare-preflight) bare_preflight ;;
    doctor|bare-doctor) bare_doctor ;;
    link) link_bare_offline ;;
    codex-link) link_codex_assets ;;
    neovim) install_workstation_neovim ;;
    herdr) install_herdr ;;
    pi-packages) source "$DOTFILES_DIR/scripts/bare-env.sh"; install_pi_packages "$PI_CODING_AGENT_DIR/settings.json" ;;
    pi-version) printf '%s\n' "$PI_CLI_VERSION" ;;
    pi-check) source "$DOTFILES_DIR/scripts/bare-env.sh"; check_pi_subagents_revision ;;
    --help|-h) usage ;;
esac
