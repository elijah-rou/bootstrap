import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import test, { after } from 'node:test';

const root = mkdtempSync(join(tmpdir(), 'bootstrap-lsp-'));
const previousPath = process.env.PATH;
after(() => { process.env.PATH = previousPath; rmSync(root, { recursive: true, force: true }); });
mkdirSync(join(root, 'bin'));
process.env.PATH = `${join(root, 'bin')}:${previousPath}`;
writeFileSync(join(root, 'bin', 'rustup'), '#!/bin/sh\nexit 99\n', { mode: 0o755 });
writeFileSync(join(root, 'bin', 'rust-analyzer'), `#!${process.execPath}
let buffer = Buffer.alloc(0);
function send(message) { const json = JSON.stringify(message); process.stdout.write('Content-Length: ' + Buffer.byteLength(json) + '\\r\\n\\r\\n' + json); }
process.stdin.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  while (true) {
    const end = buffer.indexOf('\\r\\n\\r\\n'); if (end < 0) return;
    const length = Number(buffer.subarray(0, end).toString().match(/Content-Length: (\\d+)/i)[1]);
    if (buffer.length < end + 4 + length) return;
    const message = JSON.parse(buffer.subarray(end + 4, end + 4 + length));
    buffer = buffer.subarray(end + 4 + length);
    if (message.id !== undefined) send({ jsonrpc: '2.0', id: message.id, result: message.method === 'initialize' ? { capabilities: {} } : [] });
    if (message.method === 'textDocument/didOpen') send({ jsonrpc: '2.0', method: 'textDocument/publishDiagnostics', params: { uri: message.params.textDocument.uri, diagnostics: [] } });
    if (message.method === 'exit') process.exit(0);
  }
});
`, { mode: 0o755 });
for (const [extension, server] of [['rs', 'rust-analyzer'], ['ex', 'elixir-ls'], ['exs', 'elixir-ls'], ['zig', 'zls']]) {
  writeFileSync(join(root, 'bin', server), readFileSync(join(root, 'bin', 'rust-analyzer')), { mode: 0o755 });
  writeFileSync(join(root, `main.${extension}`), '// fixture\n');
}
writeFileSync(join(root, 'verification-receipt.ts'), readFileSync(new URL('../pi/extensions/verification-receipt.ts', import.meta.url)));

for (const name of ['lsp-diagnostics', 'lsp-navigation']) {
  for (const [extension, server] of [['rs', 'rust-analyzer'], ['ex', 'elixir-ls'], ['exs', 'elixir-ls'], ['zig', 'zls']]) {
  test(`${name} uses ${server} for .${extension}`, async () => {
    const source = readFileSync(new URL(`../pi/extensions/${name}.ts`, import.meta.url), 'utf8')
      .replace('import { Type } from "@mariozechner/pi-ai";', 'const Type = new Proxy({}, { get: () => () => ({}) });');
    const file = join(root, `${name}.ts`); writeFileSync(file, source);
    const { default: register } = await import(pathToFileURL(file));
    const tools = new Map(); register({ on() {}, registerTool(tool) { tools.set(tool.name, tool); } });
    const diagnostic = name === 'lsp-diagnostics';
    const tool = tools.get(diagnostic ? 'lsp_diagnostics' : 'lsp_definition');
    const params = diagnostic ? { paths: [join(root, `main.${extension}`)], timeoutMs: 2000 } : { path: `main.${extension}`, line: 1, character: 1, timeoutMs: 2000 };
    const result = await tool.execute('test', params, undefined, undefined, { cwd: root });
    if (diagnostic) assert.equal(result.details.outcome, 'clean');
    else assert.equal(result.details.server, server);
  });
  }
}
