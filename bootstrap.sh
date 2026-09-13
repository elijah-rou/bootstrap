#!/usr/bin/env bash
set -euo pipefail

REVISION='d91fa741b3174627c095d4e6dfd36c31b82b3cce'
ARCHIVE_SHA256='6175c18800846da124233da6837ceb72f331395ef39a23741a32ec750ab339b4'
BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$HOME/.local/share/bootstrap}"
snapshot="$BOOTSTRAP_ROOT/snapshots/$REVISION"
command_name="${1:-install}"

case "$command_name" in
    install|fetch|preflight|doctor|link|codex-link|herdr) [[ $# -le 1 ]] || { printf 'Unexpected arguments\n' >&2; exit 2; } ;;
    uninstall) case "${2:-}" in --dry-run|--yes) [[ $# -eq 2 ]] ;; '') [[ $# -eq 1 ]] ;; *) false ;; esac || { printf 'Usage: bootstrap.sh uninstall [--dry-run|--yes]\n' >&2; exit 2; } ;;
    migrate-legacy) [[ $# -eq 2 && "$2" == --yes ]] || { printf 'Usage: bootstrap.sh migrate-legacy --yes\n' >&2; exit 2; } ;;
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
        printf '%s\n' 'Usage: bash bootstrap.sh [install|fetch|preflight|doctor|link|codex-link|herdr]' \
            '       bash bootstrap.sh (--languages|-l) LANGUAGE...' \
            '       bash bootstrap.sh (--lsp|-s) SERVER...' \
            '       bash bootstrap.sh (--tools|-t) TOOL...' \
            '       bash bootstrap.sh uninstall [--dry-run|--yes]' \
            '       bash bootstrap.sh migrate-legacy --yes' \
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

if [[ "$command_name" == doctor || "$command_name" == link || "$command_name" == codex-link || "$command_name" == uninstall || "$command_name" == migrate-legacy || "$command_name" == enroll-project ]]; then
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
