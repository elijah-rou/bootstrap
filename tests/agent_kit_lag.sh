#!/usr/bin/env bash
# bin/agent-kit-lag against a local agent-kit remote: the warning for each lag, silence otherwise,
# the background refresh of origin/main, and a hook that returns while a fetch hangs. No network.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid HOME="$work/home with space"
# A quote and a backslash in the root must not reach the JSON.
root="$HOME/.local/share/boot\"strap\\"
kit="$root/tools/agent-kit"
hook="$repo/bin/agent-kit-lag"
mkdir -p "$HOME" "$root/tools"

# The remote has three commits; the kit is installed at the first, as install_git leaves it.
git init --quiet --initial-branch=main "$work/remote"
for n in 1 2 3; do git -C "$work/remote" commit --quiet --allow-empty -m "commit $n"; done
first="$(git -C "$work/remote" rev-parse HEAD~2)"
second="$(git -C "$work/remote" rev-parse HEAD~1)"
main="$(git -C "$work/remote" rev-parse HEAD)"
git clone --quiet "$work/remote" "$kit"
git -C "$kit" -c advice.detachedHead=false checkout --quiet --detach "$first"
# Fresh stamp: no background refresh for the checks that do not test it.
touch "$kit/.git/bootstrap-kit-lag"
# Prints the hook's output after checking it is a single JSON object, or empty.
run_hook() {
    local output
    output="$("$hook" "$root")" || fail 'hook exited nonzero'
    if [[ -n "$output" ]]; then
        python3 -c 'import json, sys; assert isinstance(json.loads(sys.argv[1]), dict)' "$output" || fail "not hook JSON: $output"
    fi
    printf '%s' "$output"
}

# Behind: one JSON line with both commits and the advice to pin through scripts/pin-agent-kit from a
# bootstrap clone, never a path under the install root.
expected="{\"systemMessage\": \"agent-kit is 2 commits behind origin/main (installed ${first:0:7}, main ${main:0:7}). Run scripts/pin-agent-kit from a bootstrap clone to open the pin PR.\"}"
output="$(run_hook)"
[[ "$output" == "$expected" ]] || fail "behind printed: $output"

# One commit behind is singular.
git -C "$kit" -c advice.detachedHead=false checkout --quiet --detach "$second"
[[ "$(run_hook)" == *'is 1 commit behind'* ]] || fail 'one commit behind is not singular'

# Up to date, or ahead of the tracking ref: silent.
git -C "$kit" -c advice.detachedHead=false checkout --quiet --detach "$main"
[[ -z "$("$hook" "$root")" ]] || fail 'up to date printed a warning'

# No tracking ref, no checkout, or a linked development checkout: silent and successful.
git -C "$kit" update-ref -d refs/remotes/origin/main
[[ -z "$("$hook" "$root")" ]] || fail 'missing tracking ref printed a warning'
[[ -z "$("$hook" "$work/absent")" ]] || fail 'missing checkout printed a warning'
mv "$kit" "$work/dev-kit" && ln -s "$work/dev-kit" "$kit"
git -C "$work/dev-kit" update-ref refs/remotes/origin/main "$main"
git -C "$work/dev-kit" -c advice.detachedHead=false checkout --quiet --detach "$first"
[[ -z "$("$hook" "$root")" ]] || fail 'a linked development checkout was checked'
rm "$kit" && mv "$work/dev-kit" "$kit"

# A stale stamp starts a background fetch of origin/main; the session after it sees the new commit.
git -C "$kit" update-ref refs/remotes/origin/main "$main"
git -C "$kit" -c advice.detachedHead=false checkout --quiet --detach "$main"
git -C "$work/remote" commit --quiet --allow-empty -m 'commit 4'
touch -t 200001010000 "$kit/.git/bootstrap-kit-lag"
[[ -z "$("$hook" "$root")" ]] || fail 'the refreshing session printed before its fetch'
for _ in $(seq 50); do
    [[ "$(git -C "$kit" rev-parse refs/remotes/origin/main)" == "$main" ]] || break
    sleep 0.1
done
[[ "$(git -C "$kit" rev-parse refs/remotes/origin/main)" == "$(git -C "$work/remote" rev-parse HEAD)" ]] || fail 'background refresh did not update origin/main'
[[ "$("$hook" "$root")" == *'is 1 commit behind'* ]] || fail 'the next session did not warn about the fetched commit'
[[ -n "$(find "$kit/.git/bootstrap-kit-lag" -mmin -60)" ]] || fail 'refresh did not renew the stamp'

# A fetch that hangs in a transport child, as git-remote-https or ssh would: the hook still returns at
# once with its stdout closed, the fetch survives a kill of the hook's process group, and the watchdog
# kills the fetch and its transport child. The copy shortens the watchdog to two seconds.
mkdir -p "$work/stub"
cat >"$work/stub/git" <<STUB
#!/bin/sh
for a in "\$@"; do
    if [ "\$a" = fetch ]; then
        printf '%s|%s|%s|%s\\n' "\$GIT_TERMINAL_PROMPT" "\${GIT_ASKPASS-unset}" "\${SSH_ASKPASS-unset}" "\$GIT_SSH_COMMAND" >"$work/fetch.env"
        sleep 600 &
        echo \$! >"$work/transport.pid"
        echo \$\$ >"$work/fetch.pid"
        wait
        exit 1
    fi
done
exec $(command -v git) "\$@"
STUB
chmod +x "$work/stub/git"
sed 's/^fetch_seconds=30$/fetch_seconds=2/' "$hook" >"$work/agent-kit-lag"
grep -qx 'fetch_seconds=2' "$work/agent-kit-lag" || fail 'could not shorten the watchdog'
touch -t 200001010000 "$kit/.git/bootstrap-kit-lag"
start="$(date +%s)"
# Job control runs the hook in its own process group, which is killed once the hook returns.
output="$(set -m; PATH="$work/stub:$PATH" bash "$work/agent-kit-lag" "$root" & hook_pid=$!; wait "$hook_pid"
    for _ in $(seq 20); do [[ -s "$work/fetch.pid" ]] && break; sleep 0.1; done
    kill -TERM -- "-$hook_pid" 2>/dev/null || true)"
(( $(date +%s) - start <= 2 )) || fail 'hook waited for a hanging fetch'
[[ "$output" == *'is 1 commit behind'* ]] || fail "the warning did not precede the refresh: $output"
[[ -s "$work/fetch.pid" ]] || fail 'the hanging fetch never started'
[[ "$(cat "$work/fetch.env")" == "0|||ssh -oBatchMode=yes" ]] || fail "the fetch could prompt for credentials: $(cat "$work/fetch.env")"
fetch_pid="$(cat "$work/fetch.pid")"
transport_pid="$(cat "$work/transport.pid")"
sleep 0.2
kill -0 "$fetch_pid" 2>/dev/null || fail 'the fetch did not survive the hook process group'
for _ in $(seq 50); do
    if ! kill -0 "$fetch_pid" 2>/dev/null && ! kill -0 "$transport_pid" 2>/dev/null; then break; fi
    sleep 0.1
done
! kill -0 "$fetch_pid" 2>/dev/null || { kill "$fetch_pid" "$transport_pid"; fail 'watchdog left the hanging fetch running'; }
! kill -0 "$transport_pid" 2>/dev/null || { kill "$transport_pid"; fail 'watchdog left the transport child running'; }

printf 'PASS agent-kit-lag\n'
