#!/usr/bin/env bash
# Build CI fixtures from an empty application home, not a developer's plugin cache.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -eq 1 ]] || { printf 'Usage: %s ABSENT_CACHE_DIRECTORY\n' "$0" >&2; exit 2; }
cache_root="$1"
[[ "$cache_root" == /* && ! -e "$cache_root" && ! -L "$cache_root" ]] || { printf 'Fixture directory must be absolute and absent\n' >&2; exit 2; }
for command in node nvim cc git curl tar gzip; do command -v "$command" >/dev/null || { printf '%s is required\n' "$command" >&2; exit 1; }; done
mkdir -m 0700 "$cache_root"
cache_root="$(cd "$cache_root" && pwd -P)"
export HOME="$cache_root/home" XDG_CONFIG_HOME="$cache_root/home/.config" XDG_DATA_HOME="$cache_root/home/.local/share" XDG_STATE_HOME="$cache_root/home/.local/state" XDG_CACHE_HOME="$cache_root/home/.cache"
export NVIM_LEETCODE_MODE=0
unset DOTFILES_BARE_ROOT BOOTSTRAP_PRIVATE_ROOT BOOTSTRAP_STATE_ROOT NVIM_CONFIG_REPO_URL NVIM_CONFIG_CHECKOUT_DIR BOOTSTRAP_NEOVIM_PROFILE
mkdir -m 0700 "$HOME"
cd "$cache_root"
source "$ROOT/install.sh"
source "$ROOT/scripts/bare-env.sh"
bash "$ROOT/configure.sh" neovim
bare_stage="$(mktemp -d "$BOOTSTRAP_STATE_ROOT/fixture.XXXXXX")"
trap 'rm -rf "$bare_stage"' EXIT
install_upstream_tool tree-sitter
case "$(bare_platform)" in
    linux-64) artifact=rust-analyzer-x86_64-unknown-linux-gnu.gz; checksum=23f711d86b5f826e22886f01d7355dc01e0f4c1357dafa29710a95b903b48c85 ;;
    osx-arm64) artifact=rust-analyzer-aarch64-apple-darwin.gz; checksum=54ec873d8996e2c127d758bf45d4eacb6d3371dae4f6f6d5d3f05cedbae5fd59 ;;
    *) printf 'No pinned standalone Rust fixture for this CI platform\n' >&2; exit 1 ;;
esac
download_verified "https://github.com/rust-lang/rust-analyzer/releases/download/2026-09-28/$artifact" "$checksum" "$bare_stage/rust-analyzer.gz"
mkdir "$cache_root/bin"
gzip -dc "$bare_stage/rust-analyzer.gz" > "$cache_root/bin/rust-analyzer"
chmod 0755 "$cache_root/bin/rust-analyzer"
"$cache_root/bin/rust-analyzer" --version
install_neovim_parsers
verify_neovim_runtime
printf 'PASS cold locked Neovim runtime and standalone Rust fixture prepared in %s\n' "$cache_root"
