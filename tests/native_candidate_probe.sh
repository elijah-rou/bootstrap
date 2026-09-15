#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$ROOT/install.sh"
backend="$(native_backend)"
for key in git compiler node neovim; do
    IFS=$'\t' read -r executable package <<<"$(catalog_query package "$key" "$backend")"
    [[ -n "$executable" && -n "$package" ]]
    native_package_available "$backend" "$package" || { printf 'Missing representative native candidate: %s/%s\n' "$backend" "$package" >&2; exit 1; }
done
printf 'PASS %s representative native candidates resolve\n' "$backend"
