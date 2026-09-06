#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_SKIP_LOCAL_ENV=1

test_pi_subagents_doctor_detects_revision_and_tracked_drift() (
    source "$ROOT_DIR/install.sh"
    local temp_dir pin checkout
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT
    HOME="$temp_dir/home"
    DOTFILES_DIR="$temp_dir/dotfiles"
    checkout="$HOME/.pi/agent/git/github.com/elijah-rou/pi-subagents"
    mkdir -p "$DOTFILES_DIR/pi" "$HOME/.pi/agent" "$(dirname "$checkout")"
    git init -q "$checkout"
    git -C "$checkout" config user.email fixture@example.invalid
    git -C "$checkout" config user.name Fixture
    printf 'fixture\n' >"$checkout/file"
    git -C "$checkout" add file
    git -C "$checkout" commit -qm fixture
    pin="$(git -C "$checkout" rev-parse HEAD)"
    printf '{"packages":["git:github.com/elijah-rou/pi-subagents@%s"]}\n' "$pin" >"$DOTFILES_DIR/pi/settings.json"
    cp "$DOTFILES_DIR/pi/settings.json" "$HOME/.pi/agent/settings.json"

    check_pi_subagents_revision >/dev/null || return 1
    printf 'dirty\n' >>"$checkout/file"
    if check_pi_subagents_revision >/dev/null; then return 1; fi
    git -C "$checkout" reset --hard -q
    printf '{"packages":["git:github.com/elijah-rou/pi-subagents@0000000000000000000000000000000000000000"]}\n' >"$HOME/.pi/agent/settings.json"
    if check_pi_subagents_revision >/dev/null; then return 1; fi
)


test_pi_sub_limits_package_migration() (
    local mode="$1" name="${2:-sub-limits}" temp_dir source
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT
    HOME="$temp_dir/home"
    source "$ROOT_DIR/install.sh"
    mkdir -p "$HOME/.pi/agent/extensions" "$HOME/Projects/pi-$name"
    printf 'local work\n' >"$HOME/Projects/pi-$name/$name.ts"
    source="$(python3 - "$ROOT_DIR/pi/settings.json" "$name" <<'PYTHON'
import json, sys
packages = json.load(open(sys.argv[1]))["packages"]
print(next(p for p in packages if isinstance(p, str) and p.startswith("git:github.com/elijah-rou/pi-" + sys.argv[2] + "@")))
PYTHON
    )" || return 1
    python3 - "$temp_dir/settings.json" "$source" <<'PYTHON'
import json, sys
json.dump({"packages": [sys.argv[2]]}, open(sys.argv[1], "w"))
PYTHON
    local target="$HOME/Projects/pi-$name/$name.ts"
    if [[ "$mode" == custom ]]; then target="$temp_dir/custom.ts"; fi
    ln -s "$target" "$HOME/.pi/agent/extensions/$name.ts"
    pi() { [[ "$*" == "install $source" && "$mode" != failure ]]; }
    if [[ "$mode" == failure ]]; then
        if install_pi_packages "$temp_dir/settings.json"; then return 1; fi
        [[ -L "$HOME/.pi/agent/extensions/$name.ts" ]] || return 1
        [[ " ${install_failures[*]} " == *" pi-package:$source "* ]] || return 1
    else
        install_pi_packages "$temp_dir/settings.json" || return 1
        install_pi_packages "$temp_dir/settings.json" || return 1
        if [[ "$mode" == custom ]]; then
            [[ "$(readlink "$HOME/.pi/agent/extensions/$name.ts")" == "$target" ]] || return 1
        else
            [[ ! -L "$HOME/.pi/agent/extensions/$name.ts" ]] || return 1
        fi
    fi
    [[ "$(cat "$HOME/Projects/pi-$name/$name.ts")" == 'local work' ]]
)


test_pi_subagents_doctor_detects_revision_and_tracked_drift
printf 'PASS Pi-subagents doctor detects revision and tracked drift\n'
for package in sub-limits effort; do
    for mode in success custom failure; do
        test_pi_sub_limits_package_migration "$mode" "$package"
        printf 'PASS Pi %s migration: %s\n' "$package" "$mode"
    done
done
