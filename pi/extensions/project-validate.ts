import { existsSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { createLocalBashOperations } from "@earendil-works/pi-coding-agent";
import { Type } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { beginVerification, finishVerification } from "./verification-receipt.ts";

const DEFAULT_TIMEOUT_MS = 120_000;
const MIN_TIMEOUT_MS = 1_000;
const MAX_TIMEOUT_MS = 300_000;
const MAX_OUTPUT_CHARS = 30_000;
const ROOT_MARKERS = ["package.json", "bun.lock", "pnpm-lock.yaml", "package-lock.json", "yarn.lock", "Cargo.toml", "go.mod", "pyproject.toml", "uv.lock", "Makefile", "justfile"];

type Action = "test" | "lint" | "typecheck";
type ValidationOutcome = "passed" | "failed" | "timed_out" | "cancelled" | "execution_error" | "unsupported";

interface Params {
	action: Action;
	command?: string;
	cwd?: string;
	timeoutMs?: number;
}

interface CommandSpec {
	command: string;
	reason: string;
}

function stripAtPrefix(value: string): string {
	return value.startsWith("@") ? value.slice(1) : value;
}

function normalizePath(cwd: string, value: string | undefined): string {
	if (!value || !value.trim()) return cwd;
	const stripped = stripAtPrefix(value.trim());
	return isAbsolute(stripped) ? resolve(stripped) : resolve(cwd, stripped);
}

function clampTimeout(value: unknown): number {
	if (typeof value !== "number" || !Number.isFinite(value)) return DEFAULT_TIMEOUT_MS;
	return Math.max(MIN_TIMEOUT_MS, Math.min(MAX_TIMEOUT_MS, Math.trunc(value)));
}

function repositoryBoundary(start: string): { boundary: string; inGit: boolean } {
	const requested = resolve(start);
	const result = spawnSync("git", ["-C", requested, "rev-parse", "--show-toplevel"], { encoding: "utf8", timeout: 2_000 });
	if (result.status === 0 && result.stdout.trim()) return { boundary: resolve(result.stdout.trim()), inGit: true };
	return { boundary: requested, inGit: false };
}

function findProjectRoot(start: string): { root: string; markerFound: boolean; inGit: boolean } {
	const requested = resolve(start);
	const { boundary, inGit } = repositoryBoundary(requested);
	let dir = requested;
	while (true) {
		for (const marker of ROOT_MARKERS) {
			if (existsSync(resolve(dir, marker))) return { root: dir, markerFound: true, inGit };
		}
		if (dir === boundary) return { root: boundary, markerFound: false, inGit };
		const parent = dirname(dir);
		if (parent === dir || relativeEscapes(boundary, parent)) return { root: boundary, markerFound: false, inGit };
		dir = parent;
	}
}

function relativeEscapes(boundary: string, candidate: string): boolean {
	const relative = candidate.slice(resolve(boundary).length);
	return relative !== "" && !resolve(candidate).startsWith(`${resolve(boundary)}/`);
}

function commandFor(root: string, action: Action): CommandSpec | null {
	const has = (name: string) => existsSync(resolve(root, name));
	if (has("package.json")) {
		const runner = has("bun.lock") ? "bun run" : has("pnpm-lock.yaml") ? "pnpm" : has("yarn.lock") ? "yarn" : "npm run";
		switch (action) {
			case "test": return { command: `${runner} test`, reason: "package.json project" };
			case "lint": return { command: `${runner} lint`, reason: "package.json project" };
			case "typecheck": return { command: `${runner} typecheck`, reason: "package.json project" };
		}
	}
	if (has("Cargo.toml")) {
		switch (action) {
			case "test": return { command: "cargo test", reason: "Cargo.toml project" };
			case "lint": return { command: "cargo clippy --all-targets --all-features -- -D warnings", reason: "Cargo.toml project" };
			case "typecheck": return { command: "cargo check --all-targets --all-features", reason: "Cargo.toml project" };
		}
	}
	if (has("go.mod")) {
		switch (action) {
			case "test": return { command: "go test ./...", reason: "go.mod project" };
			case "lint": return { command: "go vet ./...", reason: "go.mod project" };
			case "typecheck": return { command: "go test ./...", reason: "go.mod project" };
		}
	}
	if (has("pyproject.toml") || has("uv.lock")) {
		switch (action) {
			case "test": return { command: has("uv.lock") ? "uv run pytest" : "pytest", reason: "Python project" };
			case "lint": return { command: has("uv.lock") ? "uv run ruff check ." : "ruff check .", reason: "Python project" };
			case "typecheck": return { command: has("uv.lock") ? "uv run pyright" : "pyright", reason: "Python project" };
		}
	}
	if (has("Makefile")) return { command: `make ${action}`, reason: "Makefile project" };
	if (has("justfile")) return { command: `just ${action}`, reason: "justfile project" };
	return null;
}

function truncateMiddle(text: string, maxChars: number): { text: string; truncated: boolean } {
	if (text.length <= maxChars) return { text, truncated: false };
	const head = Math.floor(maxChars * 0.35);
	const tail = maxChars - head - 32;
	return { text: `${text.slice(0, head)}\n[... truncated ...]\n${text.slice(-tail)}`, truncated: true };
}

function summarizeFailures(output: string): string[] {
	const patterns = [/\berror\b/i, /\bfail(?:ed|ure)?\b/i, /\bpanic\b/i, /\bexception\b/i, /\bassert/i, /\bE\d{3,4}\b/, /\bTS\d{4}\b/];
	const lines = output.split(/\r?\n/).filter((line) => patterns.some((pattern) => pattern.test(line))).slice(0, 40);
	return lines.length > 0 ? lines : output.split(/\r?\n/).filter(Boolean).slice(-20);
}

async function runShell(command: string, cwd: string, timeoutMs: number, signal?: AbortSignal): Promise<{ code: number | null; processSignal: NodeJS.Signals | null; output: string; elapsedMs: number; outcome: ValidationOutcome; error?: string }> {
	const started = Date.now();
	let output = "";
	try {
		const result = await createLocalBashOperations().exec(command, cwd, {
			signal,
			timeout: timeoutMs / 1000,
			onData(chunk) {
				output += chunk.toString("utf8");
				if (output.length > MAX_OUTPUT_CHARS * 4) output = output.slice(-MAX_OUTPUT_CHARS * 2);
			},
		});
		return { code: result.exitCode, processSignal: null, output, elapsedMs: Date.now() - started, outcome: result.exitCode === 0 ? "passed" : "failed" };
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		const outcome: ValidationOutcome = signal?.aborted ? "cancelled" : message.startsWith("timeout:") ? "timed_out" : "execution_error";
		return { code: null, processSignal: null, output, elapsedMs: Date.now() - started, outcome, error: message };
	}
}

export default function projectValidateExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "project_validate",
		label: "Project Validate",
		description: "Run bounded project tests, lints, or typechecks with structured diagnostics. Commands execute with local permissions; callers must select non-mutating validation. This is not a sandbox.",
		promptSnippet: "Run bounded project tests/lints/typechecks with parsed failure output",
		promptGuidelines: [
			"Use project_validate when the task needs test, lint, or typecheck verification and structured failure output is more useful than raw bash output.",
			"Do not use project_validate for install, fix, format-write, deploy, or arbitrary task-runner commands.",
			"Prefer an explicit command in project_validate when repo-specific validation is known; otherwise choose action test, lint, or typecheck.",
		],
		parameters: Type.Object({
			action: Type.Union([Type.Literal("test"), Type.Literal("lint"), Type.Literal("typecheck")], { description: "Validation kind to run." }),
			command: Type.Optional(Type.String({ description: "Explicit read-only command to run instead of detection." })),
			cwd: Type.Optional(Type.String({ description: "Project directory. Defaults to current working directory or nearest project root." })),
			timeoutMs: Type.Optional(Type.Number({ description: "Timeout in milliseconds. Defaults to 120000, max 300000." })),
		}),
		async execute(_id, params: Params, signal, _onUpdate, ctx) {
			const requestedCwd = normalizePath(ctx.cwd, params.cwd);
			const discovery = findProjectRoot(requestedCwd);
			const root = discovery.root;
			const timeoutMs = clampTimeout(params.timeoutMs);
			const receipt = beginVerification(root, "project_validate", params.action);
			const explicit = typeof params.command === "string" && params.command.trim().length > 0;
			const spec = explicit ? { command: params.command!.trim(), reason: "explicit command" } : commandFor(root, params.action);
			if (!spec) {
				const verificationReceipt = finishVerification(receipt, "unsupported", { command: null, exitCode: null, signal: null, truncated: false, exercisedPaths: [], residualGaps: ["No supported automatic command was detected."] });
				return { content: [{ type: "text" as const, text: `No ${params.action} command detected within ${root}. Pass command explicitly.` }], isError: true, details: { outcome: "unsupported", action: params.action, cwd: root, repositoryBounded: discovery.inGit, verificationReceipt } };
			}

			const result = await runShell(spec.command, root, timeoutMs, signal);
			const truncated = truncateMiddle(result.output.trim(), MAX_OUTPUT_CHARS);
			const status = result.outcome;
			const summary = result.outcome === "passed" ? ["No validation failures reported."] : summarizeFailures(result.output || result.error || "Validation process failed without output.");
			const text = [
				`project_validate ${params.action}: ${status}`,
				`Command: ${spec.command}`,
				`Cwd: ${root}`,
				`Exit: ${result.code ?? result.processSignal ?? "unavailable"}`,
				`Elapsed: ${result.elapsedMs}ms`,
				`Reason: ${spec.reason}`,
				"",
				"Summary:",
				...summary.map((line) => `- ${line}`),
				"",
				"Output:",
				truncated.text || "(no output)",
			].join("\n");
			const verificationReceipt = finishVerification(receipt, result.outcome, { command: spec.command, exitCode: result.code, signal: result.processSignal, truncated: truncated.truncated, exercisedPaths: [root], residualGaps: [] });
			return { content: [{ type: "text" as const, text }], isError: result.outcome !== "passed", details: { outcome: result.outcome, action: params.action, command: spec.command, cwd: root, exitCode: result.code, signal: result.processSignal, elapsedMs: result.elapsedMs, truncated: truncated.truncated, terminationCause: result.outcome, verificationReceipt } };
		},
	});
}
