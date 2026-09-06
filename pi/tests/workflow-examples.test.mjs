import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import { join } from "node:path";
import vm from "node:vm";
import test from "node:test";
import registerWorkflows from "../extensions/workflows.ts";

const runtime = process.env.PI_SUBAGENTS_TEST_RUNTIME_SOURCE;
test("documented tool calls and /tasks pass the public schema and execution normalizer", { skip: runtime ? false : "set PI_SUBAGENTS_TEST_RUNTIME_SOURCE" }, async () => {
 const { SubagentParams } = await import(pathToFileURL(join(runtime, "src/extension/schemas.ts")));
 const { normalizePublicSubagentExecution } = await import(pathToFileURL(join(runtime, "src/extension/public-execution.ts")));
 const require = createRequire(join(runtime, "package.json"));
 const { Compile } = await import(pathToFileURL(require.resolve("typebox/compile")));
 const schema = Compile(SubagentParams);
 const inputs = [];
 const docs = readFileSync(new URL("../WORKTREE_STREAMS.md", import.meta.url), "utf8");
 for (const block of docs.matchAll(/```js\n([\s\S]*?)\n```/g)) {
  vm.runInNewContext(block[1], { subagent: input => inputs.push(JSON.parse(JSON.stringify(input))) }, { timeout: 1000 });
 }
 let command;
 registerWorkflows({ registerCommand: (_name, value) => { command = value; } });
 let guidance;
 await command.handler("", { ui: { pasteToEditor: text => { guidance = text; } } });
 const example = guidance.match(/^- scripted shape: (.+)$/m)?.[1];
 assert.ok(example);
 inputs.push(JSON.parse(JSON.stringify(vm.runInNewContext(`(${example})`, {}, { timeout: 1000 }))));
 assert.equal(inputs.length, 4);
 for (const input of inputs) {
  assert.equal(schema.Check(input), true, JSON.stringify([...schema.Errors(input)]));
  assert.equal(normalizePublicSubagentExecution(input).ok, true, JSON.stringify(input));
 }
});
