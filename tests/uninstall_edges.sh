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

# Claude's git guard hook, rendered under this HOME with a space and run under sh -c from elsewhere as
# Claude runs it. With no guard in the kit it allows (exit 0, no output). With one, it runs bootstrap's
# own Bun, here a fixture that checks it got the kit and guard paths whole and denies a --no-verify
# commit (the round trip runs agent-kit's guard with the real Bun). Without that Bun the hook exits
# nonzero, which onFailure block turns into a refusal.
guard_command="$(node -e 'const settings = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const entry = (settings.hooks?.PreToolUse ?? []).find((entry) => entry.matcher === "Bash|Monitor|PowerShell");
    if (!entry) process.exit(1);
    console.log(entry.hooks[0].command);' "$home/.claude/settings.json")" || fail 'the rendered Claude settings have no git guard hook'
guard() { (cd / && printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | sh -c "$guard_command") 2>"$work/guard.err"; }
output="$(guard 'git commit --no-verify -m x')" && [[ -z "$output" ]] ||
    fail "the git guard without a kit guard did not allow: $output $(cat "$work/guard.err")"
mkdir -p "$kit/agentic/tools/git-guard" && touch "$kit/agentic/tools/git-guard/cli.ts"
cat >"$root/tools/bin/bun" <<FIXTURE
#!/bin/sh
[ "\$#" = 4 ] && [ "\$1" = --cwd ] && [ "\$2" = "$root/tools/agent-kit" ] && [ "\$3" = "$root/tools/agent-kit/agentic/tools/git-guard/cli.ts" ] &&
    [ "\$4" = --claude-hook ] && cd "\$2" && [ -f "\$3" ] || { echo "unexpected bun arguments: \$*" >&2; exit 1; }
if grep -q -- --no-verify; then echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}'; fi
exit 0
FIXTURE
chmod +x "$root/tools/bin/bun"
output="$(guard 'git commit --no-verify -m x')" || fail "the git guard failed under a root with a space: $(cat "$work/guard.err")"
[[ "$output" == *'"permissionDecision":"deny"'* ]] || fail "the git guard did not deny a --no-verify commit: $output"
output="$(guard 'git status')" && [[ -z "$output" ]] || fail "the git guard did not allow git status: $output $(cat "$work/guard.err")"
rm "$root/tools/bin/bun"
if guard 'git status' >/dev/null; then fail 'the git guard exited 0 without bootstrap Bun'; fi
rm -r "$kit/agentic"
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

# A recorded link whose target a new pin removed from the tools tree is undone and its record dropped,
# restoring what it replaced. An unrecorded dangling link, a recorded live link, and a recorded link
# dangling outside the tools tree stay. A run that fails prunes nothing; a prune that fails warns, keeps
# the record, and does not fail link.
skills="$home/.agents/skills"
mkdir -p "$skills/gone.bootstrap-backup"
printf 'user skill\n' >"$skills/gone.bootstrap-backup/SKILL.md"
ln -s "$root/tools/agent-kit/skills/gone" "$skills/gone"
ln -s "$root/tools/agent-kit/skills/also-gone" "$skills/also-gone"
ln -s "$root/tools/agent-kit/skills/gone" "$skills/stray"
ln -s "$root/repo/gone" "$skills/outside"
{
    printf 'link\t%s\t%s\n' "$skills/gone" "$skills/gone.bootstrap-backup"
    printf 'link\t%s\t-\n' "$skills/also-gone" "$skills/outside"
} >>"$root/state.tsv"
link_recorded() { grep -q "^link"$'\t'"$1"$'\t' "$root/state.tsv"; }
# A plain offline link removes the BOOTSTRAP_AGENT_KIT checkout link, so every recorded link into
# agent-kit dangles, then its step fails into FAILURES (not die) because no checkout is at the pin.
printf 'select\ttools\tclaude\n' >>"$root/state.tsv"
if env -i HOME="$home" PATH="$PATH" TERM=dumb CLAUDE_CONFIG_DIR="$home/.claude" /bin/bash "$repo/install.sh" link \
    >/dev/null 2>"$work/failed-run.err"; then fail 'link passed without an agent-kit checkout at the pin'; fi
grep -q 'configuration incomplete: claude' "$work/failed-run.err" || fail "the failed link run did not fail its step: $(cat "$work/failed-run.err")"
sed -i.bak '/^select\ttools\tclaude$/d' "$root/state.tsv" && rm -f "$root/state.tsv.bak"
[[ -L "$skills/gone" ]] && link_recorded "$skills/gone" || fail 'a failed link run pruned a dangling link'
[[ -L "$skills/mine" ]] && link_recorded "$skills/mine" || fail 'a failed link run pruned a link its checkout failure left dangling'
# Put back the checkout link the plain run removed, as install_git does for BOOTSTRAP_AGENT_KIT.
ln -s "$kit" "$root/tools/agent-kit"
chmod a-w "$skills"
link_kit >/dev/null 2>"$work/prune.err" || fail 'link failed when pruning failed'
chmod u+w "$skills"
grep -q 'could not undo every dangling link' "$work/prune.err" || fail 'a failed prune did not warn'
[[ -L "$skills/gone" ]] && link_recorded "$skills/gone" || fail 'a failed prune dropped its record'
link_kit >/dev/null 2>&1 || fail 'link with dangling links failed'
[[ ! -L "$skills/gone" && "$(cat "$skills/gone/SKILL.md")" == 'user skill' ]] || fail 'the replaced skill was not restored'
[[ ! -e "$skills/also-gone" && ! -L "$skills/also-gone" ]] || fail 'a recorded dangling link was kept'
if link_recorded "$skills/gone" || link_recorded "$skills/also-gone"; then fail 'a pruned link kept its record'; fi
[[ "$(readlink "$skills/stray")" == "$root/tools/agent-kit/skills/gone" ]] || fail 'an unrecorded dangling link was removed'
[[ "$(readlink "$skills/outside")" == "$root/repo/gone" ]] && link_recorded "$skills/outside" ||
    fail 'a recorded link dangling outside the tools tree was pruned'
[[ -L "$skills/mine" && -e "$skills/mine" ]] && link_recorded "$skills/mine" || fail 'a recorded live link was pruned'
# Created by this test's fixtures, not by install.
rm -r "$skills/gone" "$skills/stray"

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
