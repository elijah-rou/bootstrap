#!/usr/bin/env bash
# User-local terminal development; never invokes workstation setup.

link_bare_config() {
    link_terminal_config || return 1
    link_managed_file "$DOTFILES_DIR/scripts/bare-env.sh" "$HOME/.config/dotfiles/bare-env.sh" || return 1
    link_managed_file "$DOTFILES_DIR/scripts/dev-shell" "$HOME/.local/bin/dev-shell" || return 1
    DOTFILES_SKIP_AUTH_INSTALL=1 link_pi_config || return 1
    link_managed_file "$DOTFILES_DIR/scripts/pi-workspace" "$HOME/.local/bin/pi-workspace" || return 1
    link_managed_file "$DOTFILES_DIR/scripts/pi-workspace" "$HOME/.local/bin/piw" || return 1
    link_pi_headroom || return 1
    link_codex_assets || return 1
    local codex_home="${CODEX_HOME:-$HOME/.codex}"
    if [[ ! -e "$codex_home/config.toml" && ! -L "$codex_home/config.toml" ]]; then
        install_managed_file "$DOTFILES_DIR/codex/config.toml" "$codex_home/config.toml" 0600 || return 1
    fi
}

bare_platform() {
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64) printf 'linux-64\n' ;;
        Linux/aarch64|Linux/arm64) printf 'linux-aarch64\n' ;;
        Darwin/arm64) printf 'osx-arm64\n' ;;
        *) warn 'Bare supports glibc Linux x86_64/aarch64 and macOS arm64' >&2; return 1 ;;
    esac
}

bare_preflight() {
    local command platform failed=0
    platform="$(bare_platform)" || return 1
    if [[ "$platform" == linux-* ]] && ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
        warn 'Bare requires glibc Linux and getconf; musl/Alpine is unsupported'
        failed=1
    fi
    for command in curl awk; do
        if ! command -v "$command" >/dev/null 2>&1; then
            warn "Bootstrap prerequisite missing: $command (ask the host administrator)"
            failed=1
        fi
    done
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        warn 'Bootstrap requires sha256sum or shasum'
        failed=1
    fi
    if [[ ! -d "$HOME" || ! -w "$HOME" ]]; then
        warn 'Bare needs an existing writable HOME'
        failed=1
    fi
    if [[ "${XDG_CONFIG_HOME:-$HOME/.config}" != "$HOME/.config" ]]; then
        warn 'Shared dotfiles currently require XDG_CONFIG_HOME=$HOME/.config'
        failed=1
    fi
    if [[ "$platform" == osx-arm64 ]] && ! xcode-select -p >/dev/null 2>&1; then
        warn 'macOS needs Xcode Command Line Tools supplied by the host administrator'
        failed=1
    fi
    return "$failed"
}

install_bare_micromamba() {
    local platform="$1" sha executable
    case "$platform" in
        linux-64) sha=366cd9cd8be14df1ab8ed50352a82111082a36686b2d389fdb79a92c3fafb3e3 ;;
        linux-aarch64) sha=9f93b974adcb4d166996af969b6cd371287d1a3e52733704727884d9b74cb7a7 ;;
        osx-arm64) sha=ec2a072f028e1a7cf20f3e2e74d5a8127cf5a5f27636375b5359811565f4e5be ;;
        *) return 1 ;;
    esac
    if [[ -x "$DOTFILES_BARE_ROOT/bin/micromamba" ]] &&
        [[ "$("$DOTFILES_BARE_ROOT/bin/micromamba" --version)" == 2.9.0 ]]; then
        return 0
    fi
    executable="$bare_stage/micromamba"
    download_verified "https://github.com/mamba-org/micromamba-releases/releases/download/2.9.0-0/micromamba-$platform" "$sha" "$executable" || return 1
    chmod 0755 "$executable" || return 1
    [[ "$("$executable" --version)" == 2.9.0 ]] || return 1
    install_managed_file "$executable" "$DOTFILES_BARE_ROOT/bin/micromamba" 0755
}

install_bare_environment() {
    local package operation=create
    local packages=()
    while IFS= read -r package || [[ -n "$package" ]]; do
        case "$package" in ''|\#*) continue ;; *) packages+=("$package") ;; esac
    done < "$DOTFILES_DIR/packages/bare.txt"
    if [[ -d "$DOTFILES_BARE_ROOT/env/conda-meta" ]]; then
        operation=install
    elif [[ -e "$DOTFILES_BARE_ROOT/env" ]]; then
        warn "Incomplete environment at $DOTFILES_BARE_ROOT/env; move it aside and rerun bare"
        return 1
    fi
    "$DOTFILES_BARE_ROOT/bin/micromamba" --no-rc "$operation" --yes \
        --root-prefix "$MAMBA_ROOT_PREFIX" --prefix "$DOTFILES_BARE_ROOT/env" \
        --override-channels --channel conda-forge --strict-channel-priority "${packages[@]}"
}

bare_doctor() (
    local command failed=0
    [[ -f "$HOME/.config/dotfiles/bare-env.sh" ]] || { warn 'Bare profile is not linked'; return 1; }
    source "$HOME/.config/dotfiles/bare-env.sh"
    if [[ ! -x "$DOTFILES_BARE_ROOT/bin/micromamba" || ! -d "$DOTFILES_BARE_ROOT/env/conda-meta" ]]; then
        warn 'Bare package environment is missing; rerun bare'
        return 1
    fi
    for command in git delta gh ssh zsh tmux nvim rg fzf bat eza jq \
        python3 uv node npm bun rust-analyzer \
        basedpyright-langserver typescript-language-server bash-language-server shellcheck pi codex herdr; do
        if command -v "$command" >/dev/null 2>&1; then
            info "$command: $(command -v "$command")"
        else
            warn "Missing required command: $command"
            failed=1
        fi
    done
    if [[ "$(pi --version 2>/dev/null)" != "$PI_CLI_VERSION" ]]; then
        warn "Pi must be $PI_CLI_VERSION"
        failed=1
    fi
    rust-analyzer --version >/dev/null 2>&1 || failed=1
    check_pi_subagents_revision || failed=1
    local nvim_config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    local nvim_checkout="${NVIM_CONFIG_CHECKOUT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/lazyvim-config}"
    if [[ ! -f "$nvim_config/init.lua" || "$(resolve_path "$nvim_config")" != "$(resolve_path "$nvim_checkout")" ]]; then
        warn 'Neovim configuration is missing or not linked to its checkout; rerun bare'
        failed=1
    fi
    info 'Optional: SearXNG/web search, Headroom, desktop clipboard and the host privilege backend require separate setup'
    info 'Provider authentication remains machine-local; configure it interactively'
    return "$failed"
)

install_bare() (
    bare_preflight || return 1
    # A fixed owned prefix keeps retries and shell entry independent of checkout location.
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    mkdir -p "$DOTFILES_BARE_ROOT" || return 1
    if ! mkdir "$DOTFILES_BARE_ROOT/install.lock" 2>/dev/null; then
        warn "Bare install is locked. After confirming no installer is running, remove $DOTFILES_BARE_ROOT/install.lock and retry"
        return 1
    fi
    local bare_stage
    bare_stage="$(mktemp -d "$DOTFILES_BARE_ROOT/stage.XXXXXX")" || {
        rmdir "$DOTFILES_BARE_ROOT/install.lock"
        return 1
    }
    trap 'rm -rf "$bare_stage"; rmdir "$DOTFILES_BARE_ROOT/install.lock"' EXIT
    install_bare_micromamba "$(bare_platform)" || return 1
    install_bare_environment || return 1
    hash -r
    npm install --global "$PI_CLI_PACKAGE@$PI_CLI_VERSION" @openai/codex \
        basedpyright typescript@6 typescript-language-server@6 bash-language-server || return 1
    [[ "$(pi --version)" == "$PI_CLI_VERSION" ]] || return 1
    HERDR_INSTALL_DIR="$DOTFILES_BARE_ROOT/bin" install_herdr || return 1
    link_bare_config || return 1
    NVIM_CONFIG_REPO_URL="${NVIM_CONFIG_REPO_URL:-https://github.com/elijah-rou/lazyvim-config.git}" setup_neovim_config || return 1
    install_pi_packages "$HOME/.pi/agent/settings.json" || return 1
    report_install_failures || return 1
    bare_doctor || return 1
    info 'Bare development installed. Run ~/.local/bin/dev-shell to enter it.'
)

install_bare_rust() {
    local target sha
    case "$(bare_platform)" in
        linux-64) target=x86_64-unknown-linux-gnu; sha=20a06e644b0d9bd2fbdbfd52d42540bdde820ea7df86e92e533c073da0cdd43c ;;
        linux-aarch64) target=aarch64-unknown-linux-gnu; sha=e3853c5a252fca15252d07cb23a1bdd9377a8c6f3efa01531109281ae47f841c ;;
        osx-arm64) target=aarch64-apple-darwin; sha=20ef5516c31b1ac2290084199ba77dbbcaa1406c45c1d978ca68558ef5964ef5 ;;
        *) return 1 ;;
    esac
    if [[ ! -x "$CARGO_HOME/bin/rustup" ]]; then
        download_verified "https://static.rust-lang.org/rustup/archive/1.28.2/$target/rustup-init" "$sha" "$bare_stage/rustup-init" || return 1
        chmod 0755 "$bare_stage/rustup-init" || return 1
        "$bare_stage/rustup-init" -y --no-modify-path --profile minimal --default-toolchain none || return 1
    fi
    "$CARGO_HOME/bin/rustup" toolchain install stable --profile minimal --component rust-analyzer,rust-src,rustfmt,clippy || return 1
    "$CARGO_HOME/bin/rustup" default stable
}

install_bare_languages() (
    [[ $# -gt 0 ]] || { warn 'Select one or more toolchains: c cpp rust go'; return 2; }
    local language with_rust=0
    local packages=()
    for language in "$@"; do
        case "$language" in
            c) packages+=(c-compiler make pkg-config) ;;
            cpp) packages+=(cxx-compiler make pkg-config) ;;
            rust) with_rust=1; packages+=(c-compiler make pkg-config) ;;
            go) packages+=(go) ;;
            *) warn "Unknown toolchain: $language (choose c, cpp, rust, go)"; return 2 ;;
        esac
    done
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    [[ -x "$DOTFILES_BARE_ROOT/bin/micromamba" && -d "$DOTFILES_BARE_ROOT/env/conda-meta" ]] || {
        warn 'Install the bare environment before adding toolchains'
        return 1
    }
    if ! mkdir "$DOTFILES_BARE_ROOT/install.lock"; then
        warn "Install is locked at $DOTFILES_BARE_ROOT/install.lock; check for a running installer before removing it"
        return 1
    fi
    local bare_stage
    bare_stage="$(mktemp -d "$DOTFILES_BARE_ROOT/stage.XXXXXX")" || {
        rmdir "$DOTFILES_BARE_ROOT/install.lock"
        return 1
    }
    trap 'rm -rf "$bare_stage"; rmdir "$DOTFILES_BARE_ROOT/install.lock"' EXIT
    "$DOTFILES_BARE_ROOT/bin/micromamba" --no-rc install --yes \
        --root-prefix "$MAMBA_ROOT_PREFIX" --prefix "$DOTFILES_BARE_ROOT/env" \
        --override-channels --channel conda-forge --strict-channel-priority "${packages[@]}" || return 1
    if [[ $with_rust -eq 1 ]]; then install_bare_rust || return 1; fi
    info 'Selected toolchains installed. Run builds inside dev-shell.'
)
