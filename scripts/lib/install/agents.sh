#!/usr/bin/env bash
# Agent installation and configuration helpers retained from the bare profile.

record_install_failure() {
    local kind="$1"
    local name="$2"
    install_failures+=("$kind:$name")

    mkdir -p "$(dirname "$INSTALL_FAILURE_LOG")" 2>/dev/null || true
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$kind" "$name" >>"$INSTALL_FAILURE_LOG" 2>/dev/null || true
}

report_install_failures() {
    local failure

    [[ ${#install_failures[@]} -eq 0 ]] && return 0

    warn "Install finished with ${#install_failures[@]} failure(s):"
    for failure in "${install_failures[@]}"; do
        warn "  $failure"
    done
    return 1
}

install_herdr() (
    local installer

    installer="$(mktemp)"
    trap 'rm -f "$installer"' EXIT

    info "Installing Herdr agent multiplexer from a verified installer snapshot..."
    download_verified \
        "https://herdr.dev/install.sh" \
        "$HERDR_INSTALLER_SHA256" \
        "$installer" || return 1
    sh "$installer" || return 1
    command -v herdr &>/dev/null || error "Herdr installation failed"

    if command -v pi &>/dev/null; then
        mkdir -p "$HOME/.pi/agent/extensions" || return 1
        herdr integration install pi || return 1
    else
        warn "Pi CLI not found; run 'herdr integration install pi' after installing Pi"
    fi

    mkdir -p "$HOME/.zfunc" || return 1
    herdr completion zsh > "$HOME/.zfunc/_herdr" || return 1
    info "Herdr installed with Pi integration"
)

link_pi_headroom() {
    local launcher="$DOTFILES_DIR/scripts/pi-headroom"
    local extension="$DOTFILES_DIR/pi/extensions/headroom.ts"

    [[ -x "$launcher" ]] || {
        warn "Pi Headroom launcher missing or not executable: $launcher"
        record_install_failure "file" "pi-headroom"
        return 1
    }
    [[ -f "$extension" ]] || {
        warn "Pi Headroom extension missing: $extension"
        record_install_failure "file" "headroom.ts"
        return 1
    }

    mkdir -p "$HOME/.local/bin" "$HOME/.pi/agent/extensions"
    link_managed_file "$launcher" "$HOME/.local/bin/pi-headroom"
    link_managed_file "$launcher" "$HOME/.local/bin/pih"
    link_managed_file "$extension" "$HOME/.pi/agent/extensions/headroom.ts"
    info "Linked Pi Headroom launcher and extension"
}

sync_pi_skill_links() (
    [[ $# -eq 2 ]] || {
        warn "sync_pi_skill_links requires source and target directories"
        return 2
    }

    local source_dir="$1"
    local target_dir="$2"
    local current_target skill_dir link

    [[ -d "$source_dir" ]] || return 0
    mkdir -p "$target_dir"

    shopt -s nullglob

    for link in "$target_dir"/*; do
        [[ -L "$link" ]] || continue
        current_target="$(readlink "$link" 2>/dev/null || true)"
        if [[ "$current_target" == "$source_dir/$(basename "$link")" && ! -f "$current_target/SKILL.md" ]]; then
            rm -f "$link" || return 1
        fi
    done

    for skill_dir in "$source_dir"/*; do
        [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]] || continue
        link_managed_file "$skill_dir" "$target_dir/$(basename "$skill_dir")" "$target_dir/.backups" || return 1
        if [[ "$target_dir" == "$HOME/.pi/agent/skills" ]]; then
            reconcile_managed_skill_alias "$skill_dir" "$HOME/.agents/skills/$(basename "$skill_dir")" || return 1
        fi
    done

    # Pi discovers both roots; migrate the known system alias to the same adapter.
    local omarchy_alias="$HOME/.agents/skills/omarchy"
    if [[ "$target_dir" == "$HOME/.pi/agent/skills" && -f "$source_dir/omarchy/SKILL.md" && -L "$omarchy_alias" ]]; then
        current_target="$(readlink "$omarchy_alias")"
        if [[ "$current_target" == /usr/share/omarchy/default/agents/skills/omarchy ]]; then
            link_managed_file "$source_dir/omarchy" "$omarchy_alias" "$(dirname "$omarchy_alias")/.backups" || return 1
        fi
    fi
)

managed_skill_source_matches() {
    [[ $# -eq 2 ]] || return 2
    local source="$1" name="$2" candidate snapshots
    [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || return 2
    managed_source_matches "$source" "pi/skills/$name" && return 0

    # Only backed-up skill aliases may be adopted from a cache by a checkout.
    snapshots="${DOTFILES_DIR%/*}"
    [[ "${snapshots##*/}" != snapshots ]] || return 1
    local cache="${DOTFILES_BOOTSTRAP_ROOT:-${BOOTSTRAP_ROOT:-$HOME/.local/share/bootstrap}}"
    [[ "$cache" == /* && "$cache" != / ]] || return 1
    [[ "$source" == */"pi/skills/$name" ]] || return 1
    candidate="${source%"/pi/skills/$name"}"
    [[ "${candidate%/*}" == "$cache/snapshots" ]] || return 1
    completed_bootstrap_snapshot "$candidate" || return 1
    return 0
}

reconcile_managed_skill_alias() {
    [[ $# -eq 2 ]] || return 2
    local source="$1" alias="$2" current name
    [[ -f "$source/SKILL.md" ]] || return 1
    [[ -L "$alias" ]] || return 0
    name="$(basename "$source")"
    current="$(readlink "$alias")" || return 1
    if managed_skill_source_matches "$current" "$name"; then
        link_managed_file "$source" "$alias" "$(dirname "$alias")/.backups" || return 1
    fi
    return 0
}

link_codex_skill() {
    [[ $# -eq 1 ]] || return 2
    local source="$1" name codex_home shared legacy current other backup
    [[ -f "$source/SKILL.md" ]] || return 1
    name="$(basename "$source")"
    codex_home="${CODEX_HOME:-$HOME/.codex}"
    shared="$HOME/.agents/skills/$name"
    legacy="$codex_home/skills/$name"

    # Do not replace custom skills or silently choose between distinct definitions.
    for current in "$legacy" "$shared"; do
        [[ -e "$current" || -L "$current" ]] || continue
        if [[ -L "$current" ]]; then
            if [[ "$(resolve_path "$current")" == "$(resolve_path "$source")" ]]; then
                continue
            fi
            if managed_skill_source_matches "$(readlink "$current")" "$name"; then
                continue
            fi
            if [[ "$name" == omarchy && "$(readlink "$current")" == /usr/share/omarchy/default/agents/skills/omarchy ]]; then
                continue
            fi
        fi
        if [[ "$current" == "$legacy" ]]; then other="$shared"; else other="$legacy"; fi
        if [[ ( -e "$other" || -L "$other" ) && "$(resolve_path "$current")" != "$(resolve_path "$other")" ]]; then
            warn "Ambiguous Codex skill '$name': $legacy and $shared; leaving both intact for operator resolution"
            return 1
        fi
        warn "Preserving custom Codex skill: $current"
        return 0
    done

    link_managed_file "$source" "$shared" "$codex_home/backups/shared-skills" || return 1
    reconcile_managed_skill_alias "$source" "$HOME/.pi/agent/skills/$name" || return 1
    if [[ -L "$legacy" && "$(resolve_path "$(dirname "$legacy")")" != "$(resolve_path "$(dirname "$shared")")" ]]; then
        mkdir -p "$codex_home/backups/legacy-skills" || return 1
        backup="$(managed_backup_path "$codex_home/backups/legacy-skills/$name")" || return 1
        mv "$legacy" "$backup" || return 1
    fi
    return 0
}

link_codex_assets() {
    [[ $# -eq 0 ]] || { warn "codex-link accepts no arguments"; return 2; }
    local codex_home="${CODEX_HOME:-$HOME/.codex}" name source
    local sources=()
    [[ -f "$DOTFILES_DIR/codex/AGENTS.md" && -f "$DOTFILES_DIR/codex/native-tools.md" && -f "$DOTFILES_DIR/codex/skills.txt" ]] || return 1
    while IFS= read -r name || [[ -n "$name" ]]; do
        [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { warn "Invalid Codex skill name: $name"; return 1; }
        source="$DOTFILES_DIR/pi/skills/$name"
        [[ -f "$source/SKILL.md" ]] || { warn "Missing Codex skill source: $source"; return 1; }
        sources+=("$source")
    done <"$DOTFILES_DIR/codex/skills.txt"
    [[ ${#sources[@]} -gt 0 ]] || return 1
    source=/usr/share/omarchy/default/agents/skills/diagnose-crash
    if [[ -f "$source/SKILL.md" ]]; then
        sources+=("$source")
    fi

    link_managed_file "$DOTFILES_DIR/codex/AGENTS.md" "$codex_home/AGENTS.md" "$codex_home/backups" || return 1
    link_managed_file "$DOTFILES_DIR/codex/native-tools.md" "$codex_home/native-tools.md" "$codex_home/backups" || return 1
    if [[ -s "$codex_home/AGENTS.override.md" ]]; then
        warn "Codex will load $codex_home/AGENTS.override.md instead of the linked AGENTS.md"
    fi
    cleanup_retired_codex_skills || return 1
    for source in "${sources[@]}"; do
        link_codex_skill "$source" || return 1
    done
    info "Linked native Codex instructions and shared skills"
    return 0
}

command_exists() {
    command -v "$1" &>/dev/null
}

print_status_line() {
    local status="$1"
    local name="$2"
    local detail="${3:-}"

    if [[ -n "$detail" ]]; then
        printf '%-8s %s (%s)\n' "$status" "$name" "$detail"
    else
        printf '%-8s %s\n' "$status" "$name"
    fi
}

read_pi_subagents_package() {
    local settings_path="$1"

    command_exists python3 || return 1
    [[ -f "$settings_path" ]] || return 1
    python3 - "$settings_path" <<'PY'
import json
import re
import sys

pattern = re.compile(r"git:(github\.com/elijah-rou/pi-subagents)@([0-9a-f]{40})")
with open(sys.argv[1], encoding="utf-8") as source:
    packages = json.load(source).get("packages", [])
for package in packages:
    value = package if isinstance(package, str) else package.get("source") if isinstance(package, dict) else None
    if not isinstance(value, str):
        continue
    match = pattern.fullmatch(value)
    if match:
        print(value, match.group(1), match.group(2))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

check_pi_subagents_revision() {
    local settings_path="$DOTFILES_DIR/pi/settings.json"
    local rendered_settings_path="$HOME/.pi/agent/settings.json"
    local repo_metadata="" repo_source="" repo_path="" repo_subagents_pin=""
    local rendered_metadata="" rendered_source="" _rendered_path="" rendered_subagents_pin=""
    local installed_subagents_pin="" installed_subagents_dir=""
    local failed=0

    repo_metadata="$(read_pi_subagents_package "$settings_path" 2>/dev/null || true)"
    read -r repo_source repo_path repo_subagents_pin <<<"$repo_metadata"
    rendered_metadata="$(read_pi_subagents_package "$rendered_settings_path" 2>/dev/null || true)"
    read -r rendered_source _rendered_path rendered_subagents_pin <<<"$rendered_metadata"

    print_status_line "$([[ -n "$repo_subagents_pin" ]] && printf ok || printf failed)" "Pi-subagents repository pin" "${repo_subagents_pin:-missing}"
    if [[ -z "$repo_subagents_pin" ]]; then failed=1; fi
    if [[ -n "$rendered_subagents_pin" && "$rendered_source" == "$repo_source" && "$rendered_subagents_pin" == "$repo_subagents_pin" ]]; then
        print_status_line "ok" "Pi-subagents rendered pin" "$rendered_subagents_pin"
    else
        print_status_line "failed" "Pi-subagents rendered pin" "${rendered_subagents_pin:-missing}; expected ${repo_subagents_pin:-configured pin}"
        failed=1
    fi

    if [[ -n "$repo_path" ]]; then
        installed_subagents_dir="$HOME/.pi/agent/git/$repo_path"
    fi
    if [[ -n "$installed_subagents_dir" ]] && { [[ -d "$installed_subagents_dir/.git" ]] || git -C "$installed_subagents_dir" rev-parse --git-dir >/dev/null 2>&1; }; then
        installed_subagents_pin="$(git -C "$installed_subagents_dir" rev-parse HEAD 2>/dev/null || true)"
        if [[ "$installed_subagents_pin" == "$repo_subagents_pin" ]]; then
            print_status_line "ok" "Pi-subagents installed revision" "$installed_subagents_pin"
        else
            print_status_line "failed" "Pi-subagents installed revision" "${installed_subagents_pin:-unreadable}; expected ${repo_subagents_pin:-configured pin}"
            failed=1
        fi
        if [[ -n "$(git -C "$installed_subagents_dir" status --porcelain=v1 --untracked-files=no 2>/dev/null)" ]]; then
            print_status_line "failed" "Pi-subagents tracked checkout" "tracked changes present"
            failed=1
        else
            print_status_line "ok" "Pi-subagents tracked checkout" "clean"
        fi
        if [[ -f "$installed_subagents_dir/bun.lock" ]] && ! git -C "$installed_subagents_dir" ls-files --error-unmatch bun.lock >/dev/null 2>&1; then
            print_status_line "ok" "Pi-subagents package materialization" "untracked bun.lock"
        fi
    else
        print_status_line "failed" "Pi-subagents installed revision" "checkout missing: ${installed_subagents_dir:-portable package source unavailable}"
        failed=1
    fi
    [[ $failed -eq 0 ]]
}

cleanup_retired_codex_skills() (
    local root link current relative
    shopt -s nullglob
    for root in "$HOME/.agents/skills" "${CODEX_HOME:-$HOME/.codex}/skills"; do
        for link in "$root"/*; do
            [[ -L "$link" ]] || continue
            current="$(readlink "$link")" || return 1
            relative="pi/skills/$(basename "$link")"
            if [[ ! -f "$DOTFILES_DIR/$relative/SKILL.md" ]] && managed_source_matches "$current" "$relative"; then
                rm -f "$link" || return 1
            fi
        done
    done
)
