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
		"git:github.com/elijah-rou/pi-subagents@38ddf4c694c3cc3d2b453bd44ca3071b104873ee",
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
	assert.equal(settings.defaultModel, "gpt-6.1-sol");
	assert.equal(settings.defaultThinkingLevel, "high");
	assert.deepEqual(settings.compaction, {
		enabled: true,
		reserveTokens: 32768,
		keepRecentTokens: 20000,
	});
	assert.deepEqual(settings.subagents.agentOverrides.worker, {
		model: "openai-codex/gpt-6.1-sol",
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
