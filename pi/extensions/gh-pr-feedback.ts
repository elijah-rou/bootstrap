import { spawnSync } from "node:child_process";
import { Type } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const DEFAULT_LIMIT = 80;
const MAX_LIMIT = 200;
const MAX_OUTPUT_CHARS = 40_000;

interface Params {
	number?: number;
	repo?: string;
	includeResolved?: boolean;
	includeOutdated?: boolean;
	includeAnnotations?: boolean;
	limit?: number;
}

interface GhResult<T> {
	ok: boolean;
	value?: T;
	error?: string;
}

function runGh<T>(cwd: string, args: string[], input?: string): GhResult<T> {
	const result = spawnSync("gh", args, { cwd, input, encoding: "utf8", timeout: 30_000, maxBuffer: 8_000_000 });
	if (result.error) return { ok: false, error: result.error.message };
	if (result.status !== 0) return { ok: false, error: (result.stderr || result.stdout || `gh exited ${result.status}`).trim() };
	try { return { ok: true, value: JSON.parse(result.stdout || "null") as T }; }
	catch (error) { return { ok: false, error: error instanceof Error ? error.message : String(error) }; }
}

function repoArgs(repo?: string): string[] {
	return repo && repo.trim() ? ["--repo", repo.trim()] : [];
}

function truncate(text: string): string {
	return text.length > MAX_OUTPUT_CHARS ? `${text.slice(0, MAX_OUTPUT_CHARS)}\n[truncated]` : text;
}

function currentBranch(cwd: string): string | null {
	const result = spawnSync("git", ["branch", "--show-current"], { cwd, encoding: "utf8", timeout: 5000 });
	if (result.status !== 0) return null;
	const branch = result.stdout.trim();
	return branch.length > 0 ? branch : null;
}

function detectPr(cwd: string, repo?: string): GhResult<{ number: number }> {
	const branch = currentBranch(cwd);
	if (branch) {
		const result = runGh<Array<{ number: number }>>(cwd, ["pr", "list", ...repoArgs(repo), "--head", branch, "--json", "number"]);
		if (result.ok && Array.isArray(result.value) && result.value.length > 0) return { ok: true, value: { number: result.value[0].number } };
	}
	const view = runGh<{ number: number }>(cwd, ["pr", "view", ...repoArgs(repo), "--json", "number"]);
	if (view.ok && typeof view.value?.number === "number") return { ok: true, value: { number: view.value.number } };
	return { ok: false, error: view.error ?? "No PR found for current branch." };
}

function prView(cwd: string, number: number, repo?: string) {
	return runGh<any>(cwd, ["pr", "view", String(number), ...repoArgs(repo), "--json", "number,title,url,state,isDraft,mergeable,reviewDecision,baseRefName,headRefName,author,labels,comments,reviews,statusCheckRollup,files"]);
}

function prThreads(cwd: string, number: number, repo?: string) {
	const query = `query($owner:String!,$name:String!,$number:Int!){ repository(owner:$owner,name:$name){ pullRequest(number:$number){ reviewThreads(first:100){ nodes{ isResolved isOutdated path line startLine originalLine originalStartLine comments(first:50){ nodes{ author{login} body url createdAt diffHunk } } } } } } }`;
	const repoValue = repo && repo.trim() ? repo.trim() : currentRepo(cwd);
	if (!repoValue) return { ok: false, error: "Could not determine GitHub repo." } as GhResult<any>;
	const [owner, name] = repoValue.split("/");
	return runGh<any>(cwd, ["api", "graphql", "-f", `query=${query}`, "-F", `owner=${owner}`, "-F", `name=${name}`, "-F", `number=${number}`]);
}

function currentRepo(cwd: string): string | null {
	const result = spawnSync("gh", ["repo", "view", "--json", "nameWithOwner"], { cwd, encoding: "utf8", timeout: 10_000 });
	if (result.status !== 0) return null;
	try { return JSON.parse(result.stdout).nameWithOwner ?? null; } catch { return null; }
}

function checkRuns(cwd: string, number: number, repo?: string) {
	const result = runGh<any>(cwd, ["pr", "checks", String(number), ...repoArgs(repo), "--json", "name,state,conclusion,link,startedAt,completedAt,bucket,description"]);
	return result.ok && Array.isArray(result.value) ? result.value : [];
}

function annotations(cwd: string, checks: any[], limit: number): any[] {
	const out: any[] = [];
	for (const check of checks) {
		if (out.length >= limit) break;
		if (!check?.link || !/github\.com/.test(check.link)) continue;
		const match = /runs\/(\d+)/.exec(check.link);
		if (!match) continue;
		const result = runGh<any[]>(cwd, ["api", `repos/:owner/:repo/check-runs/${match[1]}/annotations`, "--paginate"]);
		if (!result.ok || !Array.isArray(result.value)) continue;
		for (const annotation of result.value) {
			out.push({ check: check.name, path: annotation.path, start_line: annotation.start_line, end_line: annotation.end_line, annotation_level: annotation.annotation_level, message: annotation.message, raw_details: annotation.raw_details, url: annotation.blob_href });
			if (out.length >= limit) break;
		}
	}
	return out;
}

function actionState(pr: any, checks: any[], threads: any[]): string {
	if (pr?.isDraft) return "blocked: draft PR";
	if (pr?.mergeable === "CONFLICTING") return "blocked: merge conflicts";
	if (pr?.reviewDecision === "CHANGES_REQUESTED") return "needs local changes: changes requested";
	if (threads.some((thread) => !thread.isResolved && !thread.isOutdated)) return "needs local changes: unresolved review threads";
	if (checks.some((check) => check.conclusion === "FAILURE" || check.conclusion === "TIMED_OUT" || check.conclusion === "CANCELLED")) return "needs local changes: failing checks";
	if (checks.some((check) => check.state === "PENDING" || check.state === "IN_PROGRESS" || check.state === "QUEUED")) return "waiting on CI";
	if (pr?.reviewDecision === "APPROVED") return "ready: approved and no blockers found";
	return "needs review or comment-only follow-up";
}

function format(pr: any, threadsRaw: any, checks: any[], annotationsList: any[], params: Params): string {
	const limit = Math.max(1, Math.min(MAX_LIMIT, Math.trunc(params.limit ?? DEFAULT_LIMIT)));
	const threads = threadsRaw?.repository?.pullRequest?.reviewThreads?.nodes ?? [];
	const filteredThreads = threads.filter((thread: any) => (params.includeResolved || !thread.isResolved) && (params.includeOutdated || !thread.isOutdated)).slice(0, limit);
	const failingChecks = checks.filter((check) => check.conclusion && !["SUCCESS", "SKIPPED", "NEUTRAL"].includes(check.conclusion));
	const pendingChecks = checks.filter((check) => ["PENDING", "IN_PROGRESS", "QUEUED"].includes(check.state));
	const lines: string[] = [];
	lines.push(`# PR #${pr.number}: ${pr.title}`);
	lines.push(pr.url);
	lines.push(`State: ${actionState(pr, checks, threads)}`);
	lines.push(`Branch: ${pr.headRefName} -> ${pr.baseRefName}`);
	lines.push(`Draft: ${Boolean(pr.isDraft)} | Mergeable: ${pr.mergeable ?? "unknown"} | Review decision: ${pr.reviewDecision ?? "none"}`);
	lines.push("");
	lines.push("## Blockers");
	const blockers: string[] = [];
	if (pr.isDraft) blockers.push("Draft PR");
	if (pr.mergeable === "CONFLICTING") blockers.push("Merge conflicts");
	if (pr.reviewDecision === "CHANGES_REQUESTED") blockers.push("Changes requested");
	if (filteredThreads.some((thread: any) => !thread.isResolved && !thread.isOutdated)) blockers.push(`${filteredThreads.filter((thread: any) => !thread.isResolved && !thread.isOutdated).length} unresolved review thread(s)`);
	if (failingChecks.length > 0) blockers.push(`${failingChecks.length} failing/cancelled/timed-out check(s)`);
	if (pendingChecks.length > 0) blockers.push(`${pendingChecks.length} pending check(s)`);
	lines.push(blockers.length ? blockers.map((item) => `- ${item}`).join("\n") : "- None found");
	lines.push("");
	lines.push("## Human review/comments");
	if (filteredThreads.length === 0) lines.push("No matching review threads.");
	for (const thread of filteredThreads) {
		const status = thread.isResolved ? "resolved" : thread.isOutdated ? "outdated" : "unresolved";
		lines.push(`- ${thread.path}:${thread.line ?? thread.originalLine ?? "?"} (${status})`);
		for (const comment of thread.comments?.nodes ?? []) {
			const body = String(comment.body ?? "").trim().replace(/\n{3,}/g, "\n\n");
			lines.push(`  - ${comment.author?.login ?? "unknown"}: ${body}`);
			if (comment.url) lines.push(`    ${comment.url}`);
		}
	}
	lines.push("");
	lines.push("## Top-level comments");
	const comments = Array.isArray(pr.comments) ? pr.comments.slice(0, limit) : [];
	if (comments.length === 0) lines.push("No top-level comments.");
	for (const comment of comments) lines.push(`- ${comment.author?.login ?? "unknown"}: ${String(comment.body ?? "").trim().replace(/\n+/g, " ").slice(0, 1000)}${comment.url ? `\n  ${comment.url}` : ""}`);
	lines.push("");
	lines.push("## CI/checks");
	if (checks.length === 0) lines.push("No checks returned by gh.");
	for (const check of [...failingChecks, ...pendingChecks].slice(0, limit)) lines.push(`- ${check.name}: state=${check.state ?? "?"} conclusion=${check.conclusion ?? "?"}${check.description ? ` — ${check.description}` : ""}${check.link ? `\n  ${check.link}` : ""}`);
	if (params.includeAnnotations !== false) {
		lines.push("");
		lines.push("## Check annotations");
		if (annotationsList.length === 0) lines.push("No check annotations found or accessible.");
		for (const annotation of annotationsList.slice(0, limit)) lines.push(`- ${annotation.path}:${annotation.start_line ?? "?"}-${annotation.end_line ?? annotation.start_line ?? "?"} [${annotation.check}] ${annotation.annotation_level}: ${annotation.message}${annotation.url ? `\n  ${annotation.url}` : ""}`);
	}
	lines.push("");
	lines.push("## Changed files");
	for (const file of (pr.files ?? []).slice(0, 80)) lines.push(`- ${file.path} (+${file.additions ?? 0}/-${file.deletions ?? 0})`);
	return truncate(lines.join("\n"));
}

export default function ghPrFeedbackExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "gh_pr_feedback",
		label: "GitHub PR Feedback",
		description: "Read GitHub PR human review comments, unresolved threads, CI/check state, and check annotations, then summarize what must be actioned locally. Read-only.",
		promptSnippet: "Read current GitHub PR review/CI feedback as local action items",
		promptGuidelines: [
			"Use gh_pr_feedback when the user asks to act on PR reviews, comments, failing checks, or the current PR state.",
			"gh_pr_feedback is read-only; do not use it to reply, resolve threads, approve, request changes, merge, or push.",
		],
		parameters: Type.Object({
			number: Type.Optional(Type.Number({ description: "PR number. Defaults to the PR for the current branch." })),
			repo: Type.Optional(Type.String({ description: "GitHub repo as owner/name. Defaults to current repo." })),
			includeResolved: Type.Optional(Type.Boolean({ description: "Include resolved review threads. Defaults false." })),
			includeOutdated: Type.Optional(Type.Boolean({ description: "Include outdated review threads. Defaults false." })),
			includeAnnotations: Type.Optional(Type.Boolean({ description: "Fetch check annotations. Defaults true." })),
			limit: Type.Optional(Type.Number({ description: "Maximum comments/threads/checks/annotations per section. Defaults 80." })),
		}),
		async execute(_id, params: Params, _signal, _onUpdate, ctx) {
			const number = typeof params.number === "number" && Number.isFinite(params.number) ? Math.trunc(params.number) : undefined;
			const detected = number ? { ok: true, value: { number } } as GhResult<{ number: number }> : detectPr(ctx.cwd, params.repo);
			if (!detected.ok || !detected.value) return { content: [{ type: "text" as const, text: `gh_pr_feedback could not find PR: ${detected.error}` }], isError: true };
			const pr = prView(ctx.cwd, detected.value.number, params.repo);
			if (!pr.ok || !pr.value) return { content: [{ type: "text" as const, text: `gh_pr_feedback failed to read PR: ${pr.error}` }], isError: true };
			const threads = prThreads(ctx.cwd, detected.value.number, params.repo);
			const checks = checkRuns(ctx.cwd, detected.value.number, params.repo);
			const anns = params.includeAnnotations === false ? [] : annotations(ctx.cwd, checks.filter((check: any) => check.conclusion && check.conclusion !== "SUCCESS"), Math.max(1, Math.min(MAX_LIMIT, Math.trunc(params.limit ?? DEFAULT_LIMIT))));
			const text = format(pr.value, threads.ok ? threads.value : {}, checks, anns, params);
			return { content: [{ type: "text" as const, text }], details: { number: detected.value.number, repo: params.repo ?? currentRepo(ctx.cwd), threadReadError: threads.ok ? undefined : threads.error, checkCount: checks.length, annotationCount: anns.length } };
		},
	});
}
