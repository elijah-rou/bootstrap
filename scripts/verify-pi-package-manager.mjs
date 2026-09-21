#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, isAbsolute } from 'node:path';
import { pathToFileURL } from 'node:url';

const { BUN_INSTALL, PI_CODING_AGENT_DIR } = process.env;
assert.ok(BUN_INSTALL && isAbsolute(BUN_INSTALL), 'BUN_INSTALL must be absolute');
assert.ok(PI_CODING_AGENT_DIR && isAbsolute(PI_CODING_AGENT_DIR), 'PI_CODING_AGENT_DIR must be absolute');
const settings = JSON.parse(readFileSync(join(PI_CODING_AGENT_DIR, 'settings.json'), 'utf8'));
const packageDir = join(BUN_INSTALL, 'install/global/node_modules/@earendil-works/pi-coding-agent');
const { detectInstallMethod, getSelfUpdateCommand, PACKAGE_NAME } = await import(pathToFileURL(join(packageDir, 'dist/config.js')).href);
assert.equal(detectInstallMethod(), 'bun', 'Pi must resolve to its Bun installation');
// npmCommand is optional in preserved profiles; the owning installation selects the updater.
// Resolve it without fetching a version or replacing the running CLI.
const update = getSelfUpdateCommand(PACKAGE_NAME, settings.npmCommand);
assert.equal(update?.command, 'bun', 'Pi must support self-update through the owning Bun installation');
assert.ok(update.args.includes('-g'), 'Pi self-update must target the global installation');
