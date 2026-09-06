import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

type DiffState = { lastChangedFiles?: string[] };
type GlobalWithDiffState = typeof globalThis & { __piDiffState?: DiffState };

function getLastDiffFiles(): string[] {
	const files = (globalThis as GlobalWithDiffState).__piDiffState?.lastChangedFiles;
	return Array.isArray(files) ? [...files] : [];
}

const exec = promisify(execFile);

async function git(cwd: string, args: string[]): Promise<string> {
	return (await exec("git", args, { cwd, timeout: 5_000, maxBuffer: 200_000 })).stdout.trim();
}

export default function changesExtension(pi: ExtensionAPI) {
	pi.registerCommand("changes", {
		description: "Read-only git status, diff stats, untracked files, recent commits, last agent files",
		async handler(_args, ctx) {
			try {
				const root = await git(ctx.cwd, ["rev-parse", "--show-toplevel"]);
				const lastFiles = getLastDiffFiles();
				const parts = [
					"# Changes",
					`Repo: ${root}`,
					"",
					"## Status",
					await git(ctx.cwd, ["status", "--short"]).then((s) => s || "clean"),
					"",
					"## Staged diff stat",
					await git(ctx.cwd, ["diff", "--cached", "--stat"]).then((s) => s || "no staged diff"),
					"",
					"## Unstaged diff stat",
					await git(ctx.cwd, ["diff", "--stat"]).then((s) => s || "no unstaged diff"),
					"",
					"## Untracked files",
					await git(ctx.cwd, ["ls-files", "--others", "--exclude-standard"]).then((s) => s || "none"),
					"",
					"## Recent commits",
					await git(ctx.cwd, ["log", "--oneline", "-5"]),
					"",
					"## Last-agent changed files",
					lastFiles.length ? lastFiles.map((file) => `- ${file}`).join("\n") : "none recorded",
				];
				ctx.ui.pasteToEditor(parts.join("\n"));
			} catch {
				ctx.ui.notify("/changes: not inside a git repo", "info");
			}
		},
	});
}
