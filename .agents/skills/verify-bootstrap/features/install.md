# Install and converge tools

Users install pinned core tools, optionally select additional tools/languages/servers, rerun to converge, and use the resulting commands from a new shell.

## Sub-features

- `install-core` downloads checksum-verified pinned binaries and configures the account.
- `install-selection` installs and records a user-selected tool (`just` in this smoke).
- `install-rerun` repeats the same install arguments successfully.
- `install-shell` exposes real executables and bootstrap-first PATH in interactive and login Bash.
- `selection-replay` remembers choices on later no-option installs; mapped but not proved by the current harness.

## How to get to it (user POV)

- Run `./install.sh` for core tools and previously remembered selections.
- Run `./install.sh --tools just` for a concrete additional tool. The same grouped interface accepts `--languages` and `--lsp`, with names listed by help.
- Repeat installation to converge. Short aliases `-l`, `-s`, and `-t` exist.

## Driving it with Docker

Preconditions:

- Fresh parent-skill Launch with `NETWORK=bridge`, Doctor passes, public release downloads reachable, no user credentials.

- **Install a real selection.** Run the parent's `roundtrip --tools just` Drive block. The helper calls `bash -x tests/roundtrip.sh /src --tools just`, which copies the checkout and invokes its `install.sh --tools just` twice. Require two `installed; start a new shell to use it` lines.
- **Use installed commands.** The unchanged test relinks, invokes product `doctor`, starts interactive Bash for command lookup and `hx --version`, and executes Bun through `node`. Require doctor `ok` rows including `just`, real versions, and the login PATH assertion to pass.
- **Observe side effects and undo.** Require the existing harness's final `PASS: install, rerun, doctor, and uninstall left HOME and packages unchanged`. Export `/proof/roundtrip` for independent before/after account and package-version snapshots. Stderr/xtrace shows the real action sequence.
- **Report unexercised entries.** Bare install, no-option replay, short aliases, language/LSP success, root/system-package selections, and other catalog selections are skipped. This tool-selection run exercises core installation, not every entry point to it.

## Gotchas

- Network failure or timeout is incomplete verification, never a simulated pass.
- The original harness repeats the same arguments; it does not prove remembered selections with arguments omitted.
- The 180-second smoke timeout is intentionally bounded; large language/agent matrices need separate reviewed runs.
- The image's preinstalled Node is a test prerequisite; the installed-shell test checks the bootstrap Bun-backed `node`, not merely baseline Node.
