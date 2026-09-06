import { existsSync, readFileSync } from "node:fs";
import { extname, isAbsolute, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { Type } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const MAX_RESULTS = 20;
const MAX_SNIPPET_LINES = 8;
const MAX_OUTPUT_CHARS = 25_000;
const TEXT_EXTENSIONS = new Set([".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".rs", ".go", ".zig", ".java", ".kt", ".swift", ".c", ".h", ".cpp", ".hpp", ".lua", ".sh", ".bash", ".zsh", ".md", ".mdx", ".txt", ".json", ".toml", ".yaml", ".yml", ".html", ".css", ".scss", ".sql"]);

interface Params {
	query: string;
	path?: string;
	limit?: number;
	mode?: "code" | "docs" | "all";
}

interface Result {
	path: string;
	line: number;
	score: number;
	snippet: string;
}

function stripAtPrefix(value: string): string {
	return value.startsWith("@") ? value.slice(1) : value;
}

function normalizePath(cwd: string, value: string | undefined): string {
	if (!value || !value.trim()) return cwd;
	const stripped = stripAtPrefix(value.trim());
	return isAbsolute(stripped) ? resolve(stripped) : resolve(cwd, stripped);
}

function commandExists(command: string): boolean {
	return spawnSync("sh", ["-c", "command -v -- \"$1\" >/dev/null 2>&1", "_", command], { stdio: "ignore", timeout: 1000 }).status === 0;
}

function queryTerms(query: string): string[] {
	return Array.from(new Set(query.toLowerCase().split(/[^a-z0-9_./-]+/).filter((term) => term.length >= 2))).slice(0, 12);
}

function modeAllows(path: string, mode: Params["mode"]): boolean {
	const ext = extname(path).toLowerCase();
	if (mode === "docs") return ext === ".md" || ext === ".mdx" || ext === ".txt";
	if (mode === "code") return TEXT_EXTENSIONS.has(ext) && ext !== ".md" && ext !== ".mdx" && ext !== ".txt";
	return TEXT_EXTENSIONS.has(ext);
}

function readSnippet(path: string, line: number): string {
	try {
		const lines = readFileSync(path, "utf8").split(/\r?\n/);
		const start = Math.max(0, line - 1 - 2);
		const end = Math.min(lines.length, start + MAX_SNIPPET_LINES);
		return lines.slice(start, end).map((text, index) => `${start + index + 1}: ${text}`).join("\n");
	} catch {
		return "";
	}
}

function lexicalSearch(root: string, terms: string[], limit: number, mode: Params["mode"]): Result[] {
	if (terms.length === 0) return [];
	const pattern = terms.map((term) => term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|");
	const rg = spawnSync("rg", ["--with-filename", "--line-number", "--no-heading", "--color=never", "--ignore-case", "--max-count", "20", pattern, root], { encoding: "utf8", timeout: 10_000, maxBuffer: 2_000_000 });
	if (rg.error || (rg.status !== 0 && rg.status !== 1)) {
		throw new Error(`semantic_search failed: ${rg.error?.message || rg.stderr?.trim() || `rg exited with ${rg.status}`}`);
	}
	const rows = (rg.stdout || "").split(/\r?\n/).filter(Boolean);
	const byKey = new Map<string, Omit<Result, "snippet">>();
	for (const row of rows) {
		const match = /^(.*?):(\d+):(.*)$/.exec(row);
		if (!match) continue;
		const path = resolve(match[1]);
		if (!modeAllows(path, mode)) continue;
		const text = match[3].toLowerCase();
		let score = 0;
		for (const term of terms) if (text.includes(term)) score += term.length;
		if (score === 0) continue;
		const line = Number(match[2]);
		const key = `${path}:${line}`;
		const previous = byKey.get(key);
		if (!previous || previous.score < score) byKey.set(key, { path, line, score });
	}
	return Array.from(byKey.values())
		.sort((a, b) => b.score - a.score || a.path.localeCompare(b.path))
		.slice(0, limit)
		.map((result) => ({ ...result, snippet: readSnippet(result.path, result.line) }));
}

function formatResults(cwd: string, query: string, results: Result[], backend: string): string {
	if (results.length === 0) return `No semantic_search results for: ${query}\nBackend: ${backend}`;
	const chunks = [`semantic_search results for: ${query}`, `Backend: ${backend}`, ""];
	for (const [index, result] of results.entries()) {
		chunks.push(`${index + 1}. ${relative(cwd, result.path)}:${result.line} score=${result.score}`, result.snippet, "");
	}
	const text = chunks.join("\n").trim();
	return text.length > MAX_OUTPUT_CHARS ? `${text.slice(0, MAX_OUTPUT_CHARS)}\n[truncated]` : text;
}

export default function semanticSearchExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "semantic_search",
		label: "Semantic Search",
		description: "Search code or docs using ranked lexical matches across query terms. Supports files and directories. No embedding or configurable semantic backend is implemented.",
		promptSnippet: "Search repo code/docs with ranked multi-term lexical matching",
		promptGuidelines: [
			"Use semantic_search for ranked multi-term code/docs searches when a single exact grep pattern is insufficient.",
			"Do not treat semantic_search fallback results as true embeddings; check the Backend line and verify important matches with read before editing.",
		],
		parameters: Type.Object({
			query: Type.String({ description: "Natural language or keyword search query." }),
			path: Type.Optional(Type.String({ description: "Directory or file to search. Defaults to current working directory." })),
			limit: Type.Optional(Type.Number({ description: "Maximum result count. Defaults to 10, max 20." })),
			mode: Type.Optional(Type.Union([Type.Literal("code"), Type.Literal("docs"), Type.Literal("all")], { description: "Restrict results by content type. Defaults to all." })),
		}),
		async execute(_id, params: Params, _signal, _onUpdate, ctx) {
			const root = normalizePath(ctx.cwd, params.path);
			if (!existsSync(root)) return { content: [{ type: "text" as const, text: `semantic_search path does not exist: ${root}` }], isError: true, details: { root } };
			const limit = Math.max(1, Math.min(MAX_RESULTS, Math.trunc(params.limit ?? 10)));
			const mode = params.mode ?? "all";
			const terms = queryTerms(params.query);
			if (terms.length === 0) return { content: [{ type: "text" as const, text: "semantic_search query has no searchable terms." }], isError: true, details: { root, mode } };
			if (!commandExists("rg")) return { content: [{ type: "text" as const, text: "semantic_search requires rg for fallback search; no semantic backend configured." }], isError: true, details: { root, mode, backend: "none" } };
			const results = lexicalSearch(root, terms, limit, mode);
			return { content: [{ type: "text" as const, text: formatResults(ctx.cwd, params.query, results, "ranked-lexical-fallback") }], details: { root, mode, backend: "ranked-lexical-fallback", count: results.length } };
		},
	});
}
