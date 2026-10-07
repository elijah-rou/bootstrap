# Help and selection validation

Users discover supported names and groups without installing, and receive errors for unknown selections before any account changes.

## Sub-features

- `help-long` lists usage and catalog choices through `--help`.
- `help-short` exposes the same interface through `-h`.
- `selection-invalid` rejects unknown names in languages, LSP, and tools without side effects.

## How to get to it (user POV)

- Invoke `./install.sh --help` or `./install.sh -h` from the checkout.
- Pass a name after `--languages`, `--lsp`, or `--tools`; unknown names must fail.
- Short group aliases `-l`, `-s`, and `-t` also exist; they are mapped but not exercised by this smoke.

## Driving it with Docker

Preconditions:

- Parent-skill Launch and Doctor pass in a fresh offline container.

- **Discover names.** Use the parent's `help` Drive mode. It invokes `./install.sh --help` and `./install.sh -h`; stdout must show `Usage:` and all three groups from `catalog.tsv`.
- **Reject invalid names.** The same mode invokes `./install.sh --tools verification-does-not-exist`, `./install.sh --languages verification-does-not-exist`, and `./install.sh --lsp verification-does-not-exist`; each must fail. Stderr identifies the unknown group selection.
- **Prove no mutations.** Require the mode's PASS line and exit 0. Export `/proof/help`; `before.home`/`after.home` and `before.packages`/`after.packages` compare equal.
- **Alias gap.** Report short selection flags as skipped, not verified by the long-option cases.

## Gotchas

- Help is a successful early return, not evidence of installed tools.
- Invalid selections are expected product failures; the helper fails if they unexpectedly succeed.
- Catalog names change. Read captured help rather than inventing a selection.
