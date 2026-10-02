#!/usr/bin/env bash
# Install, check, or purge the bootstrap environment. See README.md.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${BOOTSTRAP_ROOT:-$HOME/.local/share/bootstrap}"
TOOLS="$ROOT/tools"
PRIVATE="$ROOT/private"
STATE="$ROOT/state.tsv"
CATALOG="$REPO/catalog.tsv"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SELECTION_GROUPS="languages lsp tools"
PLATFORM=''
BACKEND=''
PACKAGE_INDEX_FRESH=0
FAILURES=''

info() { printf '[bootstrap] %s\n' "$*"; }
warn() { printf '[bootstrap] warning: %s\n' "$*" >&2; }
die() { printf '[bootstrap] error: %s\n' "$*" >&2; exit 1; }

usage() {
    local group
    printf '%s\n' 'Usage: ./install.sh [--languages NAME...] [--lsp NAME...] [--tools NAME...]' \
        '       ./install.sh doctor' \
        '       ./install.sh uninstall [--yes]' \
        '' 'Install converges core tools, configuration, and every recorded selection.'
    for group in $SELECTION_GROUPS; do printf '  %-10s %s\n' "$group:" "$(catalog_names "$group" | tr '\n' ' ')"; done
}

# ---------------------------------------------------------------- platform

platform() {
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64) printf 'linux-x86_64\n' ;;
        Linux/aarch64|Linux/arm64) printf 'linux-aarch64\n' ;;
        Darwin/arm64) printf 'darwin-arm64\n' ;;
        *) return 1 ;;
    esac
}

backend() {
    if [[ "$(uname -s)" == Darwin ]]; then
        if command -v brew >/dev/null; then printf 'brew\n'; fi
    elif command -v apt-get >/dev/null; then printf 'apt\n'
    elif command -v dnf >/dev/null; then printf 'dnf\n'
    elif command -v pacman >/dev/null; then printf 'pacman\n'
    fi
}

# Root, Homebrew, or sudo can change system packages; any other account cannot.
can_manage_packages() {
    [[ -n "$BACKEND" ]] || return 1
    [[ "$BACKEND" == brew || "$(id -u)" == 0 ]] && return 0
    command -v sudo >/dev/null || return 1
    sudo -n true 2>/dev/null && return 0
    [[ -t 0 ]] && sudo -v
}

as_admin() {
    if [[ "$BACKEND" == brew || "$(id -u)" == 0 ]]; then "$@"; else sudo -- "$@"; fi
}

package_list() {
    case "$BACKEND" in
        apt) dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' | awk '$1 == "ii" { print $2 }' ;;
        dnf) rpm -qa --qf '%{NAME}\n' ;;
        pacman) pacman -Qq ;;
        brew) brew list --formula -1 ;;
    esac | LC_ALL=C sort -u
}

package_install() {
    case "$BACKEND" in
        apt)
            if [[ "$PACKAGE_INDEX_FRESH" == 0 ]]; then as_admin apt-get update; PACKAGE_INDEX_FRESH=1; fi
            as_admin env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "$@" ;;
        dnf) as_admin dnf install --assumeyes --setopt=install_weak_deps=False "$@" ;;
        pacman) as_admin pacman -S --needed --noconfirm -- "$@" ;;
        brew) HOMEBREW_NO_AUTO_UPDATE=1 brew install "$@" ;;
    esac
}

# Removes exactly the recorded names, including their configuration files; no autoremove,
# so pre-existing packages stay.
package_remove() {
    case "$BACKEND" in
        apt) as_admin env DEBIAN_FRONTEND=noninteractive apt-get purge --yes "$@" ;;
        dnf) as_admin dnf remove --assumeyes --setopt=clean_requirements_on_remove=False "$@" ;;
        pacman) as_admin pacman -R --noconfirm -- "$@" ;;
        brew) brew uninstall --ignore-dependencies "$@" ;;
    esac
}

# ---------------------------------------------------------------- state

# One record per side effect outside the private root, replayed in reverse by uninstall:
#   block FILE created|existing   marked lines added to FILE
#   link TARGET BACKUP|-          symlink; BACKUP holds what it replaced
#   dir PATH                      directory install created; removed if empty
#   own PATH                      absent before install; deleted with its contents
#   package BACKEND NAME          system package that install added
#   select GROUP NAME             persisted selection
record() {
    local line
    line="$(printf '%s\t' "$@")"
    line="${line%$'\t'}"
    grep -qxF -- "$line" "$STATE" 2>/dev/null || printf '%s\n' "$line" >>"$STATE"
}

recorded() { awk -F '\t' -v kind="$1" -v key="$2" '$1 == kind && $2 == key { found = 1 } END { exit !found }' "$STATE" 2>/dev/null; }

# Prints PATH and its missing ancestors inside HOME, outermost first.
absent_dirs() {
    local path="$1" list=''
    while [[ "$path" == "$HOME"/* && ! -e "$path" && ! -L "$path" ]]; do
        list="$path"$'\n'"$list"
        path="$(dirname "$path")"
    done
    printf '%s' "$list"
}

make_dirs() {
    local path
    while IFS= read -r path; do
        if [[ -n "$path" ]]; then record dir "$path"; fi
    done < <(absent_dirs "$1")
    mkdir -p "$1"
}

# Claims paths that applications create later, such as caches, when they do not exist yet.
own() {
    local path parent
    for path in "$@"; do
        recorded own "$path" && continue
        [[ ! -e "$path" && ! -L "$path" ]] || continue
        while IFS= read -r parent; do
            if [[ -n "$parent" ]]; then record dir "$parent"; fi
        done < <(absent_dirs "$(dirname "$path")")
        record own "$path"
    done
}

acquire_lock() {
    local lock="$ROOT/.lock" holder
    mkdir -p "$ROOT"
    if ! mkdir "$lock" 2>/dev/null; then
        holder="$(cat "$lock/pid" 2>/dev/null || true)"
        if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then die "another install (pid $holder) holds $lock"; fi
        warn "removing stale lock from pid ${holder:-unknown}"
        rm -rf "$lock"
        mkdir "$lock"
    fi
    printf '%s\n' "$$" >"$lock/pid"
    trap 'rm -rf "$ROOT/.lock" "$ROOT/tmp"' EXIT
}

# ---------------------------------------------------------------- files

block_text() { printf '# >>> bootstrap %s >>>\n%s\n# <<< bootstrap %s <<<\n' "$1" "$2" "$1"; }

# Prints stdin without bootstrap blocks; with an id, only that block is removed.
strip_blocks() {
    awk -v id="${1:-}" '
        index($0, "# >>> bootstrap ") == 1 && (id == "" || $4 == id) { skip = 1; next }
        skip && index($0, "# <<< bootstrap ") == 1 { skip = 0; next }
        !skip { print }
    '
}

# Replaces any previous block with the same id, so reruns converge.
add_block() {
    local file="$1" id="$2" position="$3" content="$4" existed=existing rendered="$ROOT/tmp/block"
    [[ -e "$file" || -L "$file" ]] || existed=created
    [[ ! -L "$file" ]] || die "refusing to edit symlinked $file; replace it with a regular file first"
    make_dirs "$(dirname "$file")"
    recorded block "$file" || record block "$file" "$existed"
    {
        if [[ "$position" == top ]]; then block_text "$id" "$content"; fi
        if [[ -f "$file" ]]; then strip_blocks "$id" <"$file"; fi
        if [[ "$position" == bottom ]]; then block_text "$id" "$content"; fi
    } >"$rendered"
    cat "$rendered" >"$file"
}

# Points TARGET at SOURCE, moving anything else aside first.
link() {
    local source="$1" target="$2" backup='-'
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then return 0; fi
    make_dirs "$(dirname "$target")"
    if [[ -e "$target" || -L "$target" ]]; then
        if recorded link "$target"; then
            rm -rf "$target"
        else
            backup="$target.bootstrap-backup"
            [[ ! -e "$backup" && ! -L "$backup" ]] || die "$backup already exists; resolve it before installing"
            mv "$target" "$backup"
            info "moved existing $target to $backup"
        fi
    fi
    recorded link "$target" || record link "$target" "$backup"
    ln -s "$source" "$target"
}

# Links inside the private or tools root need no record: uninstall deletes the root.
link_private() {
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
}

# ---------------------------------------------------------------- downloads

sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{ print $1 }'; else shasum -a 256 "$1" | awk '{ print $1 }'; fi
}

fetch() {
    local url="$1" sha="$2" destination="$3"
    [[ "$url" == https://* && "$sha" =~ ^[0-9a-f]{64}$ ]] || die "catalog row for $url needs an https URL and sha256"
    curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
        --retry 3 --connect-timeout 15 --max-time 600 --output "$destination" "$url" || return 1
    [[ "$(sha256 "$destination")" == "$sha" ]] || die "checksum mismatch for $url"
}

extract() {
    local archive="$1" url="$2" destination="$3" name="$4"
    mkdir -p "$destination"
    case "$url" in
        *.tar.gz|*.tgz) tar -xzf "$archive" -C "$destination" ;;
        *.tar.xz) tar -xJf "$archive" -C "$destination" ;;
        *.zip)
            if command -v unzip >/dev/null; then unzip -q "$archive" -d "$destination"
            elif [[ "$(uname -s)" == Darwin ]]; then tar -xf "$archive" -C "$destination"
            else die "unzip is required to extract $url"; fi ;;
        *.gz) gzip -dc "$archive" >"$destination/$name" && chmod 0755 "$destination/$name" ;;
        *) mv "$archive" "$destination/$name" && chmod 0755 "$destination/$name" ;;
    esac
}

# Unpacks into tools/pkgs/NAME-VERSION once, links the listed executables, and drops older versions.
install_download() {
    local name="$1" version="$2" url="$3" sha="$4" bins="$5" package="$TOOLS/pkgs/$1-$2" bin path old
    if [[ ! -d "$package" ]]; then
        info "downloading $name $version"
        mkdir -p "$ROOT/tmp" "$TOOLS/pkgs"
        rm -rf "$ROOT/tmp/$name" "$ROOT/tmp/$name.extract"
        fetch "$url" "$sha" "$ROOT/tmp/$name" || return 1
        extract "$ROOT/tmp/$name" "$url" "$ROOT/tmp/$name.extract" "${bins%%,*}" || return 1
        mv "$ROOT/tmp/$name.extract" "$package" || return 1
    fi
    for old in "$TOOLS/pkgs/$name"-[0-9v]*; do
        if [[ "$old" != "$package" && -d "$old" ]]; then rm -rf "$old"; fi
    done
    [[ "$bins" != - ]] || return 0
    for bin in ${bins//,/ }; do
        path="$(find "$package" -name "$bin" -type f -perm -u+x | awk 'NR == 1')"
        [[ -n "$path" ]] || die "$name archive has no executable named $bin"
        link_private "$path" "$TOOLS/bin/$bin" || return 1
    done
}

# ---------------------------------------------------------------- catalog

catalog_names() {
    awk -F '\t' -v group="$1" '$0 !~ /^#/ && NF == 7 && index("," $2 ",", "," group ",") && !seen[$1]++ { print $1 }' "$CATALOG"
}

core_names() { awk -F '\t' '$0 !~ /^#/ && $2 == "core" && !seen[$1]++ { print $1 }' "$CATALOG"; }

# Download rows for this platform win; otherwise this system's package rows apply.
# Rows for any platform always apply. File order is install order.
applicable_rows() {
    awk -F '\t' -v name="$1" -v platform="$PLATFORM" -v backend="$BACKEND" '
        $0 ~ /^#/ || $1 != name { next }
        { rows[++count] = $0; platforms[count] = $4; if ($4 == platform) download = 1 }
        END {
            for (i = 1; i <= count; i++)
                if (platforms[i] == "any" || platforms[i] == (download ? platform : backend)) print rows[i]
        }
    ' "$CATALOG"
}

# Returns 2 when nothing can provide NAME on this host, 1 when installation fails.
install_name() {
    local name="$1" rows version sha source bins packages='' bin missing before after added
    rows="$(applicable_rows "$name")"
    [[ -n "$rows" ]] || { warn "$name has no source for $PLATFORM${BACKEND:+/$BACKEND}"; return 2; }

    # System packages go first, in one transaction, and only for missing executables.
    while IFS=$'\t' read -r _ _ _ _ _ source bins; do
        [[ "$source" == pkg:* ]] || continue
        missing=0
        for bin in ${bins//,/ }; do command -v "$bin" >/dev/null || missing=1; done
        [[ "$missing" == 0 ]] || packages="$packages ${source#pkg:}"
    done <<<"$rows"
    if [[ -n "$packages" ]]; then
        can_manage_packages || { warn "$name needs system packages ($packages ) and this account cannot install them"; return 2; }
        before="$(package_list)" || return 1
        # shellcheck disable=SC2086 # package names are single catalog words
        package_install $packages || return 1
        after="$(package_list)" || return 1
        added="$(LC_ALL=C comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
        while IFS= read -r bin; do
            if [[ -n "$bin" ]]; then record package "$BACKEND" "$bin"; fi
        done <<<"$added"
        hash -r
    fi

    while IFS=$'\t' read -r _ _ version _ sha source bins; do
        case "$source" in
            pkg:*) ;;
            https://*) install_download "$name" "$version" "$source" "$sha" "$bins" ;;
            npm:*) bun install --global --exact "${source#npm:}@$version" >/dev/null ;;
            go:*)
                command -v go >/dev/null || { warn "$name needs Go; add --languages go"; return 1; }
                GOBIN="$TOOLS/bin" go install "${source#go:}@$version" ;;
            step:*) "step_${source#step:}" "$version" ;;
            *) die "unsupported catalog source for $name: $source" ;;
        esac || { warn "$name failed at $source"; return 1; }
    done <<<"$rows"
    hash -r
}

# ---------------------------------------------------------------- steps

# Steps run where `set -e` is suspended (callers test their status), so each command chains.
step_rust() {
    { [[ -x "$CARGO_HOME/bin/rustup" ]] || "$TOOLS/bin/rustup-init" -y --no-modify-path --profile minimal --default-toolchain none; } &&
        "$CARGO_HOME/bin/rustup" toolchain install "$1" --profile minimal &&
        "$CARGO_HOME/bin/rustup" default "$1"
}

step_python() {
    local python
    uv python install "$1" && python="$(uv python find --managed-python "$1")" || return 1
    link_private "$python" "$TOOLS/bin/python3" && link_private "$python" "$TOOLS/bin/python"
}

step_elixirls() {
    local package="$TOOLS/pkgs/elixirls-$1"
    [[ -f "$package/language_server.sh" ]] || die "ElixirLS archive is missing language_server.sh"
    chmod 0755 "$package/language_server.sh" &&
        MIX_ENV=prod elixir "$package/quiet_install.exs" </dev/null &&
        link_private "$package/language_server.sh" "$TOOLS/bin/elixir-ls"
}

step_codex() {
    local name skill
    link_private "$ROOT/repo/bin/codex" "$TOOLS/bin/codex" &&
        link_private "$ROOT/repo/codex/AGENTS.md" "$PRIVATE/codex/AGENTS.md" &&
        link_private "$ROOT/repo/codex/native-tools.md" "$PRIVATE/codex/native-tools.md" || return 1
    [[ -e "$PRIVATE/codex/config.toml" ]] || cp "$REPO/codex/config.toml" "$PRIVATE/codex/config.toml" || return 1
    # Codex discovers skills in the shared agents directory, outside the private root.
    own "$HOME/.agents"
    while IFS= read -r name; do
        skill="$HOME/.agents/skills/$name"
        if [[ -e "$skill" && ! -L "$skill" ]]; then warn "keeping existing skill $skill"; continue; fi
        link "$ROOT/repo/pi/skills/$name" "$skill" || return 1
    done <"$REPO/codex/skills.txt"
}

step_zsh() {
    mkdir -p "$PRIVATE/zsh" &&
        add_block "$HOME/.zshenv" env bottom ". \"$ROOT/repo/shell/env.sh\"" &&
        add_block "$HOME/.zshrc" interactive bottom ". \"$ROOT/repo/shell/zshrc\""
}

step_tmux() {
    mkdir -p "$PRIVATE/tmux" && link "$ROOT/repo/config/tmux.conf" "$HOME/.tmux.conf"
}

# ---------------------------------------------------------------- configuration

configure_shell() {
    local login="$HOME/.bash_profile" candidate
    for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        if [[ -e "$candidate" ]]; then login="$candidate"; break; fi
    done
    mkdir -p "$PRIVATE/bash" "$PRIVATE/less" "$PRIVATE/zoxide"
    # The environment block goes first so it survives rc files that return early for
    # non-interactive shells; the interactive block goes last so its aliases win.
    add_block "$HOME/.bashrc" env top ". \"$ROOT/repo/shell/env.sh\""
    add_block "$HOME/.bashrc" interactive bottom ". \"$ROOT/repo/shell/bashrc\""
    add_block "$login" login bottom ". \"$ROOT/repo/shell/env.sh\"
case \$- in *i*) . \"$ROOT/repo/shell/bashrc\" ;; esac"
    add_block "$HOME/.gitconfig" git bottom "[include]
	path = $ROOT/repo/config/gitconfig"
}

configure_apps() {
    # Go's telemetry directory cannot be relocated; it is claimed only when it does not exist yet.
    own "$CONFIG_HOME/git" "$CONFIG_HOME/herdr" "$CONFIG_HOME/pi" "$CACHE_HOME/helix" \
        "$STATE_HOME/gh" "$CACHE_HOME/gh" "$CONFIG_HOME/go/telemetry" "$HOME/Library/Application Support/go/telemetry"
    mkdir -p "$PRIVATE/gh"
    link "$ROOT/repo/config/gitignore" "$CONFIG_HOME/git/ignore"
    link "$ROOT/repo/config/helix" "$CONFIG_HOME/helix"
    link "$ROOT/repo/config/herdr.toml" "$CONFIG_HOME/herdr/config.toml"
}

# Pi state lives in the private root; only its router configuration sits in XDG config.
configure_pi() {
    local agent="$PRIVATE/pi/agent" directory pattern source file overlay
    (umask 077 && mkdir -p "$PRIVATE/pi/sessions" "$agent/extensions/subagent")
    link_private "$ROOT/repo/bin/pi" "$TOOLS/bin/pi"
    link_private "$ROOT/repo/bin/pi-workspace" "$TOOLS/bin/pi-workspace"
    link_private "$ROOT/repo/bin/pi-workspace" "$TOOLS/bin/piw"
    for file in web-search profile-router strategy-router; do
        link "$ROOT/repo/pi/$file.json" "$CONFIG_HOME/pi/$file.json"
    done
    link_private "$ROOT/repo/pi/AGENTS.md" "$agent/AGENTS.md"
    link_private "$ROOT/repo/pi/WORKTREE_STREAMS.md" "$agent/WORKTREE_STREAMS.md"
    link_private "$ROOT/repo/pi/subagent-config.json" "$agent/extensions/subagent/config.json"

    # Drop links to files removed from the repository, then link the current set.
    for directory in extensions agents prompts skills themes; do
        mkdir -p "$agent/$directory"
        for file in "$agent/$directory"/*; do
            if [[ -L "$file" && "$(readlink "$file")" == "$ROOT/repo/"* && ! -e "$file" ]]; then rm -f "$file"; fi
        done
    done
    while read -r directory pattern; do
        for source in "$REPO/pi/$directory"/$pattern; do
            if [[ -e "$source" ]]; then link_private "$ROOT/repo/pi/$directory/${source##*/}" "$agent/$directory/${source##*/}"; fi
        done
    done <<'LINKS'
extensions *.ts
extensions *.json
agents *.md
prompts *.md
skills *
themes *.json
LINKS

    # Pi rewrites settings at runtime, so they are rendered copies merged with optional overlays.
    for file in settings models; do
        overlay="$CONFIG_HOME/bootstrap/pi-$file.json"
        bun "$REPO/bin/merge-json" "$REPO/pi/$file.json" "$overlay" >"$ROOT/tmp/pi-$file.json"
        if ! cmp -s "$ROOT/tmp/pi-$file.json" "$agent/$file.json"; then
            if [[ -f "$agent/$file.json" ]]; then cp "$agent/$file.json" "$agent/$file.json.bak"; fi
            (umask 077 && cp "$ROOT/tmp/pi-$file.json" "$agent/$file.json")
        fi
    done

    herdr integration install pi >/dev/null
    while IFS= read -r source; do
        pi install "$source" >/dev/null || { warn "Pi package failed: $source"; return 1; }
    done < <(bun -e 'for (const p of require(process.argv[1]).packages ?? []) console.log(typeof p === "string" ? p : p.source)' "$agent/settings.json")
}

# ---------------------------------------------------------------- commands

load_environment() {
    export BOOTSTRAP_ROOT="$ROOT"
    # shellcheck source=shell/env.sh
    . "$REPO/shell/env.sh"
    hash -r
}

preflight() {
    local command
    PLATFORM="$(platform)" || die "supported platforms are Linux x86_64/aarch64 and Apple Silicon macOS"
    BACKEND="$(backend)"
    [[ "$HOME" == /* && -d "$HOME" && -w "$HOME" ]] || die "HOME must be an absolute writable directory"
    [[ "$ROOT" == /* && "$ROOT" != / ]] || die "BOOTSTRAP_ROOT must be an absolute directory"
    for command in git curl tar gzip awk; do command -v "$command" >/dev/null || die "missing prerequisite: $command"; done
    command -v sha256sum >/dev/null || command -v shasum >/dev/null || die "missing prerequisite: sha256sum or shasum"
    if [[ "$PLATFORM" == linux-* ]] && ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then die "Linux hosts need glibc"; fi
}

install_selection() {
    if install_name "$2"; then record select "$1" "$2"; else FAILURES="$FAILURES $2"; fi
}

cmd_install() {
    local group='' name requested='' root_parents
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --languages|-l) group=languages ;;
            --lsp|-s) group=lsp ;;
            --tools|-t) group=tools ;;
            -h|--help) usage; return 0 ;;
            -*) die "unknown option: $1" ;;
            *) [[ -n "$group" ]] || die "$1 needs --languages, --lsp, or --tools before it"
               catalog_names "$group" | grep -qxF -- "$1" || die "unknown $group selection: $1"
               requested="$requested $group:$1" ;;
        esac
        shift
    done
    preflight
    root_parents="$(absent_dirs "$(dirname "$ROOT")")"
    acquire_lock
    mkdir -p "$TOOLS/bin" "$ROOT/tmp"
    (umask 077 && mkdir -p "$PRIVATE")
    chmod 0700 "$PRIVATE"
    touch "$STATE"
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then record dir "$name"; fi
    done <<<"$root_parents"
    ln -sfn "$REPO" "$ROOT/repo"
    load_environment
    # Bun is the only JavaScript runtime; this covers `#!/usr/bin/env node` entrypoints.
    link_private "$ROOT/repo/bin/node" "$TOOLS/bin/node"

    for name in $(core_names); do
        if install_name "$name"; then :; elif [[ $? == 2 ]]; then warn "continuing without $name"; else FAILURES="$FAILURES $name"; fi
    done
    [[ -z "$FAILURES" ]] || die "core tools failed:$FAILURES"
    configure_shell
    configure_apps
    configure_pi

    while IFS=$'\t' read -r _ group name; do
        install_selection "$group" "$name"
    done < <(awk -F '\t' '$1 == "select"' "$STATE")
    for name in $requested; do
        if ! grep -qxF "select"$'\t'"${name%%:*}"$'\t'"${name#*:}" "$STATE"; then install_selection "${name%%:*}" "${name#*:}"; fi
    done

    [[ -z "$FAILURES" ]] || die "incomplete:$FAILURES"
    info "installed; start a new shell to use it"
}

cmd_doctor() {
    local name bin version failed=0
    preflight
    [[ -f "$STATE" ]] || die "not installed at $ROOT"
    load_environment
    for name in $(core_names) $(awk -F '\t' '$1 == "select" { print $3 }' "$STATE"); do
        for bin in $(applicable_rows "$name" | awk -F '\t' '$7 != "-" { n = split($7, bins, ","); for (i = 1; i <= n; i++) if (!seen[bins[i]]++) print bins[i] }'); do
            if command -v "$bin" >/dev/null; then printf 'ok       %-28s %s\n' "$name" "$bin"
            else printf 'missing  %-28s %s\n' "$name" "$bin"; failed=1; fi
        done
    done
    version="$(awk -F '\t' '$1 == "pi" { print $3; exit }' "$CATALOG")"
    if [[ "$(pi --version 2>/dev/null)" != "$version" ]]; then printf 'wrong    pi version, want %s\n' "$version"; failed=1; fi
    return "$failed"
}

cmd_uninstall() {
    local confirmed="${1:-}" kind path value packages='' records
    [[ $# -le 1 && ( -z "$confirmed" || "$confirmed" == --yes ) ]] || die "usage: ./install.sh uninstall [--yes]"
    BACKEND="$(backend)"
    [[ -f "$STATE" ]] || { info "nothing to uninstall at $ROOT"; return 0; }
    [[ -z "${HERDR_PANE_ID:-}" && -z "${TMUX:-}" ]] || die "run uninstall outside herdr and tmux; it stops their servers"

    info "uninstall deletes $ROOT (tools, auth, sessions, history) and undoes:"
    awk -F '\t' '$1 != "select" { print "  " $0 }' "$STATE"
    if [[ "$confirmed" != --yes ]]; then
        [[ -t 0 ]] || die "pass --yes to uninstall non-interactively"
        printf 'Continue? [y/N] '
        read -r confirmed
        [[ "$confirmed" == y || "$confirmed" == Y ]] || die "cancelled"
    fi
    load_environment

    # Sign out first so tokens kept in an OS keyring are deleted, not orphaned.
    if command -v gh >/dev/null && [[ -f "$GH_CONFIG_DIR/hosts.yml" ]]; then
        for value in $(awk '/^[^ #][^:]*:/ { sub(/:.*/, ""); print }' "$GH_CONFIG_DIR/hosts.yml"); do
            while gh auth logout --hostname "$value" >/dev/null 2>&1; do :; done
        done
    fi
    if command -v herdr >/dev/null && [[ -S "$CONFIG_HOME/herdr/herdr.sock" ]]; then herdr server stop || true; fi
    for path in "$TMUX_TMPDIR"/tmux-*/*; do
        if [[ -S "$path" ]] && command -v tmux >/dev/null; then tmux -S "$path" kill-server 2>/dev/null || true; fi
    done

    # The root goes first so the directories that held it can be removed while replaying.
    records="$(awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$STATE")"
    chmod -R u+w "$ROOT" 2>/dev/null || true
    rm -rf "$ROOT"
    while IFS=$'\t' read -r kind path value; do
        case "$kind" in
            block)
                if [[ -f "$path" ]]; then
                    strip_blocks <"$path" >"$path.bootstrap-tmp"
                    cat "$path.bootstrap-tmp" >"$path"
                    rm -f "$path.bootstrap-tmp"
                    if [[ "$value" == created && ! -s "$path" ]]; then rm -f "$path"; fi
                fi ;;
            link)
                if [[ -L "$path" && "$(readlink "$path")" == "$ROOT/"* ]]; then rm -f "$path"; fi
                if [[ "$value" != - && ( -e "$value" || -L "$value" ) && ! -e "$path" && ! -L "$path" ]]; then mv "$value" "$path"; fi ;;
            own) rm -rf "$path" ;;
            dir) rmdir "$path" 2>/dev/null || true ;;
            package) packages="$packages $value" ;;
            select) ;;
            *) warn "ignoring unknown state record: $kind" ;;
        esac
    done <<<"$records"

    if [[ -n "$packages" ]]; then
        info "removing system packages:$packages"
        # shellcheck disable=SC2086 # package names are single catalog words
        if ! { can_manage_packages && package_remove $packages; }; then warn "remove these packages manually:$packages"; fi
    fi
    info "uninstalled. Remove this checkout with: rm -rf \"$REPO\""
}

case "${1:-}" in
    doctor) shift; [[ $# -eq 0 ]] || die "doctor takes no arguments"; cmd_doctor ;;
    uninstall) shift; cmd_uninstall "$@" ;;
    ''|-*) cmd_install "$@" ;;
    *) usage >&2; exit 2 ;;
esac
