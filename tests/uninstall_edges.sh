#!/usr/bin/env bash
# Edge cases for install link and uninstall that the full round-trip does not reach. Uses the
# offline link command, so it needs no downloads; it does need a Node-compatible runtime.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
home="$work/home with space"
mkdir -p "$home"
run() { env -i HOME="$home" PATH="$PATH" TERM=dumb USER="${USER:-tester}" /bin/bash "$repo/install.sh" "$@"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

# A root that is HOME (or holds other files) is refused before anything is written.
if env -i HOME="$home" PATH="$PATH" BOOTSTRAP_ROOT="$home" /bin/bash "$repo/install.sh" link >/dev/null 2>&1; then fail 'HOME accepted as root'; fi
[[ -z "$(ls -A "$home")" ]] || fail 'refused root still wrote files'

# An unterminated block is reported and the file left exactly as it was.
printf 'user line\n# >>> bootstrap env >>>\nno end marker\n' >"$home/.bashrc"
cp "$home/.bashrc" "$work/bashrc.before"
if run link >/dev/null 2>&1; then fail 'unterminated block accepted'; fi
cmp -s "$home/.bashrc" "$work/bashrc.before" || fail 'unterminated block file changed'
printf 'user line\n' >"$home/.bashrc"
run uninstall --yes >/dev/null 2>&1

# A file the user puts in place of a bootstrap link survives reruns and uninstall.
run link >/dev/null
rm "$home/.config/git/ignore"
printf 'mine\n' >"$home/.config/git/ignore"
run link >/dev/null 2>&1
[[ "$(cat "$home/.config/git/ignore")" == mine ]] || fail 'rerun replaced a user file'

# A skill entry the user already has stays as it is, with no backup copy left in the skill directory.
kit="$work/agent-kit"
mkdir -p "$kit/codex" "$kit/skills/mine" "$kit/skills/theirs" "$home/.agents/skills" "$work/custom-skill"
printf '{}\n' >"$kit/package.json"
printf 'mine\ntheirs\n' >"$kit/codex/skills.txt"
touch "$kit/codex/AGENTS.md" "$kit/codex/native-tools.md" "$kit/skills/mine/SKILL.md" "$kit/skills/theirs/SKILL.md"
ln -s "$work/custom-skill" "$home/.agents/skills/theirs"
printf 'select\ttools\tcodex\n' >>"$home/.local/share/bootstrap/state.tsv"
env -i HOME="$home" PATH="$PATH" TERM=dumb USER="${USER:-tester}" BOOTSTRAP_AGENT_KIT="$kit" /bin/bash "$repo/install.sh" link >/dev/null 2>&1 || fail 'link with codex selected failed'
[[ "$(readlink "$home/.agents/skills/theirs")" == "$work/custom-skill" ]] || fail 'an existing skill link was replaced'
[[ "$(readlink "$home/.agents/skills/mine")" == "$home/.local/share/bootstrap/tools/agent-kit/skills/mine" ]] || fail 'a new skill was not linked'
[[ -z "$(find "$home/.agents/skills" -name '*.bootstrap-backup')" ]] || fail 'a backup was left in the skill directory'
rm "$home/.agents/skills/theirs"
# Undo the test selection so the uninstall below covers only what install recorded.
sed -i.bak '/^select\ttools\tcodex$/d' "$home/.local/share/bootstrap/state.tsv" && rm -f "$home/.local/share/bootstrap/state.tsv.bak"

# A failed uninstall keeps its state, and a rerun completes it.
chmod a-w "$home/.bashrc"
if run uninstall --yes >/dev/null 2>&1; then fail 'uninstall ignored a failed step'; fi
[[ -f "$home/.local/share/bootstrap/state.tsv" ]] || fail 'failed uninstall lost its state'
chmod u+w "$home/.bashrc"
run uninstall --yes >/dev/null 2>&1 || fail 'rerun of uninstall failed'
[[ ! -e "$home/.local/share/bootstrap" ]] || fail 'root left behind'
[[ "$(cat "$home/.bashrc")" == 'user line' ]] || fail '.bashrc not restored'
[[ "$(cat "$home/.config/git/ignore")" == mine ]] || fail 'uninstall removed a user file'
rmdir "$home/.agents/skills" "$home/.agents"  # created by this test's skill fixture, not by install
leftover="$(cd "$home" && find . -mindepth 1 ! -path ./.bashrc ! -path ./.config ! -path ./.config/git ! -path ./.config/git/ignore)"
[[ -z "$leftover" ]] || fail "uninstall left: $leftover"
printf 'PASS install link and uninstall edge cases\n'
