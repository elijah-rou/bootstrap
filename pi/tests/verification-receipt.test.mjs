import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { beginVerification, fingerprintWorkspace, finishVerification } from "../extensions/verification-receipt.ts";

test("receipt actor reflects child execution without granting acceptance authority", () => {
  const previous = process.env.PI_SUBAGENT_CHILD;
  try {
    for (const [marker, actor] of [[undefined, "root-parent-or-user"], ["1", "subagent"], ["0", "unknown"], ["", "unknown"], ["unexpected", "unknown"]]) {
      if (marker === undefined) delete process.env.PI_SUBAGENT_CHILD;
      else process.env.PI_SUBAGENT_CHILD = marker;
      const started = beginVerification(tmpdir(), "fixture", "check");
      assert.equal(started.verifier.actor, actor);
      assert.equal(started.verifier.authority, "local-verification");
      assert.deepEqual(finishVerification(started, "passed", {}).verifier, started.verifier);
    }
  } finally {
    if (previous === undefined) delete process.env.PI_SUBAGENT_CHILD;
    else process.env.PI_SUBAGENT_CHILD = previous;
  }
});

function repository() {
  const root = mkdtempSync(join(tmpdir(), "verification-receipt-"));
  execFileSync("git", ["init", "-q", root]);
  execFileSync("git", ["-C", root, "config", "user.email", "fixture@example.invalid"]);
  execFileSync("git", ["-C", root, "config", "user.name", "Fixture"]);
  writeFileSync(join(root, "tracked.txt"), "tracked\n");
  execFileSync("git", ["-C", root, "add", "tracked.txt"]);
  execFileSync("git", ["-C", root, "commit", "-qm", "fixture"]);
  return root;
}

test("untracked content changes workspace identity", () => {
  const root = repository();
  writeFileSync(join(root, "new.txt"), "first\n");
  const first = fingerprintWorkspace(root);
  writeFileSync(join(root, "new.txt"), "second\n");
  const second = fingerprintWorkspace(root);
  assert.equal(first.cacheable, true);
  assert.equal(second.cacheable, true);
  assert.notEqual(first.digest, second.digest);
});

test("fingerprint limits fail closed instead of partially keying", () => {
  const root = repository();
  for (let index = 0; index < 101; index++) writeFileSync(join(root, `untracked-${index}`), "x");
  const fingerprint = fingerprintWorkspace(root);
  assert.equal(fingerprint.cacheable, false);
  assert.match(fingerprint.reason, /limit exceeded/);
  assert.equal(fingerprint.digest, undefined);
});

test("versioned receipts preserve immutable attempt identity and terminal facts", () => {
  const root = repository();
  const started = beginVerification(root, "fixture", "check");
  const receipt = finishVerification(started, "passed", { command: "true", exitCode: 0, signal: null, truncated: false, exercisedPaths: ["tracked.txt"], residualGaps: [] });
  assert.equal(receipt.version, 1);
  assert.match(receipt.attemptId, /^[0-9a-f-]{36}$/);
  assert.equal(receipt.outcome, "passed");
  assert.equal(receipt.workspace.repositoryRoot, realpathSync(root));
});
