#!/usr/bin/env bash
# Safe, rollback-capable managed links, files, and rendered overlays.

resolve_path() {
    local path="$1"

    if command -v realpath &>/dev/null; then
        realpath "$path" 2>/dev/null || true
        return
    fi

    command -v node >/dev/null || return 0
    node -e 'try { console.log(require("node:fs").realpathSync(process.argv[1])) } catch {}' "$path" 2>/dev/null || true
}

managed_source_matches() {
    [[ $# -eq 2 ]] || return 2
    local source="$1" relative="$2" snapshots candidate snapshot
    case "$relative" in
        ''|/*|..|../*|*/../*|*/..) return 2 ;;
    esac
    if [[ "$source" == "$DOTFILES_DIR/$relative" ||
          ( -n "${BOOTSTRAP_LEGACY_ROOT:-}" && "$source" == "$BOOTSTRAP_LEGACY_ROOT/$relative" ) ]]; then
        return 0
    fi

    # Completed sibling snapshots retain ownership across a pinned revision upgrade.
    snapshots="${DOTFILES_DIR%/*}"
    [[ "${snapshots##*/}" == snapshots ]] || return 1
    [[ "$source" == */"$relative" ]] || return 1
    candidate="${source%"/$relative"}"
    [[ "${candidate%/*}" == "$snapshots" ]] || return 1
    for snapshot in "$DOTFILES_DIR" "$candidate"; do
        completed_bootstrap_snapshot "$snapshot" || return 1
    done
    return 0
}

completed_bootstrap_snapshot() {
    [[ $# -eq 1 ]] || return 2
    local snapshot="$1" marker size checksum
    [[ "${snapshot##*/}" =~ ^[0-9a-f]{40}$ ]] || return 1
    [[ -d "$snapshot" && ! -L "$snapshot" && -x "$snapshot/install.sh" ]] || return 1
    marker="$snapshot/.bootstrap-archive-sha256"
    [[ -f "$marker" && ! -L "$marker" ]] || return 1
    size="$(wc -c < "$marker")" || return 1
    [[ "$size" -eq 64 || "$size" -eq 65 ]] || return 1
    checksum="$(cat "$marker")" || return 1
    [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || return 1
    return 0
}

managed_backup_path() {
    local target="$1"
    local timestamp candidate counter=0

    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    while [[ $counter -lt 1000 ]]; do
        candidate="${target}.bak.${timestamp}.$$.${counter}"
        if [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
        counter=$((counter + 1))
    done
    warn "Unable to allocate backup path for $target"
    return 1
}

managed_target_is_private() {
    local target="$1" target_parent private_parent private
    [[ -n "${BOOTSTRAP_PRIVATE_ROOT:-}" ]] || return 1
    target_parent="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || return 1
    private_parent="$(cd "$(dirname "$BOOTSTRAP_PRIVATE_ROOT")" 2>/dev/null && pwd -P)" || return 1
    target="$target_parent/$(basename "$target")"
    private="$private_parent/$(basename "$BOOTSTRAP_PRIVATE_ROOT")"
    [[ "$target" == "$private" || "$target" == "$private"/* ]]
}

record_managed_target() {
    local target="$1" source="$2"
    managed_target_is_private "$target" && return 0
    [[ -f "${BOOTSTRAP_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap}/install.json" ]] || return 0
    node "$DOTFILES_DIR/scripts/state-helper.mjs" prepare "$target" shared "$source"
}

activate_managed_target() {
    local target="$1"
    managed_target_is_private "$target" && return 0
    [[ -f "${BOOTSTRAP_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap}/install.json" ]] || return 0
    node "$DOTFILES_DIR/scripts/state-helper.mjs" activate "$target"
}

link_external_policy_plugin() {
    local source="$1" checkout="$2" target current=''
    [[ -f "$source" && -d "$checkout" && ! -L "$checkout" ]] || { warn 'External Neovim policy source/checkout is invalid'; return 1; }
    checkout="$(cd "$checkout" && pwd -P)" || return 1
    target="$checkout/lua/plugins/zz-bootstrap-managed.lua"
    [[ -d "$(dirname "$target")" && ! -L "$(dirname "$target")" ]] || { warn 'External Neovim checkout must provide a non-symlink lua/plugins directory'; return 1; }
    if [[ -e "$target" || -L "$target" ]]; then
        [[ -L "$target" ]] || { warn 'External Neovim policy plugin is custom or tracked; refusing replacement'; return 1; }
        current="$(readlink "$target")" || return 1
        managed_source_matches "$current" neovim/bootstrap.lua || { warn 'External Neovim policy plugin is not bootstrap-managed'; return 1; }
    fi
    node "$DOTFILES_DIR/scripts/state-helper.mjs" prepare-policy-plugin "$target" "$checkout" "$source" || return 1
    if [[ "$current" != "$source" ]]; then rm -f "$target" || return 1; ln -s "$source" "$target" || return 1; fi
    node "$DOTFILES_DIR/scripts/state-helper.mjs" activate-policy-plugin "$target"
}

link_managed_file() {
    local source="$1"
    local target="$2"
    local backup_dir="${3:-}" backup_target="$target"
    local current_target backup_path=""

    if [[ ! -e "$source" && ! -L "$source" ]]; then
        warn "Managed link source is missing: $source"
        return 1
    fi

    if [[ -L "$target" ]]; then
        current_target="$(readlink "$target")"
        if [[ "$current_target" == "$source" ]]; then
            record_managed_target "$target" "$source" || return 1
            activate_managed_target "$target" || return 1
            return 0
        fi
        if [[ -e "$target" && "$(resolve_path "$target")" == "$(resolve_path "$source")" ]]; then
            record_managed_target "$target" "$current_target" || return 1
            activate_managed_target "$target" || return 1
            return 0
        fi
    fi

    record_managed_target "$target" "$source" || return 1
    mkdir -p "$(dirname "$target")"
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ -n "$backup_dir" ]]; then
            mkdir -p "$backup_dir" || return 1
            backup_target="$backup_dir/$(basename "$target")"
        fi
        backup_path="$(managed_backup_path "$backup_target")" || return 1
        if ! mv "$target" "$backup_path"; then
            warn "Failed to preserve existing path: $target"
            return 1
        fi
        if ! managed_target_is_private "$target" && [[ -f "${BOOTSTRAP_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap}/install.json" ]]; then node "$DOTFILES_DIR/scripts/state-helper.mjs" backup "$target" "$backup_path" || return 1; fi
        info "Backed up $target to $backup_path"
    fi

    if ln -s "$source" "$target"; then
        activate_managed_target "$target" || return 1
        return 0
    fi

    warn "Failed to link $target to $source"
    if [[ -n "$backup_path" ]]; then
        if ! mv "$backup_path" "$target"; then
            warn "Failed to restore original path from $backup_path"
        fi
    fi
    return 1
}

install_managed_file() {
    local source="$1"
    local target="$2"
    local mode="${3:-0644}"
    local staged_path backup_path=""

    [[ -f "$source" ]] || {
        warn "Managed file source is missing: $source"
        return 1
    }
    record_managed_target "$target" "" || return 1
    mkdir -p "$(dirname "$target")"

    if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target"; then
        chmod "$mode" "$target"
        activate_managed_target "$target" || return 1
        return 0
    fi

    staged_path="$(mktemp "${target}.new.XXXXXX")" || return 1
    if ! install -m "$mode" "$source" "$staged_path"; then
        rm -f "$staged_path"
        return 1
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        backup_path="$(managed_backup_path "$target")" || {
            rm -f "$staged_path"
            return 1
        }
        if ! mv "$target" "$backup_path"; then
            rm -f "$staged_path"
            return 1
        fi
        if ! managed_target_is_private "$target" && [[ -f "${BOOTSTRAP_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap}/install.json" ]]; then node "$DOTFILES_DIR/scripts/state-helper.mjs" backup "$target" "$backup_path" || return 1; fi
        info "Backed up $target to $backup_path"
    fi

    if mv "$staged_path" "$target"; then
        activate_managed_target "$target" || return 1
        return 0
    fi

    rm -f "$staged_path"
    if [[ -n "$backup_path" ]]; then
        mv "$backup_path" "$target" || warn "Failed to restore original path from $backup_path"
    fi
    return 1
}

materialize_json_config() {
    local base_path="$1"
    local overlay_path="$2"
    local target_path="$3"
    local rendered_path
    shift 3

    command -v node &>/dev/null || { warn "node is required to render JSON config: $target_path"; return 1; }
    rendered_path="$(mktemp)" || return 1
    if ! node "$DOTFILES_DIR/scripts/state-helper.mjs" json-merge "$rendered_path" "$base_path" "$overlay_path" "$@"; then
        rm -f "$rendered_path"
        return 1
    fi
    local status
    install_managed_file "$rendered_path" "$target_path" 0600
    status=$?
    rm -f "$rendered_path"
    return "$status"
}

materialize_concat_config() {
    local base_path="$1"
    local overlay_path="$2"
    local target_path="$3"
    local rendered_path status

    rendered_path="$(mktemp)" || return 1
    cat "$base_path" >"$rendered_path"
    if [[ -f "$overlay_path" ]]; then
        printf '\n' >>"$rendered_path"
        cat "$overlay_path" >>"$rendered_path"
    fi
    install_managed_file "$rendered_path" "$target_path" 0600
    status=$?
    rm -f "$rendered_path"
    return "$status"
}
