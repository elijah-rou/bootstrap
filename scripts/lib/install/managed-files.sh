#!/usr/bin/env bash
# Safe, rollback-capable managed links, files, and rendered overlays.

resolve_path() {
    local path="$1"

    if command -v realpath &>/dev/null; then
        realpath "$path" 2>/dev/null || true
        return
    fi

    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$path" 2>/dev/null || true
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
            return 0
        fi
        if [[ -e "$target" && "$(resolve_path "$target")" == "$(resolve_path "$source")" ]]; then
            return 0
        fi
    fi

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
        info "Backed up $target to $backup_path"
    fi

    if ln -s "$source" "$target"; then
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
    mkdir -p "$(dirname "$target")"

    if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target"; then
        chmod "$mode" "$target"
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
        info "Backed up $target to $backup_path"
    fi

    if mv "$staged_path" "$target"; then
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

    command -v python3 &>/dev/null || {
        warn "python3 is required to render JSON config: $target_path"
        return 1
    }
    rendered_path="$(mktemp)" || return 1
    if ! python3 - "$base_path" "$overlay_path" "$rendered_path" "$@" <<'PY'
import json
import pathlib
import sys

base_path, overlay_path, output_path, *additional_overlays = sys.argv[1:]


def reject_constant(value):
    raise ValueError(f"Invalid JSON constant: {value}")


def read_config(path):
    with pathlib.Path(path).open(encoding="utf-8") as source:
        value = json.load(source, parse_constant=reject_constant)
    if not isinstance(value, dict):
        raise ValueError(f"Configuration must be a JSON object: {path}")
    return value


result = read_config(base_path)


def merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        merged = dict(base)
        for key, value in overlay.items():
            merged[key] = merge(merged[key], value) if key in merged else value
        return merged
    return overlay

for path in [overlay_path, *additional_overlays]:
    if path and pathlib.Path(path).exists():
        result = merge(result, read_config(path))
with pathlib.Path(output_path).open("w", encoding="utf-8") as output:
    json.dump(result, output, indent=2, sort_keys=True)
    output.write("\n")
PY
    then
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
