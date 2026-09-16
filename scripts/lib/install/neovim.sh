#!/usr/bin/env bash

install_neovim_config() {
    if [[ -n "${NVIM_CONFIG_CHECKOUT_DIR:-}" && -z "${NVIM_CONFIG_REPO_URL:-}" ]]; then
        NVIM_CONFIG_REPO_URL="https://github.com/elijah-rou/lazyvim-config.git" setup_neovim_config
    else setup_neovim_config; fi
}
setup_neovim_config() { if [[ -n "${NVIM_CONFIG_REPO_URL:-}" || -n "${NVIM_CONFIG_CHECKOUT_DIR:-}" ]]; then setup_external_neovim_config; else setup_bundled_neovim_config; fi; }
validate_neovim_profile() { [[ $# -ge 1 && $# -le 2 && -f "$1" && ! -L "$1" ]] && node "$DOTFILES_DIR/scripts/state-helper.mjs" profile "$1" "${2:-}"; }

setup_bundled_neovim_config() (
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}" config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    local source="$DOTFILES_DIR/neovim/config" defaults="$DOTFILES_DIR/neovim/defaults"
    local app_name="${NVIM_APPNAME:-bootstrap-nvim}" profile="${BOOTSTRAP_NEOVIM_PROFILE:-bare}" stage='' profile_file='' destination seed name active_runtime=0
    [[ "$profile" == bare || "$profile" == workstation ]] || { warn "Unknown Neovim profile: $profile"; return 1; }
    local runtime="${BOOTSTRAP_PRIVATE_ROOT:-$data_home/bootstrap/private}/neovim/config"
    local target="$config_home/$app_name"
    local seed_target="${BOOTSTRAP_NEOVIM_SEED:-$target}"
    if [[ "${BOOTSTRAP_PREPARE_ONLY:-0}" == 1 ]]; then
        target="$BOOTSTRAP_PRIVATE_ROOT/neovim/staged-config/$app_name"
    fi
    [[ "$data_home" == /* && "$data_home" != / && "$config_home" == /* && "$config_home" != / ]] || { warn 'Neovim requires absolute data/config homes below /'; return 1; }
    command -v node >/dev/null || { warn 'Node.js is required for Neovim configuration'; return 1; }
    [[ -f "$source/init.lua" ]] || return 1
    for name in lazy-lock.json lazyvim.json .neoconf.json; do [[ -f "$defaults/$name" ]] || return 1; done
    mkdir -p "$(dirname "$runtime")" || return 1
    if ! mkdir "$runtime.install.lock" 2>/dev/null; then warn "Neovim setup is locked at $runtime.install.lock"; return 1; fi
    trap '[[ -z "$stage" ]] || rm -rf "$stage"; [[ -z "$profile_file" ]] || rm -f "$profile_file"; rmdir "$runtime.install.lock"' EXIT
    if [[ -e "$runtime" || -L "$runtime" ]]; then
        [[ -d "$runtime" && ! -L "$runtime" ]] && validate_neovim_profile "$runtime/bootstrap-profile.json" || { warn "Preserving unrecognized Neovim runtime at $runtime"; return 1; }
        destination="$runtime"
    else stage="$(mktemp -d "$(dirname "$runtime")/.neovim-stage.XXXXXX")" || return 1; destination="$stage"; fi
    [[ "${BOOTSTRAP_PREPARE_ONLY:-0}" != 1 && -d "$target" && "$(resolve_path "$target")" == "$(resolve_path "$runtime")" ]] && active_runtime=1
    for name in lazy-lock.json lazyvim.json .neoconf.json; do
        if [[ "$active_runtime" -eq 0 && -f "$seed_target/$name" ]]; then seed="$seed_target/$name"
        elif [[ -e "$destination/$name" || -L "$destination/$name" ]]; then continue
        else seed="$defaults/$name"; fi
        node -e 'const fs=require("node:fs"); const v=JSON.parse(fs.readFileSync(process.argv[1])); if(!v||Array.isArray(v)||typeof v!=="object")process.exit(1)' "$seed" || { warn "Invalid Neovim seed: $seed"; return 1; }
        install_managed_file "$seed" "$destination/$name" 0644 || return 1
    done
    link_managed_file "$source/init.lua" "$destination/init.lua" "${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap/neovim-backups" || return 1
    profile_file="$(mktemp "$(dirname "$runtime")/.neovim-profile.XXXXXX")" || return 1
    printf '{"version":1,"profile":"%s"}\n' "$profile" >"$profile_file"
    install_managed_file "$profile_file" "$destination/bootstrap-profile.json" 0644 || return 1
    if [[ -n "$stage" ]]; then mv "$stage" "$runtime" || return 1; stage=''; fi
    link_managed_file "$runtime" "$target" || return 1
    info "Linked bundled Neovim config ($profile); local JSON state preserved"
)

write_neovim_lsp_selections() {
    local output="${BOOTSTRAP_LSP_SELECTIONS:-$BOOTSTRAP_PRIVATE_ROOT/neovim/config/lsp-selections.json}"
    node "$DOTFILES_DIR/scripts/state-helper.mjs" lsp-output "$DOTFILES_DIR/packages/catalog.json" "$output"
}

install_neovim_parsers() (
    export NVIM_APPNAME="${NVIM_APPNAME:-bootstrap-nvim}"
    local temporary fixture receipt parser_set config_init="${XDG_CONFIG_HOME:-$HOME/.config}/${NVIM_APPNAME:-bootstrap-nvim}/init.lua"
    command -v nvim >/dev/null && command -v tree-sitter >/dev/null && command -v cc >/dev/null || { warn 'Neovim parser setup requires nvim, tree-sitter and a C compiler'; return 1; }
    temporary="$(mktemp -d "$BOOTSTRAP_STATE_ROOT/parsers.XXXXXX")" || return 1
    trap 'rm -rf "$temporary"' EXIT
    fixture="$temporary/fixture.lua"; receipt="$temporary/receipt"; parser_set="$temporary/parsers"
    printf 'local value = {\n  nested = {\n    enabled = true,\n  },\n}\nreturn value\n' >"$fixture"
    BOOTSTRAP_NVIM_INIT="$config_init" BOOTSTRAP_PLUGIN_RECEIPT="$temporary/plugins" node "$DOTFILES_DIR/scripts/run-bounded.mjs" 300 nvim --headless -i NONE -u NONE -l "$DOTFILES_DIR/neovim/install-plugins.lua" || { warn 'Neovim locked plugin repair failed or timed out'; return 1; }
    [[ -s "$temporary/plugins" ]] || { warn 'Neovim plugin repair receipt missing'; return 1; }
    BOOTSTRAP_PARSER_SET_RECEIPT="$parser_set" node "$DOTFILES_DIR/scripts/run-bounded.mjs" 620 nvim --headless -i NONE -u "$config_init" -l "$DOTFILES_DIR/neovim/install-parsers.lua" || { warn 'Effective Neovim parser installation failed or timed out'; return 1; }
    BOOTSTRAP_PARSER_SET_RECEIPT="$parser_set" BOOTSTRAP_PARSER_FIXTURE="$fixture" BOOTSTRAP_PARSER_RECEIPT="$receipt" node "$DOTFILES_DIR/scripts/run-bounded.mjs" 30 nvim --headless -i NONE -u "$config_init" -l "$DOTFILES_DIR/neovim/verify-parser.lua" || return 1
    [[ -s "$receipt" && -s "$parser_set" ]] || return 1
)

verify_neovim_runtime() (
    export NVIM_APPNAME="${NVIM_APPNAME:-bootstrap-nvim}"
    local config="${XDG_CONFIG_HOME:-$HOME/.config}/${NVIM_APPNAME:-bootstrap-nvim}" expected temporary
    [[ -f "$config/init.lua" ]] || { warn "Neovim config missing: $config"; return 1; }
    if [[ -n "${NVIM_CONFIG_REPO_URL:-}${NVIM_CONFIG_CHECKOUT_DIR:-}" ]]; then expected=external
    else
        validate_neovim_profile "$config/bootstrap-profile.json" "${BOOTSTRAP_NEOVIM_PROFILE:-}" || return 1
        expected="$(node -e 'console.log(JSON.parse(require("node:fs").readFileSync(process.argv[1])).profile)' "$config/bootstrap-profile.json")" || return 1
    fi
    temporary="$(mktemp -d)" || return 1
    trap 'rm -rf "$temporary"' EXIT
    BOOTSTRAP_NVIM_VERIFY="$DOTFILES_DIR/neovim/verify-runtime.lua" BOOTSTRAP_EXPECTED_NVIM_PROFILE="$expected" BOOTSTRAP_NVIM_RECEIPT="$temporary/receipt" node "$DOTFILES_DIR/scripts/run-bounded.mjs" 30 nvim --headless -i NONE "+lua dofile(vim.env.BOOTSTRAP_NVIM_VERIFY)" >"$temporary/output" 2>&1 || { cat "$temporary/output" >&2; warn 'Neovim ordinary startup failed'; return 1; }
    [[ -s "$temporary/receipt" ]] && grep -qxF "$expected" "$temporary/receipt" || { cat "$temporary/output" >&2; warn 'Neovim startup receipt missing'; return 1; }
)

verify_selected_lsp() {
    local selection="$1" metadata server fixture_name contents temporary receipt config_init="${XDG_CONFIG_HOME:-$HOME/.config}/${NVIM_APPNAME:-bootstrap-nvim}/init.lua"
    metadata="$(catalog_query lsp "$selection")" || return 1
    read -r server fixture_name < <(node -e 'const v=JSON.parse(process.argv[1]); console.log(v.server, v.fixture)' "$metadata")
    contents="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).contents)' "$metadata")"
    temporary="$(mktemp -d "$BOOTSTRAP_STATE_ROOT/lsp.XXXXXX")" || return 1
    receipt="$temporary/receipt.json"; printf '%s' "$contents" >"$temporary/$fixture_name"
    NVIM_APPNAME="${NVIM_APPNAME:-bootstrap-nvim}" BOOTSTRAP_EXPECTED_LSP="$server" BOOTSTRAP_LSP_RECEIPT="$receipt" node "$DOTFILES_DIR/scripts/run-bounded.mjs" 40 nvim --headless -i NONE -u "$config_init" "$temporary/$fixture_name" -l "$DOTFILES_DIR/neovim/verify-lsp.lua" || { rm -rf "$temporary"; warn "$selection installed and configured but did not attach in Neovim"; return 1; }
    node -e 'const v=JSON.parse(require("node:fs").readFileSync(process.argv[1])); if(!v.initialized||!v.attached||!v.request)process.exit(1)' "$receipt" || { rm -rf "$temporary"; return 1; }
    rm -rf "$temporary"; info "$selection installed, configured, initialized, attached, and answered a request"
    node -e 'const v=JSON.parse(process.argv[1]); if(v.limitations)console.log(v.limitations)' "$metadata"
}
