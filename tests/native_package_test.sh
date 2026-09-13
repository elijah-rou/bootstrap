#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"; mkdir -p "$HOME"; source "$ROOT/install.sh"
BOOTSTRAP_PACKAGE_BACKEND=apt; [[ "$(native_backend)" == apt ]]
metadata="$(catalog_query package gh pacman)"; [[ "$metadata" == $'gh\tgithub-cli' ]]
metadata="$(catalog_query package fd apt)"; [[ "$metadata" == $'fd\tfd-find' ]]
commands="$fixture/commands"
id() { [[ "$1" == -u ]] && printf '0\n'; }
native_package_installed() { return 0; }
apt-get() { printf 'apt-get %s\n' "$*" >>"$commands"; }
native_remove_names apt fixture-package
grep -q '^apt-get --simulate remove fixture-package$' "$commands"
grep -q '^apt-get remove --yes fixture-package$' "$commands"
! grep -q autoremove "$commands"
apt-get() { if [[ "$*" == --simulate* ]]; then printf 'Remv fixture-package [1]\nRemv unrelated-dependent [2]\n'; else return 99; fi; }
if native_remove_names apt fixture-package; then exit 1; fi
brew() { if [[ "$1" == uses ]]; then printf 'dependent\n'; else printf 'unexpected brew mutation\n' >&2; return 99; fi; }
if native_remove_names brew shared-package; then exit 1; fi
echo 'PASS native backend names, removal preview, no autoremove, and shared-package protection'
