#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"
mkdir -p "$HOME" "$fixture/zls" "$fixture/elixir-ls"
source "$ROOT_DIR/install.sh"
source "$ROOT_DIR/scripts/bare-env.sh"
export DOTFILES_BARE_ROOT
bare_stage="$fixture/stage"
mkdir "$bare_stage"
printf '#!/bin/sh\nprintf "0.16.0\\n"\n' > "$fixture/zls/zls"
printf '#!/bin/sh\nexit 0\n' > "$fixture/elixir-ls/language_server.sh"
printf 'fixture\n' > "$fixture/elixir-ls/quiet_install.exs"
chmod +x "$fixture/zls/zls" "$fixture/elixir-ls/language_server.sh"
tar -cJf "$fixture/zls.tar.xz" -C "$fixture/zls" zls
python3 - "$fixture" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1])
with zipfile.ZipFile(root / 'elixir-ls.zip', 'w') as archive:
    for path in (root / 'elixir-ls').iterdir():
        archive.write(path, path.name)
PY
# Production download verification is covered by bare_install_test.sh. These
# archives isolate activation and recovery from external release availability.
download_verified() {
    [[ "$1" == https://* && "$2" =~ ^[0-9a-f]{64}$ ]] || return 91
    printf '%s\n' "$1" >> "$fixture/downloads"
    [[ "${DOWNLOAD_STATUS:-0}" == 0 ]] || return "$DOWNLOAD_STATUS"
    case "$1" in
        */elixir-ls-*.zip) cp "$fixture/elixir-ls.zip" "$3" ;;
        */zls-*.tar.xz) cp "$fixture/zls.tar.xz" "$3" ;;
        *) return 92 ;;
    esac
}
elixir() { [[ "$MIX_ENV" == prod && -f "$1" ]]; return "${ELIXIR_STATUS:-0}"; }
for platform in linux-64 linux-aarch64 osx-arm64; do
    bare_platform() { printf '%s\n' "$platform"; }
    DOWNLOAD_STATUS=17
    status=0
    install_bare_zls || status=$?
    [[ $status -eq 1 && -s "$fixture/downloads" ]]
    : > "$fixture/downloads"
    [[ ! -e "$DOTFILES_BARE_ROOT/bin/zls" ]]
done
unset DOWNLOAD_STATUS
bare_platform() { printf 'linux-64\n'; }
: > "$fixture/downloads"
install_bare_zls
install_bare_elixir_ls
[[ -x "$DOTFILES_BARE_ROOT/bin/zls" && -x "$DOTFILES_BARE_ROOT/bin/elixir-ls" ]]
[[ $(wc -l < "$fixture/downloads") -eq 2 ]]
rm "$DOTFILES_BARE_ROOT/bin/zls" "$DOTFILES_BARE_ROOT/bin/elixir-ls"
install_bare_zls
install_bare_elixir_ls
[[ -x "$DOTFILES_BARE_ROOT/bin/zls" && -x "$DOTFILES_BARE_ROOT/bin/elixir-ls" ]]
[[ $(wc -l < "$fixture/downloads") -eq 2 ]]
ELIXIR_STATUS=18
if install_bare_elixir_ls; then exit 1; fi
[[ -x "$DOTFILES_BARE_ROOT/bin/elixir-ls" ]]
unset ELIXIR_STATUS
saved_root="$DOTFILES_BARE_ROOT"
DOTFILES_BARE_ROOT="$fixture/failure"
rm -rf "$bare_stage/elixir-ls"
ELIXIR_STATUS=18
if install_bare_elixir_ls; then exit 1; fi
[[ ! -e "$DOTFILES_BARE_ROOT/bin/elixir-ls" && ! -e "$DOTFILES_BARE_ROOT/tools/elixir-ls-0.31.1" ]]
unset ELIXIR_STATUS
rm -rf "$bare_stage/elixir-ls"
install_bare_elixir_ls
[[ -x "$DOTFILES_BARE_ROOT/bin/elixir-ls" ]]
mkdir -p "$DOTFILES_BARE_ROOT/tools/zls-0.16.0"
printf 'personal\n' > "$DOTFILES_BARE_ROOT/tools/zls-0.16.0/keep"
if install_bare_zls; then exit 1; fi
[[ "$(cat "$DOTFILES_BARE_ROOT/tools/zls-0.16.0/keep")" == personal ]]
DOTFILES_BARE_ROOT="$saved_root"
printf 'PASS release pins, activation, retries, relink, compile failure, and unowned state\n'
