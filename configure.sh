#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install.sh
source "$DOTFILES_DIR/install.sh"

usage() {
    printf '%s\n' 'Usage: ./configure.sh <terminal|pi|codex|neovim|all> [--overlay ABS_DIR]... [--legacy-root ABS_DIR]' \
        'Offline user configuration only. Overlays apply in order, low to high precedence.'
}

case "${1:-}" in
    terminal|pi|codex|neovim|all) configure_target="$1"; shift ;;
    --help|-h) [[ $# -eq 1 ]] || exit 2; usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
BOOTSTRAP_OVERLAYS=()
BOOTSTRAP_LEGACY_ROOT=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --overlay|--legacy-root)
            [[ $# -ge 2 && "$2" == /* && "$2" != / && "$2" != *$'\n'* && "$2" != *$'\r'* ]] || {
                warn "$1 requires an absolute directory path other than /"; exit 2;
            }
            if [[ "$1" == --overlay ]]; then
                [[ -d "$2" ]] || { warn "Overlay directory does not exist: $2"; exit 2; }
                overlay_path="$(cd "$2" && pwd -P)"
                [[ "$overlay_path" != / ]] || { warn 'Overlay directory cannot be /'; exit 2; }
                BOOTSTRAP_OVERLAYS+=("$overlay_path")
            else
                [[ -z "$BOOTSTRAP_LEGACY_ROOT" ]] || { warn '--legacy-root may appear only once'; exit 2; }
                BOOTSTRAP_LEGACY_ROOT="${2%/}"
            fi
            shift 2
            ;;
        *) warn "Unknown configure argument: $1"; exit 2 ;;
    esac
done
[[ "$HOME" == /* && "$HOME" != / ]] || { warn 'HOME must be an absolute user directory'; exit 2; }
command -v python3 >/dev/null || { warn 'python3 is required for offline configuration'; exit 1; }

# One owner prevents overlapping backup/move operations in the same user profile.
configure_lock="${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap/configure.lock"
mkdir -p "$(dirname "$configure_lock")"
if ! mkdir "$configure_lock" 2>/dev/null; then
    warn "Configuration is locked at $configure_lock; confirm no configure process is running before removing it"
    exit 1
fi
trap 'rmdir "$configure_lock"' EXIT
DOTFILES_RELINK_ONLY=1
BOOTSTRAP_WORKSTATION=1
case "$configure_target" in
    terminal) link_terminal_config ;;
    pi) link_pi_config; link_pi_launchers ;;
    codex) link_codex_assets ;;
    neovim) setup_neovim_config ;;
    all) link_terminal_config; link_pi_config; link_pi_launchers; link_codex_assets; setup_neovim_config ;;
esac
