# Delegation and worktrees

Use upstream `pi-subagents` for delegated execution. The parent owns strategy, role selection, topology, context, worktrees, acceptance, tools, and permissions. Select child models and thinking through explicit role profiles or per-run overrides; these selections do not change those boundaries.

## Tool hierarchy

| Tier | Tool | When |
|------|------|------|
| 1 | `subagent` | One direct child, scripted workflows, and async run control |
| 2 | `subagent_wait` | Block on async completion without sleep or polling loops |
| 3 | `worktree` | Explicit managed worktree create/list/info/remove/prune operations |

## Workspace launcher

Use `piw` or `pi-workspace` when worktree choice matters before starting Pi:

```text
piw                         # pick main, existing worktree, or new worktree
piw --main                  # start Pi in current repo checkout root
piw --worktree <query>      # start Pi in matching managed worktree
piw --new <label>           # create managed worktree, then start Pi there
piw --list                  # list managed worktrees for current repo
piw -- --model opus         # pass args after -- to Pi
```

Normal `pi` stays unchanged. Inside Pi, `/piw` selects a registered workspace and `/worktrees list|info|create|remove|prune` manages entries under `~/piw-worktrees`.

## Current command surface

Run `/tasks` for local guidance.

| Command | Purpose |
|---------|---------|
| `/run <agent> <task> [--bg] [--fork]` | Run one typed-role child |
| `/prompt-workflow <name> [args]` | Compile a repeatable prompt template into `workflowScript` |
| `/subagents-fleet` | Show the active foreground/background fleet |
| `/subagent-cost` | Show parent and child token usage and cost |
| `/subagents-doctor` | Diagnose runtime and supervisor-bridge configuration |

## Execution patterns

Use direct execution for a provable singleton:

```js
subagent({ agent: "reviewer", task: "Review the supplied diff for unresolved semantic issues", delegationReason: "semantic_review", async: true });
```

Use `workflowScript` only when the control flow requires dependencies, parallel fanout, or result aggregation. Use stable keys and ordinary JavaScript:

```js
subagent({ workflowScript: `
  const scan = await runs.run("scan", { agent: "scout", task: "Find affected files" });
  const reviews = await runs.all([
    { key: "correctness", agent: "reviewer", task: "Review correctness: " + scan.output },
    { key: "security", agent: "second-opinion", task: "Review security boundaries: " + scan.output }
  ]);
  return reviews.map(result => result.output);
`, delegationReason: "elevated_risk_review", async: true });
```

Use `await runs.run(key, {...})` for dependency order and `await runs.all([...])` for independent parallel work. Bound list sizes before mapping dynamic entries into `runs.all`. Observe every launched promise with `await`, `Promise.all`, or `Promise.race`.

### Structured dependencies

Add `outputSchema` to the producing child when a later step requires structured data. Consume the validated `structuredOutput` rather than parsing prose:

```js
subagent({ workflowScript: `
  const inventory = await runs.run("inventory", {
    agent: "scout",
    task: "Return up to five files to review.",
    outputSchema: {
      type: "object",
      properties: { files: { type: "array", items: { type: "string" }, maxItems: 5 } },
      required: ["files"],
      additionalProperties: false
    }
  });
  const files = inventory.structuredOutput.files.slice(0, 5);
  return runs.all(files.map((file, index) => ({
    key: "review-" + index,
    agent: "reviewer",
    task: "Audit current behavior in " + file
  })));
`, delegationReason: "independent_parallel_lane", delegationBasis: {
  ownership: ["read-only file inventory", "read-only findings for each inventoried file"],
  deliverable: "Independent file-level review reports for parent synthesis"
}, async: true });
```

### Steering and resume

Use `await runs.steer(key, message, options)` to guide a live keyed child. Resume a retained child in a later scripted step with `runs.run(newKey, { resume: runId, task })`; continue from the newest returned `runId`. Outside a workflow, use `subagent` actions `status`, `interrupt`, `resume`, and `steer`. Parent-owned role and topology remain explicit rather than automatically routed.

## Run lifetime and async control

Launch detached workflows with `async: true`. Continue useful independent work or yield for completion events. Use `subagent_wait({ id })`, `subagent_wait({ all: true })`, or a bounded wait only at a real run-to-completion dependency barrier; do not sleep or poll status repeatedly. A `subagent_wait` timeout does not terminate the run.

Blocking workflows default to a bounded runtime. Async workflows have no default timeout and end on completion, explicit interrupt, or external failure. Keep timeouts for bounded micro-actions such as one command, request, classifier, test, lock, or observation window.

Acceptance evidence levels are `attested`, `checked`, and `verified`. Review is a separate gate. Use `acceptance: { level: "checked", review: { required: false } }` for checked work that does not require independent review; when review is required by policy, orchestrate a read-only reviewer explicitly and inspect its findings. The optional gate does not accept `required: true`. Child-reported command success does not replace runtime verification.

## Worktree rules

- Default to the current checkout for bounded work with one writer. Inspect status first, preserve unrelated changes, and do not let the parent and child edit concurrently.
- Use an isolated worktree when requested, for parallel mutable writers, broad/risky/long-lived work, or conflicting checkout state. Do not create one merely because files will change.
- Set `worktree: true` on individual `runs.run`/`runs.all` items, or at workflow level as the default. Give parallel writers disjoint ownership; otherwise use one writer.
- Bound task count and concurrency before launch.
- The `worktree` tool manages registered worktrees. After creation, use the returned absolute path or pass it as child `cwd`; the current session cwd does not change.
- Retain a task worktree until its branch or commit reaches upstream default, or is otherwise confirmed reachable.
- Remove only clean, merged/reachable worktrees. Use `prune` for missing paths and stale registry entries.
