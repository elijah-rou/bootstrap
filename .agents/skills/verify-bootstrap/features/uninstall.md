# Uninstall and recovery

Users remove bootstrap's recorded changes, preserve unrelated work, refuse accidental noninteractive removal, and retry safely when an uninstall cannot finish.

## Sub-features

- `uninstall-confirmed` removes recorded files, blocks, links, and private state.
- `uninstall-refuse` requires `--yes` without a terminal and preserves state on refusal.
- `uninstall-repeat` succeeds when there is nothing left to uninstall.
- `uninstall-preserve` leaves user replacement files and restores original shell content.
- `uninstall-recover` retains state after a failed step and completes after the cause is fixed.

## How to get to it (user POV)

- Run `./install.sh uninstall --yes` for noninteractive removal.
- Run `./install.sh uninstall` without a terminal to observe the confirmation requirement.
- In a real terminal, bare uninstall offers `Continue? [y/N]`; accepting and cancelling are mapped but require a separate PTY proof, not this noninteractive harness.
- Retry the same confirmed command after a failure or after successful removal.

## Driving it with Docker

Preconditions:

- Parent-skill Doctor passes. Offline modes use an unprivileged account and `NETWORK=none`.

- **Require confirmation.** Parent `offline` mode runs `./install.sh uninstall` with stdin closed. Require failure and state.tsv unchanged.
- **Undo and repeat.** It then runs `./install.sh uninstall --yes` twice, asserts the bootstrap root is absent, and compares full HOME/package snapshots to baseline.
- **Recover while preserving user content.** Parent `edges` mode runs `bash -x tests/uninstall_edges.sh`; the existing harness makes the shell file unwritable, requires failed uninstall to keep state, restores writability, retries, and checks original shell content and user replacement git-ignore survive.
- **Remove a real installation.** Parent `roundtrip --tools just` invokes confirmed uninstall after installed-command checks and fake gh auth seeding. Require the final PASS and matching before/after snapshots; the fake-token signout warning does not prove live credential revocation.
- **Proof.** Retain offline/edge/round-trip commands, stdout, stderr, and statuses; export snapshots before the parent's separate container Cleanup. Interactive acceptance/cancellation, live keyrings, tmux/Herdr shutdown, backup restoration with preexisting target files, and package-manager removal remain explicit coverage gaps.

## Gotchas

- Container deletion alone does not prove uninstall. Observe equality while the container still exists, then delete it.
- Root can write supposedly unwritable files; using root invalidates the recovery test.
- Provider-side sessions and external `CODEX_HOME` are outside the installer’s purge promise.
- Cleanup must never remove host evidence or containers belonging to other runs.
