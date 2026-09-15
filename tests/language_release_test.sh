#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node - "$ROOT/packages/catalog.json" <<'NODE'
const c=JSON.parse(require('node:fs').readFileSync(process.argv[2]));
if(c.schemaVersion!==1) throw Error('catalog version');
for(const name of ['c','cpp','rust','go','python','typescript','elixir','zig']) if(!c.languages[name]) throw Error(`missing language ${name}`);
for(const name of ['clangd','rust-analyzer','gopls','basedpyright','ruff','typescript-language-server','bash-language-server','elixirls','zls']) {
 const v=c.lsp[name]; if(!v||!v.executable||!v.server||!v.command?.length||!v.fixture||!Array.isArray(v.prerequisites)) throw Error(`incomplete LSP ${name}`);
}
NODE
grep -q 'node-v24.18.0-linux-x64.tar.xz' "$ROOT/scripts/lib/install/native.sh"
grep -q 'tree-sitter-linux-x64.gz' "$ROOT/scripts/lib/install/native.sh"
grep -q 'nvim-linux-x86_64.tar.gz' "$ROOT/scripts/lib/install/native.sh"
! grep -Rqi 'micromamba\|conda-forge' "$ROOT/install.sh" "$ROOT/scripts" "$ROOT/packages"
echo 'PASS versioned native/direct catalog and no Conda runtime'
