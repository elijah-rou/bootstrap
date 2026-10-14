#!/usr/bin/env bash
# Edge cases for install link and uninstall that the full round-trip does not reach. Uses the
# offline link command, so it needs no downloads; it does need a Node-compatible runtime.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
home="$work/home with space"
mkdir -p "$home" "$work/stub-bin"
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

# security and launchctl are always stubs, so no run reaches this machine's keychain or launchd. Each logs
# its arguments; the keychain item exists while $work/keychain does, and launchctl tracks loaded labels.
# uname reports STUB_KERNEL when it is set, so both platforms' paths run on either host; a stubbed Linux
# also needs getconf to report glibc.
real_uname="$(command -v uname)"
real_getconf="$(command -v getconf || printf false)"
cat >"$work/stub-bin/security" <<STUB
#!/bin/sh
printf '%s\\n' "\$*" >>"$work/security.log"
case "\$1" in find-generic-password) ;; *) exit 0 ;; esac
[ -f "$work/keychain" ] || exit 44
case " \$* " in *" -w "*) cat "$work/keychain" ;; *) printf 'keychain: "login.keychain-db"\\n' ;; esac
STUB
cat >"$work/stub-bin/launchctl" <<STUB
#!/bin/sh
printf '%s\\n' "\$*" >>"$work/launchctl.log"
mkdir -p "$work/loaded"
case "\$1" in
    print) [ -e "$work/loaded/\${2##*/}" ] || exit 113 ;;
    bootstrap) label="\${3##*/}"; touch "$work/loaded/\${label%.plist}" ;;
    bootout) [ -e "$work/loaded/\${2##*/}" ] || exit 3; rm "$work/loaded/\${2##*/}" ;;
esac
STUB
cat >"$work/stub-bin/uname" <<STUB
#!/bin/sh
[ -n "\${STUB_KERNEL:-}" ] || exec "$real_uname" "\$@"
case "\$1" in -s) echo "\$STUB_KERNEL" ;; -m) if [ "\$STUB_KERNEL" = Darwin ]; then echo arm64; else "$real_uname" -m; fi ;; *) exec "$real_uname" "\$@" ;; esac
STUB
cat >"$work/stub-bin/getconf" <<STUB
#!/bin/sh
if [ "\${STUB_KERNEL:-}" = Linux ] && [ "\$1" = GNU_LIBC_VERSION ]; then echo 'glibc 2.36'; exit 0; fi
exec "$real_getconf" "\$@"
STUB
chmod +x "$work/stub-bin/security" "$work/stub-bin/launchctl" "$work/stub-bin/uname" "$work/stub-bin/getconf"
run() { env -i HOME="$home" PATH="$work/stub-bin:$PATH" TERM=dumb USER="${USER:-tester}" STUB_KERNEL="${kernel:-}" /bin/bash "$repo/install.sh" "$@"; }

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
        CLAUDE_CONFIG_DIR="$home/.claude" STUB_KERNEL="${kernel:-}" /bin/bash "$repo/install.sh" link
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

# The claude selection's macOS login agents, in a fresh HOME that, like a real Mac, already has a user
# LaunchAgent. On Linux nothing touches launchd or the keychain. On macOS the watchdog agent is always
# installed, and the token agent only while the keychain item claude-code-oauth exists. No file
# install writes holds the token, and install checks only that the item exists.
home="$work/agents home"
root="$home/.local/share/bootstrap"
agents="$home/Library/LaunchAgents"
watchdog="io.github.elijah-rou.bootstrap.watchdog"
token_agent="io.github.elijah-rou.bootstrap.claude-token"
domain="gui/$(id -u)"
sentinel='fake-oauth-token-for-bootstrap-edge-test'
mkdir -p "$agents"
printf '<plist/>\n' >"$agents/com.example.mine.plist"
kernel=Linux run link >/dev/null || fail 'link without selections failed'
printf 'select\ttools\tclaude\n' >>"$root/state.tsv"
printf '%s\n' "$sentinel" >"$work/keychain"
rm -f "$work/launchctl.log" "$work/security.log"
kernel=Linux link_kit >/dev/null 2>&1 || fail 'link with claude selected failed on Linux'
[[ ! -e "$work/launchctl.log" && ! -e "$work/security.log" ]] || fail 'Linux link ran launchctl or security'
[[ -z "$(find "$agents" -name 'io.github.elijah-rou.*')" && ! -e "$root/tools/libexec" ]] || fail 'Linux link wrote a login agent'
if grep -Eq '^(agent|launchenv)'$'\t' "$root/state.tsv"; then fail 'Linux link recorded a login agent'; fi

rm "$work/keychain"
kernel=Darwin link_kit >/dev/null 2>&1 || fail 'link with claude selected failed on macOS'
[[ -f "$agents/$watchdog.plist" ]] || fail 'the watchdog agent was not written'
[[ ! -e "$agents/$token_agent.plist" ]] || fail 'the token agent was written without the keychain item'
grep -qxF "bootstrap $domain $agents/$watchdog.plist" "$work/launchctl.log" || fail 'the watchdog agent was not loaded'
if grep -q setenv "$work/launchctl.log"; then fail 'launchctl setenv ran without the keychain item'; fi
if grep -q '^launchenv' "$root/state.tsv"; then fail 'a launchenv record was written without the keychain item'; fi

printf '%s\n' "$sentinel" >"$work/keychain"
rm -f "$work/launchctl.log"
kernel=Darwin link_kit >/dev/null 2>&1 || fail 'link with the keychain item failed'
plist="$agents/$token_agent.plist"
[[ -f "$plist" ]] || fail 'the token agent was not written'
[[ "$(cat "$work/launchctl.log")" == "print $domain/$watchdog"$'\n'"bootout $domain/$token_agent"$'\n'"bootstrap $domain $plist" ]] ||
    fail "unexpected launchctl calls: $(tr '\n' ';' <"$work/launchctl.log")"
if grep -q -- ' -w' "$work/security.log"; then fail 'install read the keychain item, not only its existence'; fi
grep -qxF "find-generic-password -s claude-code-oauth" "$work/security.log" || fail 'install did not check for the keychain item'
grep -qF "<string>$root/tools/libexec/claude-token-env</string>" "$plist" && grep -q '<key>RunAtLoad</key>' "$plist" ||
    fail 'the token agent does not run claude-token-env at load'
grep -qF "<string>$root/tools/libexec/agent-kit-watchdog</string>" "$agents/$watchdog.plist" &&
    grep -qF "<string>$root</string>" "$agents/$watchdog.plist" && grep -q '<integer>900</integer>' "$agents/$watchdog.plist" ||
    fail 'the watchdog agent does not run agent-kit-watchdog every 900 seconds'
if command -v plutil >/dev/null; then plutil -lint -s "$plist" "$agents/$watchdog.plist" || fail 'a plist is malformed'; fi
for record in "agent"$'\t'"$agents/$watchdog.plist" "launchenv"$'\t'"CLAUDE_CODE_OAUTH_TOKEN" "agent"$'\t'"$plist"; do
    grep -qxF "$record" "$root/state.tsv" || fail "missing state record: $record"
done
# launchenv precedes the token agent, so uninstall's reverse replay boots the agent out before it unsets.
[[ "$(grep -nxF "launchenv"$'\t'"CLAUDE_CODE_OAUTH_TOKEN" "$root/state.tsv" | cut -d: -f1)" -lt "$(grep -nxF "agent"$'\t'"$plist" "$root/state.tsv" | cut -d: -f1)" ]] ||
    fail 'the launchenv record follows its agent'

# A rerun with both agents loaded changes nothing; a changed plist is booted out and loaded again.
cp "$root/state.tsv" "$work/state.before"
rm -f "$work/launchctl.log"
kernel=Darwin link_kit >/dev/null 2>&1 || fail 'relink with login agents failed'
if grep -Eq '^(bootout|bootstrap)' "$work/launchctl.log"; then fail 'an unchanged, loaded agent was reloaded'; fi
cmp -s "$root/state.tsv" "$work/state.before" || fail 'a rerun changed state.tsv'
printf '<!-- edited -->\n' >>"$agents/$watchdog.plist"
rm -f "$work/launchctl.log"
kernel=Darwin link_kit >/dev/null 2>&1 || fail 'relink after a plist change failed'
grep -A1 -xF "bootout $domain/$watchdog" "$work/launchctl.log" | grep -qxF "bootstrap $domain $agents/$watchdog.plist" ||
    fail 'a changed plist was not booted out and loaded again'
if grep -qF 'edited' "$agents/$watchdog.plist"; then fail 'a changed plist was not rewritten'; fi

# The token program sets the variable from the keychain and prints nothing; without the item it only fails.
rm -f "$work/launchctl.log"
output="$(env -i HOME="$home" PATH="$work/stub-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$root/tools/libexec/claude-token-env" 2>&1)" ||
    fail 'claude-token-env failed with the keychain item'
[[ -z "$output" ]] || fail 'claude-token-env printed output'
[[ "$(cat "$work/launchctl.log")" == "setenv CLAUDE_CODE_OAUTH_TOKEN $sentinel" ]] || fail 'claude-token-env did not set the token'
mv "$work/keychain" "$work/keychain.off"
rm -f "$work/launchctl.log"
if output="$(env -i HOME="$home" PATH="$work/stub-bin:/usr/bin:/bin:/usr/sbin:/sbin" "$root/tools/libexec/claude-token-env" 2>&1)"; then
    fail 'claude-token-env succeeded without the keychain item'
fi
[[ -z "$output" && ! -e "$work/launchctl.log" ]] || fail 'claude-token-env acted without the keychain item'
mv "$work/keychain.off" "$work/keychain"
if grep -rqF "$sentinel" "$home"; then fail "the token was written to: $(grep -rlF "$sentinel" "$home" | tr '\n' ' ')"; fi

# The watchdog program is a quiet no-op until agent-kit has the script, then runs it with the root's Bun
# under launchd's minimal PATH.
launchd_path=/usr/bin:/bin:/usr/sbin:/sbin
output="$(env -i HOME="$home" PATH="$launchd_path" "$root/tools/libexec/agent-kit-watchdog" "$root" 2>&1)" ||
    fail 'agent-kit-watchdog failed without the watchdog script'
[[ -z "$output" ]] || fail "agent-kit-watchdog printed output without the watchdog script: $output"
mkdir -p "$kit/skills/background-run/scripts"
touch "$kit/skills/background-run/scripts/watchdog.ts"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >"%s/bun-watchdog"\n' "$work" >"$root/tools/bin/bun"
chmod +x "$root/tools/bin/bun"
env -i HOME="$home" PATH="$launchd_path" "$root/tools/libexec/agent-kit-watchdog" "$root" || fail 'agent-kit-watchdog failed'
[[ "$(cat "$work/bun-watchdog" 2>/dev/null)" == "$root/tools/agent-kit/skills/background-run/scripts/watchdog.ts scan" ]] ||
    fail 'agent-kit-watchdog did not run the watchdog scan with the root Bun'
rm -rf "$kit/skills/background-run"

# Uninstall boots both agents out, unsets the token after its agent is gone, and deletes what install wrote.
rm -f "$work/launchctl.log"
kernel=Darwin run uninstall --yes >/dev/null 2>&1 || fail 'uninstall with login agents failed'
[[ "$(grep -E '^(bootout|unsetenv)' "$work/launchctl.log")" == "bootout $domain/$token_agent"$'\n'"unsetenv CLAUDE_CODE_OAUTH_TOKEN"$'\n'"bootout $domain/$watchdog" ]] ||
    fail "unexpected uninstall launchctl calls: $(tr '\n' ';' <"$work/launchctl.log")"
[[ ! -e "$work/loaded/$watchdog" && ! -e "$work/loaded/$token_agent" ]] || fail 'uninstall left an agent loaded'
[[ ! -e "$root" ]] || fail 'uninstall left the root'
[[ "$(ls -A "$agents")" == com.example.mine.plist ]] || fail "uninstall changed the user's LaunchAgents: $(ls -A "$agents" | tr '\n' ' ')"
leftover="$(cd "$home" && find . -mindepth 1 ! -path ./Library ! -path ./Library/LaunchAgents ! -path ./Library/LaunchAgents/com.example.mine.plist)"
[[ -z "$leftover" ]] || fail "uninstall left: $leftover"
printf 'PASS install link and uninstall edge cases\n'
