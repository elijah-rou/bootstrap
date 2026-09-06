import { execFile } from "node:child_process";
import { relative, resolve } from "node:path";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const exec = promisify(execFile);
const MAX_TRACKED_FILES = 512;
const MAX_OUTPUT = 200_000;

type DiffContext = { cwd: string; ui: { notify(message: string, level: "info" | "success" | "warning" | "error"): void; pasteToEditor(text: string): void } };
type ToolEvent = { toolName?: string; input?: unknown; content?: unknown; result?: unknown; details?: unknown };

type DiffState = {
	root: string | undefined;
	baseline: Map<string, string>;
	touchedFiles: Set<string>;
	lastChangedFiles: string[];
};

type GlobalWithDiffState = typeof globalThis & { __piDiffState?: DiffState };

const globalDiff = globalThis as GlobalWithDiffState;

export const diffState: DiffState = globalDiff.__piDiffState ??= {
	root: undefined,
	baseline: new Map<string, string>(),
	touchedFiles: new Set<string>(),
	lastChangedFiles: [],
};

async function git(cwd: string, args: string[]): Promise<string> {
	const result = await exec("git", args, { cwd, timeout: 5_000, maxBuffer: MAX_OUTPUT });
	return result.stdout;
}

async function repoRoot(cwd: string): Promise<string> {
	return (await git(cwd, ["rev-parse", "--show-toplevel"])).trim();
}

async function porcelain(cwd: string): Promise<string> {
	return git(cwd, ["status", "--porcelain=v1"]).catch(() => "");
}

function statusMap(status: string): Map<string, string> {
	const files = new Map<string, string>();
	for (const line of status.split("\n")) {
		if (!line.trim()) continue;
		const code = line.slice(0, 2);
		const raw = line.slice(3).trim();
		const renamed = raw.includes(" -> ") ? raw.split(" -> ").pop()! : raw;
		files.set(renamed, code);
	}
	return files;
}

function addPath(cwd: string, value: unknown): void {
	if (typeof value !== "string" || !value.trim()) return;
	if (diffState.touchedFiles.size >= MAX_TRACKED_FILES) return;
	const root = diffState.root ?? cwd;
	const path = resolve(cwd, value.startsWith("@") ? value.slice(1) : value);
	diffState.touchedFiles.add(relative(root, path));
}

function scanForPaths(cwd: string, value: unknown, depth = 0): void {
	if (depth > 4 || diffState.touchedFiles.size >= MAX_TRACKED_FILES) return;
	if (!value || typeof value !== "object") return;
	if (Array.isArray(value)) {
		for (const item of value) scanForPaths(cwd, item, depth + 1);
		return;
	}
	const record = value as Record<string, unknown>;
	addPath(cwd, record.path);
	addPath(cwd, record.file);
	addPath(cwd, record.filePath);
	for (const key of ["details", "result", "content", "output"]) scanForPaths(cwd, record[key], depth + 1);
}

async function resetBaseline(cwd: string): Promise<void> {
	diffState.root = await repoRoot(cwd).catch(() => undefined);
	diffState.baseline = statusMap(await porcelain(cwd));
	diffState.touchedFiles.clear();
	diffState.lastChangedFiles = [];
}

async function changedFiles(cwd: string): Promise<string[]> {
	const current = statusMap(await porcelain(cwd));
	const files = new Set<string>(diffState.touchedFiles);
	for (const [file, code] of current) {
		if (diffState.baseline.get(file) !== code) files.add(file);
	}
	for (const file of diffState.baseline.keys()) {
		if (!current.has(file)) files.add(file);
	}
	return Array.from(files).filter(Boolean).sort();
}

async function summary(cwd: string, files: string[]): Promise<string> {
	const root = await repoRoot(cwd);
	const status = (await git(cwd, ["status", "--short"]).catch(() => "")).trim();
	const staged = (await git(cwd, ["diff", "--cached", "--stat"]).catch(() => "")).trim();
	const unstaged = (await git(cwd, ["diff", "--stat"]).catch(() => "")).trim();
	const untracked = (await git(cwd, ["ls-files", "--others", "--exclude-standard"]).catch(() => "")).trim();
	return [
		"# Diff",
		`Repo: ${root}`,
		"",
		"## Changed files",
		files.length ? files.map((file) => `- ${file}`).join("\n") : "none",
		"",
		"## Status",
		status || "clean",
		"",
		"## Staged diff stat",
		staged || "no staged diff",
		"",
		"## Unstaged diff stat",
		unstaged || "no unstaged diff",
		"",
		"## Untracked files",
		untracked || "none",
	].join("\n");
}

export default function diffExtension(pi: ExtensionAPI) {
	pi.on("agent_start", async (_event: unknown, ctx: { cwd: string }) => {
		await resetBaseline(ctx.cwd);
	});

	pi.on("tool_call", async (event: ToolEvent, ctx: { cwd: string }) => {
		if (event.toolName !== "edit" && event.toolName !== "write") return;
		scanForPaths(ctx.cwd, event.input);
	});

	pi.on("tool_result", async (event: ToolEvent, ctx: { cwd: string }) => {
		if (event.toolName !== "edit" && event.toolName !== "write") return;
		scanForPaths(ctx.cwd, event);
	});

	pi.on("agent_end", async (_event: unknown, ctx: { cwd: string }) => {
		diffState.lastChangedFiles = await changedFiles(ctx.cwd).catch(() => []);
	});

	pi.registerCommand("diff", {
		description: "Paste git diff summary. Usage: /diff, /diff list, /diff clear",
		async handler(args: string | undefined, ctx: DiffContext) {
			const mode = (args ?? "").trim();
			if (mode === "clear") {
				await resetBaseline(ctx.cwd);
				ctx.ui.notify("/diff baseline reset", "success");
				return;
			}
			const files = await changedFiles(ctx.cwd).catch(() => []);
			diffState.lastChangedFiles = files;
			if (mode === "list") {
				const text = files.length ? files.join("\n") : "No changed files.";
				ctx.ui.pasteToEditor(text);
				ctx.ui.notify(`/diff: ${files.length} changed file(s)`, "info");
				return;
			}
			if (mode) {
				ctx.ui.notify("Usage: /diff, /diff list, /diff clear", "warning");
				return;
			}
			ctx.ui.pasteToEditor(await summary(ctx.cwd, files));
		},
	});
}
