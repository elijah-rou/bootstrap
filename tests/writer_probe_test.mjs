import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const source = fileURLToPath(new URL('../scripts/lib/install/bare.sh', import.meta.url));
const controller = `
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
let peer;
try {
  if (process.env.PROBE_PEER === '1') {
    peer = spawn(process.execPath, [process.env.PROBE_PEER_FILE], { stdio: ['ignore', 'pipe', 'inherit'] });
    await once(peer.stdout, 'data');
  }
  const result = spawnSync('bash', ['-c', 'warn() { printf "%s\\n" "$*" >&2; }; source "$1"; shift; bootstrap_live_writers "$@"', 'probe', process.env.PROBE_SOURCE, ...JSON.parse(process.env.PROBE_ARGS)], { encoding: 'utf8', timeout: 10000, maxBuffer: 64 * 1024 });
  console.log(JSON.stringify({ status: result.status, stdout: result.stdout, stderr: result.stderr, controller: process.pid, peer: peer?.pid }));
} finally {
  if (peer && peer.exitCode === null) { peer.kill('SIGTERM'); await once(peer, 'exit'); }
}
`;

function probe(args, peer = false) {
  const root = mkdtempSync(join(tmpdir(), 'bootstrap-writer-probe-'));
  try {
    const privateRoot = join(root, 'private');
    mkdirSync(privateRoot);
    const controllerFile = join(privateRoot, 'controller.mjs');
    const peerFile = join(privateRoot, 'peer.cjs');
    writeFileSync(controllerFile, controller);
    writeFileSync(peerFile, 'process.stdout.write("ready"); setTimeout(() => {}, 15000)');
    const result = spawnSync(process.execPath, [controllerFile], {
      env: { ...process.env, HOME: root, BOOTSTRAP_PRIVATE_ROOT: privateRoot, DOTFILES_BARE_ROOT: join(root, 'tools'), BOOTSTRAP_LEGACY_PI_ROOT: join(root, 'legacy'), BOOTSTRAP_LEGACY_RUNTIME_ROOT: join(root, 'legacy-runtime'), PROBE_SOURCE: source, PROBE_ARGS: JSON.stringify(args), PROBE_PEER: peer ? '1' : '0', PROBE_PEER_FILE: peerFile },
      encoding: 'utf8', timeout: 20000, maxBuffer: 64 * 1024,
    });
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('ordinary probes include their owned Node parent; cleanup excludes only that parent', { timeout: 30000 }, () => {
  const ordinary = probe([]);
  assert.equal(ordinary.status, 0, ordinary.stderr);
  assert.match(ordinary.stdout, new RegExp(`^${ordinary.controller} `, 'm'));
  const cleanup = probe(['--exclude-parent']);
  assert.equal(cleanup.status, 1, cleanup.stderr + cleanup.stdout);
});

test('cleanup still rejects another owned Node writer', { timeout: 30000 }, () => {
  const result = probe(['--exclude-parent'], true);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, new RegExp(`^${result.peer} `, 'm'));
  assert.doesNotMatch(result.stdout, new RegExp(`^${result.controller} `, 'm'));
});

test('writer probes reject unsupported arguments rather than excluding arbitrary PIDs', { timeout: 30000 }, () => {
  for (const args of [[''], ['--exclude-parent=1'], ['--exclude-parent', 'extra']]) {
    assert.equal(probe(args).status, 2);
  }
});
