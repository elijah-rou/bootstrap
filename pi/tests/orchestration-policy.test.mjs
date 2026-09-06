import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

const piRoot = new URL("../", import.meta.url);

async function readPiFile(relativePath) {
	const contents = await readFile(new URL(relativePath, piRoot), "utf8");
	assert.ok(contents.length > 0, `${relativePath} must not be empty`);
	return contents;
}

function parseAgentFrontmatter(agentSource, agentName) {
	const frontmatterMatch = agentSource.match(/^---\n([\s\S]*?)\n---(?:\n|$)/);
	assert.ok(frontmatterMatch, `${agentName} agent must have YAML frontmatter`);
	return frontmatterMatch[1];
}

function parseAgentTools(agentSource, agentName = "orchestrate") {
	const frontmatter = parseAgentFrontmatter(agentSource, agentName);
	const toolsMatch = frontmatter.match(/^tools:\s*(.+)$/m);
	assert.ok(toolsMatch, `${agentName} agent frontmatter must declare tools`);
	return toolsMatch[1].split(",").map((tool) => tool.trim());
}

test("active Pi extensions use portable immutable sources", async () => {
	const settings = JSON.parse(await readPiFile("settings.json"));
	assert.ok(Array.isArray(settings.packages), "Pi settings packages must be an array");
	const subagentPackages = settings.packages.filter((entry) => {
		const source = typeof entry === "string" ? entry : entry?.source;
		return typeof source === "string" && source.includes("pi-subagents");
	});
	assert.deepEqual(subagentPackages, [
		"git:github.com/elijah-rou/pi-subagents@e45ccac7518bb5648263f65ba239b9fc5bf6e5ab",
	]);
	for (const entry of settings.packages) {
		const source = typeof entry === "string" ? entry : entry?.source;
		if (typeof source !== "string") continue;
		assert.doesNotMatch(source, /(?:localhost\/|\/home\/|\/Users\/)/, `package source must be portable: ${source}`);
	}
	assert.ok(!settings.packages.includes("npm:pi-subagents"), "npm pi-subagents source must not remain configured");
	const profilePackages = settings.packages.filter((entry) => {
		const source = typeof entry === "string" ? entry : entry?.source;
		return typeof source === "string" && source.includes("pi-profile-router");
	});
	assert.deepEqual(profilePackages, [], "parent profile router must not be active");
	const strategyPackages = settings.packages.filter((entry) => {
		const source = typeof entry === "string" ? entry : entry?.source;
		return typeof source === "string" && source.includes("pi-strategy-router");
	});
	assert.deepEqual(strategyPackages, [], "parent strategy router must not be active");
	assert.ok(
		!settings.packages.some((entry) => (typeof entry === "string" ? entry : entry?.source)?.includes("pi-agent-router")),
		"identity-aware agent router must remain disabled",
	);

});

test("explicit local agent allowlists defer structured output availability to outputSchema", async () => {
	const agentFiles = (await readdir(new URL("agents/", piRoot)))
		.filter((fileName) => fileName.endsWith(".md"))
		.sort();
	assert.ok(agentFiles.length > 0, "at least one local agent definition must exist");

	for (const agentFile of agentFiles) {
		const agentName = agentFile.slice(0, -3);
		const tools = parseAgentTools(await readPiFile(`agents/${agentFile}`), agentName);
		assert.ok(
			!tools.includes("structured_output"),
			`${agentName} agent must not statically expose structured_output; outputSchema conditionally enables the internal tool`,
		);
	}
});

test("remaining local specialists disable the completion guard", async () => {
	const agentFiles = (await readdir(new URL("agents/", piRoot)))
		.filter((fileName) => fileName.endsWith(".md"))
		.sort();
	for (const agentFile of agentFiles) {
		const agentName = agentFile.slice(0, -3);
		const frontmatter = parseAgentFrontmatter(await readPiFile(`agents/${agentFile}`), agentName);
		assert.match(frontmatter, /^completionGuard:\s*false\s*$/m, `${agentName} agent must explicitly disable completionGuard`);
	}
});

test("scout returns inline without writing a default context artifact", async () => {
	const frontmatter = parseAgentFrontmatter(await readPiFile("agents/scout.md"), "scout");
	assert.match(frontmatter, /^output:\s*false\s*$/m);
});

test("active settings preserve the parent and route only child compute", async () => {
	const settings = JSON.parse(await readPiFile("settings.json"));
	assert.equal(settings.defaultProvider, "openai-codex");
	assert.equal(settings.defaultModel, "gpt-6-astra");
	assert.equal(settings.defaultThinkingLevel, "high");
	assert.deepEqual(settings.compaction, {
		enabled: true,
		reserveTokens: 32768,
		keepRecentTokens: 20000,
	});
	assert.deepEqual(settings.subagents.agentOverrides.worker, {
		model: "openai-codex/gpt-5.6-sol",
		fallbackModels: ["opencode/grok-4.6:high"],
		thinking: "medium",
		defaultContext: "fresh",
		inheritProjectContext: true,
		inheritGlobalContext: true,
	});
	assert.equal(settings.subagents.childRouting, undefined);
	assert.deepEqual(settings.subagents.agentOverrides.scout, {
		model: "openai-codex/gpt-5.6-luna",
		fallbackModels: ["opencode/deepseek-v4-flash:high"],
		thinking: "low",
	});
	assert.equal(settings.subagents.agentOverrides.researcher.thinking, "medium");
	assert.equal(settings.subagents.agentOverrides.delegate.thinking, "high");
	assert.equal(settings.subagents.agentOverrides.oracle.disabled, true);
	assert.deepEqual({
		maxActiveAsyncRunsPerSession: settings.subagents.maxActiveAsyncRunsPerSession,
		perRunConcurrencyLimit: settings.subagents.perRunConcurrencyLimit,
		maxSubagentSpawnsPerRun: settings.subagents.maxSubagentSpawnsPerRun,
		maxSubagentSpawnsPerSession: settings.subagents.maxSubagentSpawnsPerSession,
		maxSubagentDepth: settings.subagents.maxSubagentDepth,
	}, { maxActiveAsyncRunsPerSession: 4, perRunConcurrencyLimit: 6, maxSubagentSpawnsPerRun: 16, maxSubagentSpawnsPerSession: 32, maxSubagentDepth: 2 });
	assert.equal("globalConcurrencyLimit" in settings.subagents, false);
});

test("singleton guidance stays direct and reserves workflowScript for workflows", async () => {
	const streams = await readPiFile("WORKTREE_STREAMS.md");
	for (const [name, guidance] of [["WORKTREE_STREAMS.md", streams]]) {
		assert.match(guidance, /(direct[^\n]*singleton|singleton[^\n]*direct)/i, `${name} must prescribe direct singleton execution`);
		assert.match(guidance, /\{[^\n]*agent[^\n]*task[^\n]*delegationReason/i, `${name} must show the direct execution shape`);
		assert.match(guidance, /(workflowScript[^\n]*(only|reserve)|(only|reserve)[^\n]*workflowScript)/i, `${name} must reserve workflowScript for workflow control`);
		assert.doesNotMatch(guidance, /workflowScript[^\n]*(every launch|one-child)/i, `${name} must not prescribe singleton workflows`);
	}
});

test("/tasks advertises direct-first bounded orchestration", async () => {
	const { default: registerWorkflows } = await import("../extensions/workflows.ts");
	let tasksCommand;
	registerWorkflows({
		registerCommand(name, command) {
			if (name === "tasks") tasksCommand = command;
		},
	});
	assert.ok(tasksCommand, "/tasks command must be registered");
	assert.equal(typeof tasksCommand.handler, "function", "/tasks command must have a handler");

	let tasksGuidance;
	await tasksCommand.handler("", {
		ui: {
			pasteToEditor(text) {
				tasksGuidance = text;
			},
		},
	});
	assert.equal(typeof tasksGuidance, "string", "/tasks must paste guidance into the editor");
	assert.match(tasksGuidance, /direct default[^\n]*delegationReason[^\n]*one justified child/i);
	assert.match(tasksGuidance, /workflowScript only for workflow-only control/i);
	assert.match(tasksGuidance, /outputSchema[^\n]*structuredOutput/i);
	assert.match(tasksGuidance, /parent chooses strategy[^\n]*topology/i);
	assert.match(tasksGuidance, /one writer[^\n]*isolated worktrees/i);
	assert.match(tasksGuidance, /wait only at a real dependency barrier/i);
	assert.match(tasksGuidance, /status is diagnostic[^\n]*never routine polling/i);
	assert.match(tasksGuidance, /dependent work branches after observing output/i);
	assert.match(tasksGuidance, /omit transcripts[^\n]*broad context bundles/i);
	assert.match(tasksGuidance, /attested\/checked\/verified[^\n]*review is separate/i);
	assert.match(tasksGuidance, /review:\s*\{\s*required:\s*false\s*\}/i);
	assert.match(tasksGuidance, /async workflows have no default timeout/i);

	for (const relativePath of ["AGENTS.md", "WORKTREE_STREAMS.md"]) {
		const guidance = await readPiFile(relativePath);
		assert.doesNotMatch(guidance, /(?<!subagent_)\bwait\s*\(/, `${relativePath} must use the registered subagent_wait tool name`);
		assert.doesNotMatch(guidance, /`reviewed`|\breviewed acceptance/, `${relativePath} must not present reviewed as an acceptance level`);
		assert.match(guidance, /\battested\b[^\n]*\bchecked\b[^\n]*\bverified\b/, `${relativePath} must list current evidence levels`);
		assert.match(guidance, /review:\s*\{\s*required:\s*false\s*\}/, `${relativePath} must describe the separate optional review gate`);
		if (relativePath === "AGENTS.md") {
			assert.match(guidance, /Choose child models and thinking levels through explicit role profiles or per-run overrides\.[^\n]*never change the parent profile, agent role, topology, tools, permissions, context, worktree, or acceptance policy\./);
			assert.match(guidance, /no child reviewer[^\n]*one fresh reviewer[^\n]*two fresh reviewers/i);
			for (const reason of ["user_async", "independent_parallel_lane", "manager_continuity", "unresolved_ownership", "semantic_review", "elevated_risk_review"]) assert.match(guidance, new RegExp(`\\b${reason}\\b`));
			assert.match(guidance, /Bounded multi-file scope[^\n]*never independently justify/i);
			assert.match(guidance, /focused re-review[^\n]*unresolved semantic findings[^\n]*fix blast radius/i);
			assert.match(guidance, /Do not repeat broad review waves[^\n]*machine-decided corrections/i);
		}
	}
});
