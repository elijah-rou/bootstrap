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
root="$HOME/.local/share/bootstrap"
kit="$root/tools/agent-kit"
hook="$repo/bin/agent-kit-lag"
mkdir -p "$HOME" "$root/repo" "$root/tools"

# The remote has three commits; the kit is installed at the first, as install_git leaves it.
git init --quiet --initial-branch=main "$work/remote"
for n in 1 2 3; do git -C "$work/remote" commit --quiet --allow-empty -m "commit $n"; done
first="$(git -C "$work/remote" rev-parse HEAD~2)"
second="$(git -C "$work/remote" rev-parse HEAD~1)"
main="$(git -C "$work/remote" rev-parse HEAD)"
git clone --quiet "$work/remote" "$kit"
git -C "$kit" -c advice.detachedHead=false checkout --quiet --detach "$first"
pin() { printf 'agent-kit\tinternal\t%s\tany\t-\tgit:%s\t-\n' "$1" "$work/remote" >"$root/repo/catalog.tsv"; }
pin "$first"
# Fresh stamp: no background refresh for the checks that do not test it.
touch "$kit/.git/bootstrap-kit-lag"

# Behind with bootstrap still pinning the installed commit: one JSON line naming the pin command.
output="$("$hook" "$root")" || fail 'hook exited nonzero'
expected="{\"systemMessage\": \"agent-kit is 2 commits behind origin/main (installed ${first:0:7}, main ${main:0:7}). Update: cd ~/.local/share/bootstrap/repo && scripts/pin agent-kit $main && ./install.sh\"}"
[[ "$output" == "$expected" ]] || fail "behind with an unchanged pin printed: $output"
python3 -c 'import json, sys; json.loads(sys.argv[1])' "$output" || fail 'warning is not valid JSON'

# Behind with a newer pin in the catalog: install.sh alone updates.
pin "$second"
output="$("$hook" "$root")"
[[ "$output" == *'2 commits behind'*'Update: ~/.local/share/bootstrap/repo/install.sh"}' ]] || fail "behind with a newer pin printed: $output"

# One commit behind is singular.
git -C "$kit" -c advice.detachedHead=false checkout --quiet --detach "$second"
pin "$second"
[[ "$("$hook" "$root")" == *'is 1 commit behind'* ]] || fail 'one commit behind is not singular'

# A catalog pin older than the installed commit: install.sh would go back, so the pin must move.
pin "$first"
[[ "$("$hook" "$root")" == *"Update: cd ~/.local/share/bootstrap/repo && scripts/pin agent-kit $main && ./install.sh\"}" ]] ||
    fail 'an older pin recommended install.sh'

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

# A fetch that hangs: the hook still returns at once with its stdout closed, the fetch survives a
# kill of the hook's process group, and the watchdog kills it. The copy shortens the watchdog to two seconds.
mkdir -p "$work/stub"
printf '#!/bin/sh\nfor a in "$@"; do if [ "$a" = fetch ]; then echo $$ >"%s/fetch.pid"; exec sleep 600; fi; done\nexec %s "$@"\n' \
    "$work" "$(command -v git)" >"$work/stub/git"
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
fetch_pid="$(cat "$work/fetch.pid")"
sleep 0.2
kill -0 "$fetch_pid" 2>/dev/null || fail 'the fetch did not survive the hook process group'
for _ in $(seq 50); do kill -0 "$fetch_pid" 2>/dev/null || break; sleep 0.1; done
! kill -0 "$fetch_pid" 2>/dev/null || { kill "$fetch_pid"; fail 'watchdog left the hanging fetch running'; }

printf 'PASS agent-kit-lag\n'
