# ADR 001: Bundled code with writable Neovim state

Status: accepted.

## Context

Neovim setup cloned a separate repository. A checkout-path change left newer
local commits behind, and the remote repository was later found to be archived.
Bootstrap must own the portable configuration without overwriting recovered
work or making verified source snapshots writable plugin state.

## Decision

Bundle Lua code under `neovim/config/` and initial JSON under `neovim/defaults/`,
outside the Lua runtime path. Maintain a
writable runtime under the user's data home at `bootstrap/neovim`, linked from
the user's Neovim config location. Its `init.lua` links to the selected bundled
entrypoint. `bootstrap-profile.json` has exactly two fields: integer `version: 1`
and `profile: "bare" | "workstation"`. Unknown or unmarked runtime state is not
adopted. Editor startup also rejects a missing or invalid profile rather than
falling back from bare to workstation behavior. Setup serializes mutations with a sibling install lock and stages the
first runtime before activation.

Seed plugin locks, extras, and Neoconf JSON from the active config when available,
including retries while a legacy config remains active. Back up superseded pending
runtime copies. Preserve local JSON on updates to an already-active runtime. Preserve prior config targets through backups and
leave legacy checkout contents untouched. Explicit custom-repository and
custom-checkout overrides remain supported.

## Alternatives and consequences

Linking the entire config into a snapshot would let plugin updates mutate the
snapshot. Continuing to clone the archived repository would retain the ownership
problem. Copying all Lua files would require a per-file update/merge protocol.
The chosen entrypoint keeps shared code versioned together while local plugin
state survives source changes. Lazy's runtime-path reset explicitly retains the
bundled source path.

## Reversal

Restore the saved previous config target or select a custom checkout explicitly.
Do not delete old checkouts or the writable runtime as part of rollback. A future
profile format requires a versioned migration before accepting its state.
