#!/usr/bin/env bash
set -euo pipefail

REVISION='b976859d45b4c4f672b50643d671c9b03362804c'
ARCHIVE_SHA256='033fc44f740f37b657c7328fda01af18b732d6988dc320e75dbb5facee00416d'
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$HOME/.local/share/bootstrap}"
snapshot="$BOOTSTRAP_ROOT/snapshots/$REVISION"
command_name="${1:-install}"

case "$command_name" in
    install|pi|fetch|preflight|doctor|link|codex-link|herdr) [[ $# -le 1 ]] || { printf 'Unexpected arguments\n' >&2; exit 2; } ;;
    uninstall) case "${2:-}" in --dry-run|--yes) [[ $# -eq 2 ]] ;; '') [[ $# -eq 1 ]] ;; *) false ;; esac || { printf 'Usage: bootstrap.sh uninstall [--dry-run|--yes]\n' >&2; exit 2; } ;;
    migrate-legacy) [[ $# -eq 2 && "$2" == --yes ]] || { printf 'Usage: bootstrap.sh migrate-legacy --yes\n' >&2; exit 2; } ;;
    migration)
        case "${2:-}" in
            inspect|prepare|verify) [[ $# -eq 2 ]] ;;
            transfer|activate|rollback|retire) [[ $# -eq 3 && "$3" == --yes ]] ;;
            *) false ;;
        esac || { printf 'Usage: bootstrap.sh migration <inspect|prepare|transfer|activate|verify|rollback|retire> [--yes]\n' >&2; exit 2; }
        ;;
    enroll-project) [[ $# -eq 3 && "$2" == /* && "$3" == --yes ]] || { printf 'Usage: bootstrap.sh enroll-project ABS_DIR --yes\n' >&2; exit 2; } ;;
    --languages|-l)
        [[ $# -gt 1 ]] || { printf 'Select languages: c cpp rust go python typescript elixir zig\n' >&2; exit 2; }
        for selection in "${@:2}"; do
            case "$selection" in c|cpp|rust|go|python|typescript|elixir|zig) ;; *) printf 'Unknown toolchain: %s\n' "$selection" >&2; exit 2 ;; esac
        done
        ;;
    --lsp|-s)
        [[ $# -gt 1 ]] || { printf 'Select an LSP server\n' >&2; exit 2; }
        for selection in "${@:2}"; do case "$selection" in clangd|rust-analyzer|gopls|basedpyright|ruff|typescript-language-server|bash-language-server|elixirls|zls) ;; *) printf 'Unknown LSP: %s\n' "$selection" >&2; exit 2 ;; esac; done
        ;;
    --tools|-t)
        [[ $# -gt 1 ]] || { printf 'Select tools: zsh starship codex just wget unzip shellcheck ruff headroom\n' >&2; exit 2; }
        for selection in "${@:2}"; do
            case "$selection" in zsh|starship|codex|just|wget|unzip|shellcheck|ruff|headroom) ;; *) printf 'Unknown tool: %s\n' "$selection" >&2; exit 2 ;; esac
        done
        ;;
    --help|-h)
        printf '%s\n' 'Usage: bash bootstrap.sh [install|pi|fetch|preflight|doctor|link|codex-link|herdr]' \
            '       bash bootstrap.sh (--languages|-l) LANGUAGE...' \
            '       bash bootstrap.sh (--lsp|-s) SERVER...' \
            '       bash bootstrap.sh (--tools|-t) TOOL...' \
            '       bash bootstrap.sh uninstall [--dry-run|--yes]' \
            '       bash bootstrap.sh migration <inspect|prepare|transfer|activate|verify|rollback|retire> [--yes]' \
            '       bash bootstrap.sh migrate-legacy --yes  # compatibility notice only' \
            '       bash bootstrap.sh enroll-project ABS_DIR --yes' \
            'Tools: zsh starship codex just wget unzip shellcheck ruff headroom.' \
            'Languages: c cpp rust go python typescript elixir zig.' \
            'Downloads a verified public snapshot; install is the default.'
        exit 0
        ;;
    *) printf 'Unknown command: %s\n' "$command_name" >&2; exit 2 ;;
esac
[[ "$BOOTSTRAP_ROOT" == /* && "$BOOTSTRAP_ROOT" != / ]] || { printf 'BOOTSTRAP_ROOT must be an absolute directory below /\n' >&2; exit 2; }

snapshot_ready() {
    [[ -x "$snapshot/install.sh" && -f "$snapshot/.bootstrap-archive-sha256" ]] &&
        [[ "$(cat "$snapshot/.bootstrap-archive-sha256")" == "$ARCHIVE_SHA256" ]]
}

if [[ "$command_name" == doctor || "$command_name" == link || "$command_name" == codex-link || "$command_name" == uninstall || "$command_name" == migration || "$command_name" == migrate-legacy || "$command_name" == enroll-project ]]; then
    snapshot_ready || { printf 'Snapshot is missing or incomplete; run bootstrap.sh fetch first\n' >&2; exit 1; }
else
    for prerequisite in curl tar awk; do
        command -v "$prerequisite" >/dev/null || { printf 'Missing prerequisite: %s\n' "$prerequisite" >&2; exit 1; }
    done
    if command -v sha256sum >/dev/null; then
        checksum=(sha256sum)
    elif command -v shasum >/dev/null; then
        checksum=(shasum -a 256)
    else
        printf 'A SHA-256 tool is required\n' >&2; exit 1
    fi
    mkdir -p "$BOOTSTRAP_ROOT/snapshots"
    if ! mkdir "$BOOTSTRAP_ROOT/install.lock"; then
        printf 'Bootstrap is locked at %s/install.lock; check for a running installer before removing it\n' "$BOOTSTRAP_ROOT" >&2
        exit 1
    fi
    stage=''
    trap '[[ -z "$stage" ]] || rm -rf "$stage"; rmdir "$BOOTSTRAP_ROOT/install.lock"' EXIT
    if [[ -e "$snapshot" || -L "$snapshot" ]]; then
        snapshot_ready || { printf 'Unexpected snapshot at %s; move it aside after checking its contents\n' "$snapshot" >&2; exit 1; }
    else
        stage="$(mktemp -d "$BOOTSTRAP_ROOT/stage.XXXXXX")"
        curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
            --retry 3 --connect-timeout 15 --max-time 300 \
            --output "$stage/source.tar.gz" \
            "https://codeload.github.com/elijah-rou/bootstrap/tar.gz/$REVISION"
        actual_sha256="$("${checksum[@]}" "$stage/source.tar.gz" | awk '{ print $1 }')"
        [[ "$actual_sha256" == "$ARCHIVE_SHA256" ]] || { printf 'Bootstrap archive checksum mismatch\n' >&2; exit 1; }
        mkdir "$stage/source"
        tar -xzf "$stage/source.tar.gz" -C "$stage/source" --strip-components=1
        [[ -x "$stage/source/install.sh" ]] || { printf 'Archive has no installer\n' >&2; exit 1; }
        printf '%s\n' "$ARCHIVE_SHA256" > "$stage/source/.bootstrap-archive-sha256"
        mv "$stage/source" "$snapshot"
    fi
fi

if [[ "$command_name" == fetch ]]; then
    printf '%s\n' "$snapshot"
else
    if [[ $# -eq 0 ]]; then set -- install; fi
    bash "$snapshot/install.sh" "$@"
fi
