import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { extname, isAbsolute, relative, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { spawn, spawnSync } from "node:child_process";
import { Type } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const DEFAULT_TIMEOUT_MS = 10_000;
const MAX_TIMEOUT_MS = 30_000;
const MAX_RESULTS = 80;

type ServerName = "typescript-language-server" | "basedpyright" | "pyright-langserver" | "rust-analyzer" | "gopls" | "elixir-ls" | "zls";

interface ServerConfig {
	name: ServerName;
	command: string;
	args: string[];
	languageIds: Record<string, string>;
}

interface PositionParams {
	path: string;
	line: number;
	character: number;
	timeoutMs?: number;
	includeDeclaration?: boolean;
}

interface SymbolsParams {
	query: string;
	path?: string;
	limit?: number;
	timeoutMs?: number;
}

const SERVERS: ServerConfig[] = [
	{ name: "elixir-ls", command: "elixir-ls", args: [], languageIds: { ".ex": "elixir", ".exs": "elixir" } },
	{ name: "zls", command: "zls", args: [], languageIds: { ".zig": "zig" } },
	{ name: "typescript-language-server", command: "typescript-language-server", args: ["--stdio"], languageIds: { ".ts": "typescript", ".tsx": "typescriptreact", ".js": "javascript", ".jsx": "javascriptreact", ".mjs": "javascript", ".cjs": "javascript" } },
	{ name: "basedpyright", command: "basedpyright-langserver", args: ["--stdio"], languageIds: { ".py": "python", ".pyi": "python" } },
	{ name: "pyright-langserver", command: "pyright-langserver", args: ["--stdio"], languageIds: { ".py": "python", ".pyi": "python" } },
	{ name: "rust-analyzer", command: "rust-analyzer", args: [], languageIds: { ".rs": "rust" } },
	{ name: "gopls", command: "gopls", args: [], languageIds: { ".go": "go" } },
];

function stripAtPrefix(value: string): string {
	return value.startsWith("@") ? value.slice(1) : value;
}

function normalizePath(cwd: string, path: string | undefined): string {
	if (!path || !path.trim()) return cwd;
	const stripped = stripAtPrefix(path.trim());
	return isAbsolute(stripped) ? resolve(stripped) : resolve(cwd, stripped);
}

function clampTimeout(value: unknown): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return DEFAULT_TIMEOUT_MS;
	return Math.max(1000, Math.min(MAX_TIMEOUT_MS, Math.trunc(value)));
}

const commandCache = new Map<string, boolean>();
function commandExists(command: string): boolean {
	const cached = commandCache.get(command);
	if (cached !== undefined) return cached;
	const ok = spawnSync("sh", ["-c", "command -v -- \"$1\" >/dev/null 2>&1", "_", command], { stdio: "ignore", timeout: 1000 }).status === 0;
	commandCache.set(command, ok);
	return ok;
}

function configForPath(path: string): { config: ServerConfig; languageId: string } | null {
	const ext = extname(path).toLowerCase();
	for (const config of SERVERS) {
		const languageId = config.languageIds[ext];
		if (languageId && commandExists(config.command)) return { config, languageId };
	}
	return null;
}

function encode(message: unknown): string {
	const json = JSON.stringify(message);
	return `Content-Length: ${Buffer.byteLength(json, "utf8")}\r\n\r\n${json}`;
}

function decode(buffer: Buffer, onMessage: (message: any) => void): Buffer {
	let offset = 0;
	while (true) {
		const headerEnd = buffer.indexOf("\r\n\r\n", offset, "utf8");
		if (headerEnd < 0) break;
		const header = buffer.subarray(offset, headerEnd).toString("utf8");
		const match = /Content-Length: (\d+)/i.exec(header);
		if (!match) { offset = headerEnd + 4; continue; }
		const length = Number(match[1]);
		const bodyStart = headerEnd + 4;
		const bodyEnd = bodyStart + length;
		if (buffer.length < bodyEnd) break;
		try { onMessage(JSON.parse(buffer.subarray(bodyStart, bodyEnd).toString("utf8"))); } catch {}
		offset = bodyEnd;
	}
	return buffer.subarray(offset);
}

class Client {
	private nextId = 1;
	private buffer: Buffer<ArrayBufferLike> = Buffer.alloc(0);
	private pending = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void }>();
	private stderr = "";

	constructor(private readonly config: ServerConfig, private readonly root: string, private readonly timeoutMs: number) {}

	async use<T>(file: { path: string; languageId: string } | null, work: (client: Client, child: ReturnType<typeof spawn>) => Promise<T>, signal?: AbortSignal): Promise<T> {
		return await new Promise<T>((resolveUse, rejectUse) => {
			const child = spawn(this.config.command, this.config.args, { cwd: this.root, stdio: ["pipe", "pipe", "pipe"] });
			let settled = false;
			const timer = setTimeout(() => finish(new Error("LSP navigation timed out")), this.timeoutMs);
			const abort = () => finish(new Error("Cancelled"));
			signal?.addEventListener("abort", abort, { once: true });
			const finish = (error?: Error, value?: T) => {
				if (settled) return;
				settled = true;
				clearTimeout(timer);
				signal?.removeEventListener("abort", abort);
				for (const p of this.pending.values()) p.reject(new Error("LSP client closed"));
				this.pending.clear();
				child.stdin?.write(encode({ jsonrpc: "2.0", id: this.nextId++, method: "shutdown", params: null }));
				child.stdin?.write(encode({ jsonrpc: "2.0", method: "exit" }));
				setTimeout(() => child.kill("SIGTERM"), 100).unref();
				if (error) rejectUse(error); else resolveUse(value as T);
			};
			child.on("error", finish);
			child.stderr?.on("data", (chunk: Buffer) => { this.stderr += chunk.toString("utf8"); if (this.stderr.length > 4000) this.stderr = this.stderr.slice(-4000); });
			child.stdout?.on("data", (chunk: Buffer) => { this.buffer = decode(Buffer.concat([this.buffer, chunk]), (message) => this.handle(message)); });
			child.on("exit", (code) => { if (!settled) finish(new Error(`${this.config.command} exited with code ${code}: ${this.stderr.trim()}`)); });
			(async () => {
				await this.request(child, "initialize", { processId: process.pid, rootUri: pathToFileURL(this.root).toString(), capabilities: { textDocument: { definition: {}, references: {}, documentSymbol: {} }, workspace: { symbol: {} } }, workspaceFolders: [{ uri: pathToFileURL(this.root).toString(), name: this.root.split("/").pop() || "workspace" }] });
				this.notify(child, "initialized", {});
				if (file) {
					const text = await readFile(file.path, "utf8");
					this.notify(child, "textDocument/didOpen", { textDocument: { uri: pathToFileURL(file.path).toString(), languageId: file.languageId, version: 1, text } });
				}
				const value = await work(this, child);
				finish(undefined, value);
			})().catch((error) => finish(error));
		});
	}

	request(child: ReturnType<typeof spawn>, method: string, params: unknown): Promise<any> {
		const id = this.nextId++;
		return new Promise((resolve, reject) => {
			this.pending.set(id, { resolve, reject });
			child.stdin?.write(encode({ jsonrpc: "2.0", id, method, params }));
		});
	}

	private notify(child: ReturnType<typeof spawn>, method: string, params: unknown): void {
		child.stdin?.write(encode({ jsonrpc: "2.0", method, params }));
	}

	private handle(message: any): void {
		if (typeof message?.id !== "number") return;
		const pending = this.pending.get(message.id);
		if (!pending) return;
		this.pending.delete(message.id);
		if (message.error) pending.reject(new Error(message.error.message ?? JSON.stringify(message.error)));
		else pending.resolve(message.result);
	}
}

function locationPath(location: any): string | null {
	const uri = typeof location?.uri === "string" ? location.uri : typeof location?.targetUri === "string" ? location.targetUri : null;
	if (!uri) return null;
	try { return fileURLToPath(uri); } catch { return null; }
}

function locationRange(location: any): { line: number; character: number } {
	const range = location?.range ?? location?.targetSelectionRange ?? location?.targetRange ?? {};
	return { line: (range.start?.line ?? 0) + 1, character: (range.start?.character ?? 0) + 1 };
}

function formatLocations(cwd: string, title: string, locations: any[]): string {
	if (!Array.isArray(locations) || locations.length === 0) return `${title}: no results.`;
	const lines = [`${title}: ${locations.length} result(s)`];
	for (const location of locations.slice(0, MAX_RESULTS)) {
		const path = locationPath(location);
		if (!path) continue;
		const pos = locationRange(location);
		lines.push(`${relative(cwd, path)}:${pos.line}:${pos.character}`);
	}
	if (locations.length > MAX_RESULTS) lines.push(`[truncated ${locations.length - MAX_RESULTS} result(s)]`);
	return lines.join("\n");
}

function flattenSymbols(symbols: any[], query: string, limit: number): string[] {
	const needle = query.toLowerCase();
	const out: string[] = [];
	const visit = (symbol: any, prefix: string) => {
		if (out.length >= limit) return;
		const name = typeof symbol?.name === "string" ? symbol.name : "";
		const full = prefix ? `${prefix}.${name}` : name;
		const uri = typeof symbol?.location?.uri === "string" ? symbol.location.uri : undefined;
		const path = uri ? locationPath(symbol.location) : null;
		const range = symbol?.location ? locationRange(symbol.location) : locationRange(symbol);
		if (!needle || full.toLowerCase().includes(needle)) out.push(path ? `${full} ${path}:${range.line}:${range.character}` : `${full}:${range.line}:${range.character}`);
		for (const child of symbol?.children ?? []) visit(child, full);
	};
	for (const symbol of symbols ?? []) visit(symbol, "");
	return out;
}

export default function lspNavigationExtension(pi: ExtensionAPI) {
	const positionParams = Type.Object({ path: Type.String(), line: Type.Number(), character: Type.Number(), timeoutMs: Type.Optional(Type.Number()), includeDeclaration: Type.Optional(Type.Boolean()) });
	pi.registerTool({
		name: "lsp_definition",
		label: "LSP Definition",
		description: "Find definition targets for a symbol using an installed language server.",
		promptSnippet: "Find symbol definitions via installed language servers",
		promptGuidelines: ["Use lsp_definition for symbol-aware navigation when grep would be ambiguous; verify important results with read before editing."],
		parameters: positionParams,
		async execute(_id, params: PositionParams, signal, _onUpdate, ctx) {
			const path = normalizePath(ctx.cwd, params.path);
			if (!existsSync(path)) return { content: [{ type: "text" as const, text: `lsp_definition path not found: ${path}` }], isError: true, details: undefined };
			const match = configForPath(path);
			if (!match) return { content: [{ type: "text" as const, text: `No installed language server supports ${relative(ctx.cwd, path)}.` }], isError: true, details: undefined };
			const client = new Client(match.config, ctx.cwd, clampTimeout(params.timeoutMs));
			const locations = await client.use({ path, languageId: match.languageId }, (c, child) => c.request(child, "textDocument/definition", { textDocument: { uri: pathToFileURL(path).toString() }, position: { line: Math.max(0, params.line - 1), character: Math.max(0, params.character - 1) } }), signal);
			const list = Array.isArray(locations) ? locations : locations ? [locations] : [];
			return { content: [{ type: "text" as const, text: formatLocations(ctx.cwd, "lsp_definition", list) }], details: { server: match.config.name, count: list.length } };
		},
	});
	pi.registerTool({
		name: "lsp_references",
		label: "LSP References",
		description: "Find references for a symbol using an installed language server.",
		promptSnippet: "Find symbol references via installed language servers",
		promptGuidelines: ["Use lsp_references before refactors or behavior changes that depend on all call sites."],
		parameters: positionParams,
		async execute(_id, params: PositionParams, signal, _onUpdate, ctx) {
			const path = normalizePath(ctx.cwd, params.path);
			if (!existsSync(path)) return { content: [{ type: "text" as const, text: `lsp_references path not found: ${path}` }], isError: true, details: undefined };
			const match = configForPath(path);
			if (!match) return { content: [{ type: "text" as const, text: `No installed language server supports ${relative(ctx.cwd, path)}.` }], isError: true, details: undefined };
			const client = new Client(match.config, ctx.cwd, clampTimeout(params.timeoutMs));
			const locations = await client.use({ path, languageId: match.languageId }, (c, child) => c.request(child, "textDocument/references", { textDocument: { uri: pathToFileURL(path).toString() }, position: { line: Math.max(0, params.line - 1), character: Math.max(0, params.character - 1) }, context: { includeDeclaration: params.includeDeclaration ?? false } }), signal);
			const list = Array.isArray(locations) ? locations : [];
			return { content: [{ type: "text" as const, text: formatLocations(ctx.cwd, "lsp_references", list) }], details: { server: match.config.name, count: list.length } };
		},
	});
	pi.registerTool({
		name: "lsp_symbols",
		label: "LSP Symbols",
		description: "Search workspace or document symbols using an installed language server.",
		promptSnippet: "Search workspace/document symbols via language servers",
		promptGuidelines: ["Use lsp_symbols when symbol-aware navigation improves precision; use grep for obvious text lookups or unsupported languages."],
		parameters: Type.Object({ query: Type.String(), path: Type.Optional(Type.String()), limit: Type.Optional(Type.Number()), timeoutMs: Type.Optional(Type.Number()) }),
		async execute(_id, params: SymbolsParams, signal, _onUpdate, ctx) {
			const path = params.path ? normalizePath(ctx.cwd, params.path) : null;
			const match = path ? configForPath(path) : SERVERS.find((server) => commandExists(server.command)) ? { config: SERVERS.find((server) => commandExists(server.command))!, languageId: "" } : null;
			if (!match) return { content: [{ type: "text" as const, text: "No installed language server available for lsp_symbols." }], isError: true, details: undefined };
			const limit = Math.max(1, Math.min(MAX_RESULTS, Math.trunc(params.limit ?? 30)));
			const client = new Client(match.config, ctx.cwd, clampTimeout(params.timeoutMs));
			const file = path && existsSync(path) ? { path, languageId: match.languageId } : null;
			const symbols = await client.use(file, (c, child) => path ? c.request(child, "textDocument/documentSymbol", { textDocument: { uri: pathToFileURL(path).toString() } }) : c.request(child, "workspace/symbol", { query: params.query }), signal);
			const rows = flattenSymbols(Array.isArray(symbols) ? symbols : [], params.query, limit).map((row) => row.replace(ctx.cwd + "/", ""));
			return { content: [{ type: "text" as const, text: rows.length ? `lsp_symbols: ${rows.length} result(s)\n${rows.join("\n")}` : "lsp_symbols: no results." }], details: { server: match.config.name, count: rows.length } };
		},
	});
}
