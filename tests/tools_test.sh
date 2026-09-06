#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home" CODEX_HOME="$fixture/home/.codex"
mkdir -p "$HOME"
source "$ROOT_DIR/install.sh"
npm() { printf 'Unexpected npm invocation\n' >&2; return 99; }
source "$ROOT_DIR/scripts/bare-env.sh"
for arguments in '--tools' '-t' '--tools just unknown' '-t rust'; do
    status=0
    # Fixed test inputs are intentionally split into argv.
    # shellcheck disable=SC2086
    bash "$ROOT_DIR/install.sh" $arguments || status=$?
    [[ $status -eq 2 && ! -e "$DOTFILES_BARE_ROOT" ]]
done
mkdir -p "$DOTFILES_BARE_ROOT/bin" "$DOTFILES_BARE_ROOT/env/conda-meta"
cat > "$DOTFILES_BARE_ROOT/bin/micromamba" <<'MAMBA'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HOME/packages"
exit "${MAMBA_STATUS:-0}"
MAMBA
chmod +x "$DOTFILES_BARE_ROOT/bin/micromamba"
for flag in --tools -t; do
    for tool in just wget unzip; do
        bash "$ROOT_DIR/install.sh" "$flag" "$tool"
        grep -Fxq "$tool" "$HOME/packages"
        [[ ! -e "$CODEX_HOME" && ! -d "$DOTFILES_BARE_ROOT/install.lock" ]]
    done
done
bun() { printf '%s\n' "$@" > "$HOME/js-packages"; return "${JS_STATUS:-0}"; }
install_bare_optional tools codex
[[ -L "$CODEX_HOME/AGENTS.md" && -f "$CODEX_HOME/config.toml" ]]
grep -Fxq @openai/codex "$HOME/js-packages"
printf 'model = "personal"\n' > "$CODEX_HOME/config.toml"
install_bare_optional tools codex
[[ "$(cat "$CODEX_HOME/config.toml")" == 'model = "personal"' ]]
MAMBA_STATUS=17
export MAMBA_STATUS
if install_bare_optional tools just codex; then exit 1; fi
[[ ! -d "$DOTFILES_BARE_ROOT/install.lock" ]]
unset MAMBA_STATUS
JS_STATUS=17
if install_bare_optional tools codex; then exit 1; fi
[[ ! -d "$DOTFILES_BARE_ROOT/install.lock" ]]
unset JS_STATUS
mkdir "$DOTFILES_BARE_ROOT/install.lock"
if install_bare_optional tools wget; then exit 1; fi
[[ -d "$DOTFILES_BARE_ROOT/install.lock" ]]
rmdir "$DOTFILES_BARE_ROOT/install.lock"
if grep -Eq '^(just|wget|unzip)(=|$)' "$ROOT_DIR/packages/bare.txt"; then exit 1; fi
printf 'PASS optional tools, dispatch, configuration, retries, failures, and locking\n'
