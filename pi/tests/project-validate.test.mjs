import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { after } from "node:test";
import { loadExtension } from "./extension-fixture.mjs";

const runtime = process.env.PI_BASH_OPERATIONS_TEST_RUNTIME_PATH;
const tools = runtime ? await loadExtension("project-validate") : undefined;
const root = mkdtempSync(join(tmpdir(), "pi-validation-test-"));
after(() => rmSync(root, { recursive: true, force: true }));
const tool = tools?.().get("project_validate");
const run = (command, signal, timeoutMs = 1000) => tool.execute("test", { action: "test", command, cwd: root, timeoutMs }, signal, undefined, { cwd: root });

const descendantCommand = 'sleep 4 & child=$!; printf "DESCENDANT:%s\\n" "$child"; wait';
async function assertDescendantStopped(result) {
  const pid = Number(result.content[0].text.match(/DESCENDANT:(\d+)/)?.[1]);
  assert.ok(Number.isInteger(pid) && pid > 0, "fixture must report its descendant PID");
  function running() {
    try {
      process.kill(pid, 0);
      if (process.platform === "linux") return !/^\d+ \(.*\) Z /.test(readFileSync(`/proc/${pid}/stat`, "utf8"));
      return true;
    } catch (error) {
      if (error.code === "ESRCH" || error.code === "ENOENT") return false;
      throw error;
    }
  }
  for (let attempt = 0; attempt < 10 && running(); attempt++) await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(running(), false, "the descendant must be terminated, not merely disconnected");
}

test("validation timeout bounds subprocesses and inherited pipes", { skip: runtime ? false : "set PI_BASH_OPERATIONS_TEST_RUNTIME_PATH to exercise the pinned Pi bash runtime" }, async () => {
  const started = Date.now();
  const result = await run(descendantCommand);
  assert.equal(result.details.outcome, "timed_out");
  await assertDescendantStopped(result);
  assert.ok(Date.now() - started < 2500, "must not wait for the descendant's normal exit");
});

test("validation cancellation terminates descendants promptly", { skip: runtime ? false : "set PI_BASH_OPERATIONS_TEST_RUNTIME_PATH to exercise the pinned Pi bash runtime" }, async () => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 200);
  const started = Date.now();
  try {
    const result = await run(descendantCommand, controller.signal, 10000);
    assert.equal(result.details.outcome, "cancelled");
    await assertDescendantStopped(result);
    assert.ok(Date.now() - started < 2000);
  } finally { clearTimeout(timer); }
});

test("pre-aborted validation never runs the command", { skip: runtime ? false : "set PI_BASH_OPERATIONS_TEST_RUNTIME_PATH to exercise the pinned Pi bash runtime" }, async () => {
  const result = await run("printf should-not-run", AbortSignal.abort());
  assert.equal(result.details.outcome, "cancelled");
  assert.doesNotMatch(result.content[0].text.split("Output:")[1], /should-not-run/);
});

test("successful and failing commands preserve output and exit status", { skip: runtime ? false : "set PI_BASH_OPERATIONS_TEST_RUNTIME_PATH to exercise the pinned Pi bash runtime" }, async () => {
  for (const [command, outcome, exit] of [["printf passed", "passed", 0], ["printf failed >&2; exit 7", "failed", 7]]) {
    const result = await run(command);
    assert.equal(result.details.outcome, outcome);
    assert.equal(result.details.exitCode, exit);
    assert.match(result.content[0].text, new RegExp(`Output:\\n${outcome}`));
  }
});
