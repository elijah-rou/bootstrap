#!/usr/bin/env node
import {
  chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync,
  readlinkSync, readdirSync, realpathSync, renameSync, rmdirSync, rmSync, symlinkSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const [command, ...args] = process.argv.slice(2);
const sourceRoot = resolve(process.env.BOOTSTRAP_LEGACY_PI_ROOT || join(process.env.HOME || '', '.pi/agent'));
const home = resolve(process.env.HOME || '');
const privateRoot = resolve(process.env.BOOTSTRAP_PRIVATE_ROOT || join(home, '.local/share/bootstrap/private'));
const agentRoot = join(privateRoot, 'pi/agent');
const sessionRoot = join(privateRoot, 'pi/sessions');
const stateRoot = resolve(process.env.BOOTSTRAP_STATE_ROOT || join(process.env.XDG_STATE_HOME || join(home, '.local/state'), 'bootstrap'));
const journalPath = join(stateRoot, 'migration.json');
const installRecordPath = join(stateRoot, 'install.json');
const checkoutRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const maxEntries = 20000;

function fail(message, status = 1) { console.error(message); process.exit(status); }
function plainObject(value) { return value && Object.getPrototypeOf(value) === Object.prototype; }
function within(root, value, allowRoot = true) {
  const rel = relative(resolve(root), resolve(value));
  return (allowRoot && rel === '') || (rel !== '' && rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel));
}
function lstatSafe(path) { try { return lstatSync(path); } catch (error) { if (error.code === 'ENOENT') return undefined; throw error; } }
function hashFile(path) { return createHash('sha256').update(readFileSync(path)).digest('hex'); }
function validateHomePath(name, value) {
  if (!isAbsolute(value) || value === '/' || !within(home, value)) fail(`${name} must be an absolute path below HOME: ${value}`, 2);
  let cursor = dirname(resolve(value));
  while (within(home, cursor, true) && cursor !== home) {
    const stat = lstatSafe(cursor);
    if (stat?.isSymbolicLink() && !within(home, realpathSync(cursor), true)) fail(`${name} escapes HOME through symlink parent: ${cursor}`);
    cursor = dirname(cursor);
  }
}
function validateRoots() {
  if (!isAbsolute(home) || home === '/') fail(`HOME must be an absolute path below /: ${home}`, 2);
  for (const [name, value] of [['legacy Pi root', sourceRoot], ['private root', privateRoot], ['state root', stateRoot]]) validateHomePath(name, value);
  if (within(sourceRoot, privateRoot, true) || within(privateRoot, sourceRoot, true)) fail('Legacy and destination roots must not overlap', 2);
}
function completedSnapshot(root) {
  if (!/^[0-9a-f]{40}$/.test(root.split(sep).at(-1) || '')) return false;
  if (dirname(root).split(sep).at(-1) !== 'snapshots') return false;
  const stat = lstatSafe(root);
  const installer = lstatSafe(join(root, 'install.sh'));
  const marker = lstatSafe(join(root, '.bootstrap-archive-sha256'));
  if (!stat?.isDirectory() || stat.isSymbolicLink() || !installer?.isFile() || !(installer.mode & 0o111) || !marker?.isFile() || marker.isSymbolicLink()) return false;
  return /^[0-9a-f]{64}\n?$/.test(readFileSync(join(root, '.bootstrap-archive-sha256'), 'utf8'));
}
function snapshotLinkTarget(linkTarget) {
  const parts = resolve(linkTarget).split(sep);
  const index = parts.lastIndexOf('snapshots');
  if (index < 0 || index + 2 >= parts.length) return undefined;
  const snapshot = parts.slice(0, index + 2).join(sep) || sep;
  if (!completedSnapshot(snapshot)) return undefined;
  const suffix = relative(snapshot, resolve(linkTarget));
  if (!suffix || suffix.startsWith(`..${sep}`) || isAbsolute(suffix)) return undefined;
  const replacement = join(checkoutRoot, suffix);
  if (!lstatSafe(replacement)) return undefined;
  return replacement;
}
function destinationFor(relativePath) {
  if (relativePath === 'sessions') return sessionRoot;
  if (relativePath.startsWith(`sessions${sep}`)) return join(sessionRoot, relativePath.slice(`sessions${sep}`.length));
  return join(agentRoot, relativePath);
}
function sourceRelativeFor(path) {
  const value = relative(sourceRoot, path);
  if (value === '' || value === '..' || value.startsWith(`..${sep}`) || isAbsolute(value)) fail(`Source path escaped legacy root: ${path}`);
  return value;
}
function descriptor(path, sourcePath = undefined) {
  const stat = lstatSafe(path);
  if (!stat) return { type: 'absent' };
  if (stat.isDirectory() && !stat.isSymbolicLink()) return { type: 'directory', mode: stat.mode & 0o777 };
  if (stat.isFile() && !stat.isSymbolicLink()) return { type: 'file', mode: stat.mode & 0o777, size: stat.size, sha256: hashFile(path) };
  if (stat.isSymbolicLink()) {
    const target = readlinkSync(path);
    if (!sourcePath) return { type: 'symlink', target };
    const resolvedTarget = resolve(dirname(sourcePath), target);
    if (within(sourceRoot, resolvedTarget, true)) {
      const mappedTarget = resolvedTarget === sourceRoot ? agentRoot : destinationFor(sourceRelativeFor(resolvedTarget));
      if (!within(agentRoot, mappedTarget, true) && !within(sessionRoot, mappedTarget, true)) fail(`Internal link maps outside migration ownership: ${sourcePath}`);
      const mapped = isAbsolute(target) ? mappedTarget : relative(dirname(destinationFor(sourceRelativeFor(sourcePath))), mappedTarget) || '.';
      return { type: 'symlink', target: mapped, classification: 'internal' };
    }
    const managedTarget = snapshotLinkTarget(resolvedTarget);
    if (managedTarget) return { type: 'symlink', target: managedTarget, classification: 'managed' };
    return { type: 'symlink', target, classification: 'external-unknown', resolvedTarget };
  }
  return { type: 'unsupported' };
}
function inventory(root, migrationSource = false) {
  const rootStat = lstatSafe(root);
  if (!rootStat) return [];
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) fail(`Migration root must be a non-symlink directory: ${root}`);
  const entries = [];
  const pending = readdirSync(root).sort().reverse().map(name => join(root, name));
  while (pending.length) {
    const path = pending.pop();
    const rel = relative(root, path);
    const item = descriptor(path, migrationSource ? path : undefined);
    entries.push({ path: rel, ...item });
    if (entries.length > maxEntries) fail(`Migration inventory exceeds ${maxEntries} entries`);
    if (item.type === 'directory') {
      const children = readdirSync(path).sort().reverse();
      for (const child of children) pending.push(join(path, child));
    }
  }
  return entries;
}
function mappedEntries(sourceInventory) {
  return sourceInventory.map(item => ({ ...item, destination: destinationFor(item.path) }));
}
function sameDescriptor(actual, expected) {
  if (actual.type !== expected.type) return false;
  if (actual.type === 'absent') return true;
  if (actual.type === 'directory') return true;
  if (actual.type === 'file') return actual.mode === expected.mode && actual.size === expected.size && actual.sha256 === expected.sha256;
  if (actual.type === 'symlink') return actual.target === expected.target;
  return false;
}
function destinationConflicts(entries) {
  const conflicts = [];
  for (const item of entries) {
    const actual = descriptor(item.destination);
    if (item.type === 'directory') {
      if (actual.type !== 'absent' && !sameDescriptor(actual, item)) conflicts.push({ path: item.destination, reason: 'destination directory mode or type is nonidentical' });
    } else if (actual.type !== 'absent' && !sameDescriptor(actual, item)) {
      conflicts.push({ path: item.destination, reason: 'destination is populated with nonidentical state' });
    }
  }
  return conflicts;
}
function herdrConflict() {
  const root = resolve(process.env.XDG_CONFIG_HOME || join(home, '.config'), 'herdr');
  const stat = lstatSafe(root);
  if (!stat) return undefined;
  if (!stat.isDirectory() || stat.isSymbolicLink()) return { path: root, reason: 'Herdr state root is not a regular directory' };
  if (readdirSync(root).length === 0) return undefined;
  let record;
  try { record = JSON.parse(readFileSync(installRecordPath, 'utf8')); } catch { return { path: root, reason: 'existing Herdr personal state is not enrolled' }; }
  if (!Array.isArray(record.enrolledRoots) || !record.enrolledRoots.includes(root)) return { path: root, reason: 'existing Herdr personal state is not enrolled' };
  const identity = record.enrolledRootIdentities?.[root];
  if (identity) {
    const current = `${stat.dev}:${stat.ino}`;
    if (identity !== current) return { path: root, reason: 'enrolled Herdr root identity changed' };
  }
  return undefined;
}
function inspect() {
  const source = inventory(sourceRoot, true);
  const unknownExternalLinks = source.filter(item => item.classification === 'external-unknown').map(item => ({ path: join(sourceRoot, item.path), target: item.target, resolvedTarget: item.resolvedTarget }));
  const unsupported = source.filter(item => item.type === 'unsupported').map(item => join(sourceRoot, item.path));
  const mapped = mappedEntries(source);
  const conflicts = destinationConflicts(mapped);
  for (const conflict of activationTargets().map(activationConflict).filter(Boolean)) conflicts.push(conflict);
  const herdr = herdrConflict();
  if (herdr) conflicts.push(herdr);
  return {
    schemaVersion: 1,
    phase: existsSync(journalPath) ? loadJournal().phase : 'unprepared',
    sourceRoot,
    agentRoot,
    sessionRoot,
    sourceEntries: source.length,
    sourcePresent: Boolean(lstatSafe(sourceRoot)),
    unknownExternalLinks,
    unsupported,
    conflicts,
    ready: unknownExternalLinks.length === 0 && unsupported.length === 0 && conflicts.length === 0,
  };
}
function atomicWrite(path, value) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const temporary = `${path}.new.${process.pid}`;
  writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  renameSync(temporary, path);
}
function validRelativePath(path) {
  return typeof path === 'string' && path !== '' && !isAbsolute(path) && path !== '..' && !path.startsWith(`..${sep}`) && !path.includes('\0') && !path.includes('\n') && !path.includes('\r');
}
function validStoredDescriptor(item) {
  if (!plainObject(item) || !['absent', 'directory', 'file', 'symlink'].includes(item.type)) return false;
  if (item.type === 'directory') return Number.isInteger(item.mode) && item.mode >= 0 && item.mode <= 0o777;
  if (item.type === 'file') return Number.isInteger(item.mode) && item.mode >= 0 && item.mode <= 0o777 && Number.isSafeInteger(item.size) && item.size >= 0 && /^[0-9a-f]{64}$/.test(item.sha256 || '');
  if (item.type === 'symlink') return typeof item.target === 'string' && !item.target.includes('\0');
  return true;
}
function validateJournal(value) {
  if (!plainObject(value) || value.schemaVersion !== 1 || !['prepared', 'transferred', 'activated', 'verified', 'retiring', 'rolled-back', 'retired'].includes(value.phase)) fail('Malformed migration journal');
  if (value.sourceRoot !== sourceRoot || value.agentRoot !== agentRoot || value.sessionRoot !== sessionRoot) fail('Migration roots differ from the recorded operation');
  if (!Array.isArray(value.sourceInventory) || value.sourceInventory.length > maxEntries || !Array.isArray(value.destinationBefore) || value.destinationBefore.length !== value.sourceInventory.length) fail('Malformed migration inventory');
  for (const item of value.sourceInventory) {
    if (!validRelativePath(item.path) || !validStoredDescriptor(item) || (item.type === 'symlink' && !['internal', 'managed'].includes(item.classification))) fail('Malformed source migration entry');
    if (item.type === 'symlink') {
      const resolvedTarget = resolve(dirname(destinationFor(item.path)), item.target);
      if (item.classification === 'internal' && !within(agentRoot, resolvedTarget, true) && !within(sessionRoot, resolvedTarget, true)) fail('Internal migration link escaped destination roots');
      if (item.classification === 'managed' && !within(checkoutRoot, resolvedTarget, true)) fail('Managed migration link escaped the selected source');
    }
  }
  for (const item of value.destinationBefore) if (!validRelativePath(item.path) || !validStoredDescriptor(item)) fail('Malformed destination migration entry');
  if (value.activation !== undefined) {
    const expected = activationTargets();
    if (!Array.isArray(value.activation) || value.activation.length !== expected.length) fail('Malformed activation journal');
    value.activation.forEach((item, index) => {
      if (!plainObject(item) || item.target !== expected[index].target || item.source !== expected[index].source || !validStoredDescriptor(item.before)) fail('Malformed activation target');
    });
  }
  return value;
}
function loadJournal() {
  let value;
  try { value = JSON.parse(readFileSync(journalPath, 'utf8')); } catch { fail(`Migration is not prepared: ${journalPath}`); }
  return validateJournal(value);
}
function inventoriesEqual(left, right) { return JSON.stringify(left) === JSON.stringify(right); }
function requireSourceIdentity(journal) {
  const current = inventory(sourceRoot, true);
  if (!inventoriesEqual(current, journal.sourceInventory)) fail('Legacy source changed since preparation; inspect and prepare again before continuing');
}
function requireSafeRetirementRemainder(journal) {
  const expected = new Map(journal.sourceInventory.map(item => [item.path, item]));
  for (const item of inventory(sourceRoot, true)) {
    const original = expected.get(item.path);
    if (!original || !sameDescriptor(item, original) || item.classification !== original.classification) fail('Legacy source changed during retirement; preserve the remainder and inspect before retrying');
  }
}
function currentMappedInventory(entries) {
  return entries.map(item => ({ path: item.path, ...descriptor(item.destination) }));
}
function fullDestinationInventory() {
  return [
    ...inventory(agentRoot).map(item => ({ ...item, path: `agent/${item.path}` })),
    ...inventory(sessionRoot).map(item => ({ ...item, path: `sessions/${item.path}` })),
  ];
}
function transferEntries(entries) {
  for (const item of entries.filter(value => value.type === 'directory')) {
    const existing = descriptor(item.destination);
    if (existing.type === 'absent') {
      mkdirSync(item.destination, { recursive: true, mode: item.mode });
      chmodSync(item.destination, item.mode);
    }
  }
  for (const item of entries.filter(value => value.type !== 'directory')) {
    if (descriptor(item.destination).type !== 'absent') continue;
    mkdirSync(dirname(item.destination), { recursive: true, mode: 0o700 });
    if (item.type === 'file') { copyFileSync(join(sourceRoot, item.path), item.destination); chmodSync(item.destination, item.mode); }
    else if (item.type === 'symlink') symlinkSync(item.target, item.destination);
    else fail(`Unsupported transfer entry: ${item.path}`);
  }
}
function activationTargets() {
  const targets = [
    [join(home, '.config/dotfiles/bare-env.sh'), join(checkoutRoot, 'scripts/bare-env.sh')],
    [join(home, '.local/bin/dev-shell'), join(checkoutRoot, 'scripts/dev-shell')],
    [join(home, '.local/bin/pi'), join(checkoutRoot, 'scripts/pi-owned')],
    [join(home, '.local/bin/pi-workspace'), join(checkoutRoot, 'scripts/pi-workspace')],
    [join(home, '.local/bin/piw'), join(checkoutRoot, 'scripts/pi-workspace')],
    [join(home, '.local/bin/pi-headroom'), join(checkoutRoot, 'scripts/pi-headroom')],
  ];
  return targets.map(([target, source]) => {
    validateHomePath('activation target', target);
    return { target, source };
  });
}
function activationConflict(item) {
  const actual = descriptor(item.target);
  if (actual.type === 'absent' || (actual.type === 'symlink' && actual.target === item.source)) return undefined;
  if (actual.type === 'symlink' && snapshotLinkTarget(resolve(dirname(item.target), actual.target)) === item.source) return undefined;
  return { path: item.target, reason: 'activation target is not absent or a proven managed link' };
}
function writeActivation(journal) {
  const targets = activationTargets();
  const conflicts = targets.map(activationConflict).filter(Boolean);
  if (conflicts.length) fail(`Activation conflicts:\n${conflicts.map(item => `${item.path}: ${item.reason}`).join('\n')}`);
  if (!journal.activation) {
    journal.activation = targets.map(item => ({ ...item, before: descriptor(item.target) }));
    atomicWrite(journalPath, journal);
  }
  for (const item of journal.activation) {
    const current = descriptor(item.target);
    if (current.type === 'symlink' && current.target === item.source) continue;
    mkdirSync(dirname(item.target), { recursive: true, mode: 0o700 });
    if (current.type !== 'absent') rmSync(item.target);
    symlinkSync(item.source, item.target);
  }
  journal.phase = 'activated';
  atomicWrite(journalPath, journal);
}
function restoreActivation(journal) {
  for (const item of [...(journal.activation || [])].reverse()) {
    const current = descriptor(item.target);
    if (current.type !== 'symlink' || current.target !== item.source) fail(`Activation target changed; refusing rollback: ${item.target}`);
  }
  for (const item of [...(journal.activation || [])].reverse()) {
    rmSync(item.target);
    if (item.before.type === 'symlink') symlinkSync(item.before.target, item.target);
  }
}
function result(value) { process.stdout.write(`${JSON.stringify(value, null, 2)}\n`); }

validateRoots();
switch (command) {
  case 'inspect': {
    if (args.length) fail('migration inspect accepts no arguments', 2);
    result(inspect());
    break;
  }
  case 'prepare': {
    if (args.length) fail('migration prepare accepts no arguments', 2);
    if (existsSync(journalPath)) {
      const existing = loadJournal();
      if (existing.phase !== 'prepared') fail(`Preparation cannot replace migration state in phase ${existing.phase}`);
      requireSourceIdentity(existing);
      result({ schemaVersion: 1, phase: existing.phase, journalPath, sourceEntries: existing.sourceInventory.length });
      break;
    }
    const report = inspect();
    if (!report.sourcePresent) fail(`Legacy Pi state is absent: ${sourceRoot}`);
    if (!report.ready) fail(`Migration conflicts must be resolved before preparation:\n${JSON.stringify(report, null, 2)}`);
    const sourceInventory = inventory(sourceRoot, true);
    const entries = mappedEntries(sourceInventory);
    const journal = {
      schemaVersion: 1, phase: 'prepared', sourceRoot, agentRoot, sessionRoot,
      sourceInventory,
      destinationBefore: currentMappedInventory(entries),
      preparedAt: new Date().toISOString(),
    };
    atomicWrite(journalPath, journal);
    result({ schemaVersion: 1, phase: journal.phase, journalPath, sourceEntries: sourceInventory.length });
    break;
  }
  case 'transfer': {
    if (args.length) fail('migration transfer accepts no helper arguments', 2);
    const journal = loadJournal();
    if (!['prepared', 'transferred'].includes(journal.phase)) fail(`Transfer requires prepared state, found ${journal.phase}`);
    requireSourceIdentity(journal);
    if (journal.phase === 'transferred') {
      if (!Array.isArray(journal.transferredFullInventory) || !inventoriesEqual(fullDestinationInventory(), journal.transferredFullInventory)) fail('Transferred destination changed before retry');
      result({ schemaVersion: 1, phase: journal.phase, transferredEntries: journal.transferredInventory.length });
      break;
    }
    const entries = mappedEntries(journal.sourceInventory);
    const conflicts = destinationConflicts(entries);
    if (conflicts.length) fail(`Destination conflicts block transfer:\n${conflicts.map(item => `${item.path}: ${item.reason}`).join('\n')}`);
    transferEntries(entries);
    requireSourceIdentity(journal);
    const after = currentMappedInventory(entries);
    const expected = entries.map(item => ({ path: item.path, type: item.type, ...(item.mode === undefined ? {} : { mode: item.mode }), ...(item.size === undefined ? {} : { size: item.size }), ...(item.sha256 === undefined ? {} : { sha256: item.sha256 }), ...(item.type === 'symlink' ? { target: item.target } : {}) }));
    if (!inventoriesEqual(after, expected)) fail('Transferred destination verification failed; partial state is retained for retry');
    journal.transferredInventory = after;
    journal.transferredFullInventory = fullDestinationInventory();
    journal.phase = 'transferred'; journal.transferredAt = new Date().toISOString();
    atomicWrite(journalPath, journal);
    result({ schemaVersion: 1, phase: journal.phase, transferredEntries: after.length });
    break;
  }
  case 'activate': {
    if (args.length) fail('migration activate accepts no helper arguments', 2);
    const journal = loadJournal();
    if (!['transferred', 'activated'].includes(journal.phase)) fail(`Activation requires transferred state, found ${journal.phase}`);
    requireSourceIdentity(journal);
    if (!inventoriesEqual(currentMappedInventory(mappedEntries(journal.sourceInventory)), journal.transferredInventory)) fail('Transferred state changed before activation');
    writeActivation(journal);
    result({ schemaVersion: 1, phase: 'activated', activationTargets: journal.activation.length });
    break;
  }
  case 'verify': {
    if (args.length) fail('migration verify accepts no arguments', 2);
    const journal = loadJournal();
    if (!['activated', 'verified'].includes(journal.phase)) fail(`Verification requires activated state, found ${journal.phase}`);
    requireSourceIdentity(journal);
    const current = currentMappedInventory(mappedEntries(journal.sourceInventory));
    if (!inventoriesEqual(current, journal.transferredInventory)) fail('Transferred personal state changed before verification');
    for (const item of journal.activation || []) {
      const actual = descriptor(item.target);
      if (actual.type !== 'symlink' || actual.target !== item.source) fail(`Activation verification failed: ${item.target}`);
    }
    journal.phase = 'verified'; journal.verifiedAt = new Date().toISOString();
    atomicWrite(journalPath, journal);
    result({ schemaVersion: 1, phase: journal.phase, verifiedEntries: current.length });
    break;
  }
  case 'rollback': {
    if (args.length) fail('migration rollback accepts no helper arguments', 2);
    const journal = loadJournal();
    if (!['activated', 'verified'].includes(journal.phase)) fail(`Rollback requires activated or verified state, found ${journal.phase}`);
    const entries = mappedEntries(journal.sourceInventory);
    if (!Array.isArray(journal.transferredFullInventory) || !inventoriesEqual(fullDestinationInventory(), journal.transferredFullInventory)) fail('Destination has post-cutover additions, deletions, mode changes, link changes, or file changes; rollback refused. Preserve both roots and inspect differences before recovery.');
    restoreActivation(journal);
    for (let index = entries.length - 1; index >= 0; index -= 1) {
      const item = entries[index];
      const before = journal.destinationBefore[index];
      if (before.type !== 'absent') continue;
      const stat = lstatSafe(item.destination);
      if (!stat) continue;
      if (stat.isDirectory() && !stat.isSymbolicLink()) {
        if (readdirSync(item.destination).length === 0) rmdirSync(item.destination);
      } else rmSync(item.destination);
    }
    journal.phase = 'rolled-back'; journal.rolledBackAt = new Date().toISOString();
    atomicWrite(journalPath, journal);
    result({ schemaVersion: 1, phase: journal.phase });
    break;
  }
  case 'retire': {
    if (args.length) fail('migration retire accepts no helper arguments', 2);
    const journal = loadJournal();
    if (!['verified', 'retiring'].includes(journal.phase)) fail(`Retirement requires verified state, found ${journal.phase}`);
    if (journal.phase === 'verified') {
      requireSourceIdentity(journal);
      const current = currentMappedInventory(mappedEntries(journal.sourceInventory));
      if (!inventoriesEqual(current, journal.transferredInventory)) fail('Destination changed after verification; re-verify and preserve new writes before retirement');
      journal.phase = 'retiring';
      atomicWrite(journalPath, journal);
    }
    if (lstatSafe(sourceRoot)) {
      requireSafeRetirementRemainder(journal);
      rmSync(sourceRoot, { recursive: true });
    }
    journal.phase = 'retired'; journal.retiredAt = new Date().toISOString();
    atomicWrite(journalPath, journal);
    result({ schemaVersion: 1, phase: journal.phase, retiredRoot: sourceRoot });
    break;
  }
  case 'status': {
    if (args.length) fail('migration status accepts no arguments', 2);
    if (!existsSync(journalPath)) result({ schemaVersion: 1, phase: 'unprepared' });
    else { const journal = loadJournal(); result({ schemaVersion: 1, phase: journal.phase }); }
    break;
  }
  case 'allows-adoption': {
    if (args.length) fail('migration allows-adoption accepts no arguments', 2);
    const journal = loadJournal();
    if (!['activated', 'verified', 'retired'].includes(journal.phase)) process.exit(3);
    if (journal.phase === 'retired') {
      if (lstatSafe(sourceRoot)) fail('Retired legacy source unexpectedly reappeared');
    } else requireSourceIdentity(journal);
    if (!inventoriesEqual(currentMappedInventory(mappedEntries(journal.sourceInventory)), journal.transferredInventory)) fail('Migrated destination changed before adoption');
    break;
  }
  case 'protected-list': {
    if (args.length) fail('migration protected-list accepts no arguments', 2);
    if (!existsSync(journalPath)) break;
    const journal = loadJournal();
    for (const item of mappedEntries(journal.sourceInventory)) {
      if (item.type !== 'directory' && item.classification !== 'managed') console.log(item.destination);
    }
    break;
  }
  default: fail('Unknown migration helper command', 2);
}
