# Bootstrap installer verification map

This is the source of truth for user-path verification of `install.sh`. Read the parent skill for exact launch, Doctor, evidence export, and cleanup blocks. This map distinguishes exercised entry points from coverage gaps; passing one does not verify all others.

## Baseline preconditions

- A run-owned Docker container from `node:24-bookworm`, with an unprivileged `tester` account rooted at `/var/tmp/tester`. No installer command runs on the host.
- Parent-skill Doctor passes: correct source/image, run label, read-only `/src`, no published ports, no credentials forwarded.
- `NETWORK=none` for help/link/edge cases; a fresh `NETWORK=bridge` container for the real download round trip. Node is available for the existing edge harness.
- `/proof` is container scratch. `$EVIDENCE_DIR` is a unique host directory under ignored `local/verification/bootstrap/`, outside everything cleanup removes.
- Default installer paths and an otherwise clean account. No preexisting bootstrap install, external agent-kit checkout, provider credentials, or custom XDG paths. Repository tests create explicitly labeled temporary fixtures.

## Driving conventions

- Use the parent's direct Docker commands, never the host installer or host test scripts. The container helper is `/src/.agents/skills/verify-bootstrap/scripts/inside.sh`.
- Each Drive call uses `docker exec -u tester -e HOME=/var/tmp/tester`, a bounded `timeout`, and `bash -x` for command traces. Stable handles are command flags, exact log lines, state.tsv records, file contents, and symlink destinations.
- Offline modes run in order: `help`, `offline`, `edges`. Successful modes restore their own mutations. On failure, export available evidence, remove only the recorded container, and restart from Launch.
- Online mode `roundtrip --tools just` calls the unchanged `tests/roundtrip.sh /src --tools just`; it covers real core downloads and one selected tool, not all catalog entries.
- Do not substitute root for tester: unwritable-file behavior is a meaningful user path. Do not drive another run's container.

## Proof and skip reporting

- Record command, stdout, stderr, status, image/source identity, and feature/entry point. Mode names identify the entry points described below; the xtrace is the detailed action record.
- File mutations require independent observations: HOME checksums, package snapshots, state.tsv, links, and shell markers. A completion line alone is insufficient.
- For uninstall require before/after HOME and package equality, then removal of the run-owned container. Export evidence before deletion and list surviving files afterward.
- All three offline helper exits and the online round-trip exit must be zero for those cases to pass. Expected negative commands are asserted inside the helper, not mistaken for harness failures.
- Report network/timeouts and unmet prerequisites with their transcripts. A skipped path stays skipped even if a related path passes. Public downloads are real; edge-test fixtures do not prove agent downloads or live-auth cleanup.
- Not covered by the current smoke: bare no-option installation as a distinct invocation, selection short aliases (`-l`, `-s`, `-t`), successful language/LSP selections, no-option replay of remembered selections, root/package-manager transactions, interactive uninstall confirmation, external `CODEX_HOME`, macOS/keychain, and other distro/architecture matrices. Map these as additional proofs when relevant; do not claim them from `--tools just`.

## Features

- [Help and selection validation](./help.md): help aliases and invalid selection groups.
- [Install and converge tools](./install.md): real core downloads, a selected tool, rerun, usable shell commands.
- [Offline configuration linking](./link.md): shell/config links, convergence, user-file preservation.
- [Health diagnosis](./doctor.md): installed and missing-tool states.
- [Uninstall and recovery](./uninstall.md): confirmation policy, state restoration, repeat uninstall, failure recovery.
