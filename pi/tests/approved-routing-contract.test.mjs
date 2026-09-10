import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

function parseFrontmatter(source) {
	const match = source.match(/^---\n([\s\S]*?)\n---(?:\n|$)/);
	assert.ok(match, "agent must have frontmatter");
	return Object.fromEntries(match[1].split("\n").map((line) => {
		const separator = line.indexOf(":");
		return [line.slice(0, separator).trim(), line.slice(separator + 1).trim()];
	}));
}

test("explicit roles preserve parent and approved compute choices", () => {
 const settings = JSON.parse(readFileSync(new URL("../settings.json", import.meta.url), "utf8"));
 assert.equal(settings.defaultModel, "gpt-6-astra");
 assert.equal(settings.defaultThinkingLevel, "low");
 assert.equal(settings.subagents.childRouting, undefined, "no classifier is configured");
 for (const [name, model, thinking, fallback] of [
  ["deep", "openai-codex/gpt-6-astra", "xhigh", "opencode/claude-opus-4-8:xhigh"],
  ["second-opinion", "opencode/grok-4.6", "high", "opencode/claude-opus-4-8:high"],
 ]) {
  const agent = parseFrontmatter(readFileSync(new URL(`../agents/${name}.md`, import.meta.url), "utf8"));
  assert.equal(agent.model, model);
  assert.equal(agent.thinking, thinking);
  assert.equal(agent.fallbackModels, fallback);
  assert.equal(agent.inheritSkills, "false");
 }
});

const pinnedSubagentsSource = "git:github.com/elijah-rou/pi-subagents@e45ccac7518bb5648263f65ba239b9fc5bf6e5ab";

test("subagents are active with static fail-open role defaults", () => {
	const settings = JSON.parse(readFileSync(new URL("../settings.json", import.meta.url), "utf8"));
	assert.ok(settings.packages.includes(pinnedSubagentsSource));
	for (const entry of settings.packages) {
		const source = typeof entry === "string" ? entry : entry?.source;
		if (typeof source !== "string") continue;
		assert.doesNotMatch(source, /(?:localhost\/|\/home\/|\/Users\/)/, `package source must be portable: ${source}`);
	}
	assert.deepEqual(settings.subagents.agentOverrides.scout, {
		model: "openai-codex/gpt-5.6-luna",
		fallbackModels: ["opencode/deepseek-v4-flash:high"],
		thinking: "low",
	});
	assert.deepEqual(settings.subagents.agentOverrides.delegate, {
		model: "openai-codex/gpt-5.6-luna",
		fallbackModels: ["opencode/deepseek-v4-flash:high"],
		thinking: "high",
	});
	assert.deepEqual(settings.subagents.agentOverrides.worker, {
		model: "openai-codex/gpt-5.6-sol",
		fallbackModels: ["opencode/grok-4.6:high"],
		thinking: "medium",
		defaultContext: "fresh",
		inheritProjectContext: true,
		inheritGlobalContext: true,
	});
	assert.deepEqual(settings.subagents.agentOverrides.researcher, {
		model: "openai-codex/gpt-5.6-luna",
		fallbackModels: ["opencode/deepseek-v4-flash:high"],
		thinking: "medium",
	});
	assert.deepEqual(settings.subagents.agentOverrides.reviewer, {
		model: "openai-codex/gpt-6-astra",
		fallbackModels: ["opencode/grok-4.6:high"],
		thinking: "high",
	});
	assert.equal(settings.subagents.agentOverrides.oracle.disabled, true);
	assert.equal(settings.subagents.agentOverrides["oracle-eval"].disabled, true);
	assert.equal(settings.subagents.agentOverrides["oracle-investigate"].disabled, true);
	assert.equal(settings.subagents.agentOverrides["oracle-review"].disabled, true);
	assert.ok(!settings.packages.some((entry) => (typeof entry === "string" ? entry : entry?.source)?.includes("pi-profile-router")));
	assert.ok(!settings.packages.some((entry) => (typeof entry === "string" ? entry : entry?.source)?.includes("pi-strategy-router")));
	assert.ok(!settings.packages.some((entry) => (typeof entry === "string" ? entry : entry?.source)?.includes("pi-agent-router")));
});

test("researcher override uses the SearXNG-backed web tools and bounded duration contract", () => {
	const settings = JSON.parse(readFileSync(new URL("../settings.json", import.meta.url), "utf8"));
	assert.ok(settings.packages.includes("npm:pi-web-access@0.24.2"), "the immutable pi-web-access package must provide the researcher web tools");
	const webSearch = JSON.parse(readFileSync(new URL("../web-search.json", import.meta.url), "utf8"));
	assert.equal(webSearch.provider, "searxng");
	assert.deepEqual(webSearch.searchRouting.providers, ["searxng"]);
	assert.equal(webSearch.fetchRouting.allowRemoteHostedProviders, false);

	const researcher = parseFrontmatter(readFileSync(new URL("../agents/researcher.md", import.meta.url), "utf8"));
	assert.deepEqual(researcher.tools.split(",").map((tool) => tool.trim()), ["web_search", "source_check", "fetch_content", "get_search_content"]);
	assert.equal(researcher.checkpointAfterMs, "480000");
	assert.equal(researcher.timeoutMs, "900000");
	assert.equal(researcher.maxTimeoutMs, "900000");
	assert.equal(researcher.defaultContext, "fork");
	assert.equal(researcher.fallbackModels, "opencode/deepseek-v4-flash:high");
	assert.equal(researcher.thinking, "medium");

	const scout = parseFrontmatter(readFileSync(new URL("../agents/scout.md", import.meta.url), "utf8"));
	assert.equal(scout.model, "openai-codex/gpt-5.6-luna");
	assert.equal(scout.fallbackModels, "opencode/deepseek-v4-flash:high");
	assert.equal(scout.thinking, "low");
	assert.deepEqual(scout.tools.split(",").map((tool) => tool.trim()), ["read", "grep", "find", "ls", "bash", "write", "pdf_info", "pdf_extract"]);
});

test("second-opinion agents use Opus 4.8 fallback and built-in compaction", () => {
	const settings = JSON.parse(readFileSync(new URL("../settings.json", import.meta.url), "utf8"));
	assert.deepEqual(settings.compaction, {
		enabled: true,
		reserveTokens: 32768,
		keepRecentTokens: 20000,
	});
	assert.equal(existsSync(new URL("../extensions/custom-compaction.ts", import.meta.url)), false);
	assert.equal(existsSync(new URL("../presets.json", import.meta.url)), false);

	for (const agentName of ["oracle-eval", "oracle-investigate", "oracle-review"]) {
		const oracle = parseFrontmatter(readFileSync(new URL(`../agents/${agentName}.md`, import.meta.url), "utf8"));
		assert.equal(oracle.model, "opencode/grok-4.6");
		assert.equal(oracle.fallbackModels, "opencode/claude-opus-4-8:high");
		assert.equal(oracle.thinking, "high");
	}
});

async function assertRuntimeContract(runtimeRoot) {
	const publicExecutionModule = await import(pathToFileURL(join(runtimeRoot, "src/extension/public-execution.ts")).href);
	const agentsModule = await import(pathToFileURL(join(runtimeRoot, "src/agents/agents.ts")).href);
	const childProfileRoutingModule = await import(pathToFileURL(join(runtimeRoot, "src/runs/shared/child-profile-routing.ts")).href);
	const scriptedWorkflowModule = await import(pathToFileURL(join(runtimeRoot, "src/workflows/scripted-workflow.ts")).href);

	const direct = publicExecutionModule.normalizePublicSubagentExecution({ agent: "worker", task: "Implement the checked change", delegationReason: "user_async" });
	assert.equal(direct.ok, true);
	const workflow = publicExecutionModule.normalizePublicSubagentExecution({
		workflowScript: 'return runs.run("main", { agent: "worker", task: "Implement the checked change" });',
		delegationReason: "semantic_review",
	});
	assert.equal(workflow.ok, true);
	const omittedReason = publicExecutionModule.normalizePublicSubagentExecution({ agent: "worker", task: "Implement" });
	assert.equal(omittedReason.ok, false);
	assert.match(omittedReason.error, /delegationReason is required/);
	const unknownReason = publicExecutionModule.normalizePublicSubagentExecution({ agent: "worker", task: "Implement", delegationReason: "convenience" });
	assert.equal(unknownReason.ok, false);
	assert.match(unknownReason.error, /delegationReason .*must be one of/);
	const independentLane = publicExecutionModule.normalizePublicSubagentExecution({
		agent: "worker",
		task: "Implement isolated files",
		delegationReason: "independent_parallel_lane",
		delegationBasis: { ownership: ["pi/settings.json"], deliverable: "Pinned settings" },
	});
	assert.equal(independentLane.ok, true);
	const missingBasis = publicExecutionModule.normalizePublicSubagentExecution({ agent: "worker", task: "Inspect", delegationReason: "unresolved_ownership" });
	assert.equal(missingBasis.ok, false);
	assert.match(missingBasis.error, /delegationBasis/);
	const legacyChain = publicExecutionModule.normalizePublicSubagentExecution({ chain: [{ agent: "worker", task: "old" }] });
	assert.equal(legacyChain.ok, false);
	assert.match(legacyChain.error, /use workflowScript/);

	const settings = JSON.parse(readFileSync(new URL("../settings.json", import.meta.url), "utf8"));

 const sandbox = mkdtempSync(join(tmpdir(), "explicit-role-contract-"));
 try {
  mkdirSync(join(sandbox, ".pi/agents"), { recursive: true });
  writeFileSync(join(sandbox, ".pi/settings.json"), JSON.stringify({ subagents: settings.subagents }));
  for (const name of ["scout", "researcher", "deep", "second-opinion"]) {
   writeFileSync(join(sandbox, ".pi/agents", name + ".md"), readFileSync(new URL(`../agents/${name}.md`, import.meta.url)));
  }
  const discovered = agentsModule.discoverAgents(sandbox, "project");
  const roles = new Map(discovered.agents.map(agent => [agent.name, agent]));
  for (const [name, model, thinking] of [
   ["worker", "openai-codex/gpt-5.6-sol", "medium"],
   ["reviewer", "openai-codex/gpt-6-astra", "high"],
   ["deep", "openai-codex/gpt-6-astra", "xhigh"],
   ["second-opinion", "opencode/grok-4.6", "high"],
  ]) {
   assert.equal(roles.get(name)?.model, model, name);
   assert.equal(roles.get(name)?.thinking, thinking, name);
  }
  assert.equal(roles.get("scout")?.fast, false);
  assert.deepEqual(roles.get("deep")?.fallbackModels, ["opencode/claude-opus-4-8:xhigh"]);
  assert.deepEqual(roles.get("second-opinion")?.fallbackModels, ["opencode/claude-opus-4-8:high"]);
  const explicit = { agent: "worker", task: "Implement", model: "openai-codex/gpt-6-astra:xhigh" };
  const resolved = await childProfileRoutingModule.applySubagentChildProfiles(explicit, { sessionId: "explicit-only", cwd: sandbox });
  assert.equal(resolved.model, explicit.model);
 } finally { rmSync(sandbox, { recursive: true, force: true }); }

	assert.deepEqual(
		scriptedWorkflowModule.previewSimpleWorkflowRun('return runs.run("main", { agent: "scout", task: "Inspect routing" });'),
		{ agent: "scout", task: "Inspect routing" },
	);
	assert.equal(scriptedWorkflowModule.previewSimpleWorkflowRun('return runs.all([]);'), undefined);
	assert.throws(() => scriptedWorkflowModule.assertWorkflowJsonValue(new Date()), /plain JSON objects/);

}

const runtimeSource = process.env.PI_SUBAGENTS_TEST_RUNTIME_SOURCE;
test("configured source resolves explicit roles and public workflow requests", { skip: runtimeSource ? undefined : "set PI_SUBAGENTS_TEST_RUNTIME_SOURCE for runtime contract checks" }, async () => {
	await assertRuntimeContract(runtimeSource);
});

test("managed gitconfig activates the stable global excludes path in unrelated repositories", () => {
	const gitconfigPath = new URL("../../gitconfig", import.meta.url).pathname;
	const gitconfig = readFileSync(gitconfigPath, "utf8");
	assert.match(gitconfig, /excludesFile\s*=\s*~\/\.config\/git\/ignore/);
	const excludes = readFileSync(new URL("../../gitignore_global", import.meta.url), "utf8");
	assert.match(excludes, /^\.pi-subagents\/$/m);

	const sandbox = mkdtempSync(join(tmpdir(), "dotfiles-git-excludes-"));
	const home = join(sandbox, "home");
	const unrelatedRepository = join(sandbox, "unrelated");
	try {
		mkdirSync(join(home, ".config/git"), { recursive: true });
		mkdirSync(unrelatedRepository);
		writeFileSync(join(home, ".config/git/ignore"), excludes);
		execFileSync("git", ["init", "-q"], { cwd: unrelatedRepository });
		mkdirSync(join(unrelatedRepository, ".pi-subagents"));
		writeFileSync(join(unrelatedRepository, ".pi-subagents", "state"), "ignored\n");
		const env = { ...process.env, HOME: home, GIT_CONFIG_GLOBAL: gitconfigPath, GIT_CONFIG_NOSYSTEM: "1" };
		assert.equal(execFileSync("git", ["config", "--path", "--get", "core.excludesFile"], { cwd: unrelatedRepository, env, encoding: "utf8" }).trim(), join(home, ".config/git/ignore"));
		assert.equal(execFileSync("git", ["status", "--short"], { cwd: unrelatedRepository, env, encoding: "utf8" }), "");
		execFileSync("git", ["add", "-f", ".pi-subagents/state"], { cwd: unrelatedRepository, env });
		assert.match(execFileSync("git", ["status", "--short"], { cwd: unrelatedRepository, env, encoding: "utf8" }), /^A  \.pi-subagents\/state$/m);
	} finally {
		rmSync(sandbox, { recursive: true, force: true });
	}
});
