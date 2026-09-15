# Neovim configuration

Bootstrap owns the LazyVim Lua configuration in `config/` and JSON seeds in
`defaults/`. The archived
`elijah-rou/lazyvim-config` repository is no longer required for default setup.

## Configure an installed Neovim

From the bootstrap checkout or a retained snapshot:

```sh
./configure.sh neovim
```

This is offline configuration, not package installation. It creates a writable
runtime at `${XDG_DATA_HOME:-$HOME/.local/share}/bootstrap/private/neovim/config` and links it to
`${XDG_CONFIG_HOME:-$HOME/.config}/${NVIM_APPNAME:-bootstrap-nvim}`. The entrypoint loads Lua code from the selected
bootstrap source. Keep that source directory available.

`./install.sh neovim` selects the same workstation profile. The bare installer
and `./install.sh link` select the bare profile. Both profiles disable Mason and
activate only explicitly selected language servers. Configuration-only commands
do not download plugins. Core installation repairs plugins against the effective
`lazy-lock.json`, installs missing parsers, reconciles their pinned revisions and
verifies the complete configured parser set. Unchanged repair preserves lock bytes
and compatible parser artifacts. Use `:Lazy update` explicitly to upgrade plugins.

## Migration and writable state

Bundled setup preserves existing config directories and symlinks as timestamped
backups. It does not pull, reset, clean, or remove either historical LazyVim checkout.
The old commits and uncommitted Lua changes remain where they were.

When activating the bundled runtime, `lazy-lock.json`, `lazyvim.json`, and
`.neoconf.json` are copied from the active config when present, otherwise from
the bundled defaults. Retrying a failed activation picks up subsequent edits to
the still-active config and backs up any earlier runtime copies. Updates to an
already-active bundled runtime preserve its local files. Plugin updates and LazyVim extras therefore
do not modify a verified bootstrap snapshot. Shared Lua changes belong in
`config/`, not in a cached snapshot or an abandoned checkout.

`bootstrap-profile.json` identifies the managed runtime and selects `bare` or
`workstation`; use the setup commands rather than editing this file. Neovim refuses
to start without a valid profile. An existing runtime without one is preserved
and reported for manual inspection by setup.
An interrupted installer can leave `neovim.install.lock` beside the runtime;
remove that exact lock only after confirming no installer is running, then retry.

Explicit `NVIM_CONFIG_REPO_URL` and `NVIM_CONFIG_CHECKOUT_DIR` overrides retain the
external-checkout behavior. Install commands with only `NVIM_CONFIG_CHECKOUT_DIR`
set keep the legacy repository selection; set `NVIM_CONFIG_REPO_URL` for another
repository. Unset both variables to use the bundled default. External checkouts
are updated only when clean; offline configuration never fetches them. To roll back a migration, restore the saved
config symlink/directory or select an existing checkout explicitly. The new
runtime and its local JSON files can remain in place.

## Independent Rust server

Selecting rust-analyzer does not select Rust or Cargo. Without either toolchain
executable, the bundled policy uses filesystem project markers or the buffer's
directory and initializes detached Rust files with sysroot discovery, build scripts,
proc macros and Cargo checks disabled. Basic syntax/navigation remains available;
full dependency and project analysis requires an explicitly installed toolchain.
When both executables are available, the normal upstream workspace policy applies.

Readiness requires initialization, attachment and an error-free supported request:
document symbols for most servers, pull diagnostics for Ruff. Protocol errors and
timeouts fail verification even when the server executable starts.

## Preserved behavior

The leader is Space. `<leader><Space>` opens the configured file picker in the
project root, even if a plugin default assigns that key to scratch.

`leetvim solution.go` opens the recovered minimal interview mode. It requires an
installed nvim-treesitter runtime; installed parsers provide highlighting and
folding, with built-in syntax as the fallback for other languages. It does not
load LazyVim, LSP clients, or completion plugins. `:LeetcodeMode on|off|toggle`
requires Neovim 0.12 or newer and refuses to restart with modified buffers.

In interview mode, `:Question <question>` explicitly sends the current buffer and
bounded question history to Pi using GPT-5.6 Sol with medium thinking. It gives
interviewer-style hints for exercises and direct answers to general tooling
questions. Pi authentication remains local. Requests disable Pi tools and
extensions, time out after 120 seconds, and allow five seconds before forced
termination. Closing Neovim terminates the pending interviewer process.

In SSH, tmux, or Herdr contexts, the clipboard helper sends system-register copies
through OSC 52. The `<leader>y`/`<leader>p` mappings use these registers; ordinary
yanks stay in Neovim's internal registers. When Wayland clipboard tools are available, it also updates the
local clipboard and uses it for paste; otherwise paste uses an OSC 52 query.
Ordinary local sessions keep their existing clipboard provider. Set
`vim.g.omarchy_remote_clipboard_osc52 = false` to disable OSC 52 copies while
retaining Wayland copies.

## Verify

`./scripts/validate` runs migration and Lua contracts without model requests.
For full startup checks using already installed LazyVim plugins and Go/Rust/Zig
Tree-sitter parsers:

```sh
bash tests/bundled_neovim_runtime_test.sh
```

Set `NVIM_PLUGIN_ROOT` and `NVIM_SITE_ROOT` if those resources are outside their
usual Neovim data directories. The check copies caches into a disposable config/data home and checks out the
bundled plugin revisions before use. It exercises locked plugin repair, stale and
missing parsers, build failure, both profiles and the file-picker action. Repair
may fetch pinned sources; host caches are never modified.

`bash tests/real_nvim_lsp_test.sh` uses the bundled configuration and generated
selection file. It requires BasedPyright and a standalone rust-analyzer binary
(`RUST_ANALYZER_TEST_BIN` may name it), tests Rust with rustc/Cargo absent from PATH,
and checks protocol failures and timeout cleanup without provider calls.
