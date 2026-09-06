import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { after } from "node:test";
import { loadExtension } from "./extension-fixture.mjs";

const createTools = await loadExtension("lsp-diagnostics");
const fixtureRoot = mkdtempSync(join(tmpdir(), "lsp-diagnostics-test-"));
after(() => rmSync(fixtureRoot, { recursive: true, force: true }));
const environment = Object.fromEntries(["PATH", "FAKE_LSP_MODE", "FAKE_LSP_DIAGNOSTIC"].map(key => [key, process.env[key]]));
after(() => {
  for (const [key, value] of Object.entries(environment)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});
delete process.env.FAKE_LSP_MODE;
delete process.env.FAKE_LSP_DIAGNOSTIC;

function harness(root) {
  const handlers = new Map();
  const tool = createTools({ on(name, handler) { handlers.set(name, handler); } }).get("lsp_diagnostics");
  return {
    handlers,
    execute: (params = {}) => tool.execute("test", params, undefined, undefined, { cwd: root }),
  };
}

function installFakeServer(root) {
  const bin = join(root, "bin");
  mkdirSync(bin);
  const server = join(bin, "typescript-language-server");
  writeFileSync(server, `#!/usr/bin/env node
let buffer = Buffer.alloc(0);
const send = message => { const json = JSON.stringify(message); process.stdout.write('Content-Length: ' + Buffer.byteLength(json) + '\\r\\n\\r\\n' + json); };
process.stdin.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  while (true) {
    const end = buffer.indexOf('\\r\\n\\r\\n');
    if (end < 0) return;
    const length = Number(buffer.subarray(0, end).toString().match(/Content-Length: (\\d+)/i)[1]);
    if (buffer.length < end + 4 + length) return;
    const message = JSON.parse(buffer.subarray(end + 4, end + 4 + length));
    buffer = buffer.subarray(end + 4 + length);
    if (message.method === 'initialize') send({ jsonrpc: '2.0', id: message.id, result: { capabilities: {} } });
    if (message.method === 'textDocument/didOpen' && process.env.FAKE_LSP_MODE !== 'silent' && !(process.env.FAKE_LSP_MODE === 'partial' && message.params.textDocument.uri.endsWith('second.ts'))) send({ jsonrpc: '2.0', method: 'textDocument/publishDiagnostics', params: { uri: message.params.textDocument.uri, diagnostics: process.env.FAKE_LSP_DIAGNOSTIC === '1' ? [{ severity: 1, message: 'fixture diagnostic' }] : [] } });
    if (message.method === 'exit') process.exit(0);
  }
});
`);
  chmodSync(server, 0o755);
  process.env.PATH = `${bin}:${process.env.PATH}`;
}

for (const [name, diagnostic, expected] of [["clean", "0", "clean"], ["diagnostics", "1", "diagnostics"]]) {
  test(`fake LSP ${name} result settles before timeout`, async () => {
    const root = mkdtempSync(join(fixtureRoot, "lsp-diagnostics-"));
    installFakeServer(root);
    const path = join(root, "fixture.ts");
    writeFileSync(path, "const value = 1;\n");
    process.env.FAKE_LSP_DIAGNOSTIC = diagnostic;
    const started = Date.now();
    const result = await harness(root).execute({ paths: [path], timeoutMs: 2000 });
    assert.equal(result.details.outcome, expected);
    assert.ok(Date.now() - started < 1900);
  });
}

for (const mode of ["silent", "partial"]) {
  test(`LSP ${mode} diagnostic delivery cannot produce clean evidence`, async () => {
    const root = mkdtempSync(join(fixtureRoot, "lsp-diagnostics-incomplete-"));
    installFakeServer(root);
    const paths = ["first.ts", "second.ts"].map(name => {
      const path = join(root, name);
      writeFileSync(path, 'const broken: number = "wrong";\n');
      return path;
    });
    process.env.FAKE_LSP_MODE = mode;
    try {
      const result = await harness(root).execute({ paths, timeoutMs: 1200 });
      assert.equal(result.details.outcome, "timed_out");
      assert.ok(result.details.serverFailures.length > 0);
    } finally { delete process.env.FAKE_LSP_MODE; }
  });
}

test("51 requested files produce an explicit non-clean residual gap", async () => {
  const root = mkdtempSync(join(fixtureRoot, "lsp-diagnostics-limit-"));
  const paths = Array.from({ length: 51 }, (_, index) => {
    const path = join(root, `fixture-${index}.txt`);
    writeFileSync(path, "fixture\n");
    return path;
  });
  const result = await harness(root).execute({ paths });
  assert.equal(result.details.outcome, "unsupported");
  assert.deepEqual(result.details.omitted, ["fixture-50.txt: over 50-file limit"]);
  assert.match(result.details.verificationReceipt.residualGaps.at(-1), /over 50-file limit/);
});

test("more than 50 touched files remain explicit in the result", async () => {
  const root = mkdtempSync(join(fixtureRoot, "lsp-diagnostics-touched-limit-"));
  const instance = harness(root);
  for (let index = 0; index < 51; index++) {
    const path = join(root, `touched-${index}.txt`);
    writeFileSync(path, "fixture\n");
    await instance.handlers.get("tool_call")({ toolName: "write", input: { path } }, { cwd: root });
  }
  const result = await instance.execute();
  assert.equal(result.details.outcome, "unsupported");
  assert.deepEqual(result.details.omitted, ["touched-50.txt: over 50-file limit"]);
});
