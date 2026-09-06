import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import register from "../extensions/git-interceptor.ts";

const agents = await readFile(new URL("../AGENTS.md", import.meta.url), "utf8");
const worktrees = await readFile(new URL("../extensions/worktrees.ts", import.meta.url), "utf8");

function interceptor() {
  let handler;
  register({ on(event, callback) { if (event === "tool_call") handler = callback; } });
  return (command) => handler({ toolName: "bash", input: { command } });
}

test("marked children cannot publish or integrate with Git", () => {
  const original = process.env.PI_SUBAGENT_CHILD;
  process.env.PI_SUBAGENT_CHILD = "1";
  try {
    const run = interceptor();
    for (const command of ["git push origin main", "git merge topic", "git rebase main", "git cherry-pick HEAD~1", "git -C /tmp/repo pull"]) {
      assert.equal(run(command)?.block, true, command);
      assert.match(run(command).reason, /child publication\/integration/);
    }
    for (const command of ["git status --short", "git diff --check", "git log -1", "git show HEAD", "git commit -m local"]) assert.equal(run(command), undefined, command);
  } finally {
    if (original === undefined) delete process.env.PI_SUBAGENT_CHILD;
    else process.env.PI_SUBAGENT_CHILD = original;
  }
});

test("root execution is not blocked when child marker is absent", () => {
  const original = process.env.PI_SUBAGENT_CHILD;
  delete process.env.PI_SUBAGENT_CHILD;
  try {
    const run = interceptor();
    assert.equal(run("git push origin main"), undefined);
    assert.equal(run("git merge topic"), undefined);
  } finally {
    if (original !== undefined) process.env.PI_SUBAGENT_CHILD = original;
  }
});

test("root publication and repository-learning triggers are explicit", () => {
  assert.match(agents, /Publication is root-only/);
  assert.match(agents, /exact revision[^\n]*full workspace[^\n]*final verification/i);
  assert.match(agents, /Mutation-capable external runners[^\n]*no-publication/i);
  assert.match(agents, /Two materially similar[^\n]*foundation review/i);
  assert.match(agents, /One P0\/P1 escape triggers it immediately/i);
  assert.match(agents, /Create a short ADR only for public contracts, persisted formats, security boundaries, major dependencies, hard-to-reverse architecture, or substantial operational commitments/i);
  assert.match(agents, /user-journey map only after agents repeatedly rediscover a complex product path/i);
});

test("worktree gardening reports at exact thresholds and never auto-removes", () => {
  assert.match(worktrees, /REPOSITORY_GARDENING_THRESHOLD = 6/);
  assert.match(worktrees, /GLOBAL_GARDENING_THRESHOLD = 12/);
  assert.match(worktrees, />= GLOBAL_GARDENING_THRESHOLD/);
  assert.match(worktrees, />= REPOSITORY_GARDENING_THRESHOLD/);
  assert.match(worktrees, /Removal is never automatic/);
});
