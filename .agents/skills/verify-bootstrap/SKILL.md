---
name: verify-bootstrap
description: Verify bootstrap's install.sh command-line installer, configuration linking, health checks, and uninstall in disposable Docker containers after installer or catalog changes. Never install into the host account.
---

# Verify bootstrap

Read [features/README.md](features/README.md) before driving. Drive everything through `scripts/verify.sh` from the repository root; it takes the run ID as an argument, so separate Bash calls need no shared shell state. Every installer invocation stays in a container. Do not run `tests/roundtrip.sh` or `tests/uninstall_edges.sh` directly on the host.

## Repository interview

- **Surface:** the primary interface is `install.sh`: options, progress messages, exit status, and changes to the account. Installed shell/editor/agent configuration is secondary. `README.md` and `install.sh`'s command dispatch define the interface.
- **Run:** no compilation or server; Bash syntax-check once at launch. `install.sh` starts the installer. Supported platforms are glibc Linux x86_64/aarch64 and Apple Silicon macOS. `catalog.tsv` pins downloads. `tests/container.sh` provisions prerequisites and calls `tests/roundtrip.sh`; `.github/workflows/validate.yml` defines the supported test matrix.
- **Environment/auth/seed:** this recipe uses the already-local `node:24-bookworm` image (git, curl, tar, gzip, xz, unzip, Node, glibc). No credentials or application seed needed. The container account is `tester`, with `HOME=/var/tmp/tester`, `TERM=dumb`, and `LC_ALL=C`. Do not forward host credentials, SSH sockets, Docker sockets, or installer overrides. Product overrides include `BOOTSTRAP_ROOT`, `BOOTSTRAP_AGENT_KIT`, XDG paths, and `CODEX_HOME`; the default baseline leaves them unset. `tests/roundtrip.sh` seeds only a deliberately invalid gh token.
- **Drive:** reuse `tests/roundtrip.sh` and `tests/uninstall_edges.sh`. Unlike `tests/container.sh`'s anonymous foreground container, this recipe retains an explicitly owned container long enough for Doctor and evidence export. The container-only helper `scripts/inside.sh` has one mode per feature and adds side-effect assertions, not alternate installer behavior; the host CLI `scripts/verify.sh` owns the container lifecycle and evidence.
- **Observe:** stdout, stderr/xtrace, statuses, source hashes, image identity, state.tsv, links, shell blocks, HOME checksums and package names/versions. No UI, port, or PTY is required for the covered noninteractive paths.
- **Isolate:** each run has its own container, account, filesystem, label, and ID; no published ports and only the repository mounted read-only. Runs may coexist. Never attach to or remove an instance not started by this run. Recipe: `create-verification/references/cli-tui.md`.

## Launch

Requirements: reachable Docker daemon, the local `node:24-bookworm` image, Bash, Git, and shasum. Docker access needs no installer credentials.

```bash
.agents/skills/verify-bootstrap/scripts/verify.sh launch                     # offline: help, link, doctor, uninstall
.agents/skills/verify-bootstrap/scripts/verify.sh launch --network bridge    # downloads: install
```

`launch` prints `RUN_ID=` and `EVIDENCE_DIR=` first; pass that `RUN_ID` to every later command, and to `cleanup` even if launch fails after printing it. It records revision, product diff, source and image hashes, then starts a container labeled `bootstrap.verify.run=RUN_ID` with no published ports, the repository mounted read-only at `/src`, and an unprivileged `tester` account. Readiness is the exact `READY bootstrap verifier` line, after account creation and Bash syntax validation, bounded to 60 seconds. Never enable networking on an offline run; launch a separate bridge run for `install`.

## Doctor

```bash
.agents/skills/verify-bootstrap/scripts/verify.sh doctor RUN_ID
```

This read-only check verifies ownership, readiness, immutable image ID, exact current source/helper bytes, isolated writable account, prerequisites, read-only mount, and absence of published ports. It does **not** claim the tools are installed; product `install.sh doctor` is the `doctor` and `install` targets. `drive` refuses to start until Doctor has passed for the run. Doctor runs once per run.

## Drive

One target per feature in `features/`. Each runs `scripts/inside.sh TARGET` as the **unprivileged** tester (root would invalidate the permission-failure uninstall test) under `bash -x`, with a 180-second deadline plus 10 seconds to terminate. Every target restores HOME and packages, so offline targets can run in any order in one container. A target runs once per run: to repeat one, launch a new run.

```bash
.agents/skills/verify-bootstrap/scripts/verify.sh drive RUN_ID help link doctor uninstall   # offline run
.agents/skills/verify-bootstrap/scripts/verify.sh drive RUN_ID install                      # bridge run
```

| Target | Feature | Network | Proves |
| --- | --- | --- | --- |
| `help` | [help.md](features/help.md) | none | `--help` and `-h`; unknown names in all three selection groups fail without changing HOME/packages. |
| `link` | [link.md](features/link.md) | none | real `link` twice, state.tsv and filesystem convergence, shell markers and Helix link, no downloaded tools; then `tests/uninstall_edges.sh` for unsafe roots, unterminated blocks, user replacement files, existing skills. |
| `doctor` | [doctor.md](features/doctor.md) | none | product `doctor` exits 1 with `missing` rows after an offline link. The installed state is the `install` target. |
| `uninstall` | [uninstall.md](features/uninstall.md) | none | nonterminal refusal without `--yes` keeps state; confirmed and repeated uninstall restore HOME/packages; `tests/uninstall_edges.sh` failed-uninstall recovery. |
| `install` | [install.md](features/install.md) | bridge | the unchanged `tests/roundtrip.sh /src --tools just`: install twice, relink, installed `doctor`, interactive/login shell use, fake gh signout, uninstall to equal snapshots. |

A target passes only with exit 0 and its own `PASS TARGET:` line, which the CLI checks and prints. On failure the CLI stops, keeps the evidence, and names the files; run Cleanup, fix the verification instructions or product, and launch a new run. Timeout exit 124 is a failed, incomplete run, not a pass.

`install` takes another selection after `--`, for example `drive RUN_ID install -- --languages python`; a bare `--` installs core tools only. The helper requires both `installed; start a new shell to use it` lines and the harness's `PASS: install, rerun, doctor, and uninstall left HOME and packages unchanged`. Downloads must reach the public release hosts from `catalog.tsv`; no provider credentials are needed. A warning about signing out the fake gh account is not live-auth proof. Larger selections need a deliberately reviewed `--timeout SECONDS` (`drive --timeout 600 RUN_ID install -- ...`).

## Evidence

`local/verification/bootstrap/RUN_ID/` is the single evidence directory per run, under the repository's git-ignored `local/`. Cleanup never removes it. Each target leaves `drive-TARGET.command`, `.stdout`, `.stderr` (xtrace), `.exit`, and `artifacts/TARGET/` exported from the container's temporary `/proof/TARGET`. Launch and Doctor leave image/source identity and their transcripts; Cleanup exports the whole `/proof` again to `cleanup-artifacts/`.

Artifacts include before/after HOME and package-version snapshots for every target, plus: `link` first state.tsv, shell block, Helix link target, linked/relinked snapshots; `doctor` product-doctor output and status; `uninstall` first state.tsv; `install` the round-trip stdout. The round-trip harness itself compares package names.

Proof standards:

- Exercise real user commands, never internal installer functions or synthetic state setters as the main proof. Capture actions and resulting state, not just a success message.
- Verify file contents, symlink destinations, state records, package state, and cleanup independently of visible output. Xtrace from the existing edge harness may expose fixtures; never inject real secrets into it.
- Mocks are acceptable only at existing production external boundaries, and must be labeled. The edge fixture is not a substitute for the real `--tools just` download proof.
- `link` is **not a dry run**: it writes configuration and state. This installer has no dry-run flag. Disabled network, unchanged packages, and no downloaded tool files prove what the offline run skips; its captured files prove what it still changes.
- A convenient entry point does not prove other mapped entries. Report skipped aliases, selections, interactive confirmation, platform-specific behavior, and live credential/keychain cleanup explicitly.

## Cleanup

Run even on failure:

```bash
.agents/skills/verify-bootstrap/scripts/verify.sh cleanup RUN_ID
```

It removes only the container recorded in `container.id`, after checking its `bootstrap.verify.run` label, and refuses to remove anything by guessed name. Before removal it exports `/proof`, the process list, and container logs; an export failure is reported but does not leave the container running. It then proves the recorded ID and run label are absent and lists surviving evidence. Rerunning it after the container is gone only repeats the absence checks. It destroys the container's account, scratch checkout, test fixtures, and processes; no host installer, background client, published port, or persistent volume exists. Never remove evidence or prune Docker globally.

## Helpers

`scripts/verify.sh` is the host CLI (`--help` lists commands and targets). It never runs installer code on the host; its only host actions are Git/shasum reads, evidence writes under `local/`, and Docker commands on its own labeled container. `scripts/inside.sh` runs only inside that container, refuses to run without the container marker, and is invoked explicitly through Bash by `drive`. CI's `scripts/validate` syntax-checks and shellchecks both.

After changing the skill, run `shellcheck -x -P SCRIPTDIR --severity=warning .agents/skills/verify-bootstrap/scripts/*.sh` (CI's `scripts/validate` also checks both) and drive every target in fresh offline and bridge runs. Each feature file keeps the map's section shape (Sub-features, How to get to it, Driving it with Docker, Gotchas) and is linked from `features/README.md`.

Use `maintain-verification` when commands, options, platform support, or proof conventions change. Known coverage gaps are tracked in the feature map, not silently promoted to passes.
