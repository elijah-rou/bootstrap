#!/usr/bin/env node
import { chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, realpathSync, renameSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { createHash, randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const [command, ...args] = process.argv.slice(2);
const home = resolve(process.env.HOME || '');
const stateHome = resolve(process.env.XDG_STATE_HOME || join(home, '.local/state'));
const stateRoot = resolve(process.env.BOOTSTRAP_STATE_ROOT || join(stateHome, 'bootstrap'));
const recordPath = join(stateRoot, 'install.json');
const maxResources = 4096;
const maxSelections = 128;

function fail(message) { console.error(message); process.exit(1); }
function inside(root, value, allowRoot = false) {
  if (!isAbsolute(value) || value.includes('\0') || value.includes('\n') || value.includes('\r')) return false;
  const normalized = resolve(value);
  const rel = relative(resolve(root), normalized);
  return (allowRoot && rel === '') || (rel !== '' && rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel));
}
function validateTarget(value) {
  if (!inside(home, value)) fail(`Refusing path outside HOME: ${value}`);
  if (resolve(value) === home) fail('Refusing HOME as a managed target');
  let cursor = dirname(resolve(value));
  while (inside(home, cursor, true) && cursor !== home) {
    if (existsSync(cursor) && lstatSync(cursor).isSymbolicLink()) {
      const real = realpathSync(cursor);
      if (!inside(home, real, true)) fail(`Refusing symlink escape through ${cursor}`);
    }
    cursor = dirname(cursor);
  }
  return resolve(value);
}
function validatePolicyPlugin(item) {
  if (!isAbsolute(item.target) || !isAbsolute(item.checkout) || !isAbsolute(item.source)) fail('External policy paths must be absolute');
  const checkout = resolve(item.checkout);
  const target = resolve(item.target);
  if (target !== join(checkout, 'lua/plugins/zz-bootstrap-managed.lua')) fail('External policy target is not the fixed plugin path');
  const checkoutStat = lstatSafe(checkout);
  if (!checkoutStat?.isDirectory() || checkoutStat.isSymbolicLink() || realpathSync(checkout) !== checkout) fail('External Neovim checkout identity changed');
  if (`${checkoutStat.dev}:${checkoutStat.ino}` !== item.checkoutIdentity) fail('External Neovim checkout was replaced');
  let cursor = dirname(target);
  while (cursor !== checkout) {
    const stat = lstatSafe(cursor);
    if (!stat?.isDirectory() || stat.isSymbolicLink()) fail(`External policy parent changed: ${cursor}`);
    cursor = dirname(cursor);
    if (!inside(checkout, cursor, true)) fail('External policy parent escaped checkout');
  }
  return target;
}
function blank() {
  return { schemaVersion: 1, installationId: randomBytes(16).toString('hex'), status: 'installing', components: {}, selections: { languages: [], lsp: [], tools: [] }, resources: [], packages: [], enrolledRoots: [], createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
}
function validate(record) {
  if (!record || Object.getPrototypeOf(record) !== Object.prototype || record.schemaVersion !== 1) fail('Unsupported or malformed installation record');
  if (typeof record.installationId !== 'string' || !/^[0-9a-f]{32}$/.test(record.installationId)) fail('Malformed installation ID');
  if (!['installing', 'partial', 'ready', 'uninstalling', 'cleanup-failed'].includes(record.status)) fail('Malformed installation status');
  if (record.components === undefined) record.components = {};
  if (!record.components || Object.getPrototypeOf(record.components) !== Object.prototype || Object.keys(record.components).length > 32 || Object.entries(record.components).some(([name,status]) => !/^[a-z][a-z-]*$/.test(name) || !['installing','ready'].includes(status))) fail('Malformed component readiness');
  for (const group of ['languages', 'lsp', 'tools']) {
    if (!Array.isArray(record.selections?.[group]) || record.selections[group].length > maxSelections || record.selections[group].some(v => typeof v !== 'string' || !/^[a-z0-9][a-z0-9-]*$/.test(v))) fail('Malformed selections');
  }
  if (!Array.isArray(record.resources) || record.resources.length > maxResources) fail('Malformed resources');
  if (!Array.isArray(record.packages) || record.packages.length > maxResources) fail('Malformed packages');
  if (!Array.isArray(record.enrolledRoots) || record.enrolledRoots.length > maxResources) fail('Malformed enrolled roots');
  for (const item of record.resources) {
    if (!item || typeof item.target !== 'string' || !['absent','file','symlink'].includes(item.priorType) || !['shared','owned'].includes(item.class)) fail('Malformed resource');
    if (item.externalPolicyPlugin === true) validatePolicyPlugin(item); else validateTarget(item.target);
    if (item.backup && !inside(stateRoot, item.backup)) fail('Resource backup escaped state root');
    if (item.installerBackup) validateTarget(item.installerBackup);
  }
  const packageIdentities = new Set();
  for (const item of record.packages) {
    if (!item || !['apt', 'dnf', 'pacman', 'brew'].includes(item.backend) || typeof item.name !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9+_.@:/-]{0,191}$/.test(item.name) || typeof item.preexisting !== 'boolean' || typeof item.installed !== 'boolean' || typeof item.priorVersion !== 'string') fail('Malformed native package identity');
    const identity = `${item.backend}/${item.name}`;
    if (packageIdentities.has(identity)) fail('Duplicate native package identity');
    packageIdentities.add(identity);
  }
  if (record.enrolledRootIdentities !== undefined) {
    if (!record.enrolledRootIdentities || Object.getPrototypeOf(record.enrolledRootIdentities) !== Object.prototype || Object.keys(record.enrolledRootIdentities).length > maxResources) fail('Malformed enrolled root identities');
    for (const [root, identity] of Object.entries(record.enrolledRootIdentities)) {
      if (!record.enrolledRoots.includes(root) || typeof identity !== 'string' || !/^(pending|[0-9]+:[0-9]+)$/.test(identity)) fail('Malformed enrolled root identity');
      const stat = lstatSafe(root);
      if (stat && (identity === 'pending' || !stat.isDirectory() || stat.isSymbolicLink() || `${stat.dev}:${stat.ino}` !== identity)) fail(`Enrolled location identity changed: ${root}`);
    }
  }
  for (const root of record.enrolledRoots) validateTarget(root);
  return record;
}
function load(required = true) {
  if (!existsSync(recordPath)) { if (required) fail(`Installation record is missing: ${recordPath}`); return blank(); }
  let value;
  try { value = JSON.parse(readFileSync(recordPath, 'utf8')); } catch { fail('Malformed installation record JSON'); }
  return validate(value);
}
function save(record) {
  validate(record); mkdirSync(stateRoot, { recursive: true, mode: 0o700 });
  record.updatedAt = new Date().toISOString();
  const temporary = `${recordPath}.new.${process.pid}`;
  writeFileSync(temporary, `${JSON.stringify(record, null, 2)}\n`, { mode: 0o600 });
  renameSync(temporary, recordPath);
}
function prepare(target, resourceClass, source = '') {
  target = validateTarget(target);
  if (!['shared', 'owned'].includes(resourceClass)) fail('Unknown resource class');
  const record = load(false);
  if (record.resources.some(item => item.target === target)) return;
  const item = { target, class: resourceClass, source, priorType: 'absent', backup: '' };
  if (existsSync(target) || lstatSafe(target)?.isSymbolicLink()) {
    const stat = lstatSync(target);
    if (stat.isSymbolicLink()) { item.priorType = 'symlink'; item.priorLink = readlinkSync(target); }
    else if (stat.isFile()) {
      item.priorType = 'file';
      const backup = join(stateRoot, 'recovery', `${record.resources.length}.original`);
      mkdirSync(dirname(backup), { recursive: true, mode: 0o700 }); copyFileSync(target, backup); item.backup = backup; item.priorMode = stat.mode & 0o777;
    } else fail(`Refusing to replace unmanaged directory or special file: ${target}`);
  }
  record.resources.push(item); save(record);
}
function lstatSafe(path) { try { return lstatSync(path); } catch { return undefined; } }
function removePath(path) { const stat = lstatSafe(path); if (!stat) return; if (stat.isDirectory() && !stat.isSymbolicLink()) rmSync(path, { recursive: true }); else rmSync(path); }
function fileHash(path) { return createHash('sha256').update(readFileSync(path)).digest('hex'); }
function restore(item, dryRun) {
  const target = item.externalPolicyPlugin === true ? validatePolicyPlugin(item) : validateTarget(item.target);
  const stat = lstatSafe(target);
  if (item.externalPolicyPlugin === true && !item.activeType && stat) fail(`Unactivated external policy target appeared; refusing cleanup: ${target}`);
  if (item.class === 'shared' && item.activeType) {
    if (!stat) fail(`Managed target disappeared; refusing complete cleanup: ${target}`);
    if (item.activeType === 'symlink' && (!stat.isSymbolicLink() || readlinkSync(target) !== item.activeLink)) fail(`Managed target changed; refusing cleanup: ${target}`);
    if (item.activeType === 'file' && (!stat.isFile() || fileHash(target) !== item.activeHash)) fail(`Managed target changed; refusing cleanup: ${target}`);
  }
  console.log(`${item.priorType === 'absent' ? 'remove' : 'restore'}\t${target}`);
  if (dryRun) return;
  removePath(target); mkdirSync(dirname(target), { recursive: true });
  if (item.priorType === 'symlink') symlinkSync(item.priorLink, target);
  if (item.priorType === 'file') { if (!item.backup || !existsSync(item.backup)) fail(`Missing recovery backup for ${target}`); copyFileSync(item.backup, target); if (item.priorMode) chmodSync(target, item.priorMode); }
}
function merge(base, overlay) { if (base && overlay && Object.getPrototypeOf(base) === Object.prototype && Object.getPrototypeOf(overlay) === Object.prototype) { const result = { ...base }; for (const [key,value] of Object.entries(overlay)) result[key] = key in result ? merge(result[key], value) : value; return result; } return overlay; }
function readObject(path) { const value = JSON.parse(readFileSync(path, 'utf8')); if (!value || Object.getPrototypeOf(value) !== Object.prototype) fail(`Configuration must be a JSON object: ${path}`); return value; }

function run(command, args) {
switch (command) {
  case 'init': { const record = load(false); record.status = 'installing'; save(record); break; }
  case 'ready': { const record = load(); record.status = 'ready'; save(record); break; }
  case 'component-begin': { if(args.length!==1||!/^[a-z][a-z-]*$/.test(args[0]))fail('component-begin NAME');const record=load(false);record.components[args[0]]='installing';record.status='installing';save(record);break; }
  case 'component-ready': { if(args.length!==1||!/^[a-z][a-z-]*$/.test(args[0]))fail('component-ready NAME');const record=load();record.components[args[0]]='ready';record.status=record.components.core==='ready'?'ready':'partial';save(record);break; }
  case 'validate': { load(); console.log(recordPath); break; }
  case 'prepare': { if (args.length < 2 || args.length > 3) fail('prepare TARGET CLASS [SOURCE]'); prepare(args[0], args[1], args[2] || ''); break; }
  case 'prepare-policy-plugin': { if(args.length!==3)fail('prepare-policy-plugin TARGET CHECKOUT SOURCE');const checkout=resolve(args[1]),target=resolve(args[0]);const stat=lstatSafe(checkout);if(!stat?.isDirectory()||stat.isSymbolicLink()||realpathSync(checkout)!==checkout)fail('External Neovim checkout must be a canonical non-symlink directory');const draft={target,checkout,source:resolve(args[2]),checkoutIdentity:`${stat.dev}:${stat.ino}`,externalPolicyPlugin:true,class:'shared',priorType:'absent',backup:''};validatePolicyPlugin(draft);const record=load();const found=record.resources.find(item=>item.target===target);const targetStat=lstatSafe(target);if(found){if(found.externalPolicyPlugin!==true||found.checkout!==checkout)fail('External policy target ownership is ambiguous');if(targetStat&&(!targetStat.isSymbolicLink()||readlinkSync(target)!==found.activeLink))fail('External policy plugin identity changed');found.source=draft.source;}else{if(targetStat)fail('External policy plugin target must be absent before enrollment');record.resources.push(draft);}save(record);break; }
  case 'activate-policy-plugin': { if(args.length!==1)fail('activate-policy-plugin TARGET');const target=resolve(args[0]);const record=load();const item=record.resources.find(value=>value.target===target&&value.externalPolicyPlugin===true);if(!item)fail('External policy plugin was not prepared');validatePolicyPlugin(item);const stat=lstatSafe(target);if(!stat?.isSymbolicLink()||readlinkSync(target)!==item.source)fail('External policy plugin activation identity mismatch');item.activeType='symlink';item.activeLink=item.source;save(record);break; }
  case 'adopt-link': { if(args.length!==2)fail('adopt-link TARGET SOURCE');const target=validateTarget(args[0]);const stat=lstatSafe(target);if(!stat?.isSymbolicLink()||readlinkSync(target)!==args[1])fail('Legacy link identity changed');const record=load();if(!record.resources.some(item=>item.target===target))record.resources.push({target,class:'shared',source:args[1],priorType:'absent',backup:'',activeType:'symlink',activeLink:args[1]});save(record);break; }
  case 'activate': { if (args.length !== 1) fail('activate TARGET'); const target = validateTarget(args[0]); const record = load(); const item = record.resources.find(value => value.target === target); if (!item) fail(`Unprepared target: ${target}`); const stat = lstatSafe(target); if (!stat) fail(`Managed target was not created: ${target}`); if (stat.isSymbolicLink()) { item.activeType = 'symlink'; item.activeLink = readlinkSync(target); } else if (stat.isFile()) { item.activeType = 'file'; item.activeHash = fileHash(target); } else fail(`Unsupported managed target type: ${target}`); save(record); break; }
  case 'backup': { if(args.length!==2)fail('backup TARGET BACKUP');const target=validateTarget(args[0]),backup=validateTarget(args[1]);const record=load();const item=record.resources.find(value=>value.target===target);if(!item)fail(`Unprepared target: ${target}`);item.installerBackup=backup;save(record);break; }
  case 'select': { if (args.length !== 2 || !['languages','lsp','tools'].includes(args[0]) || !/^[a-z0-9][a-z0-9-]*$/.test(args[1])) fail('select GROUP NAME'); const record = load(false); if (!record.selections[args[0]].includes(args[1])) record.selections[args[0]].push(args[1]); save(record); break; }
  case 'selections': { const record = load(); for (const group of ['languages','lsp','tools']) for (const name of record.selections[group]) console.log(`${group}\t${name}`); break; }
  case 'package': { if (args.length !== 5 || !['0','1'].includes(args[2]) || !['pending','installed'].includes(args[4])) fail('package BACKEND NAME PREEXISTED VERSION STATUS'); const record = load(); const found = record.packages.find(item => item.backend === args[0] && item.name === args[1]); if (!found) record.packages.push({ backend: args[0], name: args[1], preexisting: args[2] === '1', priorVersion: args[3], installed: args[4] === 'installed' }); else found.installed = args[4] === 'installed'; save(record); break; }
  case 'package-removed': { if (args.length !== 2) fail('package-removed BACKEND NAME'); const record=load(); const found=record.packages.find(item=>item.backend===args[0]&&item.name===args[1]); if(!found||found.preexisting) fail('Unknown removable package'); found.installed=false; save(record); break; }
  case 'enroll': { if (args.length !== 1) fail('enroll ROOT'); const target = validateTarget(args[0]); const stat=lstatSafe(target); if(stat?.isSymbolicLink()) fail(`Refusing symlink enrollment root: ${target}`); if(stat&&!stat.isDirectory()) fail(`Enrollment root is not a directory: ${target}`); const record = load(); if (!record.enrolledRoots.includes(target)) record.enrolledRoots.push(target); save(record); break; }
  case 'json-merge': { if (args.length < 2) fail('json-merge OUTPUT BASE [OVERLAY...]'); let result = readObject(args[1]); for (const path of args.slice(2)) if (path && existsSync(path)) result = merge(result, readObject(path)); writeFileSync(args[0], `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600 }); break; }
  case 'json-packages': { const value = readObject(args[0]); if (!Array.isArray(value.packages)) fail('packages must be an array'); for (const item of value.packages) { const source = typeof item === 'string' ? item : item?.source; if (typeof source !== 'string' || source.includes('\n')) fail('Invalid package source'); console.log(source); } break; }
  case 'terminal-render': { if (args.length < 2) fail('terminal-render OUTPUT_DIR BASE [OVERLAY...]'); const [output, base, ...directories] = args; mkdirSync(output, { recursive: true }); const quote = value => `'${value.replaceAll("'", "'\\''")}'`; const git = [base, ...directories.map(value => join(value, 'gitconfig')).filter(existsSync)]; writeFileSync(join(output, 'gitconfig'), git.map(value => `[include]\n    path = ${JSON.stringify(value)}\n`).join('')); for (const [name,file] of [['env.sh','env.sh'],['zshenv','workstation.zsh']]) { const sources = directories.map(value => join(value,name)).filter(existsSync); writeFileSync(join(output,file), '# Generated by bootstrap configure; edit overlay sources.\n' + sources.map(value => `[ ! -f ${quote(value)} ] || . ${quote(value)}\n`).join('')); } break; }
  case 'lsp-output': { if (args.length !== 2) fail('lsp-output CATALOG OUTPUT'); const catalog = readObject(args[0]); if (catalog.schemaVersion !== 1 || !catalog.lsp) fail('Malformed catalog'); const record = load(); const selected = {}; for (const name of record.selections.lsp) { const value = catalog.lsp[name]; if (!value) fail(`Selected LSP missing from catalog: ${name}`); const entry = { selector: name, cmd: value.command, filetypes: value.filetypes };
      if (Object.hasOwn(value, 'root_markers')) {
        if (!Array.isArray(value.root_markers) || value.root_markers.length < 1 || value.root_markers.length > 16 || value.root_markers.some(marker => typeof marker !== 'string' || !/^[A-Za-z0-9_.-]{1,128}$/.test(marker) || ['.', '..'].includes(marker))) fail('Malformed LSP root_markers');
        entry.root_markers = value.root_markers;
      }
      if (Object.hasOwn(value, 'root_policy')) {
        if (value.root_policy !== 'rust-standalone') fail('Unknown LSP root_policy');
        entry.root_policy = value.root_policy;
      }
      if (Object.hasOwn(value, 'verification')) {
        const verification = value.verification;
        if (!verification || Object.getPrototypeOf(verification) !== Object.prototype || Object.keys(verification).join(',') !== 'method' || !['textDocument/documentSymbol', 'textDocument/diagnostic', 'workspace/symbol'].includes(verification.method)) fail('Malformed LSP verification');
        entry.verification = verification;
      }
      selected[value.server] = entry; } mkdirSync(dirname(args[1]), { recursive: true }); writeFileSync(args[1], `${JSON.stringify({schemaVersion:1,servers:selected},null,2)}\n`, {mode:0o600}); break; }
  case 'profile': { const text=readFileSync(args[0],'utf8'); const value = readObject(args[0]); if (!/"version"\s*:\s*1(?=\s*[,}])/.test(text) || Object.keys(value).sort().join(',') !== 'profile,version' || value.version !== 1 || !['bare','workstation'].includes(value.profile) || (args[1] && value.profile !== args[1])) fail('Invalid bundled Neovim profile'); break; }
  case 'uninstall': {
    const dryRun = args[0] === '--dry-run'; if (args.length > (dryRun ? 1 : 0)) fail('uninstall [--dry-run]'); const record = load();
    record.status = 'uninstalling'; record.completedRoots = record.completedRoots || []; if (!dryRun) save(record);
    for (const root of [...record.enrolledRoots].reverse()) { if(record.completedRoots.includes(root))continue; validateTarget(root); console.log(`delete-owned\t${root}`); if (!dryRun) { removePath(root); record.completedRoots.push(root); save(record); } }
    for (const item of [...record.resources].reverse()) {
      if (item.cleaned || record.enrolledRoots.some(root => inside(root, item.target, true))) continue;
      restore(item, dryRun);
      if(item.installerBackup){const backup=validateTarget(item.installerBackup);console.log(`remove-backup\t${backup}`);if(!dryRun)removePath(backup);}
      if(!dryRun){item.cleaned=true;save(record);}
    }
    for (const item of record.packages.filter(value => !value.preexisting && value.installed)) console.log(`remove-package\t${item.backend}\t${item.name}`);
    if (!dryRun) { record.status = 'cleanup-failed'; save(record); }
    break;
  }
  case 'claim-location': {
    if (args.length !== 1) fail('claim-location ROOT');
    const target = validateTarget(args[0]);
    const record = load();
    const stat = lstatSafe(target);
    if (stat && (!stat.isDirectory() || stat.isSymbolicLink() || !record.enrolledRoots.includes(target))) fail(`Existing tool state requires explicit enrollment before use: ${target}`);
    if (!record.enrolledRoots.includes(target)) record.enrolledRoots.push(target);
    record.enrolledRootIdentities ||= {};
    if (!stat) {
      record.enrolledRootIdentities[target] = 'pending'; save(record);
      mkdirSync(dirname(target), { recursive: true, mode: 0o700 });
      mkdirSync(target, { mode: 0o700 });
    }
    const current = lstatSync(target);
    record.enrolledRootIdentities[target] = `${current.dev}:${current.ino}`;
    save(record);
    break;
  }
  case 'owns-root': {
    if (args.length !== 1) fail('owns-root ROOT');
    const target = validateTarget(args[0]);
    if (!load().enrolledRoots.includes(target)) process.exit(3);
    if (lstatSafe(target)?.isSymbolicLink()) fail(`Enrolled root identity changed: ${target}`);
    break;
  }
  case 'uninstall-complete': {
    if (args.length !== 0) fail('uninstall-complete');
    // All JS modules are loaded before deleting any runtime. Do not respawn Node.
    run('uninstall', []);
    for (const backend of ['apt', 'dnf', 'pacman', 'brew']) {
      const packages = load().packages.filter(item => item.backend === backend && !item.preexisting && item.installed);
      if (!packages.length) continue;
      const result = spawnSync('bash', ['-c', 'native_remove_names "$@"', 'bootstrap-cleanup', backend, ...packages.map(item => item.name)], { stdio: 'inherit' });
      if (result.error || result.status !== 0) fail(`Native cleanup failed: ${backend}`);
      for (const item of packages) run('package-removed', [backend, item.name]);
    }
    const writers = spawnSync('bash', ['-c', 'bootstrap_live_writers'], { stdio: 'inherit' });
    if (writers.error || writers.status !== 1) fail('Owned writer check failed; recovery state retained');
    run('finish-uninstall', []);
    break;
  }
  case 'finish-uninstall': {
    const record = load();
    for (const root of record.enrolledRoots) if (lstatSafe(root)) fail(`Cleanup incomplete: ${root}`);
    for (const item of record.resources) {
      if (record.enrolledRoots.some(root => inside(root, item.target, true))) continue;
      if (!item.cleaned) fail(`Resource cleanup incomplete: ${item.target}`);
      const stat = lstatSafe(item.target);
      if (item.priorType === 'absent' && stat) fail(`Removed target reappeared: ${item.target}`);
      if (item.priorType === 'symlink' && (!stat?.isSymbolicLink() || readlinkSync(item.target) !== item.priorLink)) fail(`Restored link changed: ${item.target}`);
      if (item.priorType === 'file' && (!stat?.isFile() || stat.isSymbolicLink() || !item.backup || fileHash(item.target) !== fileHash(item.backup) || (stat.mode & 0o777) !== item.priorMode)) fail(`Restored file changed: ${item.target}`);
      if (item.installerBackup && lstatSafe(item.installerBackup)) fail(`Installer backup remains: ${item.installerBackup}`);
    }
    if (record.packages.some(item => !item.preexisting && item.installed)) fail('Bootstrap-added packages remain');
    rmSync(stateRoot, { recursive: true });
    break;
  }
  default: fail('Unknown state-helper command');
}
}
run(command, args);
