#!/usr/bin/env bash
# Configuration ownership shared by bare and workstation profiles.

setup_neovim_config() (
    local checkout="${NVIM_CONFIG_CHECKOUT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/lazyvim-config}"
    local target="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    local repo_url="${NVIM_CONFIG_REPO_URL:-}" changes origin

    if [[ "${DOTFILES_RELINK_ONLY:-0}" == 1 || -z "$repo_url" ]]; then
        [[ -d "$checkout" ]] || return 0
    fi
    mkdir -p "$(dirname "$checkout")" || return 1
    if ! mkdir "$checkout.install.lock"; then
        warn "Neovim setup is locked. After confirming no installer is running, remove $checkout.install.lock and retry"
        return 1
    fi
    trap 'rmdir "$checkout.install.lock"' EXIT

    if [[ "${DOTFILES_RELINK_ONLY:-0}" != 1 && -n "$repo_url" ]]; then
        if [[ -e "$checkout" || -L "$checkout" ]]; then
            if [[ ! -e "$checkout/.git" || ! -f "$checkout/init.lua" ]]; then
                warn "Incomplete or unexpected Neovim checkout at $checkout; move it aside and retry"
                return 1
            fi
            origin="$(git -C "$checkout" remote get-url origin)" || return 1
            if [[ "$origin" != "$repo_url" ]]; then
                warn 'Neovim checkout has a different origin; use its NVIM_CONFIG_REPO_URL or a separate NVIM_CONFIG_CHECKOUT_DIR'
                return 1
            fi
            changes="$(git -C "$checkout" status --porcelain)" || return 1
            if [[ -n "$changes" ]]; then
                warn 'Keeping locally modified Neovim config; skipping update'
            else
                info 'Updating Neovim config checkout...'
                GIT_TERMINAL_PROMPT=0 git -C "$checkout" pull --ff-only || return 1
            fi
        else
            info 'Cloning Neovim config checkout...'
            GIT_TERMINAL_PROMPT=0 git clone -- "$repo_url" "$checkout" || return 1
        fi
    fi

    [[ -f "$checkout/init.lua" ]] || { warn "Neovim config is missing init.lua: $checkout"; return 1; }
    if [[ "$(resolve_path "$checkout")" != "$(resolve_path "$target")" ]]; then
        link_managed_file "$checkout" "$target" || return 1
    fi
    info 'Neovim config ready'
)

link_terminal_config() {
    local source target
    mkdir -p "$HOME/.config/dotfiles" "$HOME/.local/bin" || return 1
    while read -r source target; do
        [[ -f "$DOTFILES_DIR/$source" ]] || continue
        link_managed_file "$DOTFILES_DIR/$source" "$HOME/$target" || return 1
    done <<'LINKS'
local/env.sh .config/dotfiles/env.sh
local/gitconfig .gitconfig.local
local/repos.conf .config/dotfiles/repos.conf
zshenv .zshenv
zshrc .zshrc
zprofile .zprofile
bashrc .bashrc
starship.toml .config/starship.toml
tmux.conf .tmux.conf
herdr/config.toml .config/herdr/config.toml
gitconfig .gitconfig
gitignore_global .config/git/ignore
ripgrep/config .config/ripgrep/config
LINKS
    info "Linked terminal configuration"
}

sync_pi_links() (
    local source_dir="$1" target_dir="$2" pattern="$3" link current source
    [[ -d "$source_dir" ]] || return 0
    shopt -s nullglob

    # The pattern is an installer-owned glob; quoting the directory preserves spaces.
    # shellcheck disable=SC2231
    for link in "$target_dir"/$pattern; do
        [[ -L "$link" ]] || continue
        current="$(readlink "$link")"
        case "$current" in
            "$source_dir"/*)
                [[ -e "$current" || -L "$current" ]] || rm -f "$link" || return 1
                ;;
        esac
    done
    # shellcheck disable=SC2231
    for source in "$source_dir"/$pattern; do
        link_managed_file "$source" "$target_dir/$(basename "$source")" || return 1
    done
)

link_pi_config() {
    if [[ -d "$DOTFILES_DIR/pi" ]]; then
        mkdir -p ~/.pi/agent/{extensions,agents,prompts,skills,themes} "${XDG_CONFIG_HOME:-$HOME/.config}/pi" || return 1
        link_managed_file "$DOTFILES_DIR/pi/web-search.json" "${XDG_CONFIG_HOME:-$HOME/.config}/pi/web-search.json" || return 1
        link_managed_file "$DOTFILES_DIR/pi/profile-router.json" "${XDG_CONFIG_HOME:-$HOME/.config}/pi/profile-router.json" || return 1
        link_managed_file "$DOTFILES_DIR/pi/strategy-router.json" "${XDG_CONFIG_HOME:-$HOME/.config}/pi/strategy-router.json" || return 1

        local pi_settings_path="$HOME/.pi/agent/settings.json"
        local pi_auth_path="$HOME/.pi/agent/auth.json"

        materialize_json_config \
            "$DOTFILES_DIR/pi/settings.json" \
            "$DOTFILES_DIR/local/pi-settings.json" \
            "$pi_settings_path" || return 1

        if [[ "${DOTFILES_RELINK_ONLY:-0}" != "1" && "${DOTFILES_SKIP_AUTH_INSTALL:-0}" != "1" ]]; then
            if [[ -L "$pi_auth_path" && "$(readlink "$pi_auth_path")" == "$DOTFILES_DIR/pi/auth.json" ]]; then
                if [[ -f "$DOTFILES_DIR/pi/auth.json" ]]; then
                    install_managed_file "$DOTFILES_DIR/pi/auth.json" "$pi_auth_path" 0600
                    info "Migrated existing auth symlink to local file"
                else
                    rm -f "$pi_auth_path"
                fi
            fi
            if [[ ! -f "$pi_auth_path" ]]; then
                if [[ -f "$DOTFILES_DIR/secrets/pi-auth.json" ]]; then
                    install_managed_file "$DOTFILES_DIR/secrets/pi-auth.json" "$pi_auth_path" 0600
                    info "Installed Pi auth tokens"
                else
                    warn "No secrets/pi-auth.json found; skip Pi auth install"
                fi
            fi
        fi

        if [[ -f "$DOTFILES_DIR/pi/models.json" ]]; then
            link_managed_file "$DOTFILES_DIR/pi/models.json" "$HOME/.pi/agent/models.json" || return 1
        fi
        link_managed_file "$DOTFILES_DIR/pi/AGENTS.md" "$HOME/.pi/agent/AGENTS.md" || return 1
        local retired_pi_presets_link="$HOME/.pi/agent/presets.json"
        if [[ -L "$retired_pi_presets_link" && "$(readlink "$retired_pi_presets_link")" == "$DOTFILES_DIR/pi/presets.json" ]]; then
            rm -f "$retired_pi_presets_link"
        fi
        if [[ -L "$HOME/.pi/agent/interactive-shell.json" ]]; then
            rm -f "$HOME/.pi/agent/interactive-shell.json"
        fi
        link_managed_file "$DOTFILES_DIR/pi/WORKTREE_STREAMS.md" "$HOME/.pi/agent/WORKTREE_STREAMS.md" || return 1
        mkdir -p "$HOME/.pi/agent/extensions/subagent" || return 1
        link_managed_file "$DOTFILES_DIR/pi/subagent-config.json" "$HOME/.pi/agent/extensions/subagent/config.json" || return 1

        # Custom extensions only (package extensions are managed by `pi install`).
        # Remove retired router components only when they are still our managed links.
        local legacy_route_context_link="$HOME/.pi/agent/components/legacy-route-context.ts"
        if [[ -L "$legacy_route_context_link" && "$(readlink "$legacy_route_context_link")" == "$DOTFILES_DIR/pi/components/legacy-route-context.ts" ]]; then
            rm -f "$legacy_route_context_link"
        fi
        local legacy_router_link="$HOME/.pi/agent/components/auto-router"
        if [[ -L "$legacy_router_link" && "$(readlink "$legacy_router_link")" == "$DOTFILES_DIR/pi/components/auto-router" ]]; then
            rm -f "$legacy_router_link"
        fi
        sync_pi_links "$DOTFILES_DIR/pi/extensions" "$HOME/.pi/agent/extensions" "*.ts" || return 1
        sync_pi_links "$DOTFILES_DIR/pi/extensions" "$HOME/.pi/agent/extensions" "*.json" || return 1
        sync_pi_links "$DOTFILES_DIR/pi/agents" "$HOME/.pi/agent/agents" "*.md" || return 1
        sync_pi_links "$DOTFILES_DIR/pi/prompts" "$HOME/.pi/agent/prompts" "*.md" || return 1
        sync_pi_skill_links "$DOTFILES_DIR/pi/skills" "$HOME/.pi/agent/skills" || return 1
        sync_pi_links "$DOTFILES_DIR/pi/themes" "$HOME/.pi/agent/themes" "*.json" || return 1

        info "Linked Pi coding agent config"
    fi

}

install_pi_packages() {
    local settings_path="$1" packages package legacy_link legacy_target failed=0
    packages="$(python3 - "$settings_path" <<'PYTHON'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    for package in json.load(source).get("packages", []):
        print(package if isinstance(package, str) else package["source"])
PYTHON
    )" || return 1
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        if ! pi install "$package"; then
            record_install_failure "pi-package" "$package"
            failed=1
        elif [[ "$package" == git:github.com/elijah-rou/pi-sub-limits@* ]]; then
            # Retire only known links, and only after their replacement installs.
            legacy_link="$HOME/.pi/agent/extensions/sub-limits.ts"
            if [[ -L "$legacy_link" ]]; then
                legacy_target="$(readlink "$legacy_link")"
                case "$legacy_target" in
                    "${PI_SUB_LIMITS_DIR:-$HOME/Projects/pi-sub-limits}/sub-limits.ts"|"$DOTFILES_DIR/pi/extensions/sub-limits.ts")
                        rm -f "$legacy_link" || return 1
                        ;;
                esac
            fi
        elif [[ "$package" == git:github.com/elijah-rou/pi-effort@* ]]; then
            legacy_link="$HOME/.pi/agent/extensions/effort.ts"
            if [[ -L "$legacy_link" ]]; then
                legacy_target="$(readlink "$legacy_link")"
                if [[ "$legacy_target" == "$HOME/Projects/pi-effort/effort.ts" ]]; then
                    rm -f "$legacy_link" || return 1
                fi
            fi
        fi
    done <<< "$packages"
    return "$failed"
}
