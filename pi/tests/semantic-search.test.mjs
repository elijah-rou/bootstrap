import assert from "node:assert/strict";
import fs, { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { after } from "node:test";
import { loadExtension } from "./extension-fixture.mjs";

const tools = await loadExtension("semantic-search");
const root = mkdtempSync(join(tmpdir(), "pi-search-test-"));
after(() => rmSync(root, { recursive: true, force: true }));
const path = join(root, "notes with spaces.md");
writeFileSync(path, "alpha beta\nsecond alpha\n");
writeFileSync(join(root, "code.ts"), "const alpha = 1;\n");
const tool = tools().get("semantic_search");
const run = params => tool.execute("test", { query: "alpha", ...params }, undefined, undefined, { cwd: root });

test("ranked lexical search supports file and directory inputs without claiming embeddings", async () => {
  for (const input of [path, root]) {
    const result = await run({ path: input, mode: "docs" });
    assert.equal(result.details.count, 2);
    assert.equal(result.details.backend, "ranked-lexical-fallback");
    assert.match(result.content[0].text, /alpha beta/);
  }
  assert.equal((await run({ path: root, mode: "code" })).details.count, 1);
  assert.equal((await run({ path, limit: 1 })).details.count, 1);
  assert.equal((await run({ path, query: "absentneedle" })).details.count, 0);
  assert.doesNotMatch(tool.description, /configured semantic backend/);
});

test("search process failure is not reported as an empty result", async () => {
  const bin = join(root, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "rg"), "#!/bin/sh\nprintf 'fixture search failure' >&2\nexit 2\n", { mode: 0o755 });
  const previous = process.env.PATH;
  process.env.PATH = `${bin}:${previous}`;
  try { await assert.rejects(run({ path }), /fixture search failure/); }
  finally { process.env.PATH = previous; }
});

test("snippet reads are bounded by returned results and preserve rank and missing snippets", async () => {
  const directory = join(root, "ranked");
  mkdirSync(directory);
  const best = join(directory, "a-best.md");
  const tied = join(directory, "b-best.md");
  writeFileSync(best, "alpha beta\n");
  writeFileSync(tied, "alpha beta\n");
  for (let index = 0; index < 10; index++) writeFileSync(join(directory, `lower-${index}.md`), "alpha\n");
  const readFileSync = fs.readFileSync;
  const reads = [];
  fs.readFileSync = (file, ...args) => {
    if (typeof file === "string" && file.startsWith(directory + "/")) {
      reads.push(file);
      if (file === tied) throw new Error("fixture snippet became unreadable");
    }
    return readFileSync(file, ...args);
  };
  syncBuiltinESMExports();
  try {
    const result = await run({ path: directory, query: "alpha beta", limit: 2 });
    assert.equal(result.details.count, 2);
    assert.match(result.content[0].text, /1\. ranked\/a-best\.md:1 score=9\n1: alpha beta/);
    assert.match(result.content[0].text, /2\. ranked\/b-best\.md:1 score=9$/);
    assert.deepEqual(reads, [best, tied]);
  } finally {
    fs.readFileSync = readFileSync;
    syncBuiltinESMExports();
  }
});
