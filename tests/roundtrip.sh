#!/usr/bin/env bash
# Install from a copy of SOURCE, check it works, uninstall, and require HOME and the system
# package list to match their state before install. Run it in a disposable account or container.
# Usage: tests/roundtrip.sh SOURCE [install arguments...]
set -euo pipefail

source_dir="$(cd "${1:?usage: roundtrip.sh SOURCE [install arguments...]}" && pwd)"
shift
checkout="$HOME/bootstrap"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Paths and hashes under HOME, plus installed packages, excluding the checkout itself.
snapshot() {
    (
        cd "$HOME"
        find . -mindepth 1 ! -path './bootstrap' ! -path './bootstrap/*' -print | LC_ALL=C sort | while IFS= read -r path; do
            if [[ -L "$path" ]]; then printf 'link %s -> %s\n' "$path" "$(readlink "$path")"
            elif [[ -f "$path" ]]; then printf 'file %s %s\n' "$path" "$(cksum <"$path")"
            else printf 'dir  %s\n' "$path"; fi
        done
    )
    if command -v dpkg-query >/dev/null; then dpkg-query -W -f='package ${Package}\n'
    elif command -v rpm >/dev/null; then rpm -qa --qf 'package %{NAME}\n'
    elif command -v pacman >/dev/null; then pacman -Qq | sed 's/^/package /'
    elif command -v brew >/dev/null; then brew list --formula -1 | sed 's/^/package /'
    fi | LC_ALL=C sort
}

[[ ! -e "$checkout" ]] || { printf '%s already exists\n' "$checkout" >&2; exit 1; }
snapshot >"$work/before"
cp -R "$source_dir" "$checkout"

"$checkout/install.sh" "$@"
"$checkout/install.sh" "$@"   # a rerun must converge without errors
"$checkout/install.sh" link   # configuration-only relink
"$checkout/install.sh" doctor
bash -ic 'set -e; for command in hx rg fd fzf bat jq delta gh zoxide node hyperfine; do command -v "$command" >/dev/null; done; hx --version; node -e "console.log(process.versions.bun)"; hyperfine --version; hyperfine --shell=none --runs 2 "sleep 0.01"'
# Bootstrap's tools come first on PATH in login shells too, after macOS path_helper has run.
tools="$HOME/.local/share/bootstrap/tools/bin"
[[ "$(bash -lc 'printf %s "${PATH%%:*}"')" == "$tools" ]] || { printf 'FAIL: bash login PATH does not start with %s\n' "$tools" >&2; exit 1; }
if grep -qx "select	tools	zsh" "$HOME/.local/share/bootstrap/state.tsv"; then
    [[ "$(zsh -lc 'printf %s "${PATH%%:*}"')" == "$tools" ]] || { printf 'FAIL: zsh login PATH does not start with %s\n' "$tools" >&2; exit 1; }
fi
# Selected agents must start from an interactive shell; Claude also runs a Mod command, which writes its
# caches, at zero model cost.
for agent in pi claude codex herdr; do
    if grep -qx "select	tools	$agent" "$HOME/.local/share/bootstrap/state.tsv"; then bash -ic "$agent --version" >/dev/null; fi
done
if grep -qx "select	tools	claude" "$HOME/.local/share/bootstrap/state.tsv"; then
    bash -ic 'cd "$(mktemp -d)" && claude --print /tps --output-format json --no-session-persistence --max-budget-usd 0.01' | grep -q '"total_cost_usd":0'
fi

# A signed-in gh (file storage) must be signed out without stalling uninstall.
bash -c '. "$HOME/.local/share/bootstrap/repo/shell/env.sh"
printf "github.com:\n    oauth_token: gho_roundtrip\n    user: roundtrip\n    git_protocol: https\n" >"$GH_CONFIG_DIR/hosts.yml"
gh auth status --hostname github.com >/dev/null 2>&1 || true'

"$checkout/install.sh" uninstall --yes
rm -rf "$checkout"
snapshot >"$work/after"

if ! diff -u "$work/before" "$work/after"; then
    printf 'FAIL: uninstall left changes behind\n' >&2
    exit 1
fi
printf 'PASS: install, rerun, doctor, and uninstall left HOME and packages unchanged\n'
