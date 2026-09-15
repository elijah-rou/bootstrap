#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { createReadStream, lstatSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';

const [revision, archiveArgument, ...extra] = process.argv.slice(2);
function fail(message) { console.error(message); process.exit(1); }
if (extra.length || !/^[0-9a-f]{40}$/.test(revision || '') || !archiveArgument) {
  console.error('Usage: scripts/release-pin.mjs FULL_40_HEX_REVISION VERIFIED_ARCHIVE.tar.gz');
  process.exit(2);
}
const archive = resolve(archiveArgument);
let stat;
try { stat = lstatSync(archive); } catch { fail(`Release archive is missing: ${archive}`); }
if (!stat.isFile() || stat.isSymbolicLink()) fail(`Release archive must be a regular file: ${archive}`);
if (stat.size < 1 || stat.size > 512 * 1024 * 1024) fail('Release archive size is outside the 1-byte to 512-MiB verification bound');

const object = spawnSync('git', ['cat-file', '-t', revision], { encoding: 'utf8' });
if (object.error || object.status !== 0 || object.stdout.trim() !== 'commit') fail(`Revision is not a local Git commit: ${revision}`);
const listing = spawnSync('tar', ['-tzf', archive], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
if (listing.error || listing.status !== 0) fail('Release archive is not a readable gzip-compressed tar archive');
const paths = listing.stdout.split('\n').filter(Boolean);
const prefix = `bootstrap-${revision}/`;
if (!paths.length || paths.length > 100000 || paths.some(path => path !== prefix.slice(0, -1) && !path.startsWith(prefix))) {
  fail(`Release archive entries do not match full revision prefix ${prefix}`);
}

const hash = createHash('sha256');
const stream = createReadStream(archive);
stream.on('error', error => fail(`Unable to hash release archive: ${error.message}`));
stream.on('data', chunk => hash.update(chunk));
stream.on('end', () => {
  const archiveSha256 = hash.digest('hex');
  process.stdout.write(`${JSON.stringify({ schemaVersion: 1, revision, archiveSha256, archive }, null, 2)}\n`);
});
