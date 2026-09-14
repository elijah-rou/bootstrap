// Protocol-failure fixture. The real bundled selected-server policy launches this process.
import fs from 'node:fs';
const mode = process.env.LSP_FIXTURE_MODE;
fs.writeFileSync(process.env.LSP_FIXTURE_PID, String(process.pid));
let buffer = Buffer.alloc(0);
function send(message) {
  const text = JSON.stringify({ jsonrpc: '2.0', ...message });
  process.stdout.write(`Content-Length: ${Buffer.byteLength(text)}\r\n\r\n${text}`);
}
process.stdin.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  for (;;) {
    const header = buffer.indexOf('\r\n\r\n');
    if (header < 0) return;
    const match = /^Content-Length: (\d+)$/im.exec(buffer.subarray(0, header).toString());
    if (!match) process.exit(2);
    const length = Number(match[1]);
    if (buffer.length < header + 4 + length) return;
    const message = JSON.parse(buffer.subarray(header + 4, header + 4 + length));
    buffer = buffer.subarray(header + 4 + length);
    if (message.method === 'initialize') {
      if (mode === 'initialize-timeout') continue;
      send({id:message.id,result:{capabilities:{textDocumentSync:1,documentSymbolProvider:mode !== 'unsupported'}}});
    } else if (message.method === 'textDocument/documentSymbol') {
      if (mode === 'timeout') continue;
      if (mode === 'method-not-found' || mode === 'internal-error') {
        send({id:message.id,error:{code:mode === 'method-not-found' ? -32601 : -32603,message:mode}});
      } else send({id:message.id,result:mode === 'malformed' ? {invalid:true} : []});
    } else if (message.method === 'shutdown') send({id:message.id,result:null});
    else if (message.method === 'exit') process.exit(0);
  }
});
process.stdin.on('end', () => process.exit(0));
