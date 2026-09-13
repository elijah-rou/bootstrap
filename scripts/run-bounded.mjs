#!/usr/bin/env node
import { spawn } from 'node:child_process';
const [secondsText, command, ...args] = process.argv.slice(2);
const seconds = Number(secondsText);
if (!Number.isInteger(seconds) || seconds < 1 || seconds > 3600 || !command) process.exit(2);
const child = spawn(command, args, { stdio: 'inherit', env: process.env, detached: process.platform !== 'win32' });
const timer = setTimeout(() => { try { process.kill(process.platform === 'win32' ? child.pid : -child.pid, 'SIGTERM'); } catch {} setTimeout(() => { try { process.kill(process.platform === 'win32' ? child.pid : -child.pid, 'SIGKILL'); } catch {} }, 5000).unref(); }, seconds * 1000);
child.on('exit', (code, signal) => { clearTimeout(timer); process.exitCode = signal ? 124 : (code ?? 1); });
child.on('error', error => { clearTimeout(timer); console.error(error.message); process.exitCode = 127; });
