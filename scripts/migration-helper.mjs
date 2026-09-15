#!/usr/bin/env node
import {
  chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync,
  readlinkSync, readdirSync, realpathSync, renameSync, rmdirSync, rmSync, symlinkSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, isAbsolute, join, normalize, relative, resolve, sep } from 'node:path';
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
function pathChain(root, value) {
  const rel = relative(root, value);
  const result = [root];
  if (!rel) return result;
  let cursor = root;
  for (const component of rel.split(sep)) { cursor = join(cursor, component); result.push(cursor); }
  return result;
}
function validateHomePath(name, value) {
  if (!isAbsolute(value) || value === '/' || !within(home, value)) fail(`${name} must be an absolute path below HOME: ${value}`, 2);
  for (const path of pathChain(home, value)) {
    const stat = lstatSafe(path);
    if (!stat) continue;
    if (stat.isSymbolicLink()) fail(`${name} has a symlink component: ${path}`);
    if (path !== value && !stat.isDirectory()) fail(`${name} has a non-directory ancestor: ${path}`);
    if (realpathSync(path) !== path) fail(`${name} is not canonical at: ${path}`);
  }
}
function relevantRootPaths() {
  const paths = new Set([home]);
  for (const root of [sourceRoot, privateRoot, agentRoot, sessionRoot, stateRoot]) for (const path of pathChain(home, root)) paths.add(path);
  return [...paths].sort();
}
function captureRootIdentities() {
  const identities = {};
  for (const path of relevantRootPaths()) {
    const stat = lstatSafe(path);
    if (stat) identities[path] = `${stat.dev}:${stat.ino}`;
  }
  return identities;
}
function validateRootIdentities(identities) {
  if (!plainObject(identities)) fail('Malformed migration root identities');
  const allowed = new Set(relevantRootPaths());
  for (const [path, identity] of Object.entries(identities)) {
    if (!allowed.has(path) || !/^[0-9]+:[0-9]+$/.test(identity)) fail('Malformed migration root identity');
    const stat = lstatSafe(path);
    if (stat && (stat.isSymbolicLink() || `${stat.dev}:${stat.ino}` !== identity)) fail(`Migration root identity changed: ${path}`);
  }
}
function validateRoots() {
  const homeStat = lstatSafe(home);
  if (!isAbsolute(home) || home === '/' || !homeStat?.isDirectory() || homeStat.isSymbolicLink() || realpathSync(home) !== home) fail(`HOME must be a canonical non-symlink directory below /: ${home}`, 2);
  for (const [name, value] of [['legacy Pi root', sourceRoot], ['private root', privateRoot], ['agent root', agentRoot], ['session root', sessionRoot], ['state root', stateRoot]]) validateHomePath(name, value);
  if (within(sourceRoot, privateRoot, true) || within(privateRoot, sourceRoot, true)) fail('Legacy and destination roots must not overlap', 2);
  const sourceReal = lstatSafe(sourceRoot) ? realpathSync(sourceRoot) : undefined;
  for (const destination of [privateRoot, agentRoot, sessionRoot]) {
    if (!sourceReal || !lstatSafe(destination)) continue;
    const destinationReal = realpathSync(destination);
    if (within(sourceReal, destinationReal, true) || within(destinationReal, sourceReal, true)) fail('Legacy and destination roots physically overlap');
  }
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
  if (actual.type === 'directory') return actual.mode === expected.mode;
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
  if (typeof path !== 'string' || path === '' || isAbsolute(path) || normalize(path) !== path || path.includes('\0') || path.includes('\n') || path.includes('\r')) return false;
  return path.split(sep).every(component => component !== '' && component !== '.' && component !== '..');
}
function exactKeys(value, expected) { return Object.keys(value).sort().join(',') === [...expected].sort().join(','); }
function validStoredDescriptor(item, withPath = true, source = false) {
  if (!plainObject(item) || !['absent', 'directory', 'file', 'symlink'].includes(item.type)) return false;
  const prefix = withPath ? ['path'] : [];
  if (withPath && !validRelativePath(item.path)) return false;
  if (item.type === 'absent') return exactKeys(item, [...prefix, 'type']);
  if (item.type === 'directory') return exactKeys(item, [...prefix, 'type', 'mode']) && Number.isInteger(item.mode) && item.mode >= 0 && item.mode <= 0o777;
  if (item.type === 'file') return exactKeys(item, [...prefix, 'type', 'mode', 'size', 'sha256']) && Number.isInteger(item.mode) && item.mode >= 0 && item.mode <= 0o777 && Number.isSafeInteger(item.size) && item.size >= 0 && /^[0-9a-f]{64}$/.test(item.sha256 || '');
  const keys = source ? [...prefix, 'type', 'target', 'classification'] : [...prefix, 'type', 'target'];
  return exactKeys(item, keys) && typeof item.target === 'string' && !item.target.includes('\0') && (!source || ['internal', 'managed'].includes(item.classification));
}
function validateUniqueInventory(items, name, source = false) {
  if (!Array.isArray(items) || items.length > maxEntries) fail(`Malformed ${name}`);
  const paths = new Set();
  for (const item of items) {
    if (!validStoredDescriptor(item, true, source) || paths.has(item.path)) fail(`Malformed ${name}`);
    paths.add(item.path);
  }
}
function expectedTransferredEntry(source) {
  return { path: source.path, type: source.type, ...(source.mode === undefined ? {} : { mode: source.mode }), ...(source.size === undefined ? {} : { size: source.size }), ...(source.sha256 === undefined ? {} : { sha256: source.sha256 }), ...(source.type === 'symlink' ? { target: source.target } : {}) };
}
function fullPathForSource(path) { return path === 'sessions' || path.startsWith(`sessions${sep}`) ? path : `agent${sep}${path}`; }
function validateJournal(value) {
  const allowedKeys = ['schemaVersion','phase','sourceRoot','agentRoot','sessionRoot','sourceInventory','destinationBefore','rootIdentities','preparedAt','transferredInventory','transferredFullInventory','transferredAt','activation','verifiedInventory','verifiedFullInventory','verifiedAt','rollbackState','rolledBackAt','retiredAt'];
  if (!plainObject(value) || Object.keys(value).some(key => !allowedKeys.includes(key)) || value.schemaVersion !== 1 || !['prepared', 'transferred', 'activated', 'verified', 'retiring', 'rolling-back', 'rolled-back', 'retired'].includes(value.phase)) fail('Malformed migration journal');
  if (value.sourceRoot !== sourceRoot || value.agentRoot !== agentRoot || value.sessionRoot !== sessionRoot) fail('Migration roots differ from the recorded operation');
  validateRootIdentities(value.rootIdentities);
  validateUniqueInventory(value.sourceInventory, 'source migration inventory', true);
  validateUniqueInventory(value.destinationBefore, 'destination migration inventory');
  if (value.destinationBefore.length !== value.sourceInventory.length) fail('Migration inventories do not correspond');
  value.sourceInventory.forEach((item, index) => {
    if (value.destinationBefore[index].path !== item.path) fail('Migration inventories do not correspond');
    const destination = destinationFor(item.path);
    if (!within(agentRoot, destination, true) && !within(sessionRoot, destination, true)) fail('Mapped migration destination escaped roots');
    if (item.type === 'symlink') {
      const resolvedTarget = resolve(dirname(destination), item.target);
      if (item.classification === 'internal' && !within(agentRoot, resolvedTarget, true) && !within(sessionRoot, resolvedTarget, true)) fail('Internal migration link escaped destination roots');
      if (item.classification === 'managed' && !within(checkoutRoot, resolvedTarget, true)) fail('Managed migration link escaped the selected source');
    }
  });
  if (value.transferredInventory !== undefined) {
    validateUniqueInventory(value.transferredInventory, 'transferred migration inventory');
    if (value.transferredInventory.length !== value.sourceInventory.length) fail('Transferred inventory does not correspond');
    value.sourceInventory.forEach((item, index) => { if (!sameDescriptor(value.transferredInventory[index], expectedTransferredEntry(item)) || value.transferredInventory[index].path !== item.path) fail('Transferred inventory does not correspond'); });
    validateUniqueInventory(value.transferredFullInventory, 'full transferred inventory');
    const full = new Map(value.transferredFullInventory.map(item => [item.path, item]));
    for (const item of value.transferredInventory) if (!sameDescriptor(full.get(fullPathForSource(item.path)) || { type: 'absent' }, item)) fail('Full transferred inventory does not correspond');
  }
  if (value.verifiedInventory !== undefined) {
    validateUniqueInventory(value.verifiedInventory, 'verified migration inventory');
    if (value.verifiedInventory.length !== value.sourceInventory.length) fail('Verified inventory does not correspond');
    value.verifiedInventory.forEach((item, index) => { if (item.path !== value.sourceInventory[index].path) fail('Verified inventory does not correspond'); });
    validateUniqueInventory(value.verifiedFullInventory, 'full verified inventory');
    const full = new Map(value.verifiedFullInventory.map(item => [item.path, item]));
    for (const item of value.verifiedInventory) if (!sameDescriptor(full.get(fullPathForSource(item.path)) || { type: 'absent' }, item)) fail('Full verified inventory does not correspond');
  }
  if (value.activation !== undefined) {
    const expected = activationTargets();
    if (!Array.isArray(value.activation) || value.activation.length !== expected.length) fail('Malformed activation journal');
    value.activation.forEach((item, index) => {
      if (!plainObject(item) || !exactKeys(item, ['target','source','before']) || item.target !== expected[index].target || item.source !== expected[index].source || !validStoredDescriptor(item.before, false) || !['absent','symlink'].includes(item.before.type)) fail('Malformed activation target');
    });
  }
  if (value.phase === 'rolling-back' && value.rollbackState === undefined) fail('Rolling-back journal has no progress state');
  if (value.rollbackState !== undefined) {
    if (!plainObject(value.rollbackState) || !exactKeys(value.rollbackState, ['activationRestored','destinationsRemoved']) || !Array.isArray(value.rollbackState.activationRestored) || !Array.isArray(value.rollbackState.destinationsRemoved)) fail('Malformed rollback state');
    const targets = new Set((value.activation || []).map(item => item.target));
    if (new Set(value.rollbackState.activationRestored).size !== value.rollbackState.activationRestored.length || value.rollbackState.activationRestored.some(path => !targets.has(path))) fail('Malformed rollback progress');
    const paths = new Set(value.sourceInventory.map(item => item.path));
    if (new Set(value.rollbackState.destinationsRemoved).size !== value.rollbackState.destinationsRemoved.length || value.rollbackState.destinationsRemoved.some(path => !paths.has(path))) fail('Malformed rollback progress');
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
function destinationPreservesSource(actual, source) {
  if (actual.type !== source.type) return false;
  if (source.type === 'symlink') return actual.target === source.target;
  return ['directory', 'file'].includes(source.type);
}
function requireVerifiedDestination(journal) {
  if (!Array.isArray(journal.verifiedInventory) || !Array.isArray(journal.verifiedFullInventory)) fail('Migration needs a fresh quiescent verification receipt');
  const current = currentMappedInventory(mappedEntries(journal.sourceInventory));
  if (!inventoriesEqual(current, journal.verifiedInventory) || !inventoriesEqual(fullDestinationInventory(), journal.verifiedFullInventory)) fail('Destination changed since quiescent verification; verify again before retirement');
}
function fullDestinationInventory() {
  const result = [];
  const agent = descriptor(agentRoot); if (agent.type !== 'absent') result.push({ path: 'agent', ...agent });
  result.push(...inventory(agentRoot).map(item => ({ ...item, path: `agent/${item.path}` })));
  const sessions = descriptor(sessionRoot); if (sessions.type !== 'absent') result.push({ path: 'sessions', ...sessions });
  result.push(...inventory(sessionRoot).map(item => ({ ...item, path: `sessions/${item.path}` })));
  return result;
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
    validateHomePath('activation parent', dirname(target));
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
function testFault(boundary) {
  if (process.env.BOOTSTRAP_MIGRATION_TEST_FAULT !== boundary) return;
  if (process.env.BOOTSTRAP_MIGRATION_TEST_ONLY !== '1' || resolve(process.env.BOOTSTRAP_MIGRATION_TEST_HOME || '') !== home) fail('Migration fault injection is restricted to an explicit HOME fixture', 2);
  console.error(`Injected migration test fault: ${boundary}`);
  process.exit(86);
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
    mkdirSync(stateRoot, { recursive: true, mode: 0o700 });
    const journal = {
      schemaVersion: 1, phase: 'prepared', sourceRoot, agentRoot, sessionRoot,
      sourceInventory,
      destinationBefore: currentMappedInventory(entries),
      rootIdentities: captureRootIdentities(),
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
    journal.rootIdentities = { ...journal.rootIdentities, ...captureRootIdentities() };
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
    current.forEach((item, index) => { if (!destinationPreservesSource(item, expectedTransferredEntry(journal.sourceInventory[index]))) fail(`Migrated destination is missing or unsafe: ${item.path}`); });
    for (const item of journal.activation || []) {
      const actual = descriptor(item.target);
      if (actual.type !== 'symlink' || actual.target !== item.source) fail(`Activation verification failed: ${item.target}`);
    }
    journal.verifiedInventory = current;
    journal.verifiedFullInventory = fullDestinationInventory();
    journal.phase = 'verified'; journal.verifiedAt = new Date().toISOString();
    atomicWrite(journalPath, journal);
    result({ schemaVersion: 1, phase: journal.phase, verifiedEntries: current.length });
    break;
  }
  case 'rollback': {
    if (args.length) fail('migration rollback accepts no helper arguments', 2);
    const journal = loadJournal();
    if (!['activated', 'verified', 'rolling-back'].includes(journal.phase)) fail(`Rollback requires activated, verified, or rolling-back state, found ${journal.phase}`);
    requireSourceIdentity(journal);
    const entries = mappedEntries(journal.sourceInventory);
    if (journal.phase !== 'rolling-back') {
      if (!Array.isArray(journal.transferredFullInventory) || !inventoriesEqual(fullDestinationInventory(), journal.transferredFullInventory)) fail('Destination has post-cutover additions, deletions, mode changes, link changes, or file changes; rollback refused. Preserve both roots and inspect differences before recovery.');
      journal.phase = 'rolling-back';
      journal.rollbackState = { activationRestored: [], destinationsRemoved: [] };
      atomicWrite(journalPath, journal);
      testFault('rollback-after-intent');
    }
    for (let index = journal.activation.length - 1; index >= 0; index -= 1) {
      const item = journal.activation[index];
      const current = descriptor(item.target);
      const restored = sameDescriptor(current, item.before);
      if (!restored && !(current.type === 'symlink' && current.target === item.source)) fail(`Activation target is neither rollback before nor after state: ${item.target}`);
      if (!restored) {
        rmSync(item.target);
        if (item.before.type === 'symlink') symlinkSync(item.before.target, item.target);
        testFault(`rollback-after-activation-${index}`);
      }
      if (!journal.rollbackState.activationRestored.includes(item.target)) {
        journal.rollbackState.activationRestored.push(item.target);
        atomicWrite(journalPath, journal);
      }
    }
    for (let index = entries.length - 1; index >= 0; index -= 1) {
      const item = entries[index];
      const before = journal.destinationBefore[index];
      if (before.type !== 'absent') continue;
      const current = descriptor(item.destination);
      const removed = current.type === 'absent';
      if (!removed && !sameDescriptor(current, journal.transferredInventory[index])) fail(`Migration destination is neither rollback before nor after state: ${item.destination}`);
      if (!removed) {
        if (current.type === 'directory') {
          if (readdirSync(item.destination).length !== 0) fail(`Rollback directory still contains migrated entries: ${item.destination}`);
          rmdirSync(item.destination);
        } else rmSync(item.destination);
        testFault(`rollback-after-destination-${index}`);
      }
      if (!journal.rollbackState.destinationsRemoved.includes(item.path)) {
        journal.rollbackState.destinationsRemoved.push(item.path);
        atomicWrite(journalPath, journal);
      }
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
    requireVerifiedDestination(journal);
    if (journal.phase === 'verified') {
      requireSourceIdentity(journal);
      journal.phase = 'retiring';
      atomicWrite(journalPath, journal);
      testFault('retire-after-intent');
    }
    if (lstatSafe(sourceRoot)) {
      requireSafeRetirementRemainder(journal);
      requireVerifiedDestination(journal);
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
    const current = currentMappedInventory(mappedEntries(journal.sourceInventory));
    current.forEach((item, index) => { if (!destinationPreservesSource(item, expectedTransferredEntry(journal.sourceInventory[index]))) fail('Migrated destination is missing or unsafe before adoption'); });
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
