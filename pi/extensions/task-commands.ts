import { mkdtemp, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

function sendOrQueue(pi: ExtensionAPI, ctx: ExtensionContext, prompt: string): void {
	if (ctx.isIdle()) {
		pi.sendUserMessage(prompt);
		return;
	}
	pi.sendUserMessage(prompt, { deliverAs: "followUp" });
	ctx.ui.notify("Queued after current turn", "info");
}

function diagnosePrompt(problem: string): string {
	return `Diagnose this problem. Do not guess. Build evidence first.\n\nProblem:\n${problem}\n\nWorkflow:\n1. Reproduce or find the closest deterministic signal.\n2. Capture exact error/output and commands run.\n3. List 3-5 falsifiable hypotheses ranked by likelihood.\n4. Test one hypothesis at a time with the smallest probe.\n5. Identify root cause before proposing fixes.\n6. If a fix is requested or clearly safe, implement with regression verification.\n\nReport: evidence, root cause, commands with exit codes, files touched, verification, remaining uncertainty.`;
}

async function handoffPrompt(focus: string): Promise<string> {
	const dir = await mkdtemp(join(tmpdir(), "pi-handoff-"));
	const path = join(dir, "handoff.md");
	await writeFile(path, "", "utf8");
	return `Write a concise handoff document for a fresh agent.\n\nFocus: ${focus || "current session"}\nOutput path: ${path}\n\nRead the empty file first, then write the handoff there. Include only useful resume context: goal, current state, decisions, changed files, commands/verification, blockers, next steps. Do not duplicate artifacts already present; reference paths instead. After writing, reply with the path and a 3-line summary.`;
}

export default function taskCommands(pi: ExtensionAPI) {
	pi.registerCommand("diagnose", {
		description: "Run a repro-first debugging workflow for a problem",
		handler: async (args, ctx) => {
			const problem = args?.trim() ?? "";
			if (!problem) {
				ctx.ui.notify("Usage: /diagnose <problem>", "warning");
				return;
			}
			sendOrQueue(pi, ctx, diagnosePrompt(problem));
		},
	});

	pi.registerCommand("handoff", {
		description: "Write a compact handoff document for another agent",
		handler: async (args, ctx) => {
			sendOrQueue(pi, ctx, await handoffPrompt(args?.trim() ?? ""));
		},
	});
}
