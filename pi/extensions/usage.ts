import { access } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { execFile } from "node:child_process";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const exec = promisify(execFile);
const MAX_OUTPUT = 500_000;
const USAGE_TIMEOUT_MS = 8 * 60 * 1000;

function shellWords(input: string): string[] {
	const words: string[] = [];
	let current = "";
	let quote: "'" | '"' | undefined;
	let escaping = false;
	for (const char of input) {
		if (escaping) {
			current += char;
			escaping = false;
			continue;
		}
		if (char === "\\" && quote !== "'") {
			escaping = true;
			continue;
		}
		if ((char === "'" || char === '"') && !quote) {
			quote = char;
			continue;
		}
		if (char === quote) {
			quote = undefined;
			continue;
		}
		if (/\s/.test(char) && !quote) {
			if (current) words.push(current);
			current = "";
			continue;
		}
		current += char;
	}
	if (escaping) current += "\\";
	if (quote) throw new Error("unterminated quote");
	if (current) words.push(current);
	return words;
}

async function command(cwd: string): Promise<{ file: string; args: string[] }> {
	const local = join(cwd, "scripts", "modelusage");
	try {
		await access(local);
		return { file: local, args: [] };
	} catch {
		return { file: "modelusage", args: [] };
	}
}

export default function usageExtension(pi: ExtensionAPI) {
	pi.registerCommand("usage", {
		description: "Run scripts/modelusage or modelusage from PATH. Usage: /usage [args]",
		async handler(args: string | undefined, ctx) {
			try {
				const parsed = shellWords((args ?? "").trim());
				const target = await command(ctx.cwd);
				const result = await exec(target.file, [...target.args, ...parsed], { cwd: ctx.cwd, timeout: USAGE_TIMEOUT_MS, maxBuffer: MAX_OUTPUT });
				ctx.ui.pasteToEditor(result.stdout.trim() || result.stderr.trim() || "modelusage produced no output");
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`/usage failed: ${message}`, "error");
			}
		},
	});
}
