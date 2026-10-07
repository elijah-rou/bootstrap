# Offline configuration linking

Users reapply shell and application configuration without downloading tools, while reruns preserve user-owned replacements and avoid duplicating installer state.

## Sub-features

- `link-shell` adds marked Bash and Git blocks.
- `link-apps` links Helix and git-ignore configuration.
- `link-converge` reapplies configuration without additional state or filesystem changes.
- `link-preserve` respects user replacements, existing skills, unsafe roots, and malformed blocks.

## How to get to it (user POV)

- Run `./install.sh link`, either on a clean account or after installation.
- Installation also applies configuration; the download round trip relinks an installed account.
- Rerun after changing the checkout/configuration or replacing an owned link with a user file.

## Driving it with Docker

Preconditions:

- Parent-skill Doctor passes; use `NETWORK=none` for the offline and edge proof.

- **Link from clean state.** Parent `offline` mode runs `./install.sh link`, saves state.tsv and the Bash block, asserts the Helix symlink destination, and captures a complete account snapshot.
- **Relink.** The same mode runs `./install.sh link` again. Require byte-identical state.tsv and equal linked/relinked HOME snapshots. Docker has no network, package snapshots remain equal, and no tool files were downloaded.
- **Protect user files.** Parent `edges` mode invokes `bash -x tests/uninstall_edges.sh`. Require `PASS install link and uninstall edge cases` and exit 0; its xtrace covers malformed blocks, unsafe roots, user replacement git-ignore files, and existing skill links.
- **Relink after installation.** The parent's online `roundtrip --tools just` also invokes real `install.sh link` after both installs; capture `configuration linked` and subsequent doctor success.
- **Proof.** Export `/proof/offline` and retain `offline.stderr`/`edges.stderr`. Do not infer offline behavior only from the command's name.

## Gotchas

- `link` is not dry-run: it creates state and configuration, even on a clean account.
- Missing downloaded tools after a clean offline link are expected; product doctor should fail, not be bypassed.
- The edge harness's local agent-kit fixture proves link preservation, not a production agent install.
- Node-compatible JSON rendering is why this recipe uses the Node image rather than a minimal distro image.
