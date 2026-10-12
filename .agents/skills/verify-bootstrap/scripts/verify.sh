#!/usr/bin/env bash
# Host control for bootstrap's container verification. Every installer command runs as the unprivileged
# tester inside a container this run owns; nothing installs on the host. See ../SKILL.md.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: verify.sh COMMAND [ARGS]

Commands:
  launch [--network none|bridge]   Start a run-owned container and print RUN_ID and EVIDENCE_DIR.
                                   none (default) is the offline baseline; bridge allows downloads.
  doctor RUN_ID                    Read-only check of ownership, image, source bytes, account,
                                   prerequisites, read-only mount, and ports. Required before drive.
  drive [--timeout SECONDS] RUN_ID TARGET...
                                   Drive features in order, stopping at the first failure.
  drive [--timeout SECONDS] RUN_ID install [-- SELECTION...]
                                   Real download round trip. SELECTION defaults to --tools just;
                                   a bare -- installs core tools only.
  cleanup RUN_ID                   Export /proof, then remove only this run's container. Run it even
                                   after a failure.
  help, --help, -h                 Show this help.

Targets (one per feature in features/):
  help        help.md        none     --help, -h, invalid selections leave no changes
  link        link.md        none     link, convergent relink, user-file and unsafe-root edges
  doctor      doctor.md      none     product doctor reports missing tools after offline link
  uninstall   uninstall.md   none     refusal without --yes, confirmed/repeated uninstall, recovery
  install     install.md     bridge   install, rerun, relink, installed doctor, shell use, uninstall

Each target has a 180-second deadline unless --timeout says otherwise, and may run once per run.
Evidence for a run lives in local/verification/bootstrap/RUN_ID/: drive-TARGET.command, .stdout, .stderr,
.exit, and artifacts/TARGET/ exported from the container.

Example:
  verify.sh launch                      # prints RUN_ID=run-...
  verify.sh doctor RUN_ID
  verify.sh drive RUN_ID help link doctor uninstall
  verify.sh cleanup RUN_ID
EOF
}

fail_usage() { printf 'verify.sh: %s\nRun verify.sh --help for usage.\n' "$*" >&2; exit 2; }
die() { printf 'verify.sh: %s\n' "$*" >&2; exit 1; }

repo="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
runs="$repo/local/verification/bootstrap"
image=node:24-bookworm
label=bootstrap.verify.run
helper=/src/.agents/skills/verify-bootstrap/scripts/inside.sh
sources=(install.sh catalog.tsv tests/roundtrip.sh tests/uninstall_edges.sh
    .agents/skills/verify-bootstrap/scripts/inside.sh .agents/skills/verify-bootstrap/scripts/verify.sh)
as_tester=(docker exec -u tester -e HOME=/var/tmp/tester)

target_network() {
    case "$1" in
        help | link | doctor | uninstall) printf 'none\n' ;;
        install) printf 'bridge\n' ;;
        *) return 1 ;;
    esac
}

# Sets run, evidence, and cid for RUN_ID, refusing anything this checkout did not launch.
load_run() {
    run="${1:-}"
    [[ "$run" =~ ^run-[0-9A-Za-z-]+$ ]] || fail_usage "expected a RUN_ID printed by launch, got '${run}'"
    evidence="$runs/$run"
    [[ -d "$evidence" ]] || die "no evidence directory $evidence"
    cid=""
    [[ -f "$evidence/container.id" ]] && IFS= read -r cid <"$evidence/container.id" || true
    [[ -n "$cid" ]] || die "$run recorded no container ID; remove nothing by guessed name"
}

owned_and_running() {
    [[ "$(docker inspect -f "{{index .Config.Labels \"$label\"}}" "$cid")" == "$run" ]] || die "container $cid is not labeled $label=$run"
    [[ "$(docker inspect -f '{{.State.Running}}' "$cid")" == true ]] || die "container $cid is not running"
}

# Writes PHASE.exit when the shell exits, and reports failures on the saved terminal stderr (fd 4).
record_exit() {
    local status=$?
    printf '%s\n' "$status" >"$evidence/$phase.exit"
    if [[ "$status" != 0 ]]; then
        printf 'FAIL %s (exit %s): see %s/%s.stdout and %s.stderr\n' "$phase" "$status" "$evidence" "$phase" "$phase" >&4
    fi
}

cmd_launch() {
    local network=none
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --network) [[ $# -ge 2 ]] || fail_usage "--network needs none or bridge"; network="$2"; shift 2 ;;
            *) fail_usage "unknown launch argument '$1'" ;;
        esac
    done
    [[ "$network" == none || "$network" == bridge ]] || fail_usage "--network must be none or bridge"
    mkdir -p "$runs"
    run="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    evidence="$runs/$run"
    mkdir "$evidence"   # never reuse another run's evidence
    printf 'RUN_ID=%s\nEVIDENCE_DIR=%s\n' "$run" "$evidence"
    git -C "$repo" check-ignore -q "$evidence" || die "$evidence is not git-ignored"
    git -C "$repo" rev-parse HEAD >"$evidence/revision.txt"
    git -C "$repo" diff -- install.sh catalog.tsv tests .agents/skills/verify-bootstrap >"$evidence/product.diff"
    (cd "$repo" && shasum -a 256 "${sources[@]}") >"$evidence/source.sha256"
    docker image inspect "$image" >"$evidence/image.json"
    docker image inspect -f '{{.Id}}' "$image" >"$evidence/image.id"
    docker run -d --init --name "verify-bootstrap-$run" \
        --label "$label=$run" --cidfile "$evidence/container.id" \
        --network "$network" --mount "type=bind,src=$repo,dst=/src,readonly" -w /src \
        -e BOOTSTRAP_VERIFY_CONTAINER=1 -e LC_ALL=C -e TERM=dumb \
        "$image" bash -euc 'useradd --create-home --home-dir /var/tmp/tester tester; mkdir /proof; chown tester:tester /proof; bash -n /src/install.sh; printf "READY bootstrap verifier\n"; exec sleep infinity' \
        >"$evidence/launch.stdout" 2>"$evidence/launch.stderr" || die "docker run failed; see $evidence/launch.stderr"
    load_run "$run"
    local ready=0 i
    for ((i = 0; i < 60; i++)); do
        docker logs "$cid" >"$evidence/readiness.stdout" 2>"$evidence/readiness.stderr"
        if grep -qx 'READY bootstrap verifier' "$evidence/readiness.stdout"; then ready=1; break; fi
        sleep 1
    done
    [[ "$ready" == 1 ]] || die "container not ready within 60 seconds; see $evidence/readiness.*; run cleanup $run"
    docker inspect "$cid" >"$evidence/container.json"
    printf 'READY %s (network %s); next: verify.sh doctor %s\n' "$run" "$network" "$run"
}

cmd_doctor() {
    [[ $# -eq 1 ]] || fail_usage "doctor takes exactly one RUN_ID"
    load_run "$1"
    [[ ! -e "$evidence/doctor.exit" ]] || die "doctor already ran for $run; launch a new run"
    phase=doctor
    exec 4>&2
    trap record_exit EXIT
    {
        owned_and_running
        test "$(docker inspect -f '{{len .HostConfig.PortBindings}}' "$cid")" = 0
        test "$(docker inspect -f '{{range .Mounts}}{{.Destination}}:{{.RW}}{{end}}' "$cid")" = /src:false
        docker inspect -f '{{.Image}}' "$cid" >"$evidence/doctor-image.id"
        cmp "$evidence/image.id" "$evidence/doctor-image.id"
        "${as_tester[@]}" "$cid" bash -euc 'test "$HOME" = /var/tmp/tester; test -w "$HOME"; test -w /proof; for c in git curl tar gzip xz unzip node timeout; do command -v "$c" >/dev/null; done; getconf GNU_LIBC_VERSION; bash -n /src/install.sh'
        docker exec -u tester "$cid" sha256sum "${sources[@]}" >"$evidence/doctor-source.sha256"
        cmp "$evidence/source.sha256" "$evidence/doctor-source.sha256"
        printf 'PASS owned container, exact image/source, isolated account, prerequisites, no ports\n'
    } >"$evidence/doctor.stdout" 2>"$evidence/doctor.stderr"
    cat "$evidence/doctor.stdout"
}

# Runs one target's helper mode, exports its /proof directory, and requires exit 0 and its PASS line.
drive_target() {
    local target="$1" timeout="$2"; shift 2
    local want network status
    want="$(target_network "$target")" || fail_usage "unknown target '$target'"
    network="$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$cid")"
    [[ "$network" == "$want" ]] || die "target $target needs a --network $want run; $run uses $network"
    [[ ! -e "$evidence/drive-$target.exit" ]] || die "$target already ran for $run; launch a new run"
    local argv=("${as_tester[@]}" "$cid" timeout --signal=TERM --kill-after=10s "${timeout}s" bash -x "$helper" "$target" "$@")
    printf '%q ' "${argv[@]}" >"$evidence/drive-$target.command"
    printf '\n' >>"$evidence/drive-$target.command"
    printf 'DRIVE %s ...\n' "$target"
    if "${argv[@]}" >"$evidence/drive-$target.stdout" 2>"$evidence/drive-$target.stderr"; then status=0; else status=$?; fi
    printf '%s\n' "$status" >"$evidence/drive-$target.exit"
    mkdir -p "$evidence/artifacts"
    docker cp "$cid:/proof/$target" "$evidence/artifacts/$target" >/dev/null 2>"$evidence/drive-$target.export.stderr" \
        || printf 'warning: could not export /proof/%s; see %s/%s.export.stderr\n' "$target" "$evidence" "$target" >&2
    if [[ "$status" != 0 ]]; then
        [[ "$status" != 124 ]] || printf 'timeout: %s exceeded %s seconds; incomplete, not a pass\n' "$target" "$timeout" >&2
        die "FAIL $target (exit $status): see $evidence/drive-$target.stdout and drive-$target.stderr; run cleanup $run, fix, and launch a new run"
    fi
    grep "^PASS $target: " "$evidence/drive-$target.stdout" || die "FAIL $target: exit 0 without its PASS line; see $evidence/drive-$target.stdout"
}

cmd_drive() {
    local timeout=180
    if [[ "${1:-}" == --timeout ]]; then
        [[ "${2:-}" =~ ^[1-9][0-9]{0,3}$ ]] || fail_usage "--timeout needs whole seconds between 1 and 9999"
        timeout="$2"; shift 2
    fi
    [[ $# -ge 2 ]] || fail_usage "drive needs a RUN_ID and at least one target"
    load_run "$1"; shift
    [[ -e "$evidence/doctor.exit" ]] || die "doctor has not run for $run; run verify.sh doctor $run first"
    [[ "$(cat "$evidence/doctor.exit")" == 0 ]] || die "doctor failed for $run; run cleanup $run and launch a new run"
    owned_and_running
    if [[ "$1" == install ]]; then
        shift
        local selection=(--tools just) arg
        if [[ $# -gt 0 ]]; then
            [[ "$1" == -- ]] || fail_usage "install takes its selection after --, for example: install -- --tools just"
            shift
            selection=("$@")
            for arg in ${selection[@]+"${selection[@]}"}; do
                [[ "$arg" =~ ^[-A-Za-z0-9._+]+$ ]] || fail_usage "unexpected selection argument '$arg'"
            done
        fi
        drive_target install "$timeout" ${selection[@]+"${selection[@]}"}
        return
    fi
    local target
    for target in "$@"; do
        [[ "$target" != install ]] || fail_usage "install needs its own bridge run and drive call"
        target_network "$target" >/dev/null || fail_usage "unknown target '$target'"
    done
    for target in "$@"; do drive_target "$target" "$timeout"; done
}

cmd_cleanup() {
    [[ $# -eq 1 ]] || fail_usage "cleanup takes exactly one RUN_ID"
    load_run "$1"
    local present
    present="$(docker ps -aq --no-trunc --filter "id=$cid")"
    if [[ -n "$present" ]]; then
        [[ "$(docker inspect -f "{{index .Config.Labels \"$label\"}}" "$cid")" == "$run" ]] || die "container $cid is not labeled $label=$run; removing nothing"
        # A failed export is not permission to leave the container running.
        docker cp "$cid:/proof/." "$evidence/cleanup-artifacts" >/dev/null 2>"$evidence/cleanup-export.stderr" \
            || printf 'warning: /proof export failed; see %s/cleanup-export.stderr\n' "$evidence" >&2
        docker top "$cid" >"$evidence/processes-before-cleanup.txt" 2>&1 || true
        docker logs "$cid" >"$evidence/container.log" 2>&1 || true
        docker rm -f "$cid" >"$evidence/cleanup.stdout"
        test -s "$evidence/cleanup.stdout"
    else
        printf 'container %s was already removed\n' "$cid"
    fi
    docker ps -aq --no-trunc >"$evidence/remaining-container-ids.txt"
    ! grep -qxF "$cid" "$evidence/remaining-container-ids.txt" || die "container $cid still exists"
    docker ps -aq --filter "label=$label=$run" >"$evidence/remaining-run-containers.txt"
    [[ ! -s "$evidence/remaining-run-containers.txt" ]] || die "containers labeled $label=$run remain"
    find "$evidence" -type f -size +0c | LC_ALL=C sort >"$evidence/surviving-evidence.txt"
    test -s "$evidence/surviving-evidence.txt"
    printf 'PASS cleanup: container and run label absent; evidence kept in %s\n' "$evidence"
}

[[ $# -gt 0 ]] || { usage >&2; exit 2; }
subcommand="$1"; shift
case "$subcommand" in
    launch) cmd_launch "$@" ;;
    doctor) cmd_doctor "$@" ;;
    drive) cmd_drive "$@" ;;
    cleanup) cmd_cleanup "$@" ;;
    help | --help | -h) usage ;;
    *) fail_usage "unknown command '$subcommand'" ;;
esac
