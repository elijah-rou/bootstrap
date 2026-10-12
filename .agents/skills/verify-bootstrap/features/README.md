# Bootstrap installer verification map

This is the source of truth for user-path verification of `install.sh`. Read the parent skill for the `scripts/verify.sh` launch, Doctor, drive, and cleanup commands. This map distinguishes exercised entry points from coverage gaps; passing one does not verify all others.

## Baseline preconditions

- A run-owned Docker container from `node:24-bookworm`, with an unprivileged `tester` account rooted at `/var/tmp/tester`. No installer command runs on the host.
- Parent-skill Doctor passes: correct source/image, run label, read-only `/src`, no published ports, no credentials forwarded.
- An offline run (`verify.sh launch`) for the `help`, `link`, `doctor`, and `uninstall` targets; a separate `verify.sh launch --network bridge` run for the `install` target. Node is available for the existing edge harness.
- `/proof` is container scratch. The run's evidence directory is a unique host directory under ignored `local/verification/bootstrap/RUN_ID/`, outside everything cleanup removes.
- Default installer paths and an otherwise clean account. No preexisting bootstrap install, external agent-kit checkout, provider credentials, or custom XDG paths. Repository tests create explicitly labeled temporary fixtures.

## Driving conventions

- Drive each feature with `verify.sh drive RUN_ID TARGET`, where TARGET is the feature's file name; never run the host installer or host test scripts. The CLI runs the container helper `/src/.agents/skills/verify-bootstrap/scripts/inside.sh TARGET` as tester with a bounded `timeout` and `bash -x` for command traces. Stable handles are command flags, exact log lines, state.tsv records, file contents, and symlink destinations.
- Every target restores its own mutations, so offline targets run in any order in one container, each once per run. On failure the CLI keeps the evidence and stops; run `verify.sh cleanup RUN_ID` and restart from Launch.
- The `install` target calls the unchanged `tests/roundtrip.sh /src --tools just` by default; it covers real core downloads and one selected tool, not all catalog entries.
- Do not substitute root for tester: unwritable-file behavior is a meaningful user path. Do not drive another run's container.

## Proof and skip reporting

- Record command, stdout, stderr, status, image/source identity, and feature/entry point. Mode names identify the entry points described below; the xtrace is the detailed action record.
- File mutations require independent observations: HOME checksums, package snapshots, state.tsv, links, and shell markers. A completion line alone is insufficient.
- For uninstall require before/after HOME and package equality, then removal of the run-owned container. Export evidence before deletion and list surviving files afterward.
- Each target passes only with exit 0 and its `PASS TARGET:` line, which the CLI checks. Expected negative commands are asserted inside the helper, not mistaken for harness failures.
- Report network/timeouts and unmet prerequisites with their transcripts. A skipped path stays skipped even if a related path passes. Public downloads are real; edge-test fixtures do not prove agent downloads or live-auth cleanup.
- Not covered by the current smoke: bare no-option installation as a distinct invocation, selection short aliases (`-l`, `-s`, `-t`), successful language/LSP selections, no-option replay of remembered selections, root/package-manager transactions, interactive uninstall confirmation, external `CODEX_HOME`, macOS/keychain, and other distro/architecture matrices. Map these as additional proofs when relevant; do not claim them from `--tools just`.

## Features

- [Help and selection validation](./help.md): help aliases and invalid selection groups.
- [Install and converge tools](./install.md): real core downloads, a selected tool, rerun, usable shell commands.
- [Offline configuration linking](./link.md): shell/config links, convergence, user-file preservation.
- [Health diagnosis](./doctor.md): installed and missing-tool states.
- [Uninstall and recovery](./uninstall.md): confirmation policy, state restoration, repeat uninstall, failure recovery.
