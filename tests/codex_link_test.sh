#!/usr/bin/env bash
set -euo pipefail
export DOTFILES_SKIP_LOCAL_ENV=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

(
    export HOME="$scratch/normal"
    unset CODEX_HOME
    mkdir -p "$HOME/.codex/skills" "$HOME/.agents/skills"
    printf 'model = "keep-current-model"\n' >"$HOME/.codex/config.toml"
    printf '{"fixture":true}\n' >"$HOME/.codex/auth.json"
    printf '{"hooks":{}}\n' >"$HOME/.codex/hooks.json"
    cp "$HOME/.codex/config.toml" "$scratch/config.before"
    cp "$HOME/.codex/auth.json" "$scratch/auth.before"
    cp "$HOME/.codex/hooks.json" "$scratch/hooks.before"
    ln -s "$ROOT_DIR/pi/AGENTS.md" "$HOME/.codex/AGENTS.md"
    ln -s /usr/share/omarchy/default/agents/skills/omarchy "$HOME/.codex/skills/omarchy"
    ln -s /usr/share/omarchy/default/agents/skills/omarchy "$HOME/.agents/skills/omarchy"
    bash "$ROOT_DIR/install.sh" codex-link
    [[ "$(readlink "$HOME/.codex/AGENTS.md")" == "$ROOT_DIR/codex/AGENTS.md" ]]
    [[ "$(readlink "$HOME/.codex/native-tools.md")" == "$ROOT_DIR/codex/native-tools.md" ]]
    while IFS= read -r skill || [[ -n "$skill" ]]; do
        [[ "$(readlink "$HOME/.agents/skills/$skill")" == "$ROOT_DIR/pi/skills/$skill" ]]
    done <"$ROOT_DIR/codex/skills.txt"
    [[ ! -L "$HOME/.codex/skills/omarchy" ]]
    backups_before="$(find "$HOME/.codex/backups" -type l | wc -l)"
    bash "$ROOT_DIR/install.sh" codex-link
    [[ "$backups_before" == "$(find "$HOME/.codex/backups" -type l | wc -l)" ]]
    cmp "$scratch/config.before" "$HOME/.codex/config.toml"
    cmp "$scratch/auth.before" "$HOME/.codex/auth.json"
    cmp "$scratch/hooks.before" "$HOME/.codex/hooks.json"
    [[ ! -e "$HOME/.pi" ]]
)
printf 'PASS Codex linking migrates managed aliases, preserves preferences, and converges\n'

(
    export HOME="$scratch/custom"
    export CODEX_HOME="$HOME/profile"
    mkdir -p "$HOME/.agents/skills/how" "$CODEX_HOME/skills/why" "$HOME/custom-omarchy"
    printf 'custom shared skill\n' >"$HOME/.agents/skills/how/SKILL.md"
    printf 'custom legacy skill\n' >"$CODEX_HOME/skills/why/SKILL.md"
    printf 'custom override\n' >"$CODEX_HOME/AGENTS.override.md"
    ln -s "$HOME/custom-omarchy" "$HOME/.agents/skills/omarchy"
    bash "$ROOT_DIR/install.sh" codex-link
    [[ "$(readlink "$CODEX_HOME/AGENTS.md")" == "$ROOT_DIR/codex/AGENTS.md" ]]
    [[ "$(readlink "$HOME/.agents/skills/omarchy")" == "$HOME/custom-omarchy" ]]
    [[ ! -L "$HOME/.agents/skills/how" ]]
    grep -qx 'custom shared skill' "$HOME/.agents/skills/how/SKILL.md"
    grep -qx 'custom legacy skill' "$CODEX_HOME/skills/why/SKILL.md"
    [[ ! -e "$HOME/.agents/skills/why" ]]
    grep -qx 'custom override' "$CODEX_HOME/AGENTS.override.md"
    [[ ! -e "$HOME/.codex" ]]
)
printf 'PASS Codex linking honors CODEX_HOME and preserves custom skill ownership\n'

(
    export HOME="$scratch/invalid"
    unset CODEX_HOME
    if bash "$ROOT_DIR/install.sh" codex-link unexpected; then
        printf 'Unexpected argument was accepted\n' >&2
        exit 1
    fi
    [[ ! -e "$HOME/.codex/AGENTS.md" ]]
)
printf 'PASS Codex linking rejects unexpected arguments before changing files\n'

(
    export HOME="$scratch/shared-root"
    unset CODEX_HOME
    mkdir -p "$HOME/.agents/skills" "$HOME/.codex"
    ln -s "$HOME/.agents/skills" "$HOME/.codex/skills"
    bash "$ROOT_DIR/install.sh" codex-link
    [[ -L "$HOME/.agents/skills/how" ]]
    [[ -L "$HOME/.codex/skills/how" ]]
    [[ ! -e "$HOME/.codex/backups/legacy-skills" ]]
)
printf 'PASS aliased skill roots retain the shared entries\n'

(
    export HOME="$scratch/invalid-manifest-home"
    unset CODEX_HOME
    DOTFILES_SOURCE_ONLY=1 source "$ROOT_DIR/install.sh"
    DOTFILES_DIR="$scratch/invalid-manifest"
    mkdir -p "$DOTFILES_DIR/codex"
    cp "$ROOT_DIR/codex/AGENTS.md" "$ROOT_DIR/codex/native-tools.md" "$DOTFILES_DIR/codex/"
    for entry in '' '../escape' 'Uppercase' 'missing-source'; do
        printf '%s\n' "$entry" >"$DOTFILES_DIR/codex/skills.txt"
        if link_codex_assets; then
            printf 'Invalid manifest was accepted: %s\n' "$entry" >&2
            exit 1
        fi
        [[ ! -e "$HOME/.codex" ]]
    done
    rm "$DOTFILES_DIR/codex/skills.txt"
    if link_codex_assets; then exit 1; fi
    [[ ! -e "$HOME/.codex" ]]
)
printf 'PASS invalid or missing manifests fail before linking\n'
