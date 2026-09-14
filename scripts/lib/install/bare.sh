#!/usr/bin/env bash
# Native Bash-first terminal development; never invokes workstation setup.

link_bare_config() {
    link_terminal_config || return 1
    link_managed_file "$DOTFILES_DIR/scripts/bare-env.sh" "$HOME/.config/dotfiles/bare-env.sh" || return 1
    link_managed_file "$DOTFILES_DIR/scripts/dev-shell" "$HOME/.local/bin/dev-shell" || return 1
    link_pi_config || return 1
    link_pi_launchers || return 1
}

link_bare_codex_config() (
    export CODEX_HOME="$BOOTSTRAP_PRIVATE_ROOT/codex"
    node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$BOOTSTRAP_PRIVATE_ROOT" || return 1
    link_codex_assets || return 1
    [[ -e "$CODEX_HOME/config.toml" || -L "$CODEX_HOME/config.toml" ]] || install_managed_file "$DOTFILES_DIR/codex/config.toml" "$CODEX_HOME/config.toml" 0600 || return 1
    link_runtime_environment || return 1
    link_managed_file "$DOTFILES_DIR/scripts/codex-owned" "$DOTFILES_BARE_ROOT/bin/codex" || return 1
    link_managed_file "$DOTFILES_DIR/scripts/codex-owned" "$HOME/.local/bin/codex"
)

bare_platform() {
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64) printf 'linux-64\n' ;;
        Linux/aarch64|Linux/arm64) printf 'linux-aarch64\n' ;;
        Darwin/arm64) printf 'osx-arm64\n' ;;
        *) warn 'Bootstrap supports glibc Linux x86_64/aarch64 and macOS arm64'; return 1 ;;
    esac
}

bare_preflight() {
    local command platform failed=0
    platform="$(bare_platform)" || return 1
    if [[ "$platform" == linux-* ]] && ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then warn 'Bootstrap requires glibc Linux and getconf'; failed=1; fi
    for command in bash curl awk; do command -v "$command" >/dev/null 2>&1 || { warn "Bootstrap prerequisite missing: $command"; failed=1; }; done
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then warn 'Bootstrap requires sha256sum or shasum'; failed=1; fi
    [[ -d "$HOME" && -w "$HOME" && "$HOME" == /* && "$HOME" != / ]] || { warn 'Bootstrap needs an absolute writable HOME below /'; failed=1; }
    if [[ "${USER:-}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        local account_home; account_home="$(eval "printf '%s' ~${USER}")"
        [[ "$HOME" == "$account_home" ]] || { warn "HOME must match the operating-system account home ($account_home) so Herdr state ownership is reliable"; failed=1; }
    else warn 'USER is missing or invalid'; failed=1; fi
    [[ "${XDG_CONFIG_HOME:-$HOME/.config}" == /* && "${XDG_CONFIG_HOME:-$HOME/.config}" != / ]] || { warn 'XDG_CONFIG_HOME must be absolute and below /'; failed=1; }
    native_backend >/dev/null || failed=1
    return "$failed"
}

bootstrap_lock_acquire() {
    BOOTSTRAP_STATE_ROOT="${BOOTSTRAP_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap}"
    mkdir -p "$BOOTSTRAP_STATE_ROOT"
    if ! mkdir "$BOOTSTRAP_STATE_ROOT/mutate.lock" 2>/dev/null; then warn "Bootstrap mutation is locked at $BOOTSTRAP_STATE_ROOT/mutate.lock; do not remove it automatically"; return 1; fi
}
bootstrap_lock_release() { rmdir "$BOOTSTRAP_STATE_ROOT/mutate.lock" 2>/dev/null || [[ ! -e "$BOOTSTRAP_STATE_ROOT" ]]; }

version_at_least() {
    local actual="${1#v}" minimum="$2" major minor patch min_major min_minor min_patch
    [[ "$actual" =~ ^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$ ]] || return 1
    IFS=. read -r major minor patch <<<"$actual"
    IFS=. read -r min_major min_minor min_patch <<<"$minimum"
    (( 10#$major > 10#$min_major || (10#$major == 10#$min_major && (10#$minor > 10#$min_minor || (10#$minor == 10#$min_minor && 10#$patch >= 10#$min_patch))) ))
}

ensure_bootstrap_node() {
    local backend package existed=0 status prefix version pending="$BOOTSTRAP_STATE_ROOT/bootstrap-node.pending" dependency_plan dependency dependency_existed dependency_version
    if ! command -v node >/dev/null 2>&1; then
        backend="$(native_backend)" || return 1
        case "$backend" in apt|dnf|pacman) package=nodejs ;; brew) package=node@24 ;; *) return 2 ;; esac
        if native_package_present "$backend" "$package"; then existed=1; else status=$?; [[ "$status" == 1 ]] || return 1; fi
        if [[ "$existed" == 1 ]] || native_package_available "$backend" "$package"; then
            if [[ ! -f "$pending" ]]; then
                ( umask 077; printf 'version=1\nbackend=%s\npackage=%s\npreexisting=%s\n' "$backend" "$package" "$existed" >"$pending" ) || return 1
            else
                grep -qx 'version=1' "$pending" && grep -qx "backend=$backend" "$pending" && grep -qx "package=$package" "$pending" && grep -qEx 'preexisting=[01]' "$pending" || { warn "Malformed bootstrap Node recovery journal: $pending"; return 1; }
            fi
            if [[ "$existed" != 1 && "$backend" == apt ]]; then
                dependency_plan="$(native_apt_install_plan "$package")" || return 1
                local dependency_records=''
                while IFS= read -r dependency; do
                    [[ -n "$dependency" ]] || continue
                    dependency="${dependency%%:*}"
                    [[ "$dependency" == "$package" ]] && continue
                    dependency_existed=0
                    if native_package_present "$backend" "$dependency"; then
                        dependency_existed=1
                    else
                        [[ $? == 1 ]] || return 1
                    fi
                    dependency_version="$(native_package_version "$backend" "$dependency")"
                    dependency_records+="dependency=$dependency|$dependency_existed|$dependency_version"$'\n'
                done <<<"$dependency_plan"
                {
                    printf 'version=1\nbackend=%s\npackage=%s\npreexisting=%s\n' "$backend" "$package" "$existed"
                    printf '%s' "$dependency_records"
                } >"$pending" || return 1
            fi
            [[ "$existed" == 1 ]] || native_install_names "$backend" "$package" || return 1
            if [[ "$backend" == brew ]]; then
                prefix="$(brew --prefix "$package")" || return 1
                [[ -x "$prefix/bin/node" ]] || { warn 'Homebrew Node keg has no executable'; return 1; }
                export PATH="$prefix/bin:$PATH"
                BOOTSTRAP_NODE_KEG="$prefix"
            fi
        fi
    fi
    # No modern helper or package client executes on an old/absent runtime.
    if ! version="$(node --version 2>/dev/null)" || ! version_at_least "$version" 22.19.0; then
        BOOTSTRAP_NODE_STAGING_ONLY=1 install_upstream_tool node || return 1
        BOOTSTRAP_NODE_FALLBACK=1
    fi
    version="$(node --version)" || return 1
    version_at_least "$version" 22.19.0
}

adopt_bootstrap_node_journal() {
    local pending="$BOOTSTRAP_STATE_ROOT/bootstrap-node.pending" backend package existed executable dependency dependency_existed dependency_version
    if [[ -f "$pending" ]]; then
        backend="$(sed -n 's/^backend=//p' "$pending")"; package="$(sed -n 's/^package=//p' "$pending")"; existed="$(sed -n 's/^preexisting=//p' "$pending")"
        [[ -n "$backend" && -n "$package" && "$existed" =~ ^[01]$ ]] || return 1
        node "$DOTFILES_DIR/scripts/state-helper.mjs" package "$backend" "$package" "$existed" "$(native_package_version "$backend" "$package")" installed || return 1
        while IFS='|' read -r dependency dependency_existed dependency_version; do
            [[ -n "$dependency" ]] || continue
            node "$DOTFILES_DIR/scripts/state-helper.mjs" package "$backend" "$dependency" "$dependency_existed" "$dependency_version" pending || return 1
            node "$DOTFILES_DIR/scripts/state-helper.mjs" package "$backend" "$dependency" "$dependency_existed" "$dependency_version" installed || return 1
        done < <(sed -n 's/^dependency=//p' "$pending")
    fi
    if [[ "${BOOTSTRAP_NODE_FALLBACK:-0}" == 1 ]]; then
        install_upstream_tool node || return 1
        export PATH="$DOTFILES_BARE_ROOT/bin:$PATH"
    elif [[ -n "${BOOTSTRAP_NODE_KEG:-}" ]]; then
        for executable in node npm npx corepack; do
            [[ ! -x "$BOOTSTRAP_NODE_KEG/bin/$executable" ]] || link_managed_file "$BOOTSTRAP_NODE_KEG/bin/$executable" "$DOTFILES_BARE_ROOT/bin/$executable" || return 1
        done
    fi
    [[ ! -f "$pending" ]] || rm -f "$pending"
}

ensure_pi_node_version() {
    local version
    if ! version="$(node --version 2>/dev/null)" || ! version_at_least "$version" 22.19.0; then install_upstream_tool node || return 1; hash -r; fi
    version="$(node --version 2>/dev/null)" || return 1
    version_at_least "$version" 22.19.0 || { warn 'Pi requires Node.js >=22.19.0'; return 1; }
}

ensure_runtime_versions() {
    ensure_pi_node_version || return 1
    local output version
    output="$(nvim --version 2>/dev/null)" || output=''
    read -r _ version _ <<<"$output"
    if ! version_at_least "$version" 0.12.0; then install_upstream_tool neovim || return 1; hash -r; fi
    output="$(nvim --version 2>/dev/null)" || return 1
    read -r _ version _ <<<"$output"
    version_at_least "$version" 0.12.0 || return 1
    output="$(tree-sitter --version 2>/dev/null)" || output=''
    read -r _ version _ <<<"$output"
    if ! version_at_least "$version" 0.26.1; then install_upstream_tool tree-sitter || return 1; hash -r; fi
    output="$(tree-sitter --version 2>/dev/null)" || return 1
    read -r _ version _ <<<"$output"
    version_at_least "$version" 0.26.1 || { warn 'Tree-sitter requires >=0.26.1'; return 1; }
}

bootstrap_private_links_are_proven() {
    local path source
    while IFS= read -r path; do
        [[ -L "$path" ]] || return 1
        source="$(readlink "$path")" || return 1
        [[ "$source" == "$DOTFILES_DIR"/* || ( -n "${BOOTSTRAP_LEGACY_ROOT:-}" && "$source" == "$BOOTSTRAP_LEGACY_ROOT"/* ) ]] || return 1
    done < <(find "$BOOTSTRAP_PRIVATE_ROOT" -mindepth 1 ! -type d -print)
}

initialize_bootstrap_component() {
    local component="$1"
    if [[ ! -f "$BOOTSTRAP_STATE_ROOT/install.json" ]]; then
        if [[ -d "$BOOTSTRAP_PRIVATE_ROOT" ]] && find "$BOOTSTRAP_PRIVATE_ROOT" -mindepth 1 ! -type d -print -quit | grep -q . && ! bootstrap_private_links_are_proven; then
            warn "Refusing to adopt unrecorded bootstrap runtime state: $BOOTSTRAP_PRIVATE_ROOT"
            return 1
        fi
        if [[ -d "$DOTFILES_BARE_ROOT" ]] && find "$DOTFILES_BARE_ROOT" -mindepth 1 ! -type d -print -quit | grep -q .; then
            warn "Refusing to adopt unrecorded bootstrap runtime state: $DOTFILES_BARE_ROOT"
            return 1
        fi
    fi
    node "$DOTFILES_DIR/scripts/state-helper.mjs" component-begin "$component" || return 1
    mkdir -p "$DOTFILES_BARE_ROOT" "$BOOTSTRAP_PRIVATE_ROOT"/{bash,zsh,gh,pi/agent,pi/sessions,neovim} || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$DOTFILES_BARE_ROOT" || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$BOOTSTRAP_PRIVATE_ROOT" || return 1
}

enroll_bootstrap_neovim_state() {
    local root
    for root in "${XDG_DATA_HOME:-$HOME/.local/share}/${NVIM_APPNAME:-bootstrap-nvim}" "${XDG_CACHE_HOME:-$HOME/.cache}/${NVIM_APPNAME:-bootstrap-nvim}" "${XDG_STATE_HOME:-$HOME/.local/state}/${NVIM_APPNAME:-bootstrap-nvim}"; do
        node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$root" || return 1
    done
}

pi_doctor() {
    local failed=0
    command -v node >/dev/null || { warn 'Pi Node.js runtime is missing'; failed=1; }
    command -v bun >/dev/null || { warn 'Pi Bun package runtime is missing'; failed=1; }
    [[ "$("$HOME/.local/bin/pi" --version 2>/dev/null)" == "$PI_CLI_VERSION" ]] || { warn "Pi must be $PI_CLI_VERSION"; failed=1; }
    check_pi_subagents_revision || failed=1
    return "$failed"
}

install_pi_component() {
    install_native_keys node bun || return 1
    ensure_pi_node_version || return 1
    local bun_version
    if ! bun_version="$(bun --version 2>/dev/null)" || ! version_at_least "$bun_version" 0.0.0; then install_upstream_tool bun || return 1; hash -r; fi
    bun_version="$(bun --version 2>/dev/null)" || return 1
    version_at_least "$bun_version" 0.0.0 || return 1
    bun install --global --exact "$PI_CLI_PACKAGE@$PI_CLI_VERSION" || return 1
    link_pi_launchers || return 1
    [[ "$("$HOME/.local/bin/pi" --version 2>/dev/null)" == "$PI_CLI_VERSION" ]] || { warn "Pi must be $PI_CLI_VERSION"; return 1; }
    link_pi_config || return 1
    link_pi_launchers || return 1
    install_pi_packages "$PI_CODING_AGENT_DIR/settings.json" || return 1
    pi_doctor || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" component-ready pi
}

link_bare_offline() (
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    command -v node >/dev/null || { warn 'Node.js is required for offline configuration'; return 1; }
    bootstrap_lock_acquire || return 1
    trap 'bootstrap_lock_release' EXIT
    initialize_bootstrap_component configuration || return 1
    enroll_bootstrap_neovim_state || return 1
    DOTFILES_RELINK_ONLY=1 link_bare_config || return 1
    DOTFILES_RELINK_ONLY=1 setup_neovim_config || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" component-ready configuration
)

install_workstation_neovim() (
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    command -v node >/dev/null || { warn 'Node.js is required for Neovim configuration'; return 1; }
    bootstrap_lock_acquire || return 1
    trap 'bootstrap_lock_release' EXIT
    initialize_bootstrap_component configuration || return 1
    enroll_bootstrap_neovim_state || return 1
    BOOTSTRAP_NEOVIM_PROFILE=workstation install_neovim_config || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" component-ready configuration
)

install_bare_pi() (
    bare_preflight || return 1
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    bootstrap_lock_acquire || return 1
    local bare_stage=''
    bare_stage="$(mktemp -d "$BOOTSTRAP_STATE_ROOT/stage.XXXXXX")" || { bootstrap_lock_release; return 1; }
    trap 'rm -rf "$bare_stage"; bootstrap_lock_release' EXIT
    ensure_bootstrap_node || return 1
    initialize_bootstrap_component pi || return 1
    adopt_bootstrap_node_journal || return 1
    install_pi_component || return 1
    info 'Pi component installed in the owned runtime profile'
)

bare_doctor() (
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    local command failed=0
    node "$DOTFILES_DIR/scripts/state-helper.mjs" validate >/dev/null || return 1
    for command in git delta gh ssh tmux nvim tree-sitter cc rg fd fzf bat eza zoxide jq less curl node bun pi herdr; do
        if command -v "$command" >/dev/null 2>&1; then info "$command: $(command -v "$command")"; else warn "Missing required command: $command"; failed=1; fi
    done
    [[ "$("$HOME/.local/bin/pi" --version 2>/dev/null)" == "$PI_CLI_VERSION" ]] || { warn "Pi must be $PI_CLI_VERSION"; failed=1; }
    check_pi_subagents_revision || failed=1
    verify_neovim_runtime || failed=1
    info 'Optional integrations remain unselected unless recorded explicitly'
    return "$failed"
)

install_bare() (
    bare_preflight || return 1
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    bootstrap_lock_acquire || return 1
    local bare_stage=''
    bare_stage="$(mktemp -d "$BOOTSTRAP_STATE_ROOT/stage.XXXXXX")" || { bootstrap_lock_release; return 1; }
    trap 'rm -rf "$bare_stage"; bootstrap_lock_release' EXIT
    ensure_bootstrap_node || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" init || return 1
    initialize_bootstrap_component core || return 1
    adopt_bootstrap_node_journal || return 1
    enroll_bootstrap_neovim_state || return 1
    local core=() key
    while IFS= read -r key; do [[ -z "$key" ]] || core+=("$key"); done < <(catalog_query core)
    install_native_keys "${core[@]}" || return 1
    ensure_runtime_versions || return 1
    install_pi_component || return 1
    local herdr_root="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
    if [[ -e "$herdr_root" ]]; then
        if find "$herdr_root" -mindepth 1 ! -name config.toml -print -quit | grep -q . ||
            { [[ -e "$herdr_root/config.toml" || -L "$herdr_root/config.toml" ]] && { [[ ! -L "$herdr_root/config.toml" ]] || ! managed_source_matches "$(readlink "$herdr_root/config.toml")" herdr/config.toml; }; }; then
            warn "Herdr already has personal state at $herdr_root; explicit enrollment is required before bootstrap can own it"
            return 1
        fi
    fi
    node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$herdr_root" || return 1
    HERDR_INSTALL_DIR="$DOTFILES_BARE_ROOT/bin" install_herdr || return 1
    link_bare_config || return 1
    install_neovim_config || return 1
    install_neovim_parsers || return 1
    reconcile_bootstrap_selections || return 1
    report_install_failures || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" component-ready core || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" ready || return 1
    bare_doctor || return 1
    info 'Native bootstrap installed. Run ~/.local/bin/dev-shell COMMAND.'
)

install_bare_rust() {
    local target sha
    case "$(bare_platform)" in
        linux-64) target=x86_64-unknown-linux-gnu; sha=20a06e644b0d9bd2fbdbfd52d42540bdde820ea7df86e92e533c073da0cdd43c ;;
        linux-aarch64) target=aarch64-unknown-linux-gnu; sha=e3853c5a252fca15252d07cb23a1bdd9377a8c6f3efa01531109281ae47f841c ;;
        osx-arm64) target=aarch64-apple-darwin; sha=20ef5516c31b1ac2290084199ba77dbbcaa1406c45c1d978ca68558ef5964ef5 ;;
    esac
    [[ -x "$CARGO_HOME/bin/rustup" ]] || { download_verified "https://static.rust-lang.org/rustup/archive/1.28.2/$target/rustup-init" "$sha" "$bare_stage/rustup-init" || return 1; chmod 0755 "$bare_stage/rustup-init"; "$bare_stage/rustup-init" -y --no-modify-path --profile minimal --default-toolchain none || return 1; }
    "$CARGO_HOME/bin/rustup" toolchain install stable --profile minimal || return 1
    "$CARGO_HOME/bin/rustup" default stable
}

install_bare_elixir_ls() {
    local destination="$DOTFILES_BARE_ROOT/tools/elixir-ls-0.31.1" source="$bare_stage/elixir-ls"
    if [[ ! -d "$destination" ]]; then
        download_verified 'https://github.com/elixir-lsp/elixir-ls/releases/download/v0.31.1/elixir-ls-v0.31.1.zip' bac08322ea3698157eb2373bb5b65e38c15df9dd41e1c06f142f874367fa472f "$bare_stage/elixir-ls.zip" || return 1
        command -v unzip >/dev/null || { warn 'ElixirLS installation requires the independently selectable unzip tool'; return 1; }
        mkdir -p "$source"; unzip -q "$bare_stage/elixir-ls.zip" -d "$source" || return 1
        mv "$source" "$destination" || return 1
    fi
    MIX_ENV=prod node "$DOTFILES_DIR/scripts/run-bounded.mjs" 600 elixir "$destination/quiet_install.exs" </dev/null || return 1
    [[ -x "$destination/language_server.sh" ]] || return 1
    link_managed_file "$destination/language_server.sh" "$DOTFILES_BARE_ROOT/bin/elixir-ls"
}

install_bare_zls() {
    local target sha destination="$DOTFILES_BARE_ROOT/tools/zls-0.16.0"
    case "$(bare_platform)" in linux-64) target=x86_64-linux; sha=ded6d562a0b86ee878b1ddf70ffab2797ce3cdca3b02d6077548f9d56dff96b6 ;; linux-aarch64) target=aarch64-linux; sha=430cd293d201eb70ae2519dbc96c854bf8791b8df7fc9392e8d2dc9680a2bed7 ;; osx-arm64) target=aarch64-macos; sha=b93ec549f8558a7e85984a840e9276d274f1059b54ade4254296ef4982958359 ;; esac
    if [[ ! -d "$destination" ]]; then download_verified "https://github.com/zigtools/zls/releases/download/0.16.0/zls-$target.tar.xz" "$sha" "$bare_stage/zls.tar.xz" || return 1; mkdir -p "$bare_stage/zls"; tar -xJf "$bare_stage/zls.tar.xz" -C "$bare_stage/zls"; mv "$bare_stage/zls" "$destination"; fi
    [[ -x "$destination/zls" && "$($destination/zls --version)" == 0.16.0 ]] || return 1
    link_managed_file "$destination/zls" "$DOTFILES_BARE_ROOT/bin/zls"
}

enroll_go_telemetry() {
    local root
    case "$(uname -s)" in
        Darwin) root="$HOME/Library/Application Support/go/telemetry" ;;
        Linux) root="${XDG_CONFIG_HOME:-$HOME/.config}/go/telemetry" ;;
        *) warn 'Unsupported Go telemetry location'; return 1 ;;
    esac
    node "$DOTFILES_DIR/scripts/state-helper.mjs" claim-location "$root"
}

install_lsp_selection() {
    local selection="$1" metadata executable prerequisite packages=()
    [[ "$selection" != gopls ]] || enroll_go_telemetry || return 1
    metadata="$(catalog_query lsp "$selection")" || { warn "Unknown LSP selection: $selection"; return 2; }
    executable="$(node -e 'console.log(JSON.parse(process.argv[1]).executable)' "$metadata")"
    while IFS= read -r prerequisite; do [[ -z "$prerequisite" ]] || command -v "$prerequisite" >/dev/null || { warn "$selection blocked by missing prerequisite: $prerequisite"; return 1; }; done < <(node -e 'console.log(JSON.parse(process.argv[1]).prerequisites.join("\n"))' "$metadata")
    while IFS= read -r prerequisite; do [[ -z "$prerequisite" ]] || packages+=("$prerequisite"); done < <(catalog_query group lsp "$selection")
    [[ ${#packages[@]} -eq 0 ]] || install_native_keys "${packages[@]}" || return 1
    if [[ "$selection" == typescript-language-server ]]; then
        # The server needs its implementation package even when a foreign server
        # executable already exists. This does not select the TS development extra.
        bun install --global --exact typescript@6.0.2 typescript-language-server@5.3.0 || return 1
        node -e 'require.resolve("typescript/lib/tsserver.js", {paths:[process.argv[1]]})' "$BUN_INSTALL/install/global/node_modules/typescript-language-server" || return 1
        link_managed_file "$BUN_INSTALL/bin/typescript-language-server" "$DOTFILES_BARE_ROOT/bin/typescript-language-server" || return 1
    fi
    if ! command -v "$executable" >/dev/null; then
        case "$selection" in
            basedpyright) bun install --global --exact basedpyright@1.38.3 ;;

            bash-language-server) bun install --global --exact bash-language-server@5.6.0 ;;
            gopls) command -v go >/dev/null || { warn 'gopls blocked by missing Go build prerequisite'; return 1; }; GOBIN="$DOTFILES_BARE_ROOT/bin" go install golang.org/x/tools/gopls@v0.23.0 ;;
            rust-analyzer) warn 'rust-analyzer has no native package candidate on this host'; return 1 ;;
            elixirls) install_bare_elixir_ls ;;
            zls) install_bare_zls ;;
            *) return 1 ;;
        esac || return 1
    fi
    command -v "$executable" >/dev/null || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" select lsp "$selection" || return 1
    write_neovim_lsp_selections || return 1
    verify_selected_lsp "$selection"
}

install_bootstrap_selections() {
    local group="$1" selection
    shift
    for selection in "$@"; do
        case "$group" in
            languages)
                [[ "$selection" != go ]] || enroll_go_telemetry || return 1
                local keys=() key; while IFS= read -r key; do [[ -z "$key" ]] || keys+=("$key"); done < <(catalog_query group languages "$selection")
                [[ ${#keys[@]} -eq 0 ]] || install_native_keys "${keys[@]}" || return 1
                case "$selection" in
                    python)
                        if ! python3 -c 'import sys; assert sys.version_info.major == 3'; then install_upstream_tool python || return 1; hash -r; fi
                        python3 -c 'import sys; assert sys.version_info.major == 3' || return 1 ;;
                    rust) install_bare_rust || return 1 ;; typescript) bun install --global --exact typescript@6.0.2 || return 1 ;; esac
                node "$DOTFILES_DIR/scripts/state-helper.mjs" select languages "$selection" || return 1 ;;
            lsp) install_lsp_selection "$selection" || return 1 ;;
            tools)
                local keys=() key; while IFS= read -r key; do [[ -z "$key" ]] || keys+=("$key"); done < <(catalog_query group tools "$selection")
                [[ ${#keys[@]} -eq 0 ]] || install_native_keys "${keys[@]}" || return 1
                case "$selection" in codex) bun install --global --exact @openai/codex@0.153.4; link_bare_codex_config ;; headroom) command -v headroom >/dev/null || { warn 'Headroom external application is not installed'; return 1; } ;; esac
                node "$DOTFILES_DIR/scripts/state-helper.mjs" select tools "$selection" || return 1
                case "$selection" in zsh|starship) link_selected_shell_config || return 1 ;; esac ;;
        esac
    done
}

reconcile_bootstrap_selections() {
    local selections group selection
    selections="$(node "$DOTFILES_DIR/scripts/state-helper.mjs" selections)" || return 1
    while IFS=$'\t' read -r group selection; do
        [[ -z "$group" ]] || install_bootstrap_selections "$group" "$selection" || return 1
    done <<<"$selections"
    write_neovim_lsp_selections
}

install_bare_optional() (
    local group="${1:-}" selection choices
    case "$group" in languages) choices='c cpp rust go python typescript elixir zig' ;; lsp) choices='clangd rust-analyzer gopls basedpyright ruff typescript-language-server bash-language-server elixirls zls' ;; tools) choices='zsh starship codex just wget unzip shellcheck ruff headroom' ;; *) warn "Unknown optional group: $group"; return 2 ;; esac
    shift; [[ $# -gt 0 ]] || { warn "Select one or more $group: $choices"; return 2; }
    for selection in "$@"; do [[ " $choices " == *" $selection "* ]] || { warn "Unknown $group selection: $selection"; return 2; }; done
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    node "$DOTFILES_DIR/scripts/state-helper.mjs" validate >/dev/null || { warn 'Install core before extras'; return 1; }
    bootstrap_lock_acquire || return 1
    local bare_stage; bare_stage="$(mktemp -d "$BOOTSTRAP_STATE_ROOT/stage.XXXXXX")" || { bootstrap_lock_release; return 1; }
    trap 'rm -rf "$bare_stage"; bootstrap_lock_release' EXIT
    install_bootstrap_selections "$group" "$@" || return 1
    info "Selected $group installed"
)

enroll_bootstrap_project() (
    local root="$1"
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    [[ -d "$root" && ! -L "$root" && "$root" == /* && "$root" != "$HOME" && "$root" != / ]] || { warn 'Project enrollment requires an existing absolute non-symlink directory other than HOME'; return 2; }
    node "$DOTFILES_DIR/scripts/state-helper.mjs" validate >/dev/null || return 1
    bootstrap_lock_acquire || return 1; trap 'bootstrap_lock_release' EXIT
    node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$root"
    info "Enrolled project copy for deletion on uninstall: $root"
)

migrate_legacy_bootstrap() (
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    local marker="$HOME/.config/dotfiles/bare-env.sh" legacy_pi="$HOME/.pi/agent"
    [[ -L "$marker" ]] && managed_source_matches "$(readlink "$marker")" scripts/bare-env.sh || { warn 'No provable legacy bootstrap profile was found'; return 1; }
    if [[ -d "$legacy_pi" ]]; then
        if find "$legacy_pi" -type l -print -quit | grep -q .; then warn 'Legacy Pi state contains symlinks; refusing ambiguous enrollment'; return 1; fi
    fi
    bootstrap_lock_acquire || return 1; trap 'bootstrap_lock_release' EXIT
    node "$DOTFILES_DIR/scripts/state-helper.mjs" init || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" adopt-link "$marker" "$(readlink "$marker")" || return 1
    mkdir -p "$PI_CODING_AGENT_DIR" || return 1
    node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$BOOTSTRAP_PRIVATE_ROOT" || return 1
    if [[ -d "$legacy_pi" ]]; then
        cp -a "$legacy_pi"/. "$PI_CODING_AGENT_DIR"/ || return 1
        node "$DOTFILES_DIR/scripts/state-helper.mjs" enroll "$legacy_pi" || return 1
    fi
    node "$DOTFILES_DIR/scripts/state-helper.mjs" ready || return 1
    info 'Legacy Pi credentials and sessions migrated into the isolated profile; the old tool prefix was preserved because it may contain unrelated Bun/Rust additions'
)

bootstrap_live_writers() {
    local output uid pid executable arguments environment found=1 own_uid
    own_uid="$(id -u)" || return 2
    output="$(ps -axo uid=,pid=,comm=,args=)" || { warn 'Unable to inspect active writers'; return 2; }
    while read -r uid pid executable arguments; do
        [[ "$uid" == "$own_uid" ]] || continue
        if [[ "$arguments" == *"$DOTFILES_BARE_ROOT/"* || "$arguments" == *"$BOOTSTRAP_PRIVATE_ROOT/"* ]]; then
            printf '%s %s\n' "$pid" "$executable"; found=0; continue
        fi
        case "${executable##*/}" in
            nvim|pi)
                # Native executables need profile identity, not a broad name match.
                environment="$(ps eww -p "$pid" -o command=)" || { warn 'Writer disappeared during identity check; retry cleanup'; return 2; }
                if [[ " $environment " == *" BOOTSTRAP_PRIVATE_ROOT=$BOOTSTRAP_PRIVATE_ROOT "* ]]; then printf '%s %s\n' "$pid" "$executable"; found=0; fi
                ;;
        esac
    done <<<"$output"
    return "$found"
}

bootstrap_stop_owned_servers() {
    local socket status
    # Ownership comes from enrollment, not an ambient TMUX/TMUX_TMPDIR value.
    if node "$DOTFILES_DIR/scripts/state-helper.mjs" owns-root "$BOOTSTRAP_PRIVATE_ROOT"; then
        for socket in "$TMUX_TMPDIR"/tmux-"$(id -u)"/*; do
            [[ -S "$socket" && ! -L "$socket" ]] || continue
            [[ "${TMUX:-}" != "$socket,"* ]] || { warn 'Run uninstall outside the bootstrap-owned tmux server'; return 1; }
            command -v tmux >/dev/null || return 1
            env -u TMUX tmux -S "$socket" kill-server || return 1
        done
    else status=$?; [[ "$status" == 3 ]] || return 1; fi
    local herdr_root="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
    if node "$DOTFILES_DIR/scripts/state-helper.mjs" owns-root "$herdr_root"; then
        if [[ -S "$herdr_root/herdr.sock" ]]; then
            herdr server stop || return 1
            local attempt=0; while (( attempt < 50 )) && [[ -S "$herdr_root/herdr.sock" ]]; do sleep 0.1; attempt=$((attempt + 1)); done
            [[ ! -S "$herdr_root/herdr.sock" ]] || { warn 'Herdr server is still writing bootstrap-owned state'; return 1; }
        fi
    else status=$?; [[ "$status" == 3 ]] || return 1; fi
}

uninstall_bare() (
    local dry_run="${1:-}" state_output backend name writers status packages=()
    source "$DOTFILES_DIR/scripts/bare-env.sh"
    if [[ ! -f "$BOOTSTRAP_STATE_ROOT/install.json" ]]; then info 'Bootstrap is already uninstalled'; return 0; fi
    # Preview allocates no files, locks, journals, or services, and never elevates.
    state_output="$(node "$DOTFILES_DIR/scripts/state-helper.mjs" uninstall --dry-run)" || return 1
    printf '%s\n' "$state_output"
    for backend in apt dnf pacman brew; do
        packages=()
        while IFS= read -r name; do [[ -z "$name" ]] || packages+=("$name"); done < <(printf '%s\n' "$state_output" | awk -F '\t' -v backend="$backend" '$1=="remove-package" && $2==backend { print $3 }')
        [[ ${#packages[@]} -eq 0 ]] || native_preview_remove "$backend" "${packages[@]}" || return 1
    done
    [[ "$dry_run" == --dry-run ]] && return 0
    bootstrap_lock_acquire || return 1
    trap 'bootstrap_lock_release' EXIT
    if writers="$(bootstrap_live_writers)"; then warn "Refusing cleanup while owned writers are active: $writers"; return 1; else status=$?; [[ "$status" == 1 ]] || return 1; fi
    bootstrap_stop_owned_servers || return 1
    # One already-loaded Node controller survives unlinking its own binary and
    # native package. It performs every journal update and final check in-process.
    export -f bootstrap_live_writers native_preview_remove native_remove_names native_package_present native_privileged warn
    node "$DOTFILES_DIR/scripts/state-helper.mjs" uninstall-complete || return 1
    info 'Bootstrap uninstall complete. Provider-side credentials and host snapshots are outside this cleanup boundary.'
)
