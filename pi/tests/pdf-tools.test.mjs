import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { after } from "node:test";
import { loadExtension } from "./extension-fixture.mjs";

const tools = await loadExtension("pdf-tools");
const root = mkdtempSync(join(tmpdir(), "pi-pdf-test-"));
after(() => rmSync(root, { recursive: true, force: true }));
const path = join(root, "fixture.pdf");
writeFileSync(path, "");
let calls = [];
const tool = tools({ async exec(command, args) { calls.push({ command, args }); return { code: 0, stdout: "fixture output" }; } }).get("pdf_extract");
const run = params => tool.execute("test", { path, ...params }, undefined, undefined, { cwd: root });

test("PDF ranges preserve absolute pages and bound only the range size", async () => {
  for (const [params, expected] of [
    [{}, [1, 20]],
    [{ firstPage: undefined, lastPage: undefined }, [1, 20]],
    [{ firstPage: 301, lastPage: 302 }, [301, 302]],
    [{ firstPage: 301 }, [301, 320]],
    [{ firstPage: 301, lastPage: 500 }, [301, 500]],
    [{ firstPage: 2147483628 }, [2147483628, 2147483647]],
    [{ firstPage: 2147483647, lastPage: 2147483647 }, [2147483647, 2147483647]],
  ]) {
    const result = await run(params);
    assert.deepEqual([result.details.firstPage, result.details.lastPage], expected);
    assert.deepEqual(calls.at(-1).args.slice(0, 4), ["-f", String(expected[0]), "-l", String(expected[1])]);
  }
});

test("killed PDF extraction is never reported as successful empty text", async () => {
  const interrupted = tools({ async exec() { return { code: 0, killed: true, stdout: "partial" }; } }).get("pdf_extract");
  await assert.rejects(interrupted.execute("test", { path }, undefined, undefined, { cwd: root }), /cancelled|timed out/i);
});

test("invalid PDF boundaries fail before process execution", async () => {
  for (const field of ["firstPage", "lastPage"]) {
    for (const value of [null, 0, -1, 1.5, NaN, Infinity, -Infinity, "2", true, {}, [], 2147483648]) {
      calls = [];
      await assert.rejects(run({ [field]: value }), /page|range/i);
      assert.equal(calls.length, 0);
    }
  }
  for (const params of [{ firstPage: 10, lastPage: 9 }, { firstPage: 301, lastPage: 501 }, { firstPage: 2147483647 }]) {
    calls = [];
    await assert.rejects(run(params), /page|range/i);
    assert.equal(calls.length, 0);
  }
});
