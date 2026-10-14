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

# A retired codex selection undoes only the links into agent-kit's removed codex/ directory, restoring
# what they replaced. Its skill links, wrapper link, Bun package, and owned files stay for uninstall.
# A failure to undo them warns, keeps the selection, and does not fail link; the next run retries.
mkdir -p "$home/.codex" "$root/tools/bun/install/global/node_modules/@openai/codex" "$home/.agents/skills"
printf 'user agents\n' >"$home/.codex/AGENTS.md.bootstrap-backup"
printf 'model = "mine"\n' >"$home/.codex/config.toml"
ln -s "$root/tools/agent-kit/codex/AGENTS.md" "$home/.codex/AGENTS.md"
ln -s "$root/tools/agent-kit/codex/native-tools.md" "$home/.codex/native-tools.md"
ln -s "$root/tools/agent-kit/skills/mine" "$home/.agents/skills/mine"
ln -s "$root/repo/bin/codex" "$root/tools/bin/codex"
{
    printf 'link\t%s\t%s\n' "$home/.codex/AGENTS.md" "$home/.codex/AGENTS.md.bootstrap-backup"
    printf 'link\t%s\t-\n' "$home/.codex/native-tools.md"
    printf 'own\t%s\n' "$home/.codex/config.toml"
    printf 'dir\t%s\ndir\t%s\n' "$home/.agents" "$home/.agents/skills"
    printf 'link\t%s\t-\n' "$home/.agents/skills/mine"
    printf 'select\ttools\tcodex\n'
} >>"$root/state.tsv"
codex_selected() { grep -qxF 'select'$'\t''tools'$'\t''codex' "$root/state.tsv"; }
chmod a-w "$home/.codex"
link_kit >/dev/null 2>"$work/retire.err" || fail 'link failed when retiring codex failed'
chmod u+w "$home/.codex"
grep -q 'keeping the codex selection' "$work/retire.err" || fail 'a failed codex retirement did not warn'
codex_selected || fail 'a failed codex retirement dropped the selection'
link_kit >/dev/null 2>&1 || fail 'link with codex selected failed'
link_kit >/dev/null 2>&1 || fail 'relink after retiring codex failed'
if codex_selected; then fail 'the codex selection was kept'; fi
[[ ! -e "$home/.codex/native-tools.md" && ! -L "$home/.codex/native-tools.md" ]] || fail 'a codex agent-kit link was kept'
[[ ! -L "$home/.codex/AGENTS.md" && "$(cat "$home/.codex/AGENTS.md")" == 'user agents' ]] || fail 'the replaced AGENTS.md was not restored'
if grep -q "^link"$'\t'"$home/.codex/" "$root/state.tsv"; then fail 'a codex agent-kit link record was kept'; fi
[[ -L "$root/tools/bin/codex" ]] || fail 'retiring codex removed the wrapper link'
[[ -d "$root/tools/bun/install/global/node_modules/@openai/codex" ]] || fail 'retiring codex removed the Codex package'
[[ ! -e "$work/bun-removed" ]] || fail 'retiring codex ran bun remove'
[[ -L "$home/.agents/skills/mine" ]] || fail 'retiring codex removed a skill link'
[[ -f "$home/.codex/config.toml" ]] || fail 'retiring codex removed an owned file'

# A failed uninstall keeps its state, and a rerun completes it.
chmod a-w "$home/.bashrc"
if run uninstall --yes >/dev/null 2>&1; then fail 'uninstall ignored a failed step'; fi
[[ -f "$home/.local/share/bootstrap/state.tsv" ]] || fail 'failed uninstall lost its state'
chmod u+w "$home/.bashrc"
run uninstall --yes >/dev/null 2>&1 || fail 'rerun of uninstall failed'
[[ ! -e "$home/.local/share/bootstrap" ]] || fail 'root left behind'
[[ "$(cat "$home/.bashrc")" == 'user line' ]] || fail '.bashrc not restored'
[[ "$(cat "$home/.config/git/ignore")" == mine ]] || fail 'uninstall removed a user file'
[[ ! -e "$home/.agents" ]] || fail 'uninstall left the codex skill links'
[[ ! -e "$home/.codex/config.toml" ]] || fail 'uninstall left the owned codex config'
[[ "$(cat "$home/.codex/AGENTS.md")" == 'user agents' ]] || fail 'uninstall removed the restored AGENTS.md'
# Created by this test's fixtures, not by install.
rm "$home/.codex/AGENTS.md" && rmdir "$home/.codex" "$home/.claude/skills" "$home/.claude"
leftover="$(cd "$home" && find . -mindepth 1 ! -path ./.bashrc ! -path ./.config ! -path ./.config/git ! -path ./.config/git/ignore)"
[[ -z "$leftover" ]] || fail "uninstall left: $leftover"
printf 'PASS install link and uninstall edge cases\n'
