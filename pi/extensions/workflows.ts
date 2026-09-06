import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const TASKS = `# Local tasks
/changes - git status/diff summary
/usage - local Pi usage summary
/diagnose <problem> - repro-first debugging
/handoff [focus] - write a compact handoff file

Upstream orchestration:
- direct default: use { agent, task, delegationReason } for one justified child; use workflowScript only for workflow-only control or multiple dependent children
- provenance: every new execution supplies one approved delegationReason and any reason-specific delegationBasis
- scripted shape: { delegationReason: "elevated_risk_review", async: true, workflowScript: \`const reviews = await runs.all([{ key: "correctness", agent: "reviewer", task: "Review the supplied diff for correctness" }, { key: "security", agent: "second-opinion", task: "Review the supplied security boundary" }]); return reviews.map(result => result.output);\` }
- ownership: parent chooses strategy, roles, topology, context, worktrees, acceptance, tools, and permissions; explicit role profiles or per-run overrides select only model/thinking
- dependencies: writers sharing files or mutable state must be sequential; use one writer unless isolated worktrees have disjoint ownership
- promises: observe every launched child with await, Promise.all, or Promise.race; bound dynamic lists before runs.all
- structured dependencies: put outputSchema on the producer and consume result.structuredOutput
- steering/resume: await runs.steer(stableKey, message, options); resume retained children with runs.run(newKey, { resume: runId, task })
- async: use completion and attention notifications; wait only at a real dependency barrier; status is diagnostic or an explicit fleet view, never routine polling
- queues: pre-sent steering or follow-up input must be independent of or invariant under the pending result; dependent work branches after observing output
- lifetime: blocking workflows default to a bounded runtime; async workflows have no default timeout
- acceptance: evidence levels are attested/checked/verified; review is separate, for example acceptance: { level: "checked", review: { required: false } }
- fleet/cost: /subagents-fleet, /subagent-cost, or status view fleet
- handoff: include objective, accepted decisions, authority, exact existing typed paths, current state, and acceptance evidence; omit transcripts and broad context bundles
- worktree: set worktree:true per child or workflow, isolate parallel writers, and retain managed worktrees until changes are reachable

Tools: subagent, subagent_wait, worktree, project_validate, semantic_search, lsp_definition, lsp_references, lsp_symbols, gh_pr_feedback, web_search, source_check, fetch_content, get_search_content, pdf_info, pdf_extract
Safety: git-interceptor, pi-cloak`;

export default function workflowsExtension(pi: ExtensionAPI) {
	pi.registerCommand("tasks", {
		description: "List local workflow commands and tools",
		async handler(_args, ctx) {
			ctx.ui.pasteToEditor(TASKS);
		},
	});
}
