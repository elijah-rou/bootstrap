#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"
mkdir -p "$HOME"
source "$ROOT_DIR/install.sh"
source "$ROOT_DIR/scripts/bare-env.sh"
for arguments in '' 'unknown' 'rust --bad'; do
    # These are fixed test inputs, intentionally split into argv.
    # shellcheck disable=SC2086
    if install_bare_languages $arguments; then exit 1; fi
    [[ ! -e "$DOTFILES_BARE_ROOT" ]]
done
if install_bare_languages c; then exit 1; fi
[[ ! -e "$DOTFILES_BARE_ROOT" ]]
mkdir -p "$DOTFILES_BARE_ROOT/bin" "$DOTFILES_BARE_ROOT/env/conda-meta"
cat > "$DOTFILES_BARE_ROOT/bin/micromamba" <<'MAMBA'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HOME/packages"
exit "${MAMBA_STATUS:-0}"
MAMBA
chmod +x "$DOTFILES_BARE_ROOT/bin/micromamba"
install_bare_rust() { touch "$HOME/rust-installed"; }
for selection in c cpp go; do
    install_bare_languages "$selection"
    [[ ! -e "$HOME/rust-installed" ]]
    [[ ! -d "$DOTFILES_BARE_ROOT/install.lock" ]]
    case "$selection" in
        c) expected=c-compiler ;;
        cpp) expected=cxx-compiler ;;
        go) expected=go ;;
    esac
    grep -Fxq "$expected" "$HOME/packages"
done
install_bare_languages rust
[[ -e "$HOME/rust-installed" ]]
grep -Fxq c-compiler "$HOME/packages"
rm "$HOME/rust-installed"
MAMBA_STATUS=17
export MAMBA_STATUS
if install_bare_languages rust; then exit 1; fi
[[ ! -e "$HOME/rust-installed" && ! -d "$DOTFILES_BARE_ROOT/install.lock" ]]
unset MAMBA_STATUS
install_bare_languages c cpp go
mkdir "$DOTFILES_BARE_ROOT/install.lock"
if install_bare_languages go; then exit 1; fi
[[ -d "$DOTFILES_BARE_ROOT/install.lock" ]]
rmdir "$DOTFILES_BARE_ROOT/install.lock"
if grep -Eq '^(c-compiler|cxx-compiler|rust|rustup|cargo|go)(=|$)' "$ROOT_DIR/packages/bare.txt"; then exit 1; fi
grep -Fxq rust-analyzer "$ROOT_DIR/packages/bare.txt"
printf 'PASS language selection, invalid input, no default toolchains, failures and locking\n'
