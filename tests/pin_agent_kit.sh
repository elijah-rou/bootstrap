#!/usr/bin/env bash
# scripts/pin-agent-kit against local remotes: a fake agent-kit, a fake bootstrap origin, and a gh
# stub that records its calls. No network and no push beyond the fake origin.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid HOME="$work/home"
mkdir -p "$HOME"

# agent-kit: main has an old and a new role; a side branch holds a commit main never reaches.
kit="$work/agent-kit"
git init --quiet --initial-branch=main "$kit"
mkdir -p "$kit/claude/agents"
role_text() {
    printf -- '---\nname: autopilot-owner\nmodel: claude-opus-5-5\n---\n\n%s Report code-ready, and escalate anything outside the brief in your report.\n' "$1"
}
role_text 'Old charter.' >"$kit/claude/agents/autopilot-owner.md"
git -C "$kit" add -A && git -C "$kit" commit --quiet -m 'Old charter (#1)'
old="$(git -C "$kit" rev-parse HEAD)"
role_text 'New charter.' >"$kit/claude/agents/autopilot-owner.md"
git -C "$kit" commit --quiet -am 'New charter (#2)'
new="$(git -C "$kit" rev-parse HEAD)"
git -C "$kit" checkout --quiet -b side
git -C "$kit" commit --quiet --allow-empty -m 'Unmerged'
side="$(git -C "$kit" rev-parse HEAD)"
git -C "$kit" checkout --quiet main

# bootstrap: the scripts under test, a catalog pinning the old commit, the Pi role, and a stub
# validate that records where it ran and fails on request.
seed="$work/seed"
mkdir -p "$seed/scripts" "$seed/pi/agents"
cp "$repo/scripts/pin" "$repo/scripts/pin-agent-kit" "$seed/scripts/"
printf '#!/usr/bin/env bash\nset -eu\npwd >>"$PIN_TEST_VALIDATED"\n[ ! -e "$PIN_TEST_VALIDATED.fail" ]\n' >"$seed/scripts/validate"
chmod +x "$seed/scripts/validate"
printf '# catalog\n#name\tgroups\tversion\tplatform\tsha256\tsource\tbins\nagent-kit\tinternal\t%s\tany\t-\tgit:%s\t-\n' "$old" "$kit" >"$seed/catalog.tsv"
printf -- '---\nname: autopilot-owner\ntools: read, contact_supervisor\n---\n\nOld charter. Report code-ready, and escalate anything outside the brief through the supervisor.\n' >"$seed/pi/agents/autopilot-owner.md"
git init --quiet --initial-branch=main "$seed"
git -C "$seed" add -A && git -C "$seed" commit --quiet -m 'Seed'
git clone --quiet --bare "$seed" "$work/origin.git"
checkout="$work/checkout"
git clone --quiet "$work/origin.git" "$checkout"
script="$checkout/scripts/pin-agent-kit"
export PIN_TEST_VALIDATED="$work/validated"

# gh stub: `pr list` prints $work/open-pr, `pr create` saves its body and prints a URL.
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/gh.log"
case "\$1 \$2" in
    'pr list') cat "$work/open-pr" 2>/dev/null; exit 0 ;;
    'pr create')
        while [[ \$# -gt 0 ]]; do [[ "\$1" == --body-file ]] && cp "\$2" "$work/pr-body.md"; shift; done
        printf 'Creating pull request\nhttps://github.invalid/bootstrap/pull/7\n' ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH"
branch="agent/pin-agent-kit-${new:0:12}"
remote_branch() { git -C "$work/origin.git" rev-parse --verify --quiet "refs/heads/$1" || true; }
worktrees() { git -C "$checkout" worktree list --porcelain | grep -c '^worktree '; }

# Usage errors and commits main does not reach: exit 2, nothing pushed, no GitHub call.
for argument in abc "${new:0:12}" "${new}0" --bogus; do
    status=0; "$script" "$argument" >/dev/null 2>&1 || status=$?
    [[ "$status" == 2 ]] || fail "argument $argument exited $status, not 2"
done
for argument in "$side" 0123456789012345678901234567890123456789; do
    status=0; "$script" "$argument" >/dev/null 2>"$work/err" || status=$?
    [[ "$status" == 2 ]] || fail "unreachable $argument exited $status, not 2"
    grep -q 'not a commit reachable' "$work/err" || fail "unreachable $argument: $(cat "$work/err")"
done
status=0; "$script" "$new" extra >/dev/null 2>&1 || status=$?
[[ "$status" == 2 ]] || fail "two commits exited $status, not 2"

# The pinned commit is current: exit 0, no branch, no GitHub call.
output="$("$script" "$old")" || fail 'current pin exited nonzero'
[[ "$output" == "agent-kit pin is current: origin/main pins $old" ]] || fail "current pin printed: $output"
output="$("$script" "$(tr a-f A-F <<<"$old")")" || fail 'uppercase current pin exited nonzero'
[[ "$output" == "agent-kit pin is current: origin/main pins $old" ]] || fail "uppercase current pin printed: $output"
[[ ! -e "$work/gh.log" ]] || fail 'current pin called gh'

# Dry run: the diff summary, validate in a temporary worktree, then no commit, push, or worktree.
output="$("$script" --dry-run)" || fail 'dry run exited nonzero'
[[ "$output" == *'catalog.tsv'* && "$output" == *'pi/agents/autopilot-owner.md'* ]] || fail "dry run summary: $output"
[[ "$output" == *"Dry run: would commit \"Pin agent-kit ${new:0:12}\""* ]] || fail "dry run tail: $output"
[[ -s "$PIN_TEST_VALIDATED" ]] || fail 'dry run did not validate'
[[ "$(cat "$PIN_TEST_VALIDATED")" != "$checkout" ]] || fail 'validate ran in the checkout, not a worktree'
[[ -z "$(remote_branch "$branch")" ]] || fail 'dry run pushed'
[[ ! -e "$work/gh.log" ]] || fail 'dry run called gh'
[[ "$(worktrees)" == 1 ]] || fail 'dry run left a worktree'
[[ -z "$(git -C "$checkout" status --porcelain)" ]] || fail 'dry run changed the checkout'

# A failing validate stops before the commit.
touch "$PIN_TEST_VALIDATED.fail"
status=0; "$script" >/dev/null 2>"$work/err" || status=$?
[[ "$status" == 1 ]] || fail "failing validate exited $status"
grep -q 'nothing was committed or pushed' "$work/err" || fail "failing validate: $(cat "$work/err")"
[[ -z "$(remote_branch "$branch")" ]] || fail 'failing validate pushed'
[[ "$(worktrees)" == 1 ]] || fail 'failing validate left a worktree'
rm "$PIN_TEST_VALIDATED.fail"

# The real run with no argument pins agent-kit's main.
: >"$work/gh.log"
output="$("$script")" || fail 'pin exited nonzero'
[[ "${output##*$'\n'}" == https://github.invalid/bootstrap/pull/7 ]] || fail "last line is not the URL: $output"
head="$(remote_branch "$branch")"
[[ -n "$head" ]] || fail "no $branch on origin"
[[ "$(git -C "$work/origin.git" log -1 --format=%s "$head")" == "Pin agent-kit ${new:0:12}" ]] || fail 'commit subject'
[[ "$(git -C "$work/origin.git" rev-parse "$head^")" == "$(git -C "$work/origin.git" rev-parse main)" ]] || fail 'not one commit on origin/main'
[[ "$(git -C "$work/origin.git" diff --name-only "$head^" "$head" | tr '\n' ' ')" == 'catalog.tsv pi/agents/autopilot-owner.md ' ]] || fail 'changed files'
git -C "$work/origin.git" show "$head:catalog.tsv" | grep -q "^agent-kit	internal	$new	" || fail 'catalog does not pin the new commit'
expected="$(printf -- '---\nname: autopilot-owner\ntools: read, contact_supervisor\n---\n\nNew charter. Report code-ready, and escalate anything outside the brief through the supervisor.')"
[[ "$(git -C "$work/origin.git" show "$head:pi/agents/autopilot-owner.md")" == "$expected" ]] || fail 'Pi role not synced'
grep -q -- "--head $branch --title Pin agent-kit ${new:0:12}" "$work/gh.log" || fail "gh pr create: $(cat "$work/gh.log")"
for section in '## Why' '## What changed' '## Verification' '## Revert' "${new:0:7} New charter (#2)"; do
    grep -qF -- "$section" "$work/pr-body.md" || fail "PR body lacks $section"
done
! grep -q 'merge' "$work/gh.log" || fail 'pin called gh pr merge'
[[ "$(worktrees)" == 1 ]] || fail 'pin left a worktree'
[[ -z "$(git -C "$checkout" branch --list 'agent/*')" ]] || fail 'pin left a local branch'

# An open pull request on the branch is reused: its URL, no new push.
printf 'https://github.invalid/bootstrap/pull/7\n' >"$work/open-pr"
output="$("$script" "$new")" || fail 'reuse exited nonzero'
[[ "${output##*$'\n'}" == https://github.invalid/bootstrap/pull/7 ]] || fail "reuse printed: $output"
[[ "$(remote_branch "$branch")" == "$head" ]] || fail 'reuse pushed'
rm "$work/open-pr"

# A pushed branch with no open pull request: validate it and open the pull request, never rewrite it.
: >"$work/gh.log" && : >"$PIN_TEST_VALIDATED"
output="$("$script")" || fail 'resume exited nonzero'
[[ "${output##*$'\n'}" == https://github.invalid/bootstrap/pull/7 ]] || fail "resume printed: $output"
[[ "$(remote_branch "$branch")" == "$head" ]] || fail 'resume rewrote the branch'
grep -q '^pr create' "$work/gh.log" || fail 'resume did not open the pull request'
[[ -s "$PIN_TEST_VALIDATED" ]] || fail 'resume did not validate the pushed branch'
grep -qF 'body synced from agent-kit' "$work/pr-body.md" || fail 'resume body misses the role change'

# A branch of that name that pins something else is left alone.
git -C "$work/origin.git" update-ref "refs/heads/$branch" main
status=0; "$script" >/dev/null 2>"$work/err" || status=$?
[[ "$status" == 1 ]] && grep -q 'does not pin' "$work/err" || fail "foreign branch: $status $(cat "$work/err")"
git -C "$work/origin.git" update-ref -d "refs/heads/$branch"

# Once origin/main pins agent-kit's main, a run with no argument is current.
git -C "$work/origin.git" update-ref refs/heads/main "$head"
output="$("$script")" || fail 'current main exited nonzero'
[[ "$output" == "agent-kit pin is current: origin/main pins $new" ]] || fail "current main printed: $output"
output="$("$script" "$old")" || fail 'older commit exited nonzero'
[[ "$output" == "agent-kit pin is current: origin/main pins $new, which contains $old" ]] || fail "older commit printed: $output"
[[ "$(worktrees)" == 1 ]] || fail 'older commit left a worktree'

# An agent-kit role without the escalation line stops the run instead of dropping the Pi wording.
printf -- '---\nname: autopilot-owner\n---\n\nReworded.\n' >"$kit/claude/agents/autopilot-owner.md"
git -C "$kit" commit --quiet -am 'Reword'
status=0; "$script" --dry-run >/dev/null 2>"$work/err" || status=$?
[[ "$status" == 1 ]] && grep -q 'update the Pi substitution' "$work/err" || fail "reworded role: $status $(cat "$work/err")"
[[ "$(worktrees)" == 1 ]] || fail 'reworded role left a worktree'

printf 'PASS pin-agent-kit\n'
