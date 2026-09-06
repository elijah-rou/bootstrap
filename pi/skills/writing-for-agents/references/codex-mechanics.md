# Codex instruction and skill mechanics

Use current official Codex documentation and verify the installed version. A format accepted by Pi is not proof that Codex consumes it.

## Instructions

Codex reads `AGENTS.override.md`, otherwise `AGENTS.md`, under `CODEX_HOME` (default `~/.codex`), then project instructions from the repository root toward the working directory. It uses at most one instruction file per directory. The default combined project-document budget is 32 KiB. Investigate override files and truncation before adding more instructions or increasing the budget.

Global instructions should name native capabilities rather than Pi tool APIs. Do not copy Pi extension schemas, TUI commands, external model routers, receipt protocols, or privilege assumptions into a stock Codex setup. Native subagent model/effort defaults and per-spawn selection can express a task-specific compute policy without a routing extension. Instructions do not enforce sandboxing or tool permissions.

## Skills

Use `SKILL.md` with `name` and `description` frontmatter, plus relative references and optional scripts. Keep the name identical to the directory slug. Put portable repo skills in `.agents/skills/` and user skills in `~/.agents/skills/`. Codex follows symlinked skill folders. Check legacy `~/.codex/skills/` entries for duplicates or custom ownership before migrating them.

Codex can invoke a skill implicitly from its description or explicitly through `$skill-name`. For a manual-only skill, add `agents/openai.yaml` within that skill:

```yaml
policy:
  allow_implicit_invocation: false
```

Pi's `disable-model-invocation: true` is not a replacement for this metadata. Shared manual-only skills need both settings. Do not erase the workflow from `SKILL.md` to implement progressive disclosure; keep one workflow's normal path visible and put distinct branches behind references.

Use native client tools and installed commands. MCP is a separate integration, not a way to load Pi extensions unchanged. A tool that affects the execution host's browser, clipboard, or desktop does not affect a remote client.

## Verification

- Parse metadata and check local references, directory names, duplicate skill names, and activation boundaries.
- Use installed Codex discovery, not just a Markdown parser. Where supported, `codex app-server` exposes `skills/list`; `codex debug prompt-input` shows the initial instruction and skill context without a model task.
- A manual skill should remain selectable but be absent from implicit skill guidance. Test that distinction in the actual runtime.
- Use a temporary home/profile for probes. Never copy authentication or sessions into a test fixture. Check the active client's behavior separately when rendering, approvals, or invocation UI matter.

## Sources

- https://developers.openai.com/codex/guides/agents-md/
- https://developers.openai.com/codex/skills/
- https://developers.openai.com/codex/mcp/
- https://developers.openai.com/codex/multi-agent/

These describe the native contracts. Installed-version evidence takes precedence over assumptions about a newer documentation page.
