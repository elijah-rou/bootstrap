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
root="$home/.local/share/bootstrap"
kit="$work/agent-kit"
mkdir -p "$kit/claude/mods/trial-tools" "$kit/skills/mine" "$kit/skills/theirs" "$home/.claude/skills" "$work/custom-skill"
printf '{}\n' >"$kit/package.json"
# Offline link never installs agent-kit's dependencies, even with a lockfile and no node_modules. Other bun
# commands go to the real Bun, which a Bun-backed node needs to render Claude's settings.
touch "$kit/bun.lock"
mkdir -p "$work/stub-bin"
real_bun="$(command -v bun || printf false)"
cat >"$work/stub-bin/bun" <<STUB
#!/bin/sh
case "\$1" in
    install) touch "$work/bun-called"; exit 1 ;;
    remove) printf '%s\\n' "\$*" >>"$work/bun-removed"; exit 0 ;;
esac
exec "$real_bun" "\$@"
STUB
chmod +x "$work/stub-bin/bun"
link_kit() {
    env -i HOME="$home" PATH="$work/stub-bin:$PATH" TERM=dumb USER="${USER:-tester}" BOOTSTRAP_AGENT_KIT="$kit" \
        CLAUDE_CONFIG_DIR="$home/.claude" /bin/bash "$repo/install.sh" link
}
printf 'skills/mine\nskills/theirs\n' >"$kit/claude/skills.txt"
touch "$kit/claude/CLAUDE.md" "$kit/skills/mine/SKILL.md" "$kit/skills/theirs/SKILL.md"
ln -s "$work/custom-skill" "$home/.claude/skills/theirs"
printf 'select\ttools\tclaude\n' >>"$root/state.tsv"
link_kit >/dev/null 2>&1 || fail 'link with claude selected failed'
[[ ! -e "$work/bun-called" ]] || fail 'offline link ran bun install'
[[ "$(readlink "$home/.claude/skills/theirs")" == "$work/custom-skill" ]] || fail 'an existing skill link was replaced'
[[ "$(readlink "$home/.claude/skills/mine")" == "$root/tools/agent-kit/skills/mine" ]] || fail 'a new skill was not linked'
[[ -z "$(find "$home/.claude/skills" -name '*.bootstrap-backup')" ]] || fail 'a backup was left in the skill directory'
rm "$home/.claude/skills/theirs"
# Undo the test selection so the uninstall below covers only what install recorded.
sed -i.bak '/^select\ttools\tclaude$/d' "$root/state.tsv" && rm -f "$root/state.tsv.bak"

# A retired codex selection loses its wrapper and Bun package once, and the link it made outside the
# root stays recorded, so the uninstall below removes it.
mkdir -p "$home/.codex" "$root/tools/bun/install/global/node_modules/@openai/codex"
ln -s "$root/tools/agent-kit/codex/AGENTS.md" "$home/.codex/AGENTS.md"
ln -s "$root/repo/bin/codex" "$root/tools/bin/codex"
printf 'dir\t%s\nlink\t%s\t-\nselect\ttools\tcodex\n' "$home/.codex" "$home/.codex/AGENTS.md" >>"$root/state.tsv"
link_kit >/dev/null 2>&1 || fail 'link with codex selected failed'
link_kit >/dev/null 2>&1 || fail 'relink after retiring codex failed'
if grep -qx 'select'$'\t''tools'$'\t''codex' "$root/state.tsv"; then fail 'the codex selection was kept'; fi
[[ ! -e "$root/tools/bin/codex" && ! -L "$root/tools/bin/codex" ]] || fail 'the codex wrapper was kept'
[[ "$(cat "$work/bun-removed")" == 'remove --global @openai/codex' ]] || fail 'the Codex package was not removed exactly once'
[[ -L "$home/.codex/AGENTS.md" ]] || fail 'retiring codex removed a recorded link before uninstall'
grep -qxF "link"$'\t'"$home/.codex/AGENTS.md"$'\t'"-" "$root/state.tsv" || fail 'retiring codex dropped a link record'

# A failed uninstall keeps its state, and a rerun completes it.
chmod a-w "$home/.bashrc"
if run uninstall --yes >/dev/null 2>&1; then fail 'uninstall ignored a failed step'; fi
[[ -f "$home/.local/share/bootstrap/state.tsv" ]] || fail 'failed uninstall lost its state'
chmod u+w "$home/.bashrc"
run uninstall --yes >/dev/null 2>&1 || fail 'rerun of uninstall failed'
[[ ! -e "$home/.local/share/bootstrap" ]] || fail 'root left behind'
[[ "$(cat "$home/.bashrc")" == 'user line' ]] || fail '.bashrc not restored'
[[ "$(cat "$home/.config/git/ignore")" == mine ]] || fail 'uninstall removed a user file'
[[ ! -e "$home/.codex" ]] || fail 'uninstall left the retired codex links'
rmdir "$home/.claude/skills" "$home/.claude"  # created by this test's skill fixture, not by install
leftover="$(cd "$home" && find . -mindepth 1 ! -path ./.bashrc ! -path ./.config ! -path ./.config/git ! -path ./.config/git/ignore)"
[[ -z "$leftover" ]] || fail "uninstall left: $leftover"
printf 'PASS install link and uninstall edge cases\n'
