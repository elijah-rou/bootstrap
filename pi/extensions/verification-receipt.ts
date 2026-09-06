import { createHash, randomUUID } from "node:crypto";
import { readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";

const MAX_UNTRACKED_FILES = 100;
const MAX_UNTRACKED_BYTES = 10 * 1024 * 1024;
const MAX_GIT_OUTPUT_BYTES = 1024 * 1024;

export interface WorkspaceFingerprint {
  cacheable: boolean;
  digest?: string;
  repositoryRoot: string;
  head: string | null;
  reason?: string;
}

function git(root: string, args: string[]): { ok: boolean; stdout: Buffer } {
  const result = spawnSync("git", ["-C", root, ...args], { encoding: "buffer", maxBuffer: MAX_GIT_OUTPUT_BYTES });
  return { ok: result.status === 0, stdout: result.stdout ?? Buffer.alloc(0) };
}

export function repositoryRoot(cwd: string): string {
  const result = git(cwd, ["rev-parse", "--show-toplevel"]);
  return result.ok && result.stdout.length > 0 ? resolve(result.stdout.toString("utf8").trim()) : resolve(cwd);
}

export function fingerprintWorkspace(cwd: string): WorkspaceFingerprint {
  const root = repositoryRoot(cwd);
  const headResult = git(root, ["rev-parse", "HEAD"]);
  const index = git(root, ["diff", "--cached", "--binary"]);
  const tracked = git(root, ["diff", "--binary"]);
  const untracked = git(root, ["ls-files", "--others", "--exclude-standard", "-z"]);
  if (!headResult.ok || !index.ok || !tracked.ok || !untracked.ok) return { cacheable: false, repositoryRoot: root, head: null, reason: "workspace state unreadable" };
  const paths = untracked.stdout.toString("utf8").split("\0").filter(Boolean);
  if (paths.length > MAX_UNTRACKED_FILES) return { cacheable: false, repositoryRoot: root, head: headResult.stdout.toString("utf8").trim(), reason: "untracked file limit exceeded" };

  let bytes = 0;
  const hash = createHash("sha256");
  hash.update(root); hash.update("\0"); hash.update(headResult.stdout); hash.update(index.stdout); hash.update(tracked.stdout);
  try {
    for (const path of paths.sort()) {
      const absolute = resolve(root, path);
      const size = statSync(absolute).size;
      bytes += size;
      if (bytes > MAX_UNTRACKED_BYTES) return { cacheable: false, repositoryRoot: root, head: headResult.stdout.toString("utf8").trim(), reason: "untracked byte limit exceeded" };
      hash.update(path); hash.update("\0"); hash.update(readFileSync(absolute));
    }
  } catch {
    return { cacheable: false, repositoryRoot: root, head: headResult.stdout.toString("utf8").trim(), reason: "untracked content unreadable" };
  }
  return { cacheable: true, digest: hash.digest("hex"), repositoryRoot: root, head: headResult.stdout.toString("utf8").trim() };
}

export function beginVerification(cwd: string, tool: string, action: string) {
  const childMarker = process.env.PI_SUBAGENT_CHILD;
  const actor = childMarker === "1" ? "subagent" : childMarker === undefined ? "root-parent-or-user" : "unknown";
  return { version: 1 as const, attemptId: randomUUID(), tool, action, verifier: { actor, authority: "local-verification" }, startedAt: new Date().toISOString(), workspace: fingerprintWorkspace(cwd) };
}

export function finishVerification(started: ReturnType<typeof beginVerification>, outcome: string, fields: Record<string, unknown>) {
  const finishedAt = new Date().toISOString();
  return { ...started, outcome, finishedAt, durationMs: Date.parse(finishedAt) - Date.parse(started.startedAt), artifacts: [], ...fields };
}

export default function verificationReceiptLibrary(): void {
  // Pi loads every top-level extension module; this module only supplies shared receipt functions.
}
