import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, rename, rm, rmdir, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { Type, StringEnum } from "@mariozechner/pi-ai";
import { SessionManager } from "@mariozechner/pi-coding-agent";
import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@mariozechner/pi-coding-agent";

const configuredWorktreeHome = process.env.PIW_WORKTREE_HOME ?? process.env.PI_WORKTREE_HOME;
const WORKTREE_HOME = configuredWorktreeHome ? resolve(configuredWorktreeHome) : join(homedir(), "piw-worktrees");
const REGISTRY_VERSION = 1;
const REGISTRY_FILE = "registry.json";
const LOCK_DIR = ".registry.lock";
const LOCK_TIMEOUT_MS = 5_000;
const LOCK_STALE_MS = 30_000;
const LOCK_RETRY_MS = 50;
const MAX_REGISTRY_ENTRIES = 500;
const MAX_LIST_ENTRIES = 100;
const REPOSITORY_GARDENING_THRESHOLD = 6;
const GLOBAL_GARDENING_THRESHOLD = 12;

type WorktreeAction = "create" | "list" | "info" | "remove" | "prune";
type WorktreeStatus = "active" | "removed" | "missing";
type WorkspaceMode = "main" | "worktree";

interface WorktreeRecord {
	id: string;
	status: WorktreeStatus;
	repoRoot: string;
	repoCommonDir: string;
	worktreePath: string;
	branch: string;
	baseRef: string;
	headSha: string | null;
	label: string;
	sessionId: string | null;
	sessionFile: string | null;
	lastSessionId?: string | null;
	lastSessionFile?: string | null;
	lastOpenedAt?: string;
	ownerKind?: string;
	createdFromCwd: string;
	createdAt: string;
	updatedAt: string;
}

interface WorktreeRegistry {
	version: number;
	entries: WorktreeRecord[];
}

interface WorktreeParams {
	action: WorktreeAction;
	repo?: string;
	label?: string;
	branch?: string;
	baseRef?: string;
	path?: string;
	id?: string;
	force?: boolean;
	requireClean?: boolean;
	includeRemoved?: boolean;
}

const worktreeParameters = Type.Object({
	action: StringEnum(["create", "list", "info", "remove", "prune"] as const, {
		description: "Operation to perform.",
	}),
	repo: Type.Optional(Type.String({
		description: "Git repo path. Defaults to current cwd. Used by create/list/info/prune.",
	})),
	label: Type.Optional(Type.String({
		description: "Human label for create. Used in worktree path and generated branch.",
	})),
	branch: Type.Optional(Type.String({
		description: "Branch to check out. If missing, worktree creates pi/<repo>/<label-id> from baseRef.",
	})),
	baseRef: Type.Optional(Type.String({
		description: "Base ref for new branches. Defaults to HEAD.",
	})),
	path: Type.Optional(Type.String({
		description: "Worktree path for create/remove. Relative paths resolve under ~/piw-worktrees. Absolute paths must stay under that root.",
	})),
	id: Type.Optional(Type.String({
		description: "Managed worktree id for info/remove.",
	})),
	force: Type.Optional(Type.Boolean({
		description: "Force remove when action=remove. Defaults false.",
	})),
	requireClean: Type.Optional(Type.Boolean({
		description: "Require primary checkout to be clean before create. Defaults true.",
	})),
	includeRemoved: Type.Optional(Type.Boolean({
		description: "Include removed/missing records in list/info. Defaults false.",
	})),
});

function nowIso(): string {
	return new Date().toISOString();
}

function stripAtPrefix(value: string): string {
	return value.startsWith("@") ? value.slice(1) : value;
}

function slugify(value: string, fallback: string): string {
	const slug = value
		.toLowerCase()
		.replace(/[^a-z0-9._-]+/g, "-")
		.replace(/-+/g, "-")
		.replace(/^[._-]+|[._-]+$/g, "")
		.slice(0, 48);
	return slug || fallback;
}

function assertUnderWorktreeHome(path: string): void {
	const rel = relative(WORKTREE_HOME, path);
	if (rel === "" || (!rel.startsWith("..") && !isAbsolute(rel))) return;
	throw new Error(`Path must stay under ${WORKTREE_HOME}: ${path}`);
}

function registryPath(): string {
	return join(WORKTREE_HOME, REGISTRY_FILE);
}

async function ensureHome(): Promise<void> {
	await mkdir(WORKTREE_HOME, { recursive: true });
}

async function sleep(ms: number, signal?: AbortSignal): Promise<void> {
	if (signal?.aborted) throw new Error("Cancelled");
	await new Promise<void>((resolveSleep, reject) => {
		const timeout = setTimeout(resolveSleep, ms);
		if (!signal) return;
		const onAbort = () => {
			clearTimeout(timeout);
			reject(new Error("Cancelled"));
		};
		signal.addEventListener("abort", onAbort, { once: true });
	});
}

async function withRegistryLock<T>(signal: AbortSignal | undefined, fn: () => Promise<T>): Promise<T> {
	await ensureHome();
	const lockPath = join(WORKTREE_HOME, LOCK_DIR);
	const startedAt = Date.now();

	while (true) {
		if (signal?.aborted) throw new Error("Cancelled");
		try {
			await mkdir(lockPath);
			break;
		} catch (error) {
			const code = (error as NodeJS.ErrnoException).code;
			if (code !== "EEXIST") throw error;

			try {
				const lockStat = await stat(lockPath);
				if (Date.now() - lockStat.mtimeMs > LOCK_STALE_MS) {
					await rm(lockPath, { recursive: true, force: true });
					continue;
				}
			} catch {}

			if (Date.now() - startedAt > LOCK_TIMEOUT_MS) {
				throw new Error(`Timed out waiting for worktree registry lock: ${lockPath}`);
			}
			await sleep(LOCK_RETRY_MS, signal);
		}
	}

	try {
		return await fn();
	} finally {
		await rmdir(lockPath).catch(() => undefined);
	}
}

async function readRegistry(): Promise<WorktreeRegistry> {
	try {
		const raw = await readFile(registryPath(), "utf8");
		const parsed = JSON.parse(raw) as Partial<WorktreeRegistry>;
		if (parsed.version !== REGISTRY_VERSION || !Array.isArray(parsed.entries)) {
			throw new Error(`Unsupported registry format in ${registryPath()}`);
		}
		return {
			version: REGISTRY_VERSION,
			entries: parsed.entries.slice(0, MAX_REGISTRY_ENTRIES).filter(isWorktreeRecord),
		};
	} catch (error) {
		const code = (error as NodeJS.ErrnoException).code;
		if (code === "ENOENT") return { version: REGISTRY_VERSION, entries: [] };
		throw error;
	}
}

async function writeRegistry(registry: WorktreeRegistry): Promise<void> {
	const active = registry.entries.filter((entry) => entry.status === "active" || entry.status === "missing");
	const removed = registry.entries.filter((entry) => entry.status === "removed");
	const entries = [...active, ...removed]
		.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
		.slice(0, MAX_REGISTRY_ENTRIES);
	const nextRegistry: WorktreeRegistry = { version: REGISTRY_VERSION, entries };
	const path = registryPath();
	const tmpPath = `${path}.${process.pid}.${Date.now()}.tmp`;
	await writeFile(tmpPath, `${JSON.stringify(nextRegistry, null, 2)}\n`, "utf8");
	await rename(tmpPath, path);
}

function isWorktreeRecord(value: unknown): value is WorktreeRecord {
	if (!value || typeof value !== "object") return false;
	const entry = value as Partial<WorktreeRecord>;
	return typeof entry.id === "string"
		&& (entry.status === "active" || entry.status === "removed" || entry.status === "missing")
		&& typeof entry.repoRoot === "string"
		&& typeof entry.repoCommonDir === "string"
		&& typeof entry.worktreePath === "string"
		&& typeof entry.branch === "string"
		&& typeof entry.baseRef === "string"
		&& typeof entry.label === "string"
		&& typeof entry.createdFromCwd === "string"
		&& typeof entry.createdAt === "string"
		&& typeof entry.updatedAt === "string";
}

async function git(pi: ExtensionAPI, cwd: string, args: string[], signal?: AbortSignal, timeout = 15_000): Promise<string> {
	const result = await pi.exec("git", ["-C", cwd, ...args], { signal, timeout });
	if (result.code !== 0) {
		const stderr = result.stderr?.trim();
		const stdout = result.stdout?.trim();
		throw new Error(stderr || stdout || `git ${args.join(" ")} failed with exit code ${result.code}`);
	}
	return result.stdout.trim();
}

async function resolveRepoRoot(pi: ExtensionAPI, ctx: ExtensionContext, repo: string | undefined, signal?: AbortSignal): Promise<string> {
	const input = repo?.trim() ? stripAtPrefix(repo.trim()) : ctx.cwd;
	const candidate = resolve(ctx.cwd, input);
	return git(pi, candidate, ["rev-parse", "--show-toplevel"], signal);
}

async function resolveRepoCommonDir(pi: ExtensionAPI, repoRoot: string, signal?: AbortSignal): Promise<string> {
	const commonDir = await git(pi, repoRoot, ["rev-parse", "--git-common-dir"], signal);
	return isAbsolute(commonDir) ? commonDir : resolve(repoRoot, commonDir);
}

async function requireCleanRepo(pi: ExtensionAPI, repoRoot: string, signal?: AbortSignal): Promise<void> {
	const status = await git(pi, repoRoot, ["status", "--porcelain=v1", "--untracked-files=all"], signal);
	if (status.trim()) {
		throw new Error(`Primary checkout is dirty. Commit/stash/clean first or set requireClean=false. Repo: ${repoRoot}`);
	}
}

async function branchExists(pi: ExtensionAPI, repoRoot: string, branch: string, signal?: AbortSignal): Promise<boolean> {
	const result = await pi.exec("git", ["-C", repoRoot, "show-ref", "--verify", "--quiet", `refs/heads/${branch}`], {
		signal,
		timeout: 10_000,
	});
	if (result.code === 0) return true;
	if (result.code === 1) return false;
	const stderr = result.stderr?.trim();
	throw new Error(stderr || `git show-ref failed with exit code ${result.code}`);
}

function resolveManagedPathInput(value: string): string {
	const rawPath = stripAtPrefix(value.trim());
	const candidate = isAbsolute(rawPath) ? resolve(rawPath) : resolve(WORKTREE_HOME, rawPath);
	assertUnderWorktreeHome(candidate);
	return candidate;
}

function resolveRequestedWorktreePath(repoRoot: string, label: string, params: WorktreeParams, id: string): string {
	if (params.path?.trim()) return resolveManagedPathInput(params.path);

	const repoSlug = slugify(basename(repoRoot), "repo");
	const worktreeSlug = slugify(`${label}-${id}`, id);
	const path = join(WORKTREE_HOME, repoSlug, worktreeSlug);
	assertUnderWorktreeHome(path);
	return path;
}

function recordMatches(entry: WorktreeRecord, params: WorktreeParams, repoRoot: string | null, sessionId: string | null): boolean {
	if (!params.includeRemoved && entry.status !== "active") return false;
	if (repoRoot && entry.repoRoot !== repoRoot) return false;
	if (params.id && entry.id !== params.id) return false;
	if (params.path && resolveManagedPathInput(params.path) !== entry.worktreePath) return false;
	if (sessionId && params.action === "info" && entry.sessionId !== sessionId && entry.repoRoot !== repoRoot) return false;
	return true;
}

function formatRecord(entry: WorktreeRecord): string {
	return [
		`${entry.id} [${entry.status}] ${entry.label}`,
		`  repo: ${entry.repoRoot}`,
		`  path: ${entry.worktreePath}`,
		`  branch: ${entry.branch}`,
		`  session: ${entry.sessionId ?? "none"}`,
		`  updated: ${entry.updatedAt}`,
	].join("\n");
}

function gardeningNotice(entries: WorktreeRecord[]): { recommended: boolean; reason: string | null } {
	const retained = entries.filter((entry) => entry.status === "active" || entry.status === "missing");
	const counts = new Map<string, number>();
	for (const entry of retained) counts.set(entry.repoRoot, (counts.get(entry.repoRoot) ?? 0) + 1);
	const repositoryCount = Math.max(0, ...counts.values());
	if (retained.length >= GLOBAL_GARDENING_THRESHOLD) return { recommended: true, reason: `${retained.length} retained worktrees globally` };
	if (repositoryCount >= REPOSITORY_GARDENING_THRESHOLD) return { recommended: true, reason: `${repositoryCount} retained worktrees for one repository` };
	return { recommended: false, reason: null };
}

function formatRecords(entries: WorktreeRecord[], title: string): string {
	if (entries.length === 0) return `${title}\nNo managed worktrees found.`;
	const visible = entries.slice(0, MAX_LIST_ENTRIES);
	const suffix = entries.length > visible.length ? `\n\n[Showing ${visible.length}/${entries.length} entries.]` : "";
	const gardening = gardeningNotice(entries);
	const notice = gardening.recommended ? `\n\nGardening report recommended: ${gardening.reason}. Review ownership, cleanliness, reachability, age, and missing paths. Removal is never automatic.` : "";
	return `${title}\n${visible.map(formatRecord).join("\n\n")}${suffix}${notice}`;
}

async function createWorktree(pi: ExtensionAPI, params: WorktreeParams, signal: AbortSignal | undefined, ctx: ExtensionContext) {
	const repoRoot = await resolveRepoRoot(pi, ctx, params.repo, signal);
	if (params.requireClean !== false) await requireCleanRepo(pi, repoRoot, signal);

	const repoCommonDir = await resolveRepoCommonDir(pi, repoRoot, signal);
	const id = randomUUID().slice(0, 8);
	const label = slugify(params.label?.trim() || "worktree", "worktree");
	const repoSlug = slugify(basename(repoRoot), "repo");
	const branch = params.branch?.trim() || `pi/${repoSlug}/${label}-${id}`;
	const baseRef = params.baseRef?.trim() || "HEAD";
	const worktreePath = resolveRequestedWorktreePath(repoRoot, label, params, id);

	if (existsSync(worktreePath)) {
		throw new Error(`Worktree path already exists: ${worktreePath}`);
	}

	await mkdir(dirname(worktreePath), { recursive: true });
	const exists = await branchExists(pi, repoRoot, branch, signal);
	if (exists) {
		await git(pi, repoRoot, ["worktree", "add", worktreePath, branch], signal, 60_000);
	} else {
		await git(pi, repoRoot, ["worktree", "add", "-b", branch, worktreePath, baseRef], signal, 60_000);
	}
	const headSha = await git(pi, worktreePath, ["rev-parse", "HEAD"], signal).catch(() => null);

	const timestamp = nowIso();
	const record: WorktreeRecord = {
		id,
		status: "active",
		repoRoot,
		repoCommonDir,
		worktreePath,
		branch,
		baseRef,
		headSha,
		label,
		sessionId: ctx.sessionManager.getSessionId?.() ?? null,
		sessionFile: ctx.sessionManager.getSessionFile() ?? null,
		createdFromCwd: ctx.cwd,
		createdAt: timestamp,
		updatedAt: timestamp,
	};

	return withRegistryLock(signal, async () => {
		const registry = await readRegistry();
		registry.entries.unshift(record);
		await writeRegistry(registry);
		return {
			content: [{
				type: "text" as const,
				text: [
					`Created worktree ${record.id}`,
					`repo: ${repoRoot}`,
					`path: ${worktreePath}`,
					`branch: ${branch}`,
					`session: ${record.sessionId ?? "none"}`,
					"Use absolute paths under this worktree, `git -C <path> ...`, or pass the path as subagent cwd. Do not edit the primary checkout for this task.",
				].join("\n"),
			}],
			details: { record, registryPath: registryPath(), worktreeHome: WORKTREE_HOME },
		};
	});
}

async function listWorktrees(pi: ExtensionAPI, params: WorktreeParams, signal: AbortSignal | undefined, ctx: ExtensionContext) {
	const repoRoot = params.repo ? await resolveRepoRoot(pi, ctx, params.repo, signal) : null;
	const sessionId = ctx.sessionManager.getSessionId?.() ?? null;
	return withRegistryLock(signal, async () => {
		const registry = await readRegistry();
		const entries = registry.entries.filter((entry) => recordMatches(entry, params, repoRoot, sessionId));
		const gardening = gardeningNotice(registry.entries);
		return {
			content: [{ type: "text" as const, text: formatRecords(entries, `Managed worktrees (${WORKTREE_HOME})`) }],
			details: { entries, gardening, registryPath: registryPath(), worktreeHome: WORKTREE_HOME },
		};
	});
}

async function infoWorktrees(pi: ExtensionAPI, params: WorktreeParams, signal: AbortSignal | undefined, ctx: ExtensionContext) {
	const repoRoot = params.repo ? await resolveRepoRoot(pi, ctx, params.repo, signal) : await resolveRepoRoot(pi, ctx, undefined, signal).catch(() => null);
	const sessionId = ctx.sessionManager.getSessionId?.() ?? null;
	return withRegistryLock(signal, async () => {
		const registry = await readRegistry();
		const entries = registry.entries.filter((entry) => recordMatches(entry, params, repoRoot, sessionId));
		return {
			content: [{ type: "text" as const, text: formatRecords(entries, `Current worktree context (${WORKTREE_HOME})`) }],
			details: { repoRoot, sessionId, entries, registryPath: registryPath(), worktreeHome: WORKTREE_HOME },
		};
	});
}

function findRemoveTarget(entries: WorktreeRecord[], params: WorktreeParams): WorktreeRecord {
	if (!params.id && !params.path) throw new Error("remove requires id or path");
	const path = params.path ? resolveManagedPathInput(params.path) : null;
	const matches = entries.filter((entry) => {
		if (params.id && entry.id === params.id) return true;
		if (path && entry.worktreePath === path) return true;
		return false;
	});
	if (matches.length === 0) throw new Error("No matching managed worktree found.");
	if (matches.length > 1) throw new Error("Multiple matching worktrees found; use id.");
	return matches[0];
}

async function removeWorktree(pi: ExtensionAPI, params: WorktreeParams, signal: AbortSignal | undefined) {
	return withRegistryLock(signal, async () => {
		const registry = await readRegistry();
		const entry = findRemoveTarget(registry.entries, params);
		if (entry.status === "active" && existsSync(entry.worktreePath)) {
			const args = ["worktree", "remove"];
			if (params.force) args.push("--force");
			args.push(entry.worktreePath);
			await git(pi, entry.repoRoot, args, signal, 60_000);
		}
		entry.status = "removed";
		entry.updatedAt = nowIso();
		await writeRegistry(registry);
		return {
			content: [{ type: "text" as const, text: `Removed worktree ${entry.id}\npath: ${entry.worktreePath}` }],
			details: { record: entry, registryPath: registryPath(), worktreeHome: WORKTREE_HOME },
		};
	});
}

async function pruneWorktrees(pi: ExtensionAPI, params: WorktreeParams, signal: AbortSignal | undefined, ctx: ExtensionContext) {
	const repoRoot = params.repo ? await resolveRepoRoot(pi, ctx, params.repo, signal) : null;
	return withRegistryLock(signal, async () => {
		const registry = await readRegistry();
		const changed: WorktreeRecord[] = [];
		const repos = new Set<string>();
		for (const entry of registry.entries) {
			if (repoRoot && entry.repoRoot !== repoRoot) continue;
			if (entry.status !== "active") continue;
			repos.add(entry.repoRoot);
			if (existsSync(entry.worktreePath)) continue;
			entry.status = "missing";
			entry.updatedAt = nowIso();
			changed.push(entry);
		}
		for (const repo of repos) {
			await git(pi, repo, ["worktree", "prune"], signal, 60_000);
		}
		await writeRegistry(registry);
		return {
			content: [{ type: "text" as const, text: `Pruned ${repos.size} repo(s); marked ${changed.length} missing worktree(s).` }],
			details: { changed, repos: [...repos], registryPath: registryPath(), worktreeHome: WORKTREE_HOME },
		};
	});
}

async function executeWorktree(pi: ExtensionAPI, params: WorktreeParams, signal: AbortSignal | undefined, ctx: ExtensionContext) {
	switch (params.action) {
		case "create":
			return createWorktree(pi, params, signal, ctx);
		case "list":
			return listWorktrees(pi, params, signal, ctx);
		case "info":
			return infoWorktrees(pi, params, signal, ctx);
		case "remove":
			return removeWorktree(pi, params, signal);
		case "prune":
			return pruneWorktrees(pi, params, signal, ctx);
	}
}

function workspaceStatusText(): string | null {
	const mode = process.env.PI_WORKSPACE_MODE;
	const path = process.env.PI_WORKSPACE_PATH;
	if (!mode || !path) return null;
	if (mode === "main") return "workspace:main";
	const label = process.env.PI_WORKSPACE_LABEL ?? basename(path);
	return `workspace:${label}`;
}

async function markWorkspaceOpened(ctx: ExtensionContext): Promise<void> {
	const recordId = process.env.PI_WORKTREE_RECORD_ID;
	if (!recordId) return;

	await withRegistryLock(undefined, async () => {
		const registry = await readRegistry();
		const entry = registry.entries.find((candidate) => candidate.id === recordId);
		if (!entry) return;
		entry.status = "active";
		entry.lastSessionId = ctx.sessionManager.getSessionId?.() ?? null;
		entry.lastSessionFile = ctx.sessionManager.getSessionFile() ?? null;
		entry.lastOpenedAt = nowIso();
		entry.updatedAt = entry.lastOpenedAt;
		await writeRegistry(registry);
	});
}

async function runCommandAction(pi: ExtensionAPI, ctx: ExtensionContext, params: WorktreeParams): Promise<void> {
	try {
		const result = await executeWorktree(pi, params, undefined, ctx);
		const text = result.content
			.filter((item) => item.type === "text")
			.map((item) => item.text)
			.join("\n");
		pi.sendMessage({
			customType: "worktree-report",
			content: text,
			display: true,
			details: result.details,
		});
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		ctx.ui.notify(`Worktree failed: ${message}`, "error");
		pi.sendMessage({
			customType: "worktree-report",
			content: `Worktree failed: ${message}`,
			display: true,
			details: { error: message },
		});
	}
}

function workspaceSessionName(mode: WorkspaceMode, path: string, record?: WorktreeRecord): string {
	if (mode === "main") return `main: ${basename(path)}`;
	return `worktree: ${record?.label ?? basename(path)}`;
}

function setWorkspaceEnv(mode: WorkspaceMode, path: string, repoRoot: string, record?: WorktreeRecord): void {
	process.env.PI_WORKSPACE_MODE = mode;
	process.env.PI_WORKSPACE_PATH = path;
	process.env.PI_WORKSPACE_REPO_ROOT = repoRoot;
	if (record) {
		process.env.PI_WORKTREE_RECORD_ID = record.id;
		process.env.PI_WORKSPACE_LABEL = record.label;
		return;
	}
	delete process.env.PI_WORKTREE_RECORD_ID;
	delete process.env.PI_WORKSPACE_LABEL;
}

async function switchWorkspaceSession(ctx: ExtensionCommandContext, mode: WorkspaceMode, path: string, repoRoot: string, record?: WorktreeRecord): Promise<void> {
	const sessionManager = SessionManager.create(path);
	sessionManager.appendSessionInfo(workspaceSessionName(mode, path, record));
	const sessionFile = sessionManager.getSessionFile();
	if (!sessionFile) throw new Error(`Could not create session for workspace: ${path}`);

	setWorkspaceEnv(mode, path, repoRoot, record);
	await ctx.waitForIdle();
	const result = await ctx.switchSession(sessionFile, {
		withSession: async (nextCtx) => {
			nextCtx.ui.notify(`Workspace: ${mode === "main" ? "main" : record?.label ?? basename(path)}`, "success");
		},
	});
	if (result.cancelled) throw new Error("Workspace switch cancelled.");
}

async function getRepoContext(pi: ExtensionAPI, ctx: ExtensionContext): Promise<{ repoRoot: string; repoCommonDir: string }> {
	const currentRoot = await resolveRepoRoot(pi, ctx, undefined);
	const currentCommonDir = await resolveRepoCommonDir(pi, currentRoot);
	const registry = await readRegistry();
	const existing = registry.entries.find((entry) => entry.status === "active" && entry.repoCommonDir === currentCommonDir);
	return {
		repoRoot: existing?.repoRoot ?? currentRoot,
		repoCommonDir: currentCommonDir,
	};
}

async function listActiveRepoWorktrees(repoRoot: string, repoCommonDir: string): Promise<WorktreeRecord[]> {
	return withRegistryLock(undefined, async () => {
		const registry = await readRegistry();
		return registry.entries
			.filter((entry) => entry.status === "active")
			.filter((entry) => entry.repoRoot === repoRoot || entry.repoCommonDir === repoCommonDir)
			.filter((entry) => existsSync(entry.worktreePath))
			.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
	});
}

function findWorktreeByQuery(entries: WorktreeRecord[], query: string): WorktreeRecord[] {
	const normalized = query.toLowerCase();
	return entries.filter((entry) => {
		return entry.id.startsWith(query)
			|| entry.label.toLowerCase().includes(normalized)
			|| entry.branch.toLowerCase().includes(normalized)
			|| entry.worktreePath.toLowerCase().includes(normalized);
	});
}

async function createWorkspaceFromCommand(pi: ExtensionAPI, ctx: ExtensionCommandContext, label: string): Promise<WorktreeRecord> {
	const result = await createWorktree(pi, { action: "create", label }, undefined, ctx);
	const record = (result.details as { record?: WorktreeRecord }).record;
	if (!record) throw new Error("Worktree create did not return a registry record.");
	return record;
}

async function selectWorkspaceRecord(ctx: ExtensionCommandContext, entries: WorktreeRecord[]): Promise<WorktreeRecord | "main" | "new" | undefined> {
	const options = [
		"main checkout",
		...entries.map((entry) => `${entry.label} (${entry.id}) — ${entry.branch}`),
		"new worktree",
	];
	const selected = await ctx.ui.select("Pi workspace", options);
	if (!selected) return undefined;
	if (selected === "main checkout") return "main";
	if (selected === "new worktree") return "new";
	return entries.find((entry) => selected.includes(`(${entry.id})`));
}

async function handlePiwCommand(pi: ExtensionAPI, args: string | undefined, ctx: ExtensionCommandContext): Promise<void> {
	try {
		const input = args?.trim() ?? "";
		const { repoRoot, repoCommonDir } = await getRepoContext(pi, ctx);
		const entries = await listActiveRepoWorktrees(repoRoot, repoCommonDir);

		if (input === "main") {
			await switchWorkspaceSession(ctx, "main", repoRoot, repoRoot);
			return;
		}

		if (input.startsWith("new")) {
			const label = input.slice("new".length).trim() || await ctx.ui.input("Worktree label", "worktree") || "worktree";
			const record = await createWorkspaceFromCommand(pi, ctx, label);
			await switchWorkspaceSession(ctx, "worktree", record.worktreePath, record.repoRoot, record);
			return;
		}

		if (input) {
			const matches = findWorktreeByQuery(entries, input);
			if (matches.length === 0) throw new Error(`No managed worktree matches: ${input}`);
			if (matches.length > 1) {
				const selected = await selectWorkspaceRecord(ctx, matches);
				if (!selected || selected === "main" || selected === "new") return;
				await switchWorkspaceSession(ctx, "worktree", selected.worktreePath, selected.repoRoot, selected);
				return;
			}
			const record = matches[0];
			await switchWorkspaceSession(ctx, "worktree", record.worktreePath, record.repoRoot, record);
			return;
		}

		const selected = await selectWorkspaceRecord(ctx, entries);
		if (!selected) return;
		if (selected === "main") {
			await switchWorkspaceSession(ctx, "main", repoRoot, repoRoot);
			return;
		}
		if (selected === "new") {
			const label = await ctx.ui.input("Worktree label", "worktree") || "worktree";
			const record = await createWorkspaceFromCommand(pi, ctx, label);
			await switchWorkspaceSession(ctx, "worktree", record.worktreePath, record.repoRoot, record);
			return;
		}
		await switchWorkspaceSession(ctx, "worktree", selected.worktreePath, selected.repoRoot, selected);
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		ctx.ui.notify(`piw failed: ${message}`, "error");
	}
}

export default function worktreesExtension(pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		const status = workspaceStatusText();
		if (status) {
			ctx.ui.setStatus("workspace", ctx.ui.theme.fg(process.env.PI_WORKSPACE_MODE === "main" ? "dim" : "accent", status));
		}
		await markWorkspaceOpened(ctx);
	});

	pi.on("before_agent_start", async (event) => {
		if (process.env.PI_WORKSPACE_MODE !== "worktree" || !process.env.PI_WORKSPACE_PATH) return;
		return {
			systemPrompt: `${event.systemPrompt}\n\nWorkspace launcher selected managed worktree: ${process.env.PI_WORKSPACE_PATH}. Treat the current cwd as the active workspace. Do not edit the primary checkout unless the user explicitly asks.`,
		};
	});

	pi.registerTool({
		name: "worktree",
		label: "Worktree",
		description: "Create and manage git worktrees under ~/piw-worktrees with a registry tracking repo, session, branch, and path.",
		promptSnippet: "Create/list/info/remove/prune managed git worktrees under ~/piw-worktrees",
		promptGuidelines: [
			"Use worktree when the user asks for isolated worktree work, persistent workstreams, or worktree management.",
			"After worktree create, tools still run from the original cwd; use absolute paths under the returned worktree, `git -C <worktree> ...`, or pass the worktree path as subagent cwd.",
			"Do not edit the primary checkout after creating a worktree for the task unless the user explicitly says to work in-place.",
		],
		parameters: worktreeParameters,
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			return executeWorktree(pi, params as WorktreeParams, signal, ctx);
		},
	});

	pi.registerCommand("piw", {
		description: "Pick main checkout, existing worktree, or new worktree, then switch Pi into that workspace.",
		handler: async (args, ctx) => {
			await handlePiwCommand(pi, args, ctx);
		},
	});

	pi.registerCommand("worktrees", {
		description: "Manage git worktrees under ~/piw-worktrees. Usage: /worktrees list|info|create [label]|remove <id>|prune",
		handler: async (args, ctx) => {
			const input = args?.trim() || "list";
			const [action = "list", ...rest] = input.split(/\s+/);
			if (!["list", "info", "create", "remove", "prune"].includes(action)) {
				ctx.ui.notify("Usage: /worktrees list|info|create [label]|remove <id>|prune", "warning");
				return;
			}
			if (action === "create") {
				await runCommandAction(pi, ctx, { action, label: rest.join(" ").trim() || "manual" });
				return;
			}
			if (action === "remove") {
				const id = rest[0];
				if (!id) {
					ctx.ui.notify("Usage: /worktrees remove <id>", "warning");
					return;
				}
				await runCommandAction(pi, ctx, { action, id });
				return;
			}
			await runCommandAction(pi, ctx, { action: action as WorktreeAction });
		},
	});
}
