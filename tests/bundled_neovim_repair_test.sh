#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"; temporary="$(cd "$temporary" && pwd -P)"
trap 'rm -rf "$temporary"' EXIT
source "$ROOT/tests/bundled_neovim_fixture.sh"
prepare_bundled_neovim_fixture "$temporary"
info() { printf '%s\n' "$*"; }; warn() { printf '%s\n' "$*" >&2; }
source "$ROOT/scripts/lib/install/neovim.sh"
config="$XDG_CONFIG_HOME/bootstrap-nvim"; data="$XDG_DATA_HOME/bootstrap-nvim"
# Deliberately preserve user formatting, an inactive lock entry, and an older selected revision.
node - "$config/lazy-lock.json" "$data/lazy/mini.ai" <<'JS'
const fs=require('node:fs'), cp=require('node:child_process');const [file,dir]=process.argv.slice(2);
const value=JSON.parse(fs.readFileSync(file));
value['mini.ai'].commit=cp.execFileSync('git',['-C',dir,'rev-parse','HEAD^'],{encoding:'utf8'}).trim();
value['user-disabled-plugin']={branch:'main',commit:'1234567890123456789012345678901234567890'};
fs.writeFileSync(file,JSON.stringify(value,null,4)+'\n\n');
JS
node - "$config/lazy-lock.json" "$data/lazy/gitsigns.nvim" <<'JS'
const fs=require('node:fs'), cp=require('node:child_process');const [file,dir]=process.argv.slice(2);
const value=JSON.parse(fs.readFileSync(file)); delete value['gitsigns.nvim'];
cp.execFileSync('git',['-C',dir,'checkout','--detach','HEAD^'],{stdio:'pipe'});
fs.writeFileSync(file,JSON.stringify(value,null,4)+'\n\n');
JS
unlocked_revision="$(git -C "$data/lazy/gitsigns.nvim" rev-parse HEAD)"
cp "$config/lazy-lock.json" "$temporary/lock"
rm -rf "$data/lazy/mini.ai"
install_neovim_parsers >"$temporary/first.log" 2>&1 || { cat "$temporary/first.log"; exit 1; }
cmp "$temporary/lock" "$config/lazy-lock.json"
expected="$(node -e 'console.log(require(process.argv[1])["mini.ai"].commit)' "$config/lazy-lock.json")"
[[ "$(git -C "$data/lazy/mini.ai" rev-parse HEAD)" == "$expected" ]]
find "$data/site/parser" -type f -exec shasum -a 256 {} \; | sort >"$temporary/parsers-before"
node -e 'const fs=require("node:fs"),p=process.argv[1];for(const n of fs.readdirSync(p).sort()){const s=fs.statSync(p+"/"+n);console.log(n,s.mtimeMs,s.ino)}' "$data/site/parser" >"$temporary/stat-before"
install_neovim_parsers >"$temporary/retry.log" 2>&1 || { cat "$temporary/retry.log"; exit 1; }
cmp "$temporary/lock" "$config/lazy-lock.json"
[[ "$(git -C "$data/lazy/gitsigns.nvim" rev-parse HEAD)" == "$unlocked_revision" ]]
find "$data/site/parser" -type f -exec shasum -a 256 {} \; | sort >"$temporary/parsers-after"
node -e 'const fs=require("node:fs"),p=process.argv[1];for(const n of fs.readdirSync(p).sort()){const s=fs.statSync(p+"/"+n);console.log(n,s.mtimeMs,s.ino)}' "$data/site/parser" >"$temporary/stat-after"
cmp "$temporary/parsers-before" "$temporary/parsers-after"
cmp "$temporary/stat-before" "$temporary/stat-after"
printf 'PASS R7 effective lock bytes and selected revisions restored, unchanged reinstall preserved parser bytes/inodes\n'
cp "$data/site/parser-info/bash.revision" "$temporary/bash.revision"
printf 'stale-revision' >"$data/site/parser-info/bash.revision"
rm "$data/site/parser/json.so"
install_neovim_parsers >"$temporary/stale.log" 2>&1 || { cat "$temporary/stale.log"; exit 1; }
cmp "$temporary/bash.revision" "$data/site/parser-info/bash.revision"
[[ -s "$data/site/parser/json.so" ]]
grep -q 'install/bash.*Compiling parser' "$temporary/stale.log"
grep -q 'install/json.*Compiling parser' "$temporary/stale.log"
printf 'PASS R9 stale Bash revision reconciled and missing JSON library rebuilt despite existing queries\n'
printf 'invalid shared library' >"$data/site/parser/bash.so"
install_neovim_parsers >"$temporary/incompatible.log" 2>&1 || { cat "$temporary/incompatible.log"; exit 1; }
cmp "$temporary/bash.revision" "$data/site/parser-info/bash.revision"
grep -q 'install/bash.*Compiling parser' "$temporary/incompatible.log"
printf 'PASS R9 unloadable Bash library repaired despite a matching revision receipt\n'
printf 'stale-revision' >"$data/site/parser-info/bash.revision"
mkdir "$temporary/bin"
printf '#!/bin/sh\nexit 81\n' >"$temporary/bin/tree-sitter"; chmod +x "$temporary/bin/tree-sitter"
if PATH="$temporary/bin:$PATH" install_neovim_parsers >"$temporary/failure.log" 2>&1; then cat "$temporary/failure.log"; exit 1; fi
grep -q 'parser revision reconciliation failed' "$temporary/failure.log"
[[ "$(cat "$data/site/parser-info/bash.revision")" == stale-revision ]]
[[ -z "$(find "$BOOTSTRAP_STATE_ROOT" -maxdepth 1 -name 'parsers.*' -print)" ]]
printf 'PASS R9 failed compiler propagates failure and removes temporary receipts\n'
# Restore readiness before exercising both ordinary startup profiles.
install_neovim_parsers >"$temporary/recovery.log" 2>&1 || { cat "$temporary/recovery.log"; exit 1; }
# install.sh owns this shell variable but does not export it to Neovim.
export -n DOTFILES_DIR
node -e 'if (Object.hasOwn(process.env, "DOTFILES_DIR")) process.exit(1)'
for profile in bare workstation; do
    printf '{"version":1,"profile":"%s"}\n' "$profile" >"$config/bootstrap-profile.json"
    BOOTSTRAP_NEOVIM_PROFILE="$profile" verify_neovim_runtime
    other=bare; [[ "$profile" == bare ]] && other=workstation
    if BOOTSTRAP_NEOVIM_PROFILE="$other" verify_neovim_runtime; then exit 1; fi
done
cp "$config/bootstrap-profile.json" "$temporary/profile"
rm "$config/bootstrap-profile.json"
if verify_neovim_runtime; then exit 1; fi
cp "$temporary/profile" "$config/bootstrap-profile.json"
rm "$config/init.lua"
printf 'vim.g.bootstrap_neovim_profile="workstation"\nerror("startup sentinel")\n' >"$config/init.lua"
if verify_neovim_runtime; then exit 1; fi
printf 'PASS R13 bare/workstation ordinary startup; wrong, absent and failed config rejected\n'
