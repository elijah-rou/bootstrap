#!/usr/bin/env bash

install_neovim_config() {
    if [[ -n "${NVIM_CONFIG_CHECKOUT_DIR:-}" && -z "${NVIM_CONFIG_REPO_URL:-}" ]]; then
        NVIM_CONFIG_REPO_URL="https://github.com/elijah-rou/lazyvim-config.git" setup_neovim_config
    else
        setup_neovim_config
    fi
}

setup_neovim_config() {
    if [[ -n "${NVIM_CONFIG_REPO_URL:-}" || -n "${NVIM_CONFIG_CHECKOUT_DIR:-}" ]]; then
        setup_external_neovim_config
    else
        setup_bundled_neovim_config
    fi
}

validate_neovim_profile() {
    [[ $# -ge 1 && $# -le 2 && -f "$1" && ! -L "$1" ]] || return 1
    python3 - "$1" "${2:-}" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], encoding='utf-8') as source:
        value = json.load(source)
    if type(value) is not dict or set(value) != {'version', 'profile'}:
        raise ValueError('invalid profile fields')
    if type(value['version']) is not int or value['version'] != 1:
        raise ValueError('unsupported profile version')
    if type(value['profile']) is not str or value['profile'] not in ('bare', 'workstation'):
        raise ValueError('unknown profile')
    if sys.argv[2] and value['profile'] != sys.argv[2]:
        raise ValueError('unexpected profile')
except (OSError, ValueError):
    print('Invalid bundled Neovim profile', file=sys.stderr)
    raise SystemExit(1)
PY
}

setup_bundled_neovim_config() (
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    local source="$DOTFILES_DIR/neovim/config" defaults="$DOTFILES_DIR/neovim/defaults"
    local runtime="$data_home/bootstrap/neovim" target="$config_home/nvim"
    local profile=bare stage='' profile_file='' destination seed name active_runtime=0
    [[ "$data_home" == /* && "$data_home" != / && "$config_home" == /* && "$config_home" != / ]] || {
        warn 'Neovim configuration requires absolute data/config homes below /'
        return 1
    }
    command -v python3 >/dev/null || { warn 'python3 is required for Neovim configuration'; return 1; }
    [[ -f "$source/init.lua" ]] || { warn 'Bundled Neovim entrypoint is missing'; return 1; }
    for name in lazy-lock.json lazyvim.json .neoconf.json; do
        [[ -f "$defaults/$name" ]] || { warn "Bundled Neovim default is missing: $name"; return 1; }
    done
    [[ "${BOOTSTRAP_WORKSTATION:-0}" != 1 ]] || profile=workstation
    mkdir -p "$(dirname "$runtime")" || return 1
    if ! mkdir "$runtime.install.lock"; then
        warn "Neovim setup is locked; confirm no installer is running before removing $runtime.install.lock"
        return 1
    fi
    trap '[[ -z "$stage" ]] || rm -rf "$stage"; [[ -z "$profile_file" ]] || rm -f "$profile_file"; rmdir "$runtime.install.lock"' EXIT

    if [[ -e "$runtime" || -L "$runtime" ]]; then
        if [[ ! -d "$runtime" || -L "$runtime" ]] || ! validate_neovim_profile "$runtime/bootstrap-profile.json"; then
            warn "Preserving unrecognized Neovim runtime at $runtime; inspect it before moving it aside"
            return 1
        fi
        destination="$runtime"
    else
        stage="$(mktemp -d "$(dirname "$runtime")/.neovim-stage.XXXXXX")" || return 1
        destination="$stage"
    fi

    if [[ -d "$target" && "$(resolve_path "$target")" == "$(resolve_path "$runtime")" ]]; then
        active_runtime=1
    fi
    # On activation/retry, the still-active editor remains authoritative for mutable state.
    for name in lazy-lock.json lazyvim.json .neoconf.json; do
        if [[ "$active_runtime" -eq 0 && -f "$target/$name" ]]; then
            seed="$target/$name"
        elif [[ -e "$destination/$name" || -L "$destination/$name" ]]; then
            continue
        else
            seed="$defaults/$name"
        fi
        python3 - "$seed" <<'PY' || return 1
import json
import sys

def reject_constant(value):
    raise ValueError('non-finite JSON value')

try:
    with open(sys.argv[1], encoding='utf-8') as source:
        value = json.load(source, parse_constant=reject_constant)
    if type(value) is not dict:
        raise ValueError('expected a JSON object')
except (OSError, ValueError) as error:
    print(f'Invalid Neovim seed {sys.argv[1]}: {error}', file=sys.stderr)
    raise SystemExit(1)
PY
        install_managed_file "$seed" "$destination/$name" 0644 || return 1
    done
    link_managed_file "$source/init.lua" "$destination/init.lua" \
        "${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap/neovim-backups" || return 1
    profile_file="$(mktemp "$(dirname "$runtime")/.neovim-profile.XXXXXX")" || return 1
    printf '{"version":1,"profile":"%s"}\n' "$profile" > "$profile_file" || return 1
    install_managed_file "$profile_file" "$destination/bootstrap-profile.json" 0644 || return 1
    if [[ -n "$stage" ]]; then
        mv "$stage" "$runtime" || return 1
        stage=''
    fi
    link_managed_file "$runtime" "$target" || return 1
    info "Linked bundled Neovim config ($profile); existing checkouts and local JSON state preserved"
)
