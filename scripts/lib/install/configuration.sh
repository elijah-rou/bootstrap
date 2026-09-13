#!/usr/bin/env bash
# Configuration ownership shared by bare and workstation profiles.

setup_external_neovim_config() (
    local checkout="${NVIM_CONFIG_CHECKOUT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/lazyvim-config}"
    local target="${XDG_CONFIG_HOME:-$HOME/.config}/${NVIM_APPNAME:-bootstrap-nvim}"
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
            local policy_path="$checkout/lua/plugins/zz-bootstrap-managed.lua"
            if [[ -L "$policy_path" ]] && managed_source_matches "$(readlink "$policy_path")" neovim/bootstrap.lua; then
                changes="$(printf '%s\n' "$changes" | grep -vFx '?? lua/plugins/zz-bootstrap-managed.lua' || true)"
            fi
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
    if [[ -f "$checkout/lua/config/lazy.lua" ]]; then
        local plugin="lua/plugins/zz-bootstrap-managed.lua" tracked
        tracked=''
        if [[ -d "$checkout/.git" ]]; then tracked="$(git -C "$checkout" ls-files -- "$plugin")" || return 1; fi
        if [[ -n "$tracked" ]]; then
            warn "Neovim checkout tracks $plugin; refusing to replace it"
            return 1
        fi
        link_external_policy_plugin "$DOTFILES_DIR/neovim/bootstrap.lua" "$checkout" || return 1
    fi
    if [[ "$(resolve_path "$checkout")" != "$(resolve_path "$target")" ]]; then
        link_managed_file "$checkout" "$target" || return 1
    fi
    info 'Neovim config ready'
)

selection_is_recorded() {
    local group="$1" name="$2"
    node "$DOTFILES_DIR/scripts/state-helper.mjs" selections 2>/dev/null | grep -qxF "$group"$'\t'"$name"
}

link_runtime_environment() {
    mkdir -p "$HOME/.config/dotfiles" "$HOME/.local/bin" || return 1
    link_managed_file "$DOTFILES_DIR/scripts/bare-env.sh" "$HOME/.config/dotfiles/bare-env.sh" || return 1
    link_managed_file "$DOTFILES_DIR/scripts/dev-shell" "$HOME/.local/bin/dev-shell" || return 1
}

link_terminal_config() {
    local source target
    mkdir -p "$HOME/.config/dotfiles" "$HOME/.local/bin" || return 1
    while read -r source target; do
        [[ -f "$DOTFILES_DIR/$source" ]] || continue
        link_managed_file "$DOTFILES_DIR/$source" "$HOME/$target" || return 1
    done <<'LINKS'
bashrc .bashrc
tmux.conf .tmux.conf
herdr/config.toml .config/herdr/config.toml
gitignore_global .config/git/ignore
ripgrep/config .config/ripgrep/config
LINKS
    if selection_is_recorded tools zsh; then
        for source in zshenv zshrc zprofile; do link_managed_file "$DOTFILES_DIR/$source" "$HOME/.$source" || return 1; done
    fi
    if selection_is_recorded tools starship; then
        link_managed_file "$DOTFILES_DIR/starship.toml" "$HOME/.config/starship.toml" || return 1
    fi
    configure_terminal_overlays || return 1
    link_managed_file "$DOTFILES_DIR/scripts/modelusage" "$HOME/.local/bin/modelusage" || return 1
    link_runtime_environment || return 1
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
        if [[ "$current" == "$source_dir/$(basename "$link")" && ! -e "$current" && ! -L "$current" ]]; then
            rm -f "$link" || return 1
        fi
    done
    # shellcheck disable=SC2231
    for source in "$source_dir"/$pattern; do
        link_managed_file "$source" "$target_dir/$(basename "$source")" || return 1
    done
)

link_pi_config() {
    if [[ -d "$DOTFILES_DIR/pi" ]]; then
        mkdir -p "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"/{extensions,agents,prompts,skills,themes} "${XDG_CONFIG_HOME:-$HOME/.config}/pi" || return 1
        link_managed_file "$DOTFILES_DIR/pi/web-search.json" "${XDG_CONFIG_HOME:-$HOME/.config}/pi/web-search.json" || return 1
        link_managed_file "$DOTFILES_DIR/pi/profile-router.json" "${XDG_CONFIG_HOME:-$HOME/.config}/pi/profile-router.json" || return 1
        link_managed_file "$DOTFILES_DIR/pi/strategy-router.json" "${XDG_CONFIG_HOME:-$HOME/.config}/pi/strategy-router.json" || return 1

        materialize_pi_config settings || return 1
        materialize_pi_config models || return 1
        link_managed_file "$DOTFILES_DIR/pi/AGENTS.md" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/AGENTS.md" || return 1
        remove_owned_link "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/presets.json" pi/presets.json || return 1
        remove_owned_link "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/interactive-shell.json" pi/interactive-shell.json || return 1
        link_managed_file "$DOTFILES_DIR/pi/WORKTREE_STREAMS.md" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/WORKTREE_STREAMS.md" || return 1
        mkdir -p "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions/subagent" || return 1
        link_managed_file "$DOTFILES_DIR/pi/subagent-config.json" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions/subagent/config.json" || return 1

        remove_owned_link "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/components/legacy-route-context.ts" pi/components/legacy-route-context.ts || return 1
        remove_owned_link "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/components/auto-router" pi/components/auto-router || return 1
        cleanup_retired_pi_links || return 1
        sync_pi_links "$DOTFILES_DIR/pi/extensions" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions" "*.ts" || return 1
        sync_pi_links "$DOTFILES_DIR/pi/extensions" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions" "*.json" || return 1
        sync_pi_links "$DOTFILES_DIR/pi/agents" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/agents" "*.md" || return 1
        sync_pi_links "$DOTFILES_DIR/pi/prompts" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/prompts" "*.md" || return 1
        sync_pi_skill_links "$DOTFILES_DIR/pi/skills" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills" || return 1
        sync_pi_links "$DOTFILES_DIR/pi/themes" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/themes" "*.json" || return 1

        info "Linked Pi coding agent config"
    fi

}

install_pi_packages() {
    local settings_path="$1" packages package legacy_link legacy_target failed=0
    packages="$(node "$DOTFILES_DIR/scripts/state-helper.mjs" json-packages "$settings_path")" || return 1
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        if ! pi install "$package"; then
            record_install_failure "pi-package" "$package"
            failed=1
        elif [[ "$package" == git:github.com/elijah-rou/pi-sub-limits@* ]]; then
            # Retire only known links, and only after their replacement installs.
            legacy_link="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions/sub-limits.ts"
            if [[ -L "$legacy_link" ]]; then
                legacy_target="$(readlink "$legacy_link")"
                case "$legacy_target" in
                    "${PI_SUB_LIMITS_DIR:-$HOME/Projects/pi-sub-limits}/sub-limits.ts"|"$DOTFILES_DIR/pi/extensions/sub-limits.ts")
                        rm -f "$legacy_link" || return 1
                        ;;
                esac
            fi
        elif [[ "$package" == git:github.com/elijah-rou/pi-effort@* ]]; then
            legacy_link="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions/effort.ts"
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

remove_owned_link() {
    local target="$1" relative="$2" current
    [[ -L "$target" ]] || return 0
    current="$(readlink "$target")" || return 1
    if managed_source_matches "$current" "$relative"; then
        rm -f "$target" || return 1
    fi
    return 0
}

cleanup_retired_pi_links() (
    local directory pattern link current relative
    shopt -s nullglob
    while read -r directory pattern; do
        # shellcheck disable=SC2231
        for link in "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/$directory"/$pattern; do
            [[ -L "$link" ]] || continue
            current="$(readlink "$link")" || return 1
            relative="pi/$directory/$(basename "$link")"
            if [[ ! -e "$DOTFILES_DIR/$relative" ]] && managed_source_matches "$current" "$relative"; then
                rm -f "$link" || return 1
            fi
        done
    done <<'LINKS'
extensions *.ts
extensions *.json
agents *.md
prompts *.md
skills *
themes *.json
LINKS
)

materialize_pi_config() {
    local name="$1" directory
    local overlays=("$DOTFILES_DIR/local/pi-$name.json")
    if [[ "${BOOTSTRAP_CONFIG_OVERLAYS:-0}" == 1 ]]; then
        overlays=()
        for directory in "${BOOTSTRAP_OVERLAYS[@]}"; do
            overlays+=("$directory/pi-$name.json")
        done
    fi
    materialize_json_config "$DOTFILES_DIR/pi/$name.json" "" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/$name.json" "${overlays[@]}" || return 1
}

configure_terminal_overlays() (
    local rendered directory source repos=''
    local overlays=("$DOTFILES_DIR/local")
    if [[ "${BOOTSTRAP_CONFIG_OVERLAYS:-0}" == 1 ]]; then
        overlays=("${BOOTSTRAP_OVERLAYS[@]}")
    fi
    rendered="$(mktemp -d)" || return 1
    trap 'rm -rf "$rendered"' EXIT
    node "$DOTFILES_DIR/scripts/state-helper.mjs" terminal-render "$rendered" "$DOTFILES_DIR/gitconfig" "${overlays[@]}" || return 1
    install_managed_file "$rendered/gitconfig" "$HOME/.gitconfig" 0644 || return 1
    install_managed_file "$rendered/env.sh" "$HOME/.config/dotfiles/env.sh" 0644 || return 1
    install_managed_file "$rendered/workstation.zsh" "$HOME/.config/dotfiles/workstation.zsh" 0644 || return 1
    for directory in "${overlays[@]}"; do
        source="$directory/repos.conf"
        [[ ! -f "$source" ]] || repos="$source"
    done
    if [[ -n "$repos" ]]; then
        link_managed_file "$repos" "$HOME/.config/dotfiles/repos.conf" || return 1
    fi
)

link_pi_launchers() {
    link_managed_file "$DOTFILES_DIR/scripts/pi-workspace" "$HOME/.local/bin/pi-workspace" || return 1
    link_managed_file "$DOTFILES_DIR/scripts/pi-workspace" "$HOME/.local/bin/piw" || return 1
    link_pi_headroom || return 1
}
