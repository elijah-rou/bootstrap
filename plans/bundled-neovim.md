# Bundled Neovim configuration

## Status and authority

User approved moving the recovered LazyVim configuration into public bootstrap, including the remote-clipboard helper and the file-picker fix. The seven local LeetCode commits are the recovered baseline. Plugin-lock edits remain local. Both existing checkouts must remain untouched. Root may fast-forward and push bootstrap/dotfiles and activate the result locally after verification.

Current slice: complete. Import, portable runtime, materialization, dotfiles integration, publication, and local activation are verified.

## Design

- Bootstrap owns `neovim/config/` and separate JSON seeds in `neovim/defaults/`; the archived repository is no longer a default dependency. Record source revision without copying Git history or credentials.
- Default setup maintains a writable runtime directory under the user's data home and links it into the Neovim config location. A versioned profile file identifies managed state and selects bare/workstation behavior.
- The entrypoint loads code from the selected bootstrap source. `lazy-lock.json`, `lazyvim.json`, and `.neoconf.json` remain writable local files. Seed them from the active config when present, otherwise from the bundled baseline; preserve them on updates.
- Preserve old config directories and symlinks using existing backup machinery. Do not pull, reset, clean, or delete legacy checkouts.
- Preserve explicit `NVIM_CONFIG_REPO_URL` / `NVIM_CONFIG_CHECKOUT_DIR` overrides through the existing external-checkout path. Only the default changes.
- Bare runtime retains PATH-managed LSP policy. Workstation runtime retains its existing package/Mason policy. No registration, services, credentials, or provider requests during configuration or tests.
- The LeetCode question runner must use a portable bounded process timeout; clipboard forwarding remains conditional on remote/multiplexer contexts.

## Slices and evidence

1. Import recovered source and picker fix; adapt portability; run Lua tests with mocked providers/clipboard.
2. Materialize managed runtime; test fresh setup, old-checkout migration, local JSON preservation, profile switching, retries, locks, rejected foreign state, and explicit override compatibility.
3. Update dotfiles expectations/docs, run both suites and actual Neovim startup against a disposable home using installed plugins.
4. Review persistence and public-source boundaries, fix accepted findings, publish runtime and update both pins, then activate locally and verify preserved source checkouts and effective keymap.

## Decisions and evidence

- Public snapshots must not become writable plugin state. Directly linking the entire config into a snapshot is rejected.
- Existing custom repository overrides remain opt-in rather than restoring an implicit archived dependency.
- Import committed plugin locks only; the active machine's lock is preserved by materialization.

## Verification and review

- Full bootstrap validation passed with installed Neovim runtime checks enabled; workstation/bare startup and 153 LeetCode assertions passed without provider requests.
- Full dotfiles validation passed against the development bootstrap source.
- Review identified three migration edge cases. Regression tests reproduced each: checkout-only installation compatibility, active JSON changes between failed activation and retry, and bare doctor accepting workstation mode. The fixes passed targeted tests.
- Native timeouts include forced termination and editor-exit cleanup. Tests cover a child ignoring TERM and handler cleanup.
- Alternate review found no P0/P1 in runtime placement/process/clipboard behavior. Its residual concerns were addressed by canonicalizing module paths, moving seed JSON outside the runtime path, and requiring a valid profile at startup.

- Cross-platform CI passed for runtime `cd56e04ce9a628d48c698f52f1a540425da27489`: Linux, macOS, and installed Pi/Codex jobs. Symlinked temporary roots are now exercised on every platform.
- Dotfiles installer tests now isolate HOME and inherited XDG/tool roots. A sentinel guard reproduced the prior escape and passes after correction; a full run leaves the active Neovim runtime unchanged.
- Local startup loads the bundled workstation config, recovered LeetCode command, approved clipboard helper, and file-picker binding. Both former checkouts match their recorded content hashes; local JSON matches the previously active config.
- Both installation pins select the verified runtime. The old repositories and task worktrees are retained.

## Resume

No remaining implementation steps or user decisions. Shared Neovim changes now belong in bootstrap; the archived repository is only an explicit compatibility override.
