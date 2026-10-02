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
# Set by `install.sh link`: steps then change configuration only and never download.
OFFLINE=0

info() { printf '[bootstrap] %s\n' "$*"; }
warn() { printf '[bootstrap] warning: %s\n' "$*" >&2; }
die() { printf '[bootstrap] error: %s\n' "$*" >&2; exit 1; }

usage() {
    local group
    printf '%s\n' 'Usage: ./install.sh [--languages NAME...] [--lsp NAME...] [--tools NAME...]' \
        '       ./install.sh link        relink configuration only; no downloads' \
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

# Homebrew otherwise autoremoves, cleans up, and upgrades formulae it did not install for us, and
# keeps downloads and logs in the user's Library; ours stay in the root.
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export HOMEBREW_CACHE="$PRIVATE/cache/homebrew" HOMEBREW_LOGS="$PRIVATE/cache/homebrew-logs"

# Packages dpkg knows in any state count as present, so a removed-but-configured package that
# install brings back is never purged later.
package_list() {
    case "$BACKEND" in
        apt) dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' | awk '$1 != "un" { print $2 }' ;;
        dnf) rpm -qa --qf '%{NAME}\n' ;;
        pacman) pacman -Qq ;;
        brew) brew list --formula -1 ;;
    esac | LC_ALL=C sort -u
}

# Installs packages and records the ones that appeared. The baseline is written first so an
# interrupted or failed transaction is still recorded by the next run (record_package_changes).
package_install() {
    local status=0
    if [[ "$BACKEND" == apt && "$PACKAGE_INDEX_FRESH" == 0 ]]; then as_admin apt-get update || return 1; PACKAGE_INDEX_FRESH=1; fi
    package_list >"$ROOT/package-baseline" || return 1
    # systemd-tmpfiles, run by some package hooks (Arch), creates /root/.ssh; it is removed only if empty.
    if [[ ! -e "$HOME/.ssh" ]]; then record dir "$HOME/.ssh"; fi
    # Homebrew keeps trust state in ~/.homebrew, which cannot be relocated.
    if [[ "$BACKEND" == brew ]]; then own "$HOME/.homebrew"; fi
    case "$BACKEND" in
        apt)
            # Only names in this transaction count, not packages another process adds meanwhile.
            as_admin apt-get --simulate install --no-install-recommends "$@" | awk '$1 == "Inst" { print $2 }' >"$ROOT/package-plan" || return 1
            as_admin env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "$@" || status=$? ;;
        dnf) as_admin dnf install --assumeyes --setopt=install_weak_deps=False "$@" || status=$? ;;
        pacman) as_admin pacman -S --needed --noconfirm -- "$@" || status=$? ;;
        brew) brew install "$@" || status=$? ;;
    esac
    record_package_changes
    return "$status"
}

record_package_changes() {
    local name
    [[ -f "$ROOT/package-baseline" ]] || return 0
    while IFS= read -r name; do
        if [[ -z "$name" ]]; then continue; fi
        if [[ -f "$ROOT/package-plan" ]] && ! grep -qxF -- "$name" "$ROOT/package-plan"; then continue; fi
        record package "$BACKEND" "$name"
    done < <(LC_ALL=C comm -13 "$ROOT/package-baseline" <(package_list))
    rm -f "$ROOT/package-baseline" "$ROOT/package-plan"
}

# Removes exactly the recorded names. Each tool refuses rather than cascading when something
# installed since depends on them, so nothing beyond the recorded set is removed.
package_remove() {
    case "$BACKEND" in
        apt) as_admin dpkg --purge -- "$@" ;;
        dnf) as_admin rpm -e -- "$@" ;;
        pacman) as_admin pacman -R --noconfirm -- "$@" ;;
        brew) brew uninstall "$@" ;;
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
# Fails without output change if a start marker has no end marker, rather than dropping the rest.
strip_blocks() {
    awk -v id="${1:-}" '
        index($0, "# >>> bootstrap ") == 1 && (id == "" || $4 == id) { skip = 1; next }
        skip && index($0, "# <<< bootstrap ") == 1 { skip = 0; next }
        !skip { print }
        END { exit skip ? 3 : 0 }
    '
}

# Replaces any previous block with the same id, so reruns converge.
add_block() {
    local file="$1" id="$2" position="$3" content="$4" existed=existing rendered="$ROOT/tmp/block"
    [[ -e "$file" || -L "$file" ]] || existed=created
    [[ ! -L "$file" ]] || die "refusing to edit symlinked $file; replace it with a regular file first"
    make_dirs "$(dirname "$file")"
    recorded block "$file" || record block "$file" "$existed"
    if [[ -f "$file" ]]; then
        strip_blocks "$id" <"$file" >"$rendered.rest" || die "$file has an unterminated bootstrap block; fix it by hand"
    else
        : >"$rendered.rest"
    fi
    {
        if [[ "$position" == top ]]; then block_text "$id" "$content"; fi
        cat "$rendered.rest"
        if [[ "$position" == bottom ]]; then block_text "$id" "$content"; fi
    } >"$rendered"
    cat "$rendered" >"$file"
}

# Points TARGET at SOURCE, moving anything else aside first. A file the user put in place of
# an earlier bootstrap link is left alone.
link() {
    local source="$1" target="$2" backup='-'
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        recorded link "$target" || record link "$target" -
        return 0
    fi
    make_dirs "$(dirname "$target")"
    if recorded link "$target"; then
        if [[ -L "$target" && "$(readlink "$target")" == "$ROOT/"* ]]; then rm -f "$target"
        elif [[ -e "$target" || -L "$target" ]]; then warn "keeping $target, which replaced the bootstrap link"; return 0; fi
    elif [[ -e "$target" || -L "$target" ]]; then
        backup="$target.bootstrap-backup"
        [[ ! -e "$backup" && ! -L "$backup" ]] || die "$backup already exists; resolve it before installing"
        # Recorded first: if interrupted before the move, uninstall finds no backup and leaves the original.
        record link "$target" "$backup"
        mv "$target" "$backup"
        info "moved existing $target to $backup"
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

# Keeps tools/NAME checked out at REVISION; a commit id pins the content. BOOTSTRAP_AGENT_KIT may name
# a local agent-kit checkout to develop against instead.
install_git() {
    local name="$1" revision="$2" url="$3" checkout="$TOOLS/$1"
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || die "catalog row for $name needs a full commit id"
    if [[ "$name" == agent-kit && -n "${BOOTSTRAP_AGENT_KIT:-}" ]]; then
        [[ -f "$BOOTSTRAP_AGENT_KIT/package.json" ]] || die "BOOTSTRAP_AGENT_KIT is not an agent-kit checkout"
        rm -rf "$checkout" && link_private "$BOOTSTRAP_AGENT_KIT" "$checkout"
        return
    fi
    if [[ -L "$checkout" ]]; then rm -f "$checkout"; fi
    if [[ -d "$checkout/.git" && "$(git -C "$checkout" rev-parse HEAD)" == "$revision" ]]; then return 0; fi
    [[ "$OFFLINE" == 0 ]] || { warn "$name is not checked out at the pinned commit; run install.sh"; return 1; }
    if [[ ! -d "$checkout/.git" ]]; then rm -rf "$checkout" && git clone --quiet "$url" "$checkout" || return 1; fi
    git -C "$checkout" fetch --quiet origin "$revision" &&
        git -C "$checkout" -c advice.detachedHead=false checkout --quiet --detach "$revision"
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
    local name="$1" rows version sha source bins packages='' bin missing
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
        # shellcheck disable=SC2086 # package names are single catalog words
        package_install $packages || return 1
        hash -r
    fi

    while IFS=$'\t' read -r _ _ version _ sha source bins; do
        case "$source" in
            pkg:*) ;;
            https://*) install_download "$name" "$version" "$source" "$sha" "$bins" ;;
            npm:*) bun install --global --exact "${source#npm:}@$version" >/dev/null ;;
            git:*) install_git "$name" "$version" "${source#git:}" ;;
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

# Agents discover every entry in a skill directory, so a skill link never moves an existing entry aside
# there: one bootstrap does not own is kept, and stale links into a bootstrap root are replaced.
link_skill() {
    local source="$1" target="$2"
    if [[ -L "$target" && "$(readlink "$target")" == "$ROOT/"* ]] && ! recorded link "$target"; then rm -f "$target"; fi
    if [[ ( -e "$target" || -L "$target" ) ]] && ! recorded link "$target"; then
        warn "keeping existing skill $target"
        return 0
    fi
    if [[ "$target" == "$ROOT"/* ]]; then link_private "$source" "$target"; else link "$source" "$target"; fi
}

# Links inside the root need no record; anything outside it (an existing ~/.codex or ~/.claude) does.
place() {
    if [[ "$2" == "$ROOT"/* ]]; then link_private "$1" "$2"; else link "$1" "$2"; fi
}

# Renders BASE merged with OVERLAY into TARGET, with @AGENT_KIT@ replaced by the agent-kit checkout.
# Agents rewrite their settings at runtime (model choice, packages), so TARGET is replaced only when
# the rendering itself changed; the replaced copy is kept as .bak.
render_config() {
    local base="$1" overlay="$2" target="$3" stamp
    stamp="$(dirname "$target")/.$(basename "$target").rendered"
    if [[ "$target" != "$ROOT"/* ]]; then own "$target" "$stamp" "$target.bak"; fi
    node "$REPO/bin/merge-json.mjs" "$base" "$overlay" "@AGENT_KIT@=$TOOLS/agent-kit" >"$ROOT/tmp/render" ||
        die "could not render $target; a Node-compatible runtime is required"
    if [[ ! -f "$target" ]] || ! cmp -s "$ROOT/tmp/render" "$stamp"; then
        if [[ -f "$target" ]]; then cp "$target" "$target.bak"; fi
        (umask 077 && cp "$ROOT/tmp/render" "$target" && cp "$ROOT/tmp/render" "$stamp")
    fi
}

ensure_agent_kit() { install_name agent-kit; }

# Pi state lives in the private root; only its router configuration sits in XDG config. Extensions,
# skills, the prompt, and the theme load from agent-kit as a local Pi package.
step_pi() {
    local agent="$PRIVATE/pi/agent" kit="$TOOLS/agent-kit" directory file source
    ensure_agent_kit || return 1
    (umask 077 && mkdir -p "$PRIVATE/pi/sessions" "$agent/extensions/subagent" "$agent/agents") || return 1
    own "$CONFIG_HOME/pi"
    link_private "$ROOT/repo/bin/pi" "$TOOLS/bin/pi" && link_private "$ROOT/repo/bin/pi-workspace" "$TOOLS/bin/pi-workspace" &&
        link_private "$ROOT/repo/bin/pi-workspace" "$TOOLS/bin/piw" || return 1
    for file in web-search profile-router strategy-router; do
        link "$ROOT/repo/pi/$file.json" "$CONFIG_HOME/pi/$file.json" || return 1
    done
    link_private "$kit/pi/AGENTS.md" "$agent/AGENTS.md" && link_private "$kit/pi/WORKTREE_STREAMS.md" "$agent/WORKTREE_STREAMS.md" &&
        link_private "$ROOT/repo/pi/subagent-config.json" "$agent/extensions/subagent/config.json" || return 1
    # Earlier layouts linked resources one by one; any link into a bootstrap root is replaced here.
    for directory in extensions skills prompts themes agents; do
        mkdir -p "$agent/$directory"
        for file in "$agent/$directory"/*; do
            if [[ -L "$file" && "$(readlink "$file")" == "$ROOT/"* ]]; then rm -f "$file"; fi
        done
    done
    for source in "$REPO/pi/agents"/*.md; do
        link_private "$ROOT/repo/pi/agents/${source##*/}" "$agent/agents/${source##*/}" || return 1
    done
    for file in settings models; do
        render_config "$REPO/pi/$file.json" "$CONFIG_HOME/bootstrap/pi-$file.json" "$agent/$file.json" || return 1
    done
    [[ "$OFFLINE" == 0 ]] || return 0
    if command -v herdr >/dev/null; then herdr integration install pi >/dev/null || return 1; fi
    while IFS= read -r source; do
        if [[ "$source" != /* ]]; then pi install "$source" >/dev/null || { warn "Pi package failed: $source"; return 1; }; fi
    done < <(node -e 'for (const p of require(process.argv[1]).packages ?? []) console.log(typeof p === "string" ? p : p.source)' "$agent/settings.json")
}

step_codex() {
    local kit="$TOOLS/agent-kit" name file
    ensure_agent_kit || return 1
    link_private "$ROOT/repo/bin/codex" "$TOOLS/bin/codex" || return 1
    if [[ "$CODEX_HOME" != "$ROOT"/* ]]; then make_dirs "$CODEX_HOME"; else mkdir -p "$CODEX_HOME"; fi
    for file in AGENTS.md native-tools.md; do place "$kit/codex/$file" "$CODEX_HOME/$file" || return 1; done
    if [[ ! -e "$CODEX_HOME/config.toml" ]]; then
        own "$CODEX_HOME/config.toml"
        cp "$REPO/codex/config.toml" "$CODEX_HOME/config.toml" || return 1
    fi
    # Codex discovers skills in the shared agents directory, outside the private root.
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then link_skill "$kit/skills/$name" "$HOME/.agents/skills/$name" || return 1; fi
    done <"$kit/codex/skills.txt"
}

# Claude Code's configuration directory defaults to the private root (see shell/env.sh).
step_claude() {
    local kit="$TOOLS/agent-kit" entry home="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    ensure_agent_kit || return 1
    # Claude Code keeps per-project logs in the platform cache, which CLAUDE_CONFIG_DIR does not move.
    own "$CACHE_HOME/claude-cli-nodejs" "$HOME/Library/Caches/claude-cli-nodejs"
    if [[ "$home" != "$ROOT"/* ]]; then make_dirs "$home/skills"; else (umask 077 && mkdir -p "$home/skills"); fi
    place "$kit/claude/CLAUDE.md" "$home/CLAUDE.md" || return 1
    while IFS= read -r entry; do
        if [[ -n "$entry" ]]; then link_skill "$kit/$entry" "$home/skills/${entry##*/}" || return 1; fi
    done <"$kit/claude/skills.txt"
    # Claude Code discovers the Mod's plugin manifest under its skills directory.
    link_skill "$kit/claude/mods/trial-tools" "$home/skills/trial-tools" || return 1
    render_config "$REPO/claude/settings.json" "$CONFIG_HOME/bootstrap/claude-settings.json" "$home/settings.json"
}

step_herdr() {
    own "$CONFIG_HOME/herdr"
    link "$ROOT/repo/config/herdr.toml" "$CONFIG_HOME/herdr/config.toml" || return 1
    if [[ "$OFFLINE" == 0 ]] && command -v pi >/dev/null; then herdr integration install pi >/dev/null || return 1; fi
}

step_zsh() {
    mkdir -p "$PRIVATE/zsh" &&
        add_block "$HOME/.zshenv" env bottom "if [ -r \"$ROOT/repo/shell/env.sh\" ]; then . \"$ROOT/repo/shell/env.sh\"; fi" &&
        add_block "$HOME/.zshrc" interactive bottom "if [ -r \"$ROOT/repo/shell/zshrc\" ]; then . \"$ROOT/repo/shell/zshrc\"; fi"
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
    # Guarded so a leftover block cannot break a shell once the root is gone.
    add_block "$HOME/.bashrc" env top "if [ -r \"$ROOT/repo/shell/env.sh\" ]; then . \"$ROOT/repo/shell/env.sh\"; fi"
    add_block "$HOME/.bashrc" interactive bottom "if [ -r \"$ROOT/repo/shell/bashrc\" ]; then . \"$ROOT/repo/shell/bashrc\"; fi"
    add_block "$login" login bottom "if [ -r \"$ROOT/repo/shell/env.sh\" ]; then . \"$ROOT/repo/shell/env.sh\"; fi
case \$- in *i*) if [ -r \"$ROOT/repo/shell/bashrc\" ]; then . \"$ROOT/repo/shell/bashrc\"; fi ;; esac"
    add_block "$HOME/.gitconfig" git bottom "[include]
	path = $ROOT/repo/config/gitconfig"
}

configure_apps() {
    # Go's telemetry directory cannot be relocated; it is claimed only when it does not exist yet.
    own "$CACHE_HOME/helix" "$STATE_HOME/gh" "$CACHE_HOME/gh" "$CONFIG_HOME/go/telemetry" "$HOME/Library/Application Support/go/telemetry"
    mkdir -p "$PRIVATE/gh"
    link "$ROOT/repo/config/gitignore" "$CONFIG_HOME/git/ignore"
    link "$ROOT/repo/config/helix" "$CONFIG_HOME/helix"
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
    # Uninstall deletes the root, so it must never be HOME, above it, or someone else's directory.
    [[ "${HOME%/}/" != "${ROOT%/}/"* ]] || die "BOOTSTRAP_ROOT cannot be HOME or a directory containing it"
    if [[ -d "$ROOT" && ! -f "$STATE" && ! -d "$TOOLS" && ! -d "$PRIVATE" ]] && [[ -n "$(ls -A "$ROOT")" ]]; then
        die "$ROOT already holds other files; choose an empty or new BOOTSTRAP_ROOT"
    fi
    for command in git curl tar gzip awk; do command -v "$command" >/dev/null || die "missing prerequisite: $command"; done
    command -v sha256sum >/dev/null || command -v shasum >/dev/null || die "missing prerequisite: sha256sum or shasum"
    if [[ "$PLATFORM" == linux-* ]] && ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then die "Linux hosts need glibc"; fi
}

# Creates the root, takes the lock, and points ROOT/repo at this checkout.
prepare_root() {
    local root_parents path
    preflight
    root_parents="$(absent_dirs "$(dirname "$ROOT")")"
    acquire_lock
    mkdir -p "$TOOLS/bin" "$ROOT/tmp"
    (umask 077 && mkdir -p "$PRIVATE")
    chmod 0700 "$PRIVATE"
    touch "$STATE"
    while IFS= read -r path; do
        if [[ -n "$path" ]]; then record dir "$path"; fi
    done <<<"$root_parents"
    ln -sfn "$REPO" "$ROOT/repo"
    load_environment
    record_package_changes
}

# Relinks configuration without downloading or installing anything.
cmd_link() {
    local group name
    prepare_root
    configure_shell
    configure_apps
    OFFLINE=1
    while IFS=$'\t' read -r _ group name; do
        case "$name" in
            pi|codex|claude|herdr|zsh|tmux) "step_$name" - || FAILURES="$FAILURES $name" ;;
            *) ;;
        esac
    done < <(awk -F '\t' '$1 == "select"' "$STATE")
    [[ -z "$FAILURES" ]] || die "configuration incomplete:$FAILURES"
    info "configuration linked"
}

install_selection() {
    if install_name "$2"; then record select "$1" "$2"; else FAILURES="$FAILURES $2"; fi
}

cmd_install() {
    local group='' name requested=''
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
    prepare_root

    for name in $(core_names); do
        if install_name "$name"; then :; elif [[ $? == 2 ]]; then warn "continuing without $name"; else FAILURES="$FAILURES $name"; fi
        # Bun is the only JavaScript runtime; this covers `#!/usr/bin/env node` entrypoints.
        if [[ "$name" == bun ]]; then link_private "$ROOT/repo/bin/node" "$TOOLS/bin/node"; fi
    done
    [[ -z "$FAILURES" ]] || die "core tools failed:$FAILURES"
    configure_shell
    configure_apps

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
    if grep -qx "select"$'\t'"tools"$'\t'"pi" "$STATE"; then
        version="$(awk -F '\t' '$1 == "pi" { print $3; exit }' "$CATALOG")"
        if [[ "$(pi --version 2>/dev/null)" != "$version" ]]; then printf 'wrong    pi version, want %s\n' "$version"; failed=1; fi
    fi
    return "$failed"
}

# Removes packages first, then undoes recorded changes, then deletes the root. State is kept until
# every step succeeds, so a failed or interrupted uninstall can simply be run again.
cmd_uninstall() {
    local confirmed="${1:-}" kind path value packages='' installed host user failed=0
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
    acquire_lock
    load_environment
    record_package_changes

    # Sign every account out first so tokens kept in an OS keyring are deleted, not orphaned.
    if command -v gh >/dev/null && [[ -d "$GH_CONFIG_DIR" ]]; then
        while IFS=$'\t' read -r host user; do
            [[ -n "$host" && -n "$user" ]] || continue
            gh auth logout --hostname "$host" --user "$user" </dev/null >/dev/null 2>&1 || warn "could not sign gh out of $user on $host"
        done < <(gh auth status --json hosts --jq '.hosts | to_entries[] | .key as $host | .value[] | [$host, .login] | @tsv' </dev/null 2>/dev/null)
    fi
    # Claude Code names its macOS keychain items after a hash of a custom config directory, so only
    # bootstrap's own login is removed, never a default ~/.claude one.
    if [[ "$(uname -s)" == Darwin && "${CLAUDE_CONFIG_DIR:-}" == "$ROOT"/* ]]; then
        value="$(printf '%s' "$CLAUDE_CONFIG_DIR" | sha256 /dev/stdin | cut -c1-8)"
        for host in "Claude Code-credentials-$value" "Claude Code-$value"; do
            security delete-generic-password -s "$host" >/dev/null 2>&1 || true
        done
    fi
    if command -v herdr >/dev/null && [[ -S "$CONFIG_HOME/herdr/herdr.sock" ]]; then herdr server stop || true; fi
    for path in "$TMUX_TMPDIR"/tmux-*/*; do
        if [[ -S "$path" ]] && command -v tmux >/dev/null; then tmux -S "$path" kill-server 2>/dev/null || true; fi
    done

    if grep -q '^package' "$STATE"; then
        installed="$(package_list)"
        while IFS=$'\t' read -r kind value path; do
            if [[ "$kind" == package ]] && grep -qxF -- "$path" <<<"$installed"; then packages="$packages $path"; fi
        done <"$STATE"
    fi
    if [[ -n "$packages" ]]; then
        info "removing system packages:$packages"
        # shellcheck disable=SC2086 # package names are single catalog words
        { can_manage_packages && package_remove $packages; } ||
            die "could not remove:$packages. Nothing else was changed; rerun uninstall where these can be removed"
    fi

    while IFS=$'\t' read -r kind path value; do
        case "$kind" in
            block)
                if [[ -f "$path" ]]; then
                    if strip_blocks <"$path" >"$ROOT/tmp-block"; then
                        cat "$ROOT/tmp-block" >"$path" || failed=1
                        if [[ "$value" == created && ! -s "$path" ]]; then rm -f "$path" || failed=1; fi
                    else
                        warn "$path has an unterminated bootstrap block; remove it by hand"; failed=1
                    fi
                fi ;;
            link)
                if [[ -L "$path" && "$(readlink "$path")" == "$ROOT/"* ]]; then rm -f "$path" || failed=1; fi
                if [[ "$value" != - && ( -e "$value" || -L "$value" ) && ! -e "$path" && ! -L "$path" ]]; then mv "$value" "$path" || failed=1; fi ;;
            own) rm -rf "$path" || failed=1 ;;
            dir|package|select) ;;
            *) warn "ignoring unknown state record: $kind" ;;
        esac
    done < <(awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$STATE")
    [[ "$failed" == 0 ]] || die "some changes could not be undone; $STATE is kept, so fix the cause and rerun uninstall"

    # Everything but the state file goes first; the state file goes last so a failure here
    # still leaves a rerunnable uninstall.
    chmod -R u+w "$ROOT" 2>/dev/null || true
    for path in "$ROOT"/* "$ROOT"/.[!.]*; do
        if [[ ( -e "$path" || -L "$path" ) && "$path" != "$STATE" ]]; then rm -rf "$path" || failed=1; fi
    done
    [[ "$failed" == 0 ]] || die "could not delete everything in $ROOT; rerun uninstall"
    installed="$(awk -F '\t' '$1 == "dir" { print $2 }' "$STATE" | awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }')"
    trap - EXIT
    rm -f "$STATE"
    rmdir "$ROOT"
    while IFS= read -r path; do
        if [[ -n "$path" ]]; then rmdir "$path" 2>/dev/null || true; fi
    done <<<"$installed"
    info "uninstalled. Remove this checkout with: rm -rf \"$REPO\""
}

case "${1:-}" in
    doctor) shift; [[ $# -eq 0 ]] || die "doctor takes no arguments"; cmd_doctor ;;
    link) shift; [[ $# -eq 0 ]] || die "link takes no arguments"; cmd_link ;;
    uninstall) shift; cmd_uninstall "$@" ;;
    ''|-*) cmd_install "$@" ;;
    *) usage >&2; exit 2 ;;
esac
