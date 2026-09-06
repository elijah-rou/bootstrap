import { existsSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@mariozechner/pi-ai";

const COPY_OK = "__PI_COPY_OK__";
const COPY_SCRIPT = `if [[ -n "\${XDG_RUNTIME_DIR:-}" && ! -S "\${XDG_RUNTIME_DIR}/\${WAYLAND_DISPLAY:-}" ]]; then
	for wayland_socket in "\${XDG_RUNTIME_DIR}"/wayland-*(N); do
		[[ -S "$wayland_socket" ]] || continue
		export WAYLAND_DISPLAY="\${wayland_socket:t}"
		break
	done
fi
copy -- "$1" >/dev/null || exit $?
printf '%s' '${COPY_OK}'`;

type CopyMode = "file" | "text";

const copyParameters = Type.Object({
	text: Type.Optional(Type.String({
		description: "Raw text to copy to the clipboard. Provide this OR path.",
	})),
	path: Type.Optional(Type.String({
		description: "Path to a file whose contents should be copied to the clipboard. Provide this OR text.",
	})),
});

function stripAtPrefix(value: string): string {
	return value.startsWith("@") ? value.slice(1) : value;
}

function detectFileArg(cwd: string, value: string): { kind: "file"; value: string } | { kind: "text"; value: string } {
	const trimmed = value.trim();
	if (!trimmed) return { kind: "text", value: trimmed };

	const candidate = stripAtPrefix(trimmed);
	const absolute = resolve(cwd, candidate);
	if (existsSync(absolute)) {
		return { kind: "file", value: absolute };
	}

	return { kind: "text", value: value };
}

export async function runCopy(pi: ExtensionAPI, mode: CopyMode, value: string, signal?: AbortSignal) {
	let temporaryDirectory: string | undefined;
	let sourcePath: string;

	switch (mode) {
		case "file":
			sourcePath = value;
			break;
		case "text":
			temporaryDirectory = await mkdtemp(join(tmpdir(), "pi-copy-"));
			sourcePath = join(temporaryDirectory, "content");
			await writeFile(sourcePath, value, { encoding: "utf8", mode: 0o600 });
			break;
		default:
			throw new Error(`Unknown copy mode: ${mode satisfies never}`);
	}

	try {
		const result = await pi.exec("zsh", ["-lic", COPY_SCRIPT, "_", sourcePath], {
			signal,
			timeout: 15000,
		});

		if (result.code !== 0 || !result.stdout.includes(COPY_OK)) {
			const stderr = result.stderr?.trim();
			const stdout = result.stdout?.trim();
			throw new Error(stderr || stdout || `copy failed with exit code ${result.code}`);
		}
	} finally {
		if (temporaryDirectory) await rm(temporaryDirectory, { recursive: true, force: true });
	}
}

type SessionEntry = { role?: string; content?: unknown; message?: { role?: string; content?: unknown } };
type SessionBranch = SessionEntry[] | { messages?: SessionEntry[]; entries?: SessionEntry[] };

type CopyAllContext = {
	cwd: string;
	sessionManager?: { getBranch(): SessionBranch | undefined };
	ui: { notify(message: string, level: "success" | "warning" | "error"): void };
};

function contentText(content: unknown): string {
	if (typeof content === "string") return content;
	if (Array.isArray(content)) {
		return content.map((part) => {
			if (typeof part === "string") return part;
			if (part && typeof part === "object" && "text" in part && typeof part.text === "string") return part.text;
			return "";
		}).filter(Boolean).join("\n");
	}
	return "";
}

function branchEntries(branch: SessionBranch | undefined): SessionEntry[] {
	if (!branch) return [];
	if (Array.isArray(branch)) return branch;
	if (Array.isArray(branch.messages)) return branch.messages;
	if (Array.isArray(branch.entries)) return branch.entries;
	return [];
}

function formatSessionThread(branch: SessionBranch | undefined): string {
	const out: string[] = [];
	for (const entry of branchEntries(branch)) {
		const message = entry.message ?? entry;
		const role = message.role;
		if (role !== "user" && role !== "assistant") continue;
		const text = contentText(message.content).trim();
		if (!text) continue;
		out.push(`## ${role}`, "", text, "");
	}
	return out.join("\n").trim();
}

export default function copyExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "copy",
		label: "Copy",
		description: "Copy raw text or a file's contents to the user's clipboard using their zsh copy helper.",
		promptSnippet: "Copy text or a file's contents to the user's clipboard",
		promptGuidelines: [
			"Use this tool only when the user explicitly asks to copy something to their clipboard.",
			"Provide exactly one of text or path.",
		],
		parameters: copyParameters,
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const hasText = typeof params.text === "string" && params.text.length > 0;
			const hasPath = typeof params.path === "string" && params.path.length > 0;

			if (hasText === hasPath) {
				throw new Error("Copy requires exactly one of `text` or `path`.");
			}

			const mode = hasPath ? "file" : "text";
			const value = hasPath ? resolve(ctx.cwd, stripAtPrefix(params.path!)) : params.text!;

			await runCopy(pi, mode, value, signal);
			return {
				content: [{
					type: "text",
					text: mode === "file"
						? `Copied file contents from ${params.path} to the clipboard.`
						: "Copied text to the clipboard.",
				}],
				details: { ok: true, mode, value },
			};
		},
	});

	pi.registerCommand("copy-all", {
		description: "Copy the current user+assistant thread to the clipboard.",
		handler: async (_args: string | undefined, ctx: CopyAllContext) => {
			const branch = ctx.sessionManager?.getBranch();
			if (!branch) {
				ctx.ui.notify("/copy-all: no current branch", "warning");
				return;
			}
			try {
				const thread = formatSessionThread(branch);
				if (!thread) {
					ctx.ui.notify("/copy-all: no user/assistant messages found", "warning");
					return;
				}
				await runCopy(pi, "text", thread);
				ctx.ui.notify("Copied current thread to clipboard", "success");
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`/copy-all failed: ${message}`, "error");
			}
		},
	});

	pi.registerCommand("clip", {
		description: "Copy raw text or a file to the clipboard. Usage: /clip @path/to/file or /clip some text",
		handler: async (args, ctx) => {
			const input = args?.trim() ?? "";
			if (!input) {
				ctx.ui.notify("Usage: /clip @path/to/file or /clip some text", "warning");
				return;
			}

			const detected = detectFileArg(ctx.cwd, input);
			try {
				await runCopy(pi, detected.kind, detected.value);
				ctx.ui.notify(
					detected.kind === "file"
						? `Copied file contents: ${input}`
						: "Copied text to clipboard",
					"success",
				);
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`Copy failed: ${message}`, "error");
			}
		},
	});
}
