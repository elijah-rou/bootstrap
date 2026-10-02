#!/usr/bin/env bash
# Runs tests/roundtrip.sh in a fresh container as root or as an account without sudo.
# Usage: tests/container.sh IMAGE root|user [install arguments...]
set -euo pipefail

image="${1:?usage: container.sh IMAGE root|user [install arguments...]}"
account="${2:?usage: container.sh IMAGE root|user [install arguments...]}"
shift 2
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The baseline every supported host is expected to have: git, curl, tar, gzip, xz.
prepare='
if command -v apt-get >/dev/null; then apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl ca-certificates xz-utils >/dev/null
elif command -v dnf >/dev/null; then dnf install -y -q git curl tar gzip xz findutils diffutils >/dev/null
elif command -v pacman >/dev/null; then pacman -Sy --noconfirm --needed git curl tar gzip xz diffutils >/dev/null
fi'

case "$account" in
    root) run='tests/roundtrip.sh /src "$@"' ;;
    user) run='useradd --create-home tester && su tester -c "cd /src && tests/roundtrip.sh /src $*"' ;;
    *) printf 'account must be root or user\n' >&2; exit 2 ;;
esac

docker run --rm -v "$repo:/src:ro" -w /src "$image" bash -c "$prepare
$run" roundtrip "$@"
