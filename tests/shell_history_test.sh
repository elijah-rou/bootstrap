#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
for shell in bash zsh; do
    command -v "$shell" >/dev/null || { printf 'Missing test shell: %s\n' "$shell" >&2; exit 1; }
    env -i HOME="$fixture" PATH="$PATH" "$shell" -f -c '
        source "$1/scripts/bare-env.sh"
        [[ "$HISTFILE" == "$HOME/.local/share/bootstrap/private/$2/history" ]] || exit 1
        source "$1/scripts/bare-env.sh"
        [[ "$HISTFILE" == "$HOME/.local/share/bootstrap/private/$2/history" ]] || exit 1
    ' test "$ROOT" "$shell" || exit 1
done
printf 'PASS Bash and Zsh retain distinct history paths across repeated environment loading\n'
