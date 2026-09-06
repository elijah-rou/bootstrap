import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const MAX_BYTES = 50_000;
const MAX_PAGES = 200;
const MAX_PAGE_NUMBER = 2_147_483_647;
const DEFAULT_PAGE_LIMIT = 20;

function cleanPath(cwd: string, path: string): string {
	const value = path.startsWith("@") ? path.slice(1) : path;
	const absolute = resolve(cwd, value);
	if (!existsSync(absolute)) throw new Error(`PDF not found: ${path}`);
	if (!absolute.toLowerCase().endsWith(".pdf")) throw new Error(`Expected a .pdf file: ${path}`);
	return absolute;
}

function pageNumber(value: unknown, fallback: number): number {
	const page = value === undefined ? fallback : value;
	if (typeof page !== "number" || !Number.isInteger(page) || page < 1 || page > MAX_PAGE_NUMBER) {
		throw new Error(`PDF page numbers must be integers from 1 to ${MAX_PAGE_NUMBER}.`);
	}
	return page;
}

function truncate(text: string): { text: string; truncated: boolean } {
	const bytes = Buffer.byteLength(text, "utf8");
	if (bytes <= MAX_BYTES) return { text, truncated: false };
	let output = "";
	let used = 0;
	for (const char of text) {
		const size = Buffer.byteLength(char, "utf8");
		if (used + size > MAX_BYTES) break;
		output += char;
		used += size;
	}
	return { text: `${output}\n[truncated to ${MAX_BYTES} bytes]`, truncated: true };
}

async function run(pi: ExtensionAPI, command: string, args: string[], signal?: AbortSignal): Promise<string> {
	const result = await pi.exec(command, args, { timeout: 30_000, signal });
	if (result.killed || signal?.aborted) throw new Error(`${command} was cancelled or timed out.`);
	if (result.code !== 0) throw new Error((result.stderr || result.stdout || `${command} failed`).trim());
	return result.stdout.trim();
}

export default function pdfTools(pi: ExtensionAPI) {
	pi.registerTool({
		name: "pdf_info",
		label: "PDF Info",
		description: "Inspect PDF metadata/page count using pdfinfo. Does not send PDF contents to the model.",
		promptSnippet: "Inspect PDF metadata and page count for local PDF files",
		promptGuidelines: ["Use pdf_info before extracting long PDFs so page bounds are known."],
		parameters: Type.Object({ path: Type.String({ description: "Path to a local .pdf file" }) }),
		async execute(_id, params, signal, _onUpdate, ctx) {
			const path = cleanPath(ctx.cwd, params.path);
			const info = await run(pi, "pdfinfo", [path], signal);
			return { content: [{ type: "text", text: info }], details: { path } };
		},
	});

	pi.registerTool({
		name: "pdf_extract",
		label: "PDF Extract",
		description: "Extract up to 200 consecutive pages anywhere in a local PDF using pdftotext. Output capped at 50KB; invalid ranges are rejected.",
		promptSnippet: "Extract bounded text from local PDF files",
		promptGuidelines: ["Use pdf_extract for PDF reading. Keep page ranges small; call pdf_info first for long documents."],
		parameters: Type.Object({
			path: Type.String({ description: "Path to a local .pdf file" }),
			firstPage: Type.Optional(Type.Integer({ minimum: 1, maximum: MAX_PAGE_NUMBER, description: "First page, 1-indexed. Defaults to 1." })),
			lastPage: Type.Optional(Type.Integer({ minimum: 1, maximum: MAX_PAGE_NUMBER, description: "Last page, inclusive. Defaults to firstPage + 19. Range may contain at most 200 pages." })),
		}),
		async execute(_id, params, signal, _onUpdate, ctx) {
			const path = cleanPath(ctx.cwd, params.path);
			const firstPage = pageNumber(params.firstPage, 1);
			const lastPage = pageNumber(params.lastPage, firstPage + DEFAULT_PAGE_LIMIT - 1);
			if (lastPage < firstPage || lastPage - firstPage + 1 > MAX_PAGES) {
				throw new Error(`PDF range must contain 1-${MAX_PAGES} consecutive pages in ascending order.`);
			}
			const text = await run(pi, "pdftotext", ["-f", String(firstPage), "-l", String(lastPage), "-layout", path, "-"], signal);
			const out = truncate(text || "[no extractable text]");
			return { content: [{ type: "text", text: out.text }], details: { path, firstPage, lastPage, truncated: out.truncated } };
		},
	});
}
