#!/usr/bin/env bash
# Native package catalog and bounded package-manager transactions.

native_backend() {
    if [[ -n "${BOOTSTRAP_PACKAGE_BACKEND:-}" ]]; then printf '%s\n' "$BOOTSTRAP_PACKAGE_BACKEND"; return; fi
    case "$(uname -s)" in
        Darwin) command -v brew >/dev/null || { warn 'Homebrew is required on macOS'; return 1; }; printf 'brew\n' ;;
        Linux)
            if command -v apt-get >/dev/null; then printf 'apt\n'
            elif command -v dnf >/dev/null; then printf 'dnf\n'
            elif command -v pacman >/dev/null; then printf 'pacman\n'
            else warn 'Supported Linux package manager not found (apt, dnf, pacman)'; return 1; fi ;;
        *) warn 'Supported hosts are Linux and Apple Silicon macOS'; return 1 ;;
    esac
}

catalog_query() {
    node - "$DOTFILES_DIR/packages/catalog.json" "$@" <<'NODE'
const fs=require('node:fs'); const [path, operation, ...args]=process.argv.slice(2); const c=JSON.parse(fs.readFileSync(path));
if(c.schemaVersion!==1) throw Error('unsupported catalog');
if(operation==='core') console.log(c.core.join('\n'));
else if(operation==='group'){ const value=c[args[0]]?.[args[1]]; if(value===undefined) process.exit(2); console.log((Array.isArray(value)?value:value.packages).join('\n')); }
else if(operation==='package'){ const value=c.packages[args[0]]; if(!value) process.exit(2); console.log(`${value.executable}\t${value[args[1]]??''}`); }
else if(operation==='lsp'){ const value=c.lsp[args[0]]; if(!value) process.exit(2); console.log(JSON.stringify(value)); }
else process.exit(2);
NODE
}

# Inventory queries make absence distinct from a failed package database query.
# Return 0 for present, 1 for absent, and 2 for query/contract errors.
native_package_present() {
    local output
    case "$1" in
        apt)
            output="$(dpkg-query -W -f='${binary:Package}\t${Status}\n')" || return 2
            printf '%s\n' "$output" | awk -F '\t' -v name="$2" '{sub(/:[^:]+$/,"",$1);if($1==name && $2=="install ok installed")found=1} END{exit !found}' ;;
        dnf) output="$(rpm -qa --qf '%{NAME}\n')" || return 2; [[ "$output" == "$2" || $'\n'"$output"$'\n' == *$'\n'"$2"$'\n'* ]] ;;
        pacman) output="$(pacman -Qq)" || return 2; [[ $'\n'"$output"$'\n' == *$'\n'"$2"$'\n'* ]] ;;
        brew) output="$(brew list --formula --full-name -1)" || return 2; [[ $'\n'"$output"$'\n' == *$'\n'"$2"$'\n'* ]] ;;
        *) return 2 ;;
    esac
}

native_package_available() {
    case "$1" in
        apt) apt-cache show "$2" >/dev/null 2>&1 ;;
        dnf) dnf --quiet info "$2" >/dev/null 2>&1 ;;
        pacman) pacman -Si "$2" >/dev/null 2>&1 ;;
        brew) brew info --json=v2 "$2" >/dev/null 2>&1 ;;
    esac
}

native_package_version() {
    case "$1" in
        apt) dpkg-query -W -f='${Version}' "$2" 2>/dev/null || printf absent ;;
        dnf) rpm -q --qf '%{VERSION}-%{RELEASE}' "$2" 2>/dev/null || printf absent ;;
        pacman) pacman -Q "$2" 2>/dev/null | awk '{print $2}' || printf absent ;;
        brew) brew list --versions "$2" 2>/dev/null | awk '{print $2}' || printf absent ;;
    esac
}

native_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"; return; fi
    command -v sudo >/dev/null || { warn "Package installation requires administrator approval: $*"; return 1; }
    sudo -- "$@"
}

native_preview_install() {
    case "$1" in
        apt) native_privileged apt-get --simulate install --no-install-recommends "${@:2}" ;;
        dnf) native_privileged dnf --assumeno --setopt=install_weak_deps=False install "${@:2}" || [[ $? -eq 1 ]] ;;
        pacman) pacman -Sp --needed -- "${@:2}" >/dev/null ;;
        brew) HOMEBREW_NO_AUTO_UPDATE=1 brew info --json=v2 "${@:2}" >/dev/null ;;
    esac
}

native_install_names() {
    local backend="$1"; shift
    [[ $# -gt 0 ]] || return 0
    native_preview_install "$backend" "$@" || { warn 'Native package transaction preview failed'; return 1; }
    case "$backend" in
        apt) native_privileged apt-get install --yes --no-install-recommends "$@" ;;
        dnf) native_privileged dnf install --assumeyes --setopt=install_weak_deps=False "$@" ;;
        pacman) native_privileged pacman -S --needed --noconfirm -- "$@" ;;
        brew) HOMEBREW_NO_AUTO_UPDATE=1 brew install "$@" ;;
    esac
}

native_apt_install_plan() {
    local output
    output="$(native_privileged apt-get --simulate install --no-install-recommends "$@")" || return 1
    printf '%s\n' "$output" | awk '$1 == "Inst" { sub(/:.*/, "", $2); if (!seen[$2]++) print $2 }'
}

install_native_keys() {
    local backend key metadata executable package existed version prefix planned planned_package planned_output
    local pending_records=()
    backend="$(native_backend)" || return 1
    local install_names=() pending=()
    for key in "$@"; do
        metadata="$(catalog_query package "$key" "$backend")" || { warn "Unknown package catalog key: $key"; return 2; }
        IFS=$'\t' read -r executable package <<<"$metadata"
        if command -v "$executable" >/dev/null 2>&1; then continue; fi
        if [[ -n "$package" ]]; then
            native_package_available "$backend" "$package" || { pending+=("$key"); continue; }
        else
            pending+=("$key")
            continue
        fi
        existed=0; if native_package_present "$backend" "$package"; then existed=1; else [[ $? == 1 ]] || return 1; fi
        version="$(native_package_version "$backend" "$package")"
        node "$DOTFILES_DIR/scripts/state-helper.mjs" package "$backend" "$package" "$existed" "$version" pending || return 1
        pending_records+=("$package"$'\t'"$existed"$'\t'"$version")
        install_names+=("$package")
    done
    if [[ "$backend" == apt && ${#install_names[@]} -gt 0 ]]; then
        planned_output="$(native_apt_install_plan "${install_names[@]}")" || return 1
        while IFS= read -r planned; do
            [[ -n "$planned" ]] || continue
            planned_package="${planned%%:*}"
            local already_recorded=0 plan_record plan_package
            for plan_record in "${pending_records[@]}"; do
                IFS=$'\t' read -r plan_package _ _ <<<"$plan_record"
                [[ "$plan_package" == "$planned_package" ]] || continue
                already_recorded=1
                break
            done
            [[ "$already_recorded" -eq 1 ]] && continue
            existed=0
            if native_package_present "$backend" "$planned_package"; then
                existed=1
            else
                [[ $? == 1 ]] || return 1
            fi
            version="$(native_package_version "$backend" "$planned_package")"
            node "$DOTFILES_DIR/scripts/state-helper.mjs" package "$backend" "$planned_package" "$existed" "$version" pending || return 1
            pending_records+=("$planned_package"$'\t'"$existed"$'\t'"$version")
        done <<<"$planned_output"
    fi
    [[ ${#install_names[@]} -eq 0 ]] || native_install_names "$backend" "${install_names[@]}" || return 1
    local record
    for record in "${pending_records[@]}"; do IFS=$'\t' read -r package existed version <<<"$record"; node "$DOTFILES_DIR/scripts/state-helper.mjs" package "$backend" "$package" "$existed" "$version" installed || return 1; done
    for key in "${pending[@]}"; do install_upstream_tool "$key" || return 1; done
    if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then link_managed_file "$(command -v fdfind)" "$DOTFILES_BARE_ROOT/bin/fd" || return 1; fi
    if ! command -v bat >/dev/null && command -v batcat >/dev/null; then link_managed_file "$(command -v batcat)" "$DOTFILES_BARE_ROOT/bin/bat" || return 1; fi
    if [[ "$backend" == brew ]]; then
        for key in "$@"; do
            if [[ "$key" == python ]] && ! command -v python3 >/dev/null; then
                prefix="$(brew --prefix python@3.13)" || return 1
                [[ -x "$prefix/libexec/bin/python3" ]] || return 1
                link_managed_file "$prefix/libexec/bin/python3" "$DOTFILES_BARE_ROOT/bin/python3" || return 1
            fi
        done
    fi
    hash -r
    for key in "$@"; do
        metadata="$(catalog_query package "$key" "$backend")" || return 1
        executable="${metadata%%$'\t'*}"
        command -v "$executable" >/dev/null 2>&1 || { warn "Required executable unavailable after installation: $executable"; return 1; }
    done
}

install_upstream_tool() {
    local key="$1" platform archive url sha destination version executable actual_version
    local bare_stage="${bare_stage:-}"
    [[ -n "$bare_stage" && -d "$bare_stage" ]] || { warn 'Upstream install staging directory is unavailable'; return 1; }
    platform="$(bare_platform)" || return 1
    if [[ "${BOOTSTRAP_NODE_STAGING_ONLY:-0}" != 1 ]]; then mkdir -p "$DOTFILES_BARE_ROOT/bin" "$DOTFILES_BARE_ROOT/tools" || return 1; fi
    if [[ "$key" == python ]]; then
        uv python install 3.13 || return 1
        executable="$(uv python find --managed-python 3.13)" || return 1
        [[ "$executable" == "$UV_PYTHON_INSTALL_DIR/"* && -x "$executable" ]] || return 1
        "$executable" -c 'import sys; assert sys.version_info.major == 3' || return 1
        link_managed_file "$executable" "$DOTFILES_BARE_ROOT/bin/python3" || return 1
        link_managed_file "$executable" "$DOTFILES_BARE_ROOT/bin/python"
        return
    fi
    case "$key/$platform" in
        node/linux-64) archive=node-v24.18.0-linux-x64.tar.xz; sha=55aa7153f9d88f28d765fcdad5ae6945b5c0f98a36881703817e4c450fa76742 ;;
        node/linux-aarch64) archive=node-v24.18.0-linux-arm64.tar.xz; sha=58c9520501f6ae2b52d5b210444e24b9d0c029a58c5011b797bc1fe7105886f6 ;;
        node/osx-arm64) archive=node-v24.18.0-darwin-arm64.tar.xz; sha=4477b9f78efb77744cf5eb57a0e9594dba66466b38b4e93fa9f35cb907a095a6 ;;
        tree-sitter/linux-64) archive=tree-sitter-linux-x64.gz; sha=4367a46bc8abbb8328d6efbeb26e86807af0a3a7e462548a3924f87289ee1e9c ;;
        tree-sitter/linux-aarch64) archive=tree-sitter-linux-arm64.gz; sha=86a317732cc597e1576f8b11b4853f78fedd2a3c756923e33f323667dee6b4be ;;
        tree-sitter/osx-arm64) archive=tree-sitter-macos-arm64.gz; sha=24162119aca35a160a2752a4457b17f3c47f7b2895ab63002c66b8dfd1bb41d1 ;;
        neovim/linux-64) archive=nvim-linux-x86_64.tar.gz; sha=bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875 ;;
        neovim/linux-aarch64) archive=nvim-linux-arm64.tar.gz; sha=1aa5ca085249580ae0f91eb14f27ec0919773ff2d99a163d03f3d6c21ac29725 ;;
        neovim/osx-arm64) archive=nvim-macos-arm64.tar.gz; sha=65fb000099e47ca1b762584c484cc833f40e30851a0ec450d4174e16317c1f9b ;;
        delta/linux-64) archive=delta-0.18.2-x86_64-unknown-linux-gnu.tar.gz; sha=99607c43238e11a77fe90a914d8c2d64961aff84b60b8186c1b5691b39955b0f ;;
        delta/linux-aarch64) archive=delta-0.18.2-aarch64-unknown-linux-gnu.tar.gz; sha=adf7674086daa4582f598f74ce9caa6b70c1ba8f4a57d2911499b37826b014f9 ;;
        delta/osx-arm64) archive=delta-0.18.2-aarch64-apple-darwin.tar.gz; sha=6ba38dce9f91ee1b9a24aa4aede1db7195258fe176c3f8276ae2d4457d8170a0 ;;
        uv/linux-64) archive=uv-x86_64-unknown-linux-gnu.tar.gz; sha=745765a3b6e360ad76743599ae5c42e9278c7edf8bbff9fc76d05bf2623a04dd ;;
        uv/linux-aarch64) archive=uv-aarch64-unknown-linux-gnu.tar.gz; sha=2eaa5d94f5db7b3a1a092156b9420459e42ab0217d917fe74a876309cef9b5e9 ;;
        uv/osx-arm64) archive=uv-aarch64-apple-darwin.tar.gz; sha=7e6ddb9316acc00f2296c82ff4d99977870ee34b2f0ddcae9444d714db9364ed ;;
        ruff/linux-64) archive=ruff-x86_64-unknown-linux-gnu.tar.gz; sha=73894c7b7c9a53fd66ed715eb3a1ec65077f316328e377057a98bdb7fcba0326 ;;
        ruff/linux-aarch64) archive=ruff-aarch64-unknown-linux-gnu.tar.gz; sha=1e06b11127c28387c8066da4ce6a617a84a359591be09dbf581fbb0c3e006239 ;;
        ruff/osx-arm64) archive=ruff-aarch64-apple-darwin.tar.gz; sha=80221a5e0b1ae29262a74496f2ad1380c1ab52b3edd8cee13ec76d8acff406ca ;;
        zig/linux-64) archive=zig-x86_64-linux-0.16.0.tar.xz; sha=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 ;;
        zig/linux-aarch64) archive=zig-aarch64-linux-0.16.0.tar.xz; sha=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17 ;;
        zig/osx-arm64) archive=zig-aarch64-macos-0.16.0.tar.xz; sha=b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489 ;;
        starship/linux-64) archive=starship-x86_64-unknown-linux-gnu.tar.gz; sha=321f0dd7af8340a5f2e6a8fec6538a04f617486f9ec70d878f91c09cd8deef22 ;;
        starship/linux-aarch64) archive=starship-aarch64-unknown-linux-musl.tar.gz; sha=dc30189378d2f2e287384e8a692d3f95ad1df64cf0e8c36aa9201516028aed6b ;;
        starship/osx-arm64) archive=starship-aarch64-apple-darwin.tar.gz; sha=c40b27b11f580411e068f2fa6c1be7830a387c0bc47a94d1d37f32b054c5361d ;;
        just/linux-64) archive=just-1.58.0-x86_64-unknown-linux-musl.tar.gz; sha=4a5cc2f53e6f0f8c59092a6cc38291eb729d46a7dd95d3ae582008881b84931d ;;
        just/linux-aarch64) archive=just-1.58.0-aarch64-unknown-linux-musl.tar.gz; sha=748237128c4c40cbdabc65e841d05ceba13cc23a91eaba395495894c1d9764df ;;
        just/osx-arm64) archive=just-1.58.0-aarch64-apple-darwin.tar.gz; sha=50ae3e996c974a0bf32ea7d10f495070df33f1b43e0616b2769e3d4821ed8f48 ;;
        bun/linux-64) archive=bun-linux-x64-baseline-1.4.0.tgz; sha=e8d1fcb859272945fdb9ed1de1fb787ab8ff4f85c5ad15a0a7134b76b63ceaa5 ;;
        bun/linux-aarch64) archive=bun-linux-aarch64-1.4.0.tgz; sha=39ea1a8ee3bf4c96143aa3ffc9a259b3cce5b7d0a4b1fe5ba3f741643d6cafbf ;;
        bun/osx-arm64) archive=bun-darwin-aarch64-1.4.0.tgz; sha=5aaf52d21001a538a995b01e85847d8d353a048f017d40e87795d50e86911ce4 ;;
        eza/linux-64) archive=eza_x86_64-unknown-linux-musl.tar.gz; sha=e06eebab74b73d6b7d51a796a353824b001bea82df077706382e100815d28904 ;;
        eza/linux-aarch64) archive=eza_aarch64-unknown-linux-gnu.tar.gz; sha=40b87ae8628aa2ff0f0d2dc24ab52f689631366385c3da630bae745671fd71ec ;;
        *) warn "No verified official artifact for $key on $platform"; return 1 ;;
    esac
    case "$key" in
        bun) version=1.4.0; url="https://registry.npmjs.org/@oven/${archive%-1.4.0.tgz}/-/$archive" ;;
        eza) version=0.23.5; url="https://github.com/eza-community/eza/releases/download/v$version/$archive" ;;
        node) version=24.18.0; url="https://nodejs.org/dist/v$version/$archive" ;;
        tree-sitter) version=0.26.7; url="https://github.com/tree-sitter/tree-sitter/releases/download/v$version/$archive" ;;
        neovim) version=0.12.5; url="https://github.com/neovim/neovim/releases/download/v$version/$archive" ;;
        delta) version=0.18.2; url="https://github.com/dandavison/delta/releases/download/$version/$archive" ;;
        uv) version=0.12.13; url="https://github.com/astral-sh/uv/releases/download/$version/$archive" ;;
        ruff) version=0.16.7; url="https://github.com/astral-sh/ruff/releases/download/$version/$archive" ;;
        zig) version=0.16.0; url="https://ziglang.org/download/$version/$archive" ;;
        starship) version=1.26.0; url="https://github.com/starship/starship/releases/download/v$version/$archive" ;;
        just) version=1.58.0; url="https://github.com/casey/just/releases/download/$version/$archive" ;;
    esac
    destination="$DOTFILES_BARE_ROOT/tools/$key-$version"
    if [[ "${BOOTSTRAP_NODE_STAGING_ONLY:-0}" == 1 ]]; then
        [[ "$key" == node ]] || return 2
        destination="$bare_stage/bootstrap-node"
    fi
    [[ -d "$destination" || -x "$destination" ]] || {
        download_verified "$url" "$sha" "$bare_stage/$archive" || return 1
        case "$key" in
            tree-sitter) gzip -dc "$bare_stage/$archive" >"$bare_stage/tree-sitter"; chmod 0755 "$bare_stage/tree-sitter"; mv "$bare_stage/tree-sitter" "$destination" ;;
            node) mkdir "$bare_stage/node"; tar -xJf "$bare_stage/$archive" -C "$bare_stage/node" --strip-components=1; mv "$bare_stage/node" "$destination" ;;
            neovim) mkdir "$bare_stage/neovim"; tar -xzf "$bare_stage/$archive" -C "$bare_stage/neovim" --strip-components=1; mv "$bare_stage/neovim" "$destination" ;;
            bun) mkdir "$bare_stage/bun"; tar -xzf "$bare_stage/$archive" -C "$bare_stage/bun" --strip-components=1 || return 1; mv "$bare_stage/bun" "$destination" ;;
            eza) mkdir "$bare_stage/eza"; tar -xzf "$bare_stage/$archive" -C "$bare_stage/eza" || return 1; mv "$bare_stage/eza" "$destination" ;;
            delta|uv|ruff) mkdir "$bare_stage/$key"; tar -xzf "$bare_stage/$archive" -C "$bare_stage/$key" --strip-components=1; mv "$bare_stage/$key" "$destination" ;;
            starship|just) mkdir "$bare_stage/$key"; tar -xzf "$bare_stage/$archive" -C "$bare_stage/$key"; mv "$bare_stage/$key" "$destination" ;;
            zig) mkdir "$bare_stage/zig"; tar -xJf "$bare_stage/$archive" -C "$bare_stage/zig" --strip-components=1; mv "$bare_stage/zig" "$destination" ;;
        esac
    }
    if [[ "$key" == node ]]; then
        actual_version="$("$destination/bin/node" --version)" || return 1
        version_at_least "$actual_version" 22.19.0 || return 1
    fi
    if [[ "${BOOTSTRAP_NODE_STAGING_ONLY:-0}" == 1 ]]; then
        export PATH="$destination/bin:$PATH"
        return 0
    fi
    case "$key" in
        bun)
            [[ -f "$destination/bin/bun" && ! -L "$destination/bin/bun" ]] || return 1
            actual_version="$("$destination/bin/bun" --version)" || return 1
            [[ "$actual_version" == "$version" ]] || { warn 'Official Bun binary failed verification'; return 1; }
            link_managed_file "$destination/bin/bun" "$DOTFILES_BARE_ROOT/bin/bun" ;;
        eza)
            "$destination/eza" --version || return 1
            link_managed_file "$destination/eza" "$DOTFILES_BARE_ROOT/bin/eza" ;;
        tree-sitter) link_managed_file "$destination" "$DOTFILES_BARE_ROOT/bin/tree-sitter" ;;
        node) for executable in node npm npx corepack; do [[ ! -x "$destination/bin/$executable" ]] || link_managed_file "$destination/bin/$executable" "$DOTFILES_BARE_ROOT/bin/$executable" || return 1; done ;;
        neovim) link_managed_file "$destination/bin/nvim" "$DOTFILES_BARE_ROOT/bin/nvim" ;;
        delta) link_managed_file "$destination/delta" "$DOTFILES_BARE_ROOT/bin/delta" ;;
        uv) link_managed_file "$destination/uv" "$DOTFILES_BARE_ROOT/bin/uv"; [[ ! -x "$destination/uvx" ]] || link_managed_file "$destination/uvx" "$DOTFILES_BARE_ROOT/bin/uvx" ;;
        ruff) link_managed_file "$destination/ruff" "$DOTFILES_BARE_ROOT/bin/ruff" ;;
        zig) link_managed_file "$destination/zig" "$DOTFILES_BARE_ROOT/bin/zig" ;;
        starship) link_managed_file "$destination/starship" "$DOTFILES_BARE_ROOT/bin/starship" ;;
        just) link_managed_file "$destination/just" "$DOTFILES_BARE_ROOT/bin/just" ;;
    esac
}

native_preview_remove() {
    local backend="$1" package output removed requested installed=(); shift
    for package in "$@"; do
        if native_package_present "$backend" "$package"; then installed+=("$package"); else [[ $? == 1 ]] || return 1; fi
    done
    [[ ${#installed[@]} -gt 0 ]] || return 0
    set -- "${installed[@]}"
    requested=" $* "
    case "$backend" in
        apt)
            output="$(LC_ALL=C apt-get --simulate remove "$@")" || return 1
            while read -r _ removed _; do [[ "$requested" == *" $removed "* ]] || { warn "Removal would expand to unrelated package: $removed"; return 1; }; done < <(printf '%s\n' "$output" | grep '^Remv ' || true)
            ;;
        dnf)
            # RPM queries do not create DNF logs/caches. File capabilities and
            # rich requirements are conservative: alternate providers may block.
            local provides requires
            provides="$(rpm -q --qf '[P\t%{=NAME}\t%{PROVIDENAME}\n][F\t%{=NAME}\t%{FILENAMES}\n]' "$@")" || return 1
            requires="$(rpm -qa --qf '[R\t%{=NAME}\t%{REQUIRENAME}\n]')" || return 1
            [[ -n "$provides" && ${#provides} -le 67108864 && ${#requires} -le 67108864 ]] || return 1
            printf '%s\n%s\n' "$provides" "$requires" | awk -F '\t' -v requested="$requested" '
                NF==0 {next}
                NF!=3 || $2 !~ /^[A-Za-z0-9][A-Za-z0-9+_.-]*$/ || $3=="" {bad=1;next}
                $1=="P" || $1=="F" {
                    if(index(requested," "$2" ")==0){bad=1;next}
                    provided[$3]=1; normalized=$3; gsub(/[()]/,"",normalized); provided_normalized[normalized]=1; next
                }
                $1=="R" {
                    if(index(requested," "$2" ")>0)next
                    blocked=($3 in provided)
                    if(substr($3,1,1)=="(") {
                        depth=0
                        for(i=1;i<=length($3);i++){character=substr($3,i,1);if(character=="(")depth++;if(character==")")depth--;if(depth<0)bad=1}
                        if(depth!=0 || substr($3,length($3),1)!=")")bad=1
                        expression=$3; gsub(/[()]/,"",expression); count=split(expression,tokens,/ +/)
                        for(i=1;i<=count;i++)if(tokens[i] in provided_normalized)blocked=1
                    }
                    if(blocked){print "Package has installed reverse dependency: "$2" ("$3")" >"/dev/stderr";bad=1}
                    next
                }
                {bad=1}
                END {exit bad ? 1 : 0}
            ' || { warn 'RPM dependency preview failed or found dependents'; return 1; }
            ;;
        pacman)
            output="$(pacman -R --print --print-format '%n' -- "$@")" || return 1
            while IFS= read -r removed; do [[ -z "$removed" || "$requested" == *" $removed "* ]] || { warn "Removal would expand to unrelated package: $removed"; return 1; }; done <<<"$output"
            ;;
        brew)
            for package in "$@"; do
                output="$(brew uses --installed "$package")" || return 1
                for removed in $output; do [[ "$requested" == *" $removed "* ]] || { warn "Package has installed reverse dependency: $package ($removed)"; return 1; }; done
            done
            ;;
        *) return 2 ;;
    esac
}

native_remove_names() {
    local backend="$1" package output installed=(); shift; [[ $# -gt 0 ]] || return 0
    for package in "$@"; do
        if native_package_present "$backend" "$package"; then installed+=("$package"); else [[ $? == 1 ]] || return 1; fi
    done
    [[ ${#installed[@]} -gt 0 ]] || return 0
    set -- "${installed[@]}"
    native_preview_remove "$backend" "$@" || { warn 'Package removal preview found conflicts or dependents'; return 1; }
    case "$backend" in
        apt) native_privileged dpkg --remove -- "$@" ;;
        # Exact-name RPM erase cannot cascade if another transaction adds a
        # dependent after preview. RPM dependency checks remain enabled.
        dnf) native_privileged rpm -e -- "$@" ;;
        pacman) native_privileged pacman -R --noconfirm -- "$@" ;;
        brew) brew uninstall "$@" ;;
        *) return 2 ;;
    esac || return 1
    for package in "$@"; do
        if native_package_present "$backend" "$package"; then warn "Package remains after removal: $package"; return 1; else [[ $? == 1 ]] || return 1; fi
    done
    if [[ "$backend" == apt ]]; then
        output="$(dpkg-query -W -f='${binary:Package}\t${Status}\n')" || return 1
        for package in "$@"; do
            if printf '%s\n' "$output" | awk -F '\t' -v name="$package" '{sub(/:[^:]+$/,"",$1);if($1==name && $2 ~ / config-files$/)found=1}END{exit !found}'; then
                warn "Native conffiles remain for $package; package removal does not purge modified/shared configuration"
            fi
        done
    fi
}
