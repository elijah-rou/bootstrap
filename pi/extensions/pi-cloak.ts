import { readFileSync, realpathSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const here = dirname(realpathSync(fileURLToPath(import.meta.url)));
const MAX_PATTERNS = 32;
const ALLOWED_FLAGS = /^[dgimsuvy]*$/;

type PatternConfig = string | { source: string; flags?: string };

function patterns(): RegExp[] {
	const path = join(here, "cloak.json");
	const config = JSON.parse(readFileSync(path, "utf8"));
	if (!Array.isArray(config.patterns)) throw new Error("cloak.json patterns must be an array");

	return config.patterns.slice(0, MAX_PATTERNS).map((entry: PatternConfig, index: number) => {
		const source = typeof entry === "string" ? entry : entry?.source;
		const flags = typeof entry === "string" ? "g" : entry?.flags ?? "g";
		if (typeof source !== "string" || source.length === 0) throw new Error(`cloak pattern ${index} source must be non-empty`);
		if (typeof flags !== "string" || !ALLOWED_FLAGS.test(flags)) throw new Error(`cloak pattern ${index} has invalid flags`);
		const uniqueFlags = Array.from(new Set(flags.split("").concat("g"))).join("");
		return new RegExp(source, uniqueFlags);
	});
}

function redactText(s: string, rs: RegExp[]): string {
	let out = s;
	for (const r of rs) out = out.replace(r, "[REDACTED]");
	return out;
}

export default function (pi: ExtensionAPI) {
	const rs = patterns();
	if (rs.length === 0) throw new Error("cloak.json must define at least one redaction pattern");

	pi.on("tool_result", event => {
		let changed = false;
		const content = event.content.map((c: any) => {
			if (c.type !== "text" || typeof c.text !== "string") return c;
			const text = redactText(c.text, rs);
			changed ||= text !== c.text;
			return { ...c, text };
		});
		if (changed) return { content };
	});
}
