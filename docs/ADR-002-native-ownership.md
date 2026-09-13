# ADR-002: Native selections and uninstall ownership

Status: accepted

## Context

Bootstrap is used on machines where personal credentials and sessions must be removable without treating the whole home directory or package database as owned. Native package managers can also install packages that later become shared. Language and LSP coupling made implicit installation impossible to audit.

## Decision

The public CLI has independent `--languages`, `--lsp`, and `--tools` selectors. Selections and cleanup identities use one schema-versioned record at `${XDG_STATE_HOME:-~/.local/state}/bootstrap/install.json`; `packages/catalog.json` is the single package/executable/LSP mapping. Configuration-only entry points remain offline and unprivileged.

The record is written before managed mutations. It stores a random installation ID, component and overall readiness, selections, exact managed targets, original file/link state, enrolled roots, writer identities, and package pre-presence/version. Records and paths are bounded and validated. Targets must be below the current home, cannot be the home itself, and cannot escape through symlink ancestors. The only exception is the fixed `lua/plugins/zz-bootstrap-managed.lua` symlink in an explicitly supplied external Neovim checkout: the journal records the checkout device/inode and canonical path, rejects symlink parents and tracked/custom collisions, and may remove only an unchanged managed link. The checkout is never enrolled or recursively cleaned. Unknown schemas fail closed. A non-stealable directory lock serializes mutation.

`scripts/bare-env.sh` is the single runtime path contract for install, offline configure, and ordinary Bash/Zsh launches. Pi uses its documented `PI_CODING_AGENT_DIR` and `PI_CODING_AGENT_SESSION_DIR`. Neovim uses `NVIM_APPNAME=bootstrap-nvim`, with separately enrolled data/cache/state roots. Workstation overlays change configuration composition and the persisted editor profile only; they do not change ownership roots or opt into Zsh, Starship, Mason, or incidental LSPs. Herdr has no profile-root override, so its supported `~/.config/herdr` root is enrolled only when fresh or provably managed; unrelated existing state blocks adoption. Project copies require an exact explicit enrollment command and confirmation. The legacy tools prefix is preserved because ownership cannot distinguish user additions from old bootstrap content.

Uninstall defaults to deleting enrolled private state and eligible bootstrap-added packages. It previews first, refuses live recorded writers and changed shared files, restores recorded originals, does not follow enrolled symlinks, previews dependency effects, preserves pre-existing/shared packages, and never runs blanket autoremove or downgrade. Progress is recorded after each inverse operation so interruption is retryable. Control/recovery state is removed last.

## Consequences

Core no longer depends on Python, Conda, Zsh, Starship, or an activation shell. Existing personal Herdr state and ambiguous legacy symlinks require operator action rather than unsafe adoption. Filesystem cleanup cannot provide secure erasure or revoke remote credentials. Publishing still requires advancing the separate launcher revision and archive digest after the runtime commit is public and verified.
