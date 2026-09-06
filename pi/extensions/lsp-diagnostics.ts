import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { extname, isAbsolute, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { spawn, spawnSync } from "node:child_process";
import { Type } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { beginVerification, finishVerification } from "./verification-receipt.ts";

const MAX_TOUCHED_FILES = 50;
const MAX_RECORDED_OVER_LIMIT_FILES = 50;
const MAX_DIAGNOSTICS_PER_FILE = 50;
const DIAGNOSTICS_SETTLE_MS = 750;
const DEFAULT_TIMEOUT_MS = 10_000;
const MIN_TIMEOUT_MS = 1_000;
const MAX_TIMEOUT_MS = 30_000;

type Severity = 1 | 2 | 3 | 4;
type LspOutcome = "clean" | "diagnostics" | "not_applicable" | "unsupported" | "failed" | "timed_out" | "cancelled";
type SupportedServer = "typescript-language-server" | "basedpyright" | "pyright-langserver" | "rust-analyzer" | "gopls" | "clangd" | "lua-language-server" | "sourcekit-lsp";

interface ServerConfig {
	name: SupportedServer;
	command: string;
	args: string[];
	languageIds: Record<string, string>;
}

interface Diagnostic {
	range?: {
		start?: { line?: number; character?: number };
		end?: { line?: number; character?: number };
	};
	severity?: Severity;
	code?: string | number;
	source?: string;
	message?: string;
}

interface FileDiagnosticResult {
	path: string;
	server: string;
	diagnostics: Diagnostic[];
}

interface LspRequestParams {
	paths?: string[];
	timeoutMs?: number;
}

const SERVER_CONFIGS: ServerConfig[] = [
	{
		name: "typescript-language-server",
		command: "typescript-language-server",
		args: ["--stdio"],
		languageIds: {
			".ts": "typescript",
			".tsx": "typescriptreact",
			".js": "javascript",
			".jsx": "javascriptreact",
			".mjs": "javascript",
			".cjs": "javascript",
		},
	},
	{
		name: "basedpyright",
		command: "basedpyright-langserver",
		args: ["--stdio"],
		languageIds: { ".py": "python", ".pyi": "python" },
	},
	{
		name: "pyright-langserver",
		command: "pyright-langserver",
		args: ["--stdio"],
		languageIds: { ".py": "python", ".pyi": "python" },
	},
	{
		name: "rust-analyzer",
		command: "rust-analyzer",
		args: [],
		languageIds: { ".rs": "rust" },
	},
	{
		name: "gopls",
		command: "gopls",
		args: [],
		languageIds: { ".go": "go" },
	},
	{
		name: "clangd",
		command: "clangd",
		args: ["--background-index=false"],
		languageIds: {
			".c": "c",
			".h": "c",
			".cc": "cpp",
			".cpp": "cpp",
			".cxx": "cpp",
			".hpp": "cpp",
			".hh": "cpp",
		},
	},
	{
		name: "lua-language-server",
		command: "lua-language-server",
		args: [],
		languageIds: { ".lua": "lua" },
	},
	{
		name: "sourcekit-lsp",
		command: "sourcekit-lsp",
		args: [],
		languageIds: { ".swift": "swift" },
	},
];

const lspDiagnosticsParameters = Type.Object({
	paths: Type.Optional(Type.Array(Type.String({ description: "Specific paths to diagnose. Defaults to files touched by edit/write in this session." }), {
		description: "Optional file paths. Prefer omitting this so lsp_diagnostics checks touched files only.",
	})),
	timeoutMs: Type.Optional(Type.Number({ description: "Maximum wait per language server in milliseconds. Defaults to 10000." })),
});

function stripAtPrefix(value: string): string {
	return value.startsWith("@") ? value.slice(1) : value;
}

function normalizePath(cwd: string, path: string): string {
	const stripped = stripAtPrefix(path.trim());
	return isAbsolute(stripped) ? resolve(stripped) : resolve(cwd, stripped);
}

function clampTimeout(value: unknown): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return DEFAULT_TIMEOUT_MS;
	return Math.min(MAX_TIMEOUT_MS, Math.max(MIN_TIMEOUT_MS, Math.trunc(value)));
}

const commandExistsCache = new Map<string, boolean>();

function commandExists(command: string): boolean {
	const cached = commandExistsCache.get(command);
	if (cached !== undefined) return cached;

	const result = spawnSync("sh", ["-c", "command -v -- \"$1\" >/dev/null 2>&1", "_", command], {
		stdio: "ignore",
		timeout: 1000,
	});
	const exists = result.status === 0;
	commandExistsCache.set(command, exists);
	return exists;
}

function configForPath(path: string): { config: ServerConfig; languageId: string } | null {
	const ext = extname(path).toLowerCase();
	for (const config of SERVER_CONFIGS) {
		const languageId = config.languageIds[ext];
		if (languageId) return { config, languageId };
	}
	return null;
}

function severityName(severity: Severity | undefined): string {
	switch (severity) {
		case 1:
			return "error";
		case 2:
			return "warning";
		case 3:
			return "info";
		case 4:
			return "hint";
		default:
			return "diagnostic";
	}
}

function diagnosticLine(path: string, diagnostic: Diagnostic): string {
	const line = (diagnostic.range?.start?.line ?? 0) + 1;
	const column = (diagnostic.range?.start?.character ?? 0) + 1;
	const source = diagnostic.source ? `${diagnostic.source}: ` : "";
	const code = diagnostic.code === undefined ? "" : ` [${diagnostic.code}]`;
	return `${path}:${line}:${column} ${severityName(diagnostic.severity)}: ${source}${diagnostic.message ?? "(no message)"}${code}`;
}

function encodeMessage(message: unknown): string {
	const json = JSON.stringify(message);
	return `Content-Length: ${Buffer.byteLength(json, "utf8")}\r\n\r\n${json}`;
}

function decodeMessages(buffer: Buffer, onMessage: (message: any) => void): Buffer {
	let offset = 0;
	while (true) {
		const headerEnd = buffer.indexOf("\r\n\r\n", offset, "utf8");
		if (headerEnd < 0) break;

		const header = buffer.subarray(offset, headerEnd).toString("utf8");
		const match = header.match(/Content-Length: (\d+)/i);
		if (!match) {
			offset = headerEnd + 4;
			continue;
		}

		const length = Number(match[1]);
		const bodyStart = headerEnd + 4;
		const bodyEnd = bodyStart + length;
		if (buffer.length < bodyEnd) break;

		const body = buffer.subarray(bodyStart, bodyEnd).toString("utf8");
		try {
			onMessage(JSON.parse(body));
		} catch {}
		offset = bodyEnd;
	}
	return buffer.subarray(offset);
}

class LspClient {
	private nextId = 1;
	private buffer: Buffer<ArrayBufferLike> = Buffer.alloc(0);
	private readonly pending = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void }>();
	private readonly diagnostics = new Map<string, Diagnostic[]>();
	private diagnosticsPublished: (() => void) | null = null;
	private stderr = "";

	private readonly config: ServerConfig;
	private readonly root: string;
	private readonly timeoutMs: number;

	constructor(config: ServerConfig, root: string, timeoutMs: number) {
		this.config = config;
		this.root = root;
		this.timeoutMs = timeoutMs;
	}

	async run(files: Array<{ path: string; languageId: string }>, signal?: AbortSignal): Promise<FileDiagnosticResult[]> {
		return await new Promise<FileDiagnosticResult[]>((resolveRun, rejectRun) => {
			const child = spawn(this.config.command, this.config.args, { cwd: this.root, stdio: ["pipe", "pipe", "pipe"] });
			let settled = false;
			let opened = false;
			let settleTimer: NodeJS.Timeout | null = null;

			const timer = setTimeout(() => finish(new Error("Timed out")), this.timeoutMs);
			const onAbort = () => finish(new Error("Cancelled"));
			signal?.addEventListener("abort", onAbort, { once: true });

			const fail = (error: Error) => {
				if (settled) return;
				settled = true;
				clearTimeout(timer);
				if (settleTimer) clearTimeout(settleTimer);
				this.diagnosticsPublished = null;
				signal?.removeEventListener("abort", onAbort);
				child.kill("SIGTERM");
				rejectRun(error);
			};

			const finish = (error?: Error) => {
				if (settled) return;
				settled = true;
				clearTimeout(timer);
				if (settleTimer) clearTimeout(settleTimer);
				this.diagnosticsPublished = null;
				signal?.removeEventListener("abort", onAbort);
				for (const pending of this.pending.values()) pending.reject(new Error("LSP client closed"));
				this.pending.clear();
				child.stdin?.write(encodeMessage({ jsonrpc: "2.0", id: this.nextId++, method: "shutdown", params: null }));
				child.stdin?.write(encodeMessage({ jsonrpc: "2.0", method: "exit" }));
				setTimeout(() => child.kill("SIGTERM"), 100).unref();
				if (error) {
					rejectRun(error);
					return;
				}
				resolveRun(files.map((file) => ({
					path: file.path,
					server: this.config.name,
					diagnostics: this.diagnostics.get(pathToFileURL(file.path).toString()) ?? [],
				})));
			};

			const scheduleSettledFinish = () => {
				if (!opened || settled) return;
				if (!files.every(file => this.diagnostics.has(pathToFileURL(file.path).toString()))) return;
				if (settleTimer) clearTimeout(settleTimer);
				settleTimer = setTimeout(() => finish(), DIAGNOSTICS_SETTLE_MS);
			};
			this.diagnosticsPublished = scheduleSettledFinish;

			child.on("error", (error) => fail(error));
			child.stderr?.on("data", (chunk: Buffer) => {
				this.stderr += chunk.toString("utf8");
				if (this.stderr.length > 4000) this.stderr = this.stderr.slice(-4000);
			});
			child.stdout?.on("data", (chunk: Buffer) => {
				this.buffer = decodeMessages(Buffer.concat([this.buffer, chunk]), (message) => this.handleMessage(message));
			});
			child.on("exit", (code) => {
				if (settled) return;
				fail(new Error(`${this.config.command} exited before ${opened ? "diagnostics completed" : "initialization"} with code ${code}: ${this.stderr.trim()}`));
			});

			const start = async () => {
				await this.request(child, "initialize", {
					processId: process.pid,
					rootUri: pathToFileURL(this.root).toString(),
					capabilities: {
						textDocument: {
							publishDiagnostics: { relatedInformation: false, versionSupport: false },
						},
					},
					workspaceFolders: [{ uri: pathToFileURL(this.root).toString(), name: this.root.split("/").pop() || "workspace" }],
				});
				this.notify(child, "initialized", {});

				for (const file of files) {
					const text = await readFile(file.path, "utf8");
					this.notify(child, "textDocument/didOpen", {
						textDocument: {
							uri: pathToFileURL(file.path).toString(),
							languageId: file.languageId,
							version: 1,
							text,
						},
					});
				}
				opened = true;
				scheduleSettledFinish();
			};

			start().catch(fail);
		});
	}

	private handleMessage(message: any): void {
		if (typeof message?.id === "number" && this.pending.has(message.id)) {
			const pending = this.pending.get(message.id)!;
			this.pending.delete(message.id);
			if (message.error) pending.reject(new Error(message.error.message ?? JSON.stringify(message.error)));
			else pending.resolve(message.result);
			return;
		}

		if (message?.method === "textDocument/publishDiagnostics") {
			const uri = message.params?.uri;
			const diagnostics = message.params?.diagnostics;
			if (typeof uri === "string" && Array.isArray(diagnostics)) {
				this.diagnostics.set(uri, diagnostics.slice(0, MAX_DIAGNOSTICS_PER_FILE));
				this.diagnosticsPublished?.();
			}
		}
	}

	private request(child: ReturnType<typeof spawn>, method: string, params: unknown): Promise<any> {
		const id = this.nextId++;
		const message = { jsonrpc: "2.0", id, method, params };
		return new Promise((resolve, reject) => {
			this.pending.set(id, { resolve, reject });
			child.stdin?.write(encodeMessage(message));
		});
	}

	private notify(child: ReturnType<typeof spawn>, method: string, params: unknown): void {
		child.stdin?.write(encodeMessage({ jsonrpc: "2.0", method, params }));
	}
}

function groupFiles(cwd: string, paths: string[]): { groups: Map<ServerConfig, Array<{ path: string; languageId: string }>>; skipped: string[]; unsupported: string[]; omitted: string[] } {
	const groups = new Map<ServerConfig, Array<{ path: string; languageId: string }>>();
	const skipped: string[] = [];
	const unsupported: string[] = [];
	const omitted = paths.slice(MAX_TOUCHED_FILES).map((rawPath) => `${relative(cwd, normalizePath(cwd, rawPath))}: over ${MAX_TOUCHED_FILES}-file limit`);
	for (const rawPath of paths.slice(0, MAX_TOUCHED_FILES)) {
		const path = normalizePath(cwd, rawPath);
		if (!existsSync(path)) { skipped.push(`${relative(cwd, path)}: missing`); continue; }
		const match = configForPath(path);
		if (!match) { unsupported.push(`${relative(cwd, path)}: unsupported file type`); continue; }
		if (!commandExists(match.config.command)) { unsupported.push(`${relative(cwd, path)}: ${match.config.command} unavailable`); continue; }
		const files = groups.get(match.config) ?? [];
		files.push({ path, languageId: match.languageId });
		groups.set(match.config, files);
	}
	return { groups, skipped, unsupported, omitted };
}

function formatResults(cwd: string, results: FileDiagnosticResult[], skipped: string[]): string {
	const lines: string[] = [];
	let count = 0;
	for (const result of results) {
		for (const diagnostic of result.diagnostics) {
			count++;
			lines.push(diagnosticLine(relative(cwd, result.path), diagnostic));
		}
	}
	if (count === 0) lines.push("No LSP diagnostics for touched files.");
	else lines.unshift(`Found ${count} LSP diagnostic(s) in touched files.`);
	if (skipped.length > 0) {
		lines.push("", `Skipped: ${skipped.join(", ")}`);
	}
	return lines.join("\n");
}

export default function lspDiagnosticsExtension(pi: ExtensionAPI) {
	const touchedFiles = new Set<string>();
	const overLimitTouchedFiles = new Set<string>();
	let unrecordedOverLimitCount = 0;

	pi.on("agent_start", async () => {
		touchedFiles.clear();
		overLimitTouchedFiles.clear();
		unrecordedOverLimitCount = 0;
	});

	pi.on("tool_call", async (event, ctx) => {
		if ((event.toolName !== "edit" && event.toolName !== "write") || !event.input || typeof event.input !== "object") return;
		const path = (event.input as { path?: unknown }).path;
		if (typeof path !== "string" || !path.trim()) return;
		const normalized = normalizePath(ctx.cwd, path);
		if (touchedFiles.has(normalized) || overLimitTouchedFiles.has(normalized)) return;
		if (touchedFiles.size < MAX_TOUCHED_FILES) {
			touchedFiles.add(normalized);
			return;
		}
		if (overLimitTouchedFiles.size < MAX_RECORDED_OVER_LIMIT_FILES) overLimitTouchedFiles.add(normalized);
		else unrecordedOverLimitCount++;
	});

	pi.registerTool({
		name: "lsp_diagnostics",
		label: "LSP Diagnostics",
		description: "Run installed language servers on files touched by edit/write. Intended as an end-of-implementation diagnostics pass, not during editing.",
		promptSnippet: "Run installed language servers on touched files after implementation is complete",
		promptGuidelines: [
			"Use lsp_diagnostics only near the end of implement-route work, after code edits and normal targeted tests/checks are complete.",
			"By default lsp_diagnostics checks only files touched by edit/write in this session. Do not use it for mid-edit exploration.",
			"If lsp_diagnostics reports actionable errors in touched files, fix them and rerun lsp_diagnostics once before the final response.",
		],
		parameters: lspDiagnosticsParameters,
		async execute(_toolCallId, params: LspRequestParams, signal, _onUpdate, ctx) {
			const explicitPaths = Array.isArray(params.paths) && params.paths.length > 0;
			const requestedPaths = explicitPaths ? params.paths! : [...touchedFiles, ...overLimitTouchedFiles];
			const timeoutMs = clampTimeout(params.timeoutMs);
			const receipt = beginVerification(ctx.cwd, "lsp_diagnostics", "diagnose");
			if (requestedPaths.length === 0) {
				const verificationReceipt = finishVerification(receipt, "not_applicable", { command: null, exitCode: null, signal: null, truncated: false, exercisedPaths: [], residualGaps: ["No files were requested or touched."] });
				return {
					content: [{ type: "text" as const, text: "No touched files recorded for LSP diagnostics." }],
					details: { outcome: "not_applicable", diagnostics: [], skipped: [], unsupported: [], serverFailures: [], touchedFiles: [], verificationReceipt },
				};
			}

			const grouped = groupFiles(ctx.cwd, requestedPaths);
			const results: FileDiagnosticResult[] = [];
			const serverFailures: string[] = [];
			let termination: LspOutcome | null = null;
			for (const [config, files] of grouped.groups) {
				try {
					const client = new LspClient(config, ctx.cwd, timeoutMs);
					results.push(...await client.run(files, signal));
				} catch (error) {
					const message = error instanceof Error ? error.message : String(error);
					serverFailures.push(`${config.name}: ${message}`);
					if (message === "Cancelled") termination = "cancelled";
					else if (message === "Timed out" && termination !== "cancelled") termination = "timed_out";
					else if (termination === null) termination = "failed";
				}
			}
			if (!explicitPaths && unrecordedOverLimitCount > 0) grouped.omitted.push(`${unrecordedOverLimitCount} additional touched file(s): over ${MAX_TOUCHED_FILES}-file limit`);
			const diagnosticCount = results.reduce((count, result) => count + result.diagnostics.length, 0);
			const outcome: LspOutcome = termination ?? (diagnosticCount > 0 ? "diagnostics" : grouped.unsupported.length > 0 || grouped.omitted.length > 0 ? "unsupported" : grouped.skipped.length > 0 ? "not_applicable" : "clean");
			const skipped = [...grouped.skipped, ...grouped.unsupported, ...grouped.omitted];
			const exercisedPaths = results.map((result) => relative(ctx.cwd, result.path));
			const verificationReceipt = finishVerification(receipt, outcome, { command: null, exitCode: null, signal: outcome === "cancelled" ? "abort" : null, truncated: false, exercisedPaths, residualGaps: skipped.concat(serverFailures) });
			return {
				content: [{ type: "text" as const, text: `lsp_diagnostics: ${outcome}\n${formatResults(ctx.cwd, results, skipped)}${serverFailures.length ? `\n\nServer failures: ${serverFailures.join(", ")}` : ""}` }],
				isError: outcome !== "clean" && outcome !== "diagnostics" && outcome !== "not_applicable",
				details: {
					outcome,
					diagnostics: results,
					skipped: grouped.skipped,
					unsupported: grouped.unsupported,
					omitted: grouped.omitted,
					serverFailures,
					touchedFiles: Array.from(touchedFiles).map((path) => relative(ctx.cwd, path)),
					verificationReceipt,
				},
			};
		},
	});
}
