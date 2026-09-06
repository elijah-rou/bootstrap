#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home" DOTFILES_SKIP_LOCAL_ENV=1 DOTFILES_SOURCE_ONLY=1
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
export CODEX_HOME="$HOME/.codex"
mkdir -p "$HOME"
source "$ROOT_DIR/install.sh"

# All configuration is real; network/service/auth paths must never be invoked.
sudo() { echo 'unexpected sudo' >&2; exit 90; }
systemctl() { echo 'unexpected systemctl' >&2; exit 91; }
chsh() { echo 'unexpected chsh' >&2; exit 92; }
mkdir -p "$CODEX_HOME"
printf 'model = "keep-local-choice"\n' > "$CODEX_HOME/config.toml"
link_bare_config
link_bare_config
[[ -L "$HOME/.zshrc" && -L "$HOME/.pi/agent/AGENTS.md" ]]
[[ -L "$HOME/.pi/agent/themes/iroaseta.json" ]]
[[ -L "$HOME/.config/herdr/config.toml" ]]
[[ -L "$CODEX_HOME/AGENTS.md" ]]
[[ "$(cat "$CODEX_HOME/config.toml")" == 'model = "keep-local-choice"' ]]
[[ ! -e "$HOME/.pi/agent/auth.json" ]]
[[ ! -e "$HOME/.config/ghostty" && ! -e "$HOME/.config/systemd" ]]
[[ ! -e "$HOME/.config/prime" && ! -e "$HOME/.cursor" ]]
[[ ! -e "$HOME/.local/bin/searxng-ctl" ]]
[[ -z "$(find "$HOME" -name '*.bak.*' -print)" ]]
echo 'PASS bare links converge and preserve boundaries'

pi() { return 17; }
if install_pi_packages "$HOME/.pi/agent/settings.json"; then
    echo 'failed Pi package installation reported success' >&2
    exit 1
fi
[[ ${#install_failures[@]} -eq 5 ]]
echo 'PASS required Pi package failures propagate'

(
    # Read-only preflight rejects unsupported hosts without creating state.
    uname() { printf 'unsupported\n'; }
    if output="$(bare_preflight 2>&1)"; then exit 1; fi
    [[ "$output" == *'Bare supports'* ]]
    [[ ! -e "$HOME/.local/share/dotfiles/bare" ]]
)
echo 'PASS unsupported bare preflight makes no state'

(
    bare_preflight() { return 1; }
    install_bare_micromamba() { exit 93; }
    if install_bare; then exit 1; fi
    [[ ! -e "$HOME/.local/share/dotfiles/bare" ]]
)
echo 'PASS missing prerequisite stops before writes'

(
    bare_preflight() { :; }
    install_bare_micromamba() { return 19; }
    install_bare_environment() { touch "$fixture/unexpected"; }
    if install_bare; then exit 1; fi
    [[ ! -e "$fixture/unexpected" ]]
    [[ ! -d "$HOME/.local/share/dotfiles/bare/install.lock" ]]
    if install_bare; then exit 1; fi
    [[ ! -d "$HOME/.local/share/dotfiles/bare/install.lock" ]]
)
echo 'PASS bootstrap failures stop and release lock for retry'

(
    bare_preflight() { :; }
    mkdir -p "$HOME/.local/share/dotfiles/bare/install.lock"
    install_bare_micromamba() { touch "$fixture/unexpected"; }
    if install_bare; then exit 1; fi
    [[ ! -e "$fixture/unexpected" ]]
    [[ -d "$HOME/.local/share/dotfiles/bare/install.lock" ]]
    rmdir "$HOME/.local/share/dotfiles/bare/install.lock"
)
echo 'PASS overlapping or interrupted lock is preserved and rejected'

(
    download_verified() { return 1; }
    herdr() { touch "$fixture/unexpected"; }
    if install_herdr; then exit 1; fi
    [[ ! -e "$fixture/unexpected" ]]
)
echo 'PASS Herdr checksum failure stops before execution'

(
    source "$ROOT_DIR/scripts/bare-env.sh"
    mkdir -p "$DOTFILES_BARE_ROOT/bin"
    cat > "$DOTFILES_BARE_ROOT/bin/micromamba" <<'MAMBA'
#!/usr/bin/env bash
set -eu
[[ "$1" == --no-rc ]]
printf '%s\n' "$2" >> "$DOTFILES_BARE_ROOT/operations"
mkdir -p "$DOTFILES_BARE_ROOT/env/conda-meta"
MAMBA
    chmod +x "$DOTFILES_BARE_ROOT/bin/micromamba"
    install_bare_environment
    install_bare_environment
    [[ "$(cat "$DOTFILES_BARE_ROOT/operations")" == $'create\ninstall' ]]
    rmdir "$DOTFILES_BARE_ROOT/env/conda-meta"
    if install_bare_environment; then exit 1; fi
    [[ "$(cat "$DOTFILES_BARE_ROOT/operations")" == $'create\ninstall' ]]
)
echo 'PASS environment retry reconciles and rejects incomplete prefixes'

(
    export HOME="$fixture/herdr-fresh"
    mkdir -p "$HOME"
    download_verified() { printf '#!/bin/sh\nexit 0\n' > "$3"; }
    herdr() {
        if [[ "$1" == integration ]]; then
            [[ -d "$HOME/.pi/agent/extensions" ]] || return 1
            touch "$HOME/integration-installed"
        fi
    }
    install_herdr
    [[ -f "$HOME/integration-installed" ]]
)
echo 'PASS Herdr integration initializes a fresh Pi extension directory'

(
    bare_platform() { printf 'linux-64\n'; }
    getconf() { return 1; }
    if bare_preflight; then exit 1; fi
)
echo 'PASS musl or unavailable libc detection fails preflight'

(
    export HOME="$fixture/invalid-arguments"
    mkdir -p "$HOME"
    unset DOTFILES_SOURCE_ONLY
    for command in bare bare-preflight bare-doctor; do
        status=0
        bash "$ROOT_DIR/install.sh" "$command" --dry-run >/dev/null 2>&1 || status=$?
        [[ $status -eq 2 ]]
    done
    [[ ! -e "$HOME/.local" ]]
)
echo 'PASS unknown bare arguments are rejected before installation'

(
    export HOME="$fixture/neovim-profile"
    mkdir -p "$HOME"
    bare_preflight() { :; }
    install_bare_micromamba() { :; }
    install_bare_environment() { :; }
    install_bare_rust() { echo 'unexpected default Rust toolchain' >&2; exit 95; }
    npm() { printf '%s\n' "$@" > "$HOME/npm-packages"; }
    pi() { printf '%s\n' "$PI_CLI_VERSION"; }
    install_herdr() { :; }
    link_bare_config() { :; }
    install_pi_packages() { :; }
    report_install_failures() { :; }
    bare_doctor() { :; }
    setup_neovim_config() {
        printf '%s\n' "$NVIM_CONFIG_REPO_URL" > "$HOME/nvim-source"
        return "${nvim_status:-0}"
    }
    unset NVIM_CONFIG_REPO_URL
    install_bare
    [[ "$(cat "$HOME/nvim-source")" == https://github.com/elijah-rou/lazyvim-config.git ]]
    [[ "$(cat "$HOME/npm-packages")" == "$(printf '%s\n' install --global "$PI_CLI_PACKAGE@$PI_CLI_VERSION" @openai/codex)" ]]
    NVIM_CONFIG_REPO_URL=https://example.invalid/custom-nvim.git install_bare
    [[ "$(cat "$HOME/nvim-source")" == https://example.invalid/custom-nvim.git ]]
    nvim_status=17
    if install_bare; then exit 1; fi
    [[ ! -d "$HOME/.local/share/dotfiles/bare/install.lock" ]]
)
echo 'PASS bare installs the public Neovim config, honors overrides, and propagates failure'

(
    export HOME="$fixture/neovim-home" XDG_CONFIG_HOME="$fixture/neovim-home/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
    export NVIM_CONFIG_REPO_URL="$fixture/neovim-source"
    export NVIM_CONFIG_CHECKOUT_DIR="$XDG_DATA_HOME/dotfiles/lazyvim-config"
    mkdir -p "$NVIM_CONFIG_REPO_URL" "$XDG_CONFIG_HOME/nvim"
    printf 'return {}\n' > "$NVIM_CONFIG_REPO_URL/init.lua"
    printf 'personal\n' > "$XDG_CONFIG_HOME/nvim/keep.lua"
    git -C "$NVIM_CONFIG_REPO_URL" init -q
    git -C "$NVIM_CONFIG_REPO_URL" add init.lua
    git -C "$NVIM_CONFIG_REPO_URL" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm initial
    NVIM_CONFIG_REPO_URL='' setup_neovim_config
    [[ ! -e "$NVIM_CONFIG_CHECKOUT_DIR" ]]
    DOTFILES_RELINK_ONLY=1 setup_neovim_config
    [[ ! -e "$NVIM_CONFIG_CHECKOUT_DIR" ]]
    setup_neovim_config
    [[ "$(readlink "$XDG_CONFIG_HOME/nvim")" == "$NVIM_CONFIG_CHECKOUT_DIR" ]]
    [[ "$(cat "$XDG_CONFIG_HOME"/nvim.bak.*/keep.lua)" == personal ]]
    (
        mkdir -p "$HOME/.config/dotfiles" "$HOME/.local/share/dotfiles/bare/bin" "$HOME/.local/share/dotfiles/bare/env/conda-meta"
        ln -s "$ROOT_DIR/scripts/bare-env.sh" "$HOME/.config/dotfiles/bare-env.sh"
        printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/share/dotfiles/bare/bin/micromamba"
        chmod +x "$HOME/.local/share/dotfiles/bare/bin/micromamba"
        for tool in git delta gh ssh zsh tmux nvim rg fzf bat eza jq python3 node npm bun codex herdr; do
            if ! command -v "$tool" >/dev/null; then eval "$tool() { :; }"; fi
        done
        pi() { printf '%s\n' "$PI_CLI_VERSION"; }
        rust-analyzer() { return 99; }
        check_pi_subagents_revision() { :; }
        bare_doctor > "$HOME/doctor-output" 2>&1 || { cat "$HOME/doctor-output"; exit 1; }
        mv "$XDG_CONFIG_HOME/nvim" "$XDG_CONFIG_HOME/saved-nvim"
        if bare_doctor > "$HOME/doctor-output" 2>&1; then exit 1; fi
        mkdir "$XDG_CONFIG_HOME/nvim"
        printf 'return {}\n' > "$XDG_CONFIG_HOME/nvim/init.lua"
        if bare_doctor > "$HOME/doctor-output" 2>&1; then exit 1; fi
        [[ "$(cat "$HOME/doctor-output")" == *'Neovim configuration is missing or not linked'* ]]
        rm "$XDG_CONFIG_HOME/nvim/init.lua"
        rmdir "$XDG_CONFIG_HOME/nvim"
        mv "$XDG_CONFIG_HOME/saved-nvim" "$XDG_CONFIG_HOME/nvim"
    )
    first_revision="$(git -C "$NVIM_CONFIG_CHECKOUT_DIR" rev-parse HEAD)"
    setup_neovim_config
    [[ "$(find "$XDG_CONFIG_HOME" -maxdepth 1 -name 'nvim.bak.*' | wc -l)" -eq 1 ]]
    printf 'return { updated = true }\n' > "$NVIM_CONFIG_REPO_URL/init.lua"
    git -C "$NVIM_CONFIG_REPO_URL" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qam update
    setup_neovim_config
    [[ "$(git -C "$NVIM_CONFIG_CHECKOUT_DIR" rev-parse HEAD)" != "$first_revision" ]]
    printf 'local edit\n' > "$NVIM_CONFIG_CHECKOUT_DIR/init.lua"
    setup_neovim_config
    [[ "$(cat "$NVIM_CONFIG_CHECKOUT_DIR/init.lua")" == 'local edit' ]]
    git -C "$NVIM_CONFIG_CHECKOUT_DIR" checkout -- init.lua

    if NVIM_CONFIG_REPO_URL="$fixture/different-repo" setup_neovim_config; then exit 1; fi
    [[ "$(git -C "$NVIM_CONFIG_CHECKOUT_DIR" remote get-url origin)" == "$NVIM_CONFIG_REPO_URL" ]]
    (
        git() { if [[ "${3:-}" == pull ]]; then return 19; fi; command git "$@"; }
        if setup_neovim_config; then exit 1; fi
        [[ "$(readlink "$XDG_CONFIG_HOME/nvim")" == "$NVIM_CONFIG_CHECKOUT_DIR" ]]
    )

    (
        git() { echo 'unexpected network in offline relink' >&2; exit 94; }
        DOTFILES_RELINK_ONLY=1 setup_neovim_config
    )
    mkdir "$NVIM_CONFIG_CHECKOUT_DIR.install.lock"
    if setup_neovim_config; then exit 1; fi
    [[ -d "$NVIM_CONFIG_CHECKOUT_DIR.install.lock" ]]
    rmdir "$NVIM_CONFIG_CHECKOUT_DIR.install.lock"

    original_link="$(readlink "$XDG_CONFIG_HOME/nvim")"
    NVIM_CONFIG_CHECKOUT_DIR="$XDG_DATA_HOME/dotfiles/failed-clone"
    (
        git() { mkdir -p "$NVIM_CONFIG_CHECKOUT_DIR"; return 19; }
        if setup_neovim_config; then exit 1; fi
        [[ "$(readlink "$XDG_CONFIG_HOME/nvim")" == "$original_link" ]]
    )
    if setup_neovim_config; then exit 1; fi
    [[ -d "$NVIM_CONFIG_CHECKOUT_DIR" && ! -L "$NVIM_CONFIG_CHECKOUT_DIR" ]]
    rmdir "$NVIM_CONFIG_CHECKOUT_DIR"
    setup_neovim_config
    [[ -f "$XDG_CONFIG_HOME/nvim/init.lua" ]]
    (
        XDG_CONFIG_HOME="$HOME/in-place"
        NVIM_CONFIG_CHECKOUT_DIR="$XDG_CONFIG_HOME/nvim"
        git clone -q "$NVIM_CONFIG_REPO_URL" "$NVIM_CONFIG_CHECKOUT_DIR"
        setup_neovim_config
        [[ -f "$XDG_CONFIG_HOME/nvim/init.lua" && ! -L "$XDG_CONFIG_HOME/nvim" ]]
    )
)
echo 'PASS Neovim clone, update, retry, backup, local edits, offline relink, and failure recovery'
