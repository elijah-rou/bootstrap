---
name: verify-bootstrap
description: Verify bootstrap's install.sh command-line installer, configuration linking, health checks, and uninstall in disposable Docker containers after installer or catalog changes. Never install into the host account.
---

# Verify bootstrap

Read [features/README.md](features/README.md) before driving. Run the blocks below from the repository root, in the same Bash shell. Every installer invocation stays in a container. Do not run `tests/roundtrip.sh` or `tests/uninstall_edges.sh` directly on the host.

## Repository interview

- **Surface:** the primary interface is `install.sh`: options, progress messages, exit status, and changes to the account. Installed shell/editor/agent configuration is secondary. `README.md` and `install.sh`'s command dispatch define the interface.
- **Run:** no compilation or server; Bash syntax-check once at launch. `install.sh` starts the installer. Supported platforms are glibc Linux x86_64/aarch64 and Apple Silicon macOS. `catalog.tsv` pins downloads. `tests/container.sh` provisions prerequisites and calls `tests/roundtrip.sh`; `.github/workflows/validate.yml` defines the supported test matrix.
- **Environment/auth/seed:** this recipe uses the already-local `node:24-bookworm` image (git, curl, tar, gzip, xz, unzip, Node, glibc). No credentials or application seed needed. The container account is `tester`, with `HOME=/var/tmp/tester`, `TERM=dumb`, and `LC_ALL=C`. Do not forward host credentials, SSH sockets, Docker sockets, or installer overrides. Product overrides include `BOOTSTRAP_ROOT`, `BOOTSTRAP_AGENT_KIT`, XDG paths, and `CODEX_HOME`; the default baseline leaves them unset. `tests/roundtrip.sh` seeds only a deliberately invalid gh token.
- **Drive:** reuse `tests/roundtrip.sh` and `tests/uninstall_edges.sh`. Unlike `tests/container.sh`'s anonymous foreground container, this recipe retains an explicitly owned container long enough for Doctor and evidence export. The tiny container-only helper adds offline side-effect assertions, not alternate installer behavior.
- **Observe:** stdout, stderr/xtrace, statuses, source hashes, image identity, state.tsv, links, shell blocks, HOME checksums and package names/versions. No UI, port, or PTY is required for the covered noninteractive paths.
- **Isolate:** each run has its own container, account, filesystem, label, and ID; no published ports and only the repository mounted read-only. Runs may coexist. Never attach to or remove an instance not started by this run. Recipe: `create-verification/references/cli-tui.md`.

## Launch

Requirements: reachable Docker daemon, the local `node:24-bookworm` image, Bash, Git, and shasum. Docker access needs no installer credentials. The offline baseline has **no network**. For the optional download round trip, use a fresh run and set `NETWORK=bridge` before repeating Launch; do not enable networking on the offline proof container.

```bash
set -e
REPO="$PWD"
NETWORK="${NETWORK:-none}"
mkdir -p "$REPO/local/verification/bootstrap"
RUN_ID="run-$$"
EVIDENCE_DIR="$REPO/local/verification/bootstrap/$RUN_ID"
mkdir "$EVIDENCE_DIR"
printf '%s\n' "$EVIDENCE_DIR"
git check-ignore "$EVIDENCE_DIR"
git rev-parse HEAD > "$EVIDENCE_DIR/revision.txt"
git diff -- install.sh catalog.tsv tests > "$EVIDENCE_DIR/product.diff"
shasum -a 256 install.sh catalog.tsv tests/roundtrip.sh tests/uninstall_edges.sh .agents/skills/verify-bootstrap/scripts/inside.sh > "$EVIDENCE_DIR/source.sha256"
docker image inspect node:24-bookworm > "$EVIDENCE_DIR/image.json"
docker image inspect -f '{{.Id}}' node:24-bookworm > "$EVIDENCE_DIR/image.id"
docker run -d --init --name "verify-bootstrap-$RUN_ID" \
  --label "bootstrap.verify.run=$RUN_ID" --cidfile "$EVIDENCE_DIR/container.id" \
  --network "$NETWORK" --mount "type=bind,src=$REPO,dst=/src,readonly" -w /src \
  -e BOOTSTRAP_VERIFY_CONTAINER=1 -e LC_ALL=C -e TERM=dumb \
  node:24-bookworm bash -euc 'useradd --create-home --home-dir /var/tmp/tester tester; mkdir /proof; chown tester:tester /proof; bash -n /src/install.sh; printf "READY bootstrap verifier\n"; exec sleep infinity' \
  > "$EVIDENCE_DIR/launch.stdout" 2> "$EVIDENCE_DIR/launch.stderr"
IFS= read -r CID < "$EVIDENCE_DIR/container.id" || test -n "$CID"
ready=0
for ((i=0; i<60; i++)); do
  docker logs "$CID" > "$EVIDENCE_DIR/readiness.stdout" 2> "$EVIDENCE_DIR/readiness.stderr"
  if grep -qx 'READY bootstrap verifier' "$EVIDENCE_DIR/readiness.stdout"; then ready=1; break; fi
  sleep 1
done
test "$ready" = 1
docker inspect "$CID" > "$EVIDENCE_DIR/container.json"
```

Use a new Bash shell for each run; the shell PID supplies the run suffix and plain `mkdir` refuses evidence reuse. Readiness is the exact `READY bootstrap verifier` line, after account creation and Bash syntax validation; the wait is bounded to 60 seconds. If launch/Doctor/Drive fails, retain its evidence, run Cleanup for the recorded ID, fix the verification instructions, and start a new run. Teardown is Cleanup below, never a process-name kill. If a policy requires unavailable interactive approval, do not retry it: report the exact blocked command. Direct Docker commands are intentional; a host wrapper with computed command execution was blocked in this environment.

## Doctor

This read-only check verifies ownership, readiness, immutable image ID, exact current source/helper bytes, isolated writable account, prerequisites, read-only mount, and absence of published ports. It does **not** claim the tools are installed. Product `install.sh doctor` is exercised during Drive, in both missing-tool and installed states.

```bash
{
  test "$(docker inspect -f '{{index .Config.Labels "bootstrap.verify.run"}}' "$CID")" = "$RUN_ID"
  test "$(docker inspect -f '{{.State.Running}}' "$CID")" = true
  test "$(docker inspect -f '{{len .HostConfig.PortBindings}}' "$CID")" = 0
  test "$(docker inspect -f '{{range .Mounts}}{{.Destination}}:{{.RW}}{{end}}' "$CID")" = /src:false
  docker inspect -f '{{.Image}}' "$CID" > "$EVIDENCE_DIR/doctor-image.id"
  cmp "$EVIDENCE_DIR/image.id" "$EVIDENCE_DIR/doctor-image.id"
  docker exec -u tester -e HOME=/var/tmp/tester "$CID" bash -euc 'test "$HOME" = /var/tmp/tester; test -w "$HOME"; test -w /proof; for c in git curl tar gzip xz unzip node timeout; do command -v "$c" >/dev/null; done; getconf GNU_LIBC_VERSION; bash -n /src/install.sh'
  docker exec -u tester "$CID" sha256sum install.sh catalog.tsv tests/roundtrip.sh tests/uninstall_edges.sh .agents/skills/verify-bootstrap/scripts/inside.sh > "$EVIDENCE_DIR/doctor-source.sha256"
  cmp "$EVIDENCE_DIR/source.sha256" "$EVIDENCE_DIR/doctor-source.sha256"
  printf 'PASS owned container, exact image/source, isolated account, prerequisites, no ports\n'
} > "$EVIDENCE_DIR/doctor.stdout" 2> "$EVIDENCE_DIR/doctor.stderr"
```

## Drive

### Offline baseline

Run only after Doctor. Each helper call has a 180-second deadline plus 10 seconds to terminate. The helper is executed as the **unprivileged** tester; root would invalidate the permission-failure uninstall test. Do not overwrite a mode's artifacts with a rerun; create a new run instead.

```bash
test "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$CID")" = none
for mode in help offline edges; do
  test ! -e "$EVIDENCE_DIR/$mode.exit"
  printf '%q ' docker exec -u tester -e HOME=/var/tmp/tester "$CID" timeout --signal=TERM --kill-after=10s 180s bash -x /src/.agents/skills/verify-bootstrap/scripts/inside.sh "$mode" > "$EVIDENCE_DIR/$mode.command"
  printf '\n' >> "$EVIDENCE_DIR/$mode.command"
  if docker exec -u tester -e HOME=/var/tmp/tester "$CID" timeout --signal=TERM --kill-after=10s 180s bash -x /src/.agents/skills/verify-bootstrap/scripts/inside.sh "$mode" > "$EVIDENCE_DIR/$mode.stdout" 2> "$EVIDENCE_DIR/$mode.stderr"; then status=0; else status=$?; fi
  printf '%s\n' "$status" > "$EVIDENCE_DIR/$mode.exit"
  test "$status" = 0
done
```

- `help`: real `--help` and `-h`; unknown names in all three selection groups must fail without changing HOME/packages.
- `offline`: real `link` twice, state.tsv and filesystem convergence, shell markers and Helix link, product `doctor` reporting missing tools, nonterminal uninstall refusal without `--yes`, confirmed uninstall and repeated uninstall. Full HOME/package snapshots must match baseline afterward. Network is disabled by Docker; the empty tools tree is checked separately.
- `edges`: `bash -x tests/uninstall_edges.sh`: unsafe-root refusal, unterminated blocks, preserving user replacement files and existing skills, and failed-uninstall recovery. Its local agent-kit fixture is test scaffolding, not proof of a downloaded agent install.

### Download/install round trip

In a **new** container launched with `NETWORK=bridge`, repeat Doctor, then run this block instead of the offline block. No provider credentials needed. Downloads must reach the public release hosts from `catalog.tsv`. This uses the repository's actual round-trip harness, with a lightweight real selection, not mocks.

```bash
test "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$CID")" = bridge
printf '%q ' docker exec -u tester -e HOME=/var/tmp/tester "$CID" timeout --signal=TERM --kill-after=10s 180s bash -x /src/.agents/skills/verify-bootstrap/scripts/inside.sh roundtrip --tools just > "$EVIDENCE_DIR/roundtrip.command"
printf '\n' >> "$EVIDENCE_DIR/roundtrip.command"
if docker exec -u tester -e HOME=/var/tmp/tester "$CID" timeout --signal=TERM --kill-after=10s 180s bash -x /src/.agents/skills/verify-bootstrap/scripts/inside.sh roundtrip --tools just > "$EVIDENCE_DIR/roundtrip.stdout" 2> "$EVIDENCE_DIR/roundtrip.stderr"; then status=0; else status=$?; fi
printf '%s\n' "$status" > "$EVIDENCE_DIR/roundtrip.exit"
test "$status" = 0
```

Require `PASS: install, rerun, doctor, and uninstall left HOME and packages unchanged`, both install completion lines, doctor `ok` rows including `just`, real `hx`/Bun versions, and exit 0. The test also checks interactive and login Bash PATH and seeds invalid gh file-storage auth before uninstall. A warning about signing out the fake account is not live-auth proof. Timeout exit 124 is a failed/incomplete run, not a pass; retain evidence and clean up. Larger selection matrices need a deliberately reviewed timeout.

## Evidence

`$EVIDENCE_DIR` is the single evidence directory per run, under the repository's existing git-ignored `local/` (`.gitignore`). Cleanup never removes it. Container `/proof` is temporary; export it before removing the container:

```bash
docker cp "$CID:/proof/." "$EVIDENCE_DIR/artifacts"
```

Keep command files, stdout, stderr/xtrace, exit statuses, image/source identity, and all exported artifacts. Offline artifacts include first state.tsv, shell block, link target, linked/relinked and before/after HOME and package snapshots, and the negative product-doctor output/status. The round-trip helper also saves outer before/after HOME and package **version** snapshots; the original harness compares package names.

Proof standards:

- Exercise real user commands, never internal installer functions or synthetic state setters as the main proof. Capture actions and resulting state, not just a success message.
- Verify file contents, symlink destinations, state records, package state, and cleanup independently of visible output. Xtrace from the existing edge harness may expose fixtures; never inject real secrets into it.
- Mocks are acceptable only at existing production external boundaries, and must be labeled. The edge fixture is not a substitute for the real `--tools just` download proof.
- `link` is **not a dry run**: it writes configuration and state. This installer has no dry-run flag. Disabled network, unchanged packages, and no downloaded tool files prove what the offline run skips; its captured files prove what it still changes.
- A convenient entry point does not prove other mapped entries. Report skipped aliases, selections, interactive confirmation, platform-specific behavior, and live credential/keychain cleanup explicitly.

## Cleanup

Run even on failure. Stop only the recorded container, after checking its run label. This destroys its account, scratch checkout, test fixtures, and all container processes. No host installer, background client, published port, or persistent volume is created. If no container ID was recorded, do not remove anything by guessed name.

```bash
test "$(docker inspect -f '{{index .Config.Labels "bootstrap.verify.run"}}' "$CID")" = "$RUN_ID"
docker cp "$CID:/proof/." "$EVIDENCE_DIR/cleanup-artifacts"
docker top "$CID" > "$EVIDENCE_DIR/processes-before-cleanup.txt"
docker logs "$CID" > "$EVIDENCE_DIR/container.log" 2>&1
docker rm -f "$CID" > "$EVIDENCE_DIR/cleanup.stdout"
docker ps -aq --no-trunc > "$EVIDENCE_DIR/remaining-container-ids.txt"
! grep -qxF "$CID" "$EVIDENCE_DIR/remaining-container-ids.txt"
docker ps -aq --filter "label=bootstrap.verify.run=$RUN_ID" > "$EVIDENCE_DIR/remaining-run-containers.txt"
test ! -s "$EVIDENCE_DIR/remaining-run-containers.txt"
test -s "$EVIDENCE_DIR/cleanup.stdout"
find "$EVIDENCE_DIR" -type f -size +0c | LC_ALL=C sort > "$EVIDENCE_DIR/surviving-evidence.txt"
test -s "$EVIDENCE_DIR/surviving-evidence.txt"
ls -lh "$EVIDENCE_DIR"/*.stdout "$EVIDENCE_DIR"/*.stderr "$EVIDENCE_DIR"/*.exit
printf 'PASS evidence survives; recorded container and run label absent; no published ports\n'
```

An evidence-copy failure is not permission to leave the container running: preserve available host transcripts and remove the verified owned ID, then report the missing artifacts. Never remove evidence or prune Docker globally.

## Helpers

Only `.agents/skills/verify-bootstrap/scripts/inside.sh` is shipped; it is executable and invoked explicitly through Bash inside Docker in both Drive blocks. Modes are `help`, `offline`, `edges`, and `roundtrip --tools just`. It refuses a missing container marker and never launches host commands. No host wrapper is required.

Validate the feature map after changes:

```bash
agentic feature-map-lint .agents/skills/verify-bootstrap/features
```

Use `maintain-verification` when commands, options, platform support, or proof conventions change. Known coverage gaps are tracked in the feature map, not silently promoted to passes.
