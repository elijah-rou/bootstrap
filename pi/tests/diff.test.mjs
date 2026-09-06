import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadExtension } from "./extension-fixture.mjs";

const createTools = await loadExtension("diff");
const realGit = execFileSync("sh", ["-c", "command -v git"], { encoding: "utf8" }).trim();

test("diff modes report real workspace changes and collect one changed-file snapshot", async (t) => {
  const root = mkdtempSync(join(tmpdir(), "pi-diff-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const repo = join(root, "repo");
  const bin = join(root, "bin");
  const log = join(root, "git.log");
  mkdirSync(repo);
  mkdirSync(bin);
  const git = args => execFileSync(realGit, ["-C", repo, ...args], { encoding: "utf8" });
  git(["init", "--quiet"]);
  writeFileSync(join(repo, "tracked.txt"), "original\n");
  git(["add", "tracked.txt"]);
  git(["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "fixture"]);
  writeFileSync(join(bin, "git"), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$DIFF_GIT_LOG"\nexec "$DIFF_REAL_GIT" "$@"\n', { mode: 0o755 });
  const previous = { PATH: process.env.PATH, DIFF_GIT_LOG: process.env.DIFF_GIT_LOG, DIFF_REAL_GIT: process.env.DIFF_REAL_GIT };
  Object.assign(process.env, { PATH: `${bin}:${process.env.PATH}`, DIFF_GIT_LOG: log, DIFF_REAL_GIT: realGit });
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });
  const events = new Map();
  const commands = new Map();
  const pasted = [];
  const notices = [];
  const ctx = { cwd: repo, ui: { pasteToEditor: text => pasted.push(text), notify: (message, level) => notices.push({ message, level }) } };
  createTools({ on: (name, handler) => events.set(name, handler), registerCommand: (name, command) => commands.set(name, command) });
  const run = async mode => {
    writeFileSync(log, "");
    await commands.get("diff").handler(mode, ctx);
    return readFileSync(log, "utf8").trim().split("\n").filter(Boolean);
  };
  await events.get("agent_start")({}, ctx);
  writeFileSync(join(repo, "tracked.txt"), "changed\n");
  writeFileSync(join(repo, "new.txt"), "new\n");
  const calls = await run("");
  assert.match(pasted.at(-1), /## Changed files\n- new\.txt\n- tracked\.txt/);
  assert.match(pasted.at(-1), /## Unstaged diff stat\n[\s\S]*tracked\.txt/);
  assert.match(pasted.at(-1), /## Untracked files\nnew\.txt/);
  assert.equal(calls.filter(call => call === "status --porcelain=v1").length, 1);
  await run("list");
  assert.equal(pasted.at(-1), "new.txt\ntracked.txt");
  assert.deepEqual(notices.at(-1), { message: "/diff: 2 changed file(s)", level: "info" });
  const beforeClear = pasted.length;
  await run("clear");
  assert.equal(pasted.length, beforeClear);
  assert.deepEqual(notices.at(-1), { message: "/diff baseline reset", level: "success" });
  await run("list");
  assert.equal(pasted.at(-1), "No changed files.");
  const beforeInvalid = pasted.length;
  await run("unknown");
  assert.equal(pasted.length, beforeInvalid);
  assert.deepEqual(notices.at(-1), { message: "Usage: /diff, /diff list, /diff clear", level: "warning" });
});
