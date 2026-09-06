---
name: writing-for-agents
description: Design or revise model-facing instructions. Use when editing AGENTS.md, SKILL.md, Codex or Pi instructions, agent/subagent prompts, workflow prompts, or handoff templates. Do not use for ordinary user-facing documentation.
---

# Writing for agents

Write instructions that load at the right time, lead to observable behavior, and have one source of truth. This skill is self-contained; read only its named local reference and do not invoke another skill. Completion criteria are checks for the author, not required report sections. Stop once the affected load path, instructions, and references are verified.

## 1. Identify the consumer and load path

Before editing, establish for the document or changed section:

- which agent or harness consumes it;
- whether it is always loaded, conditionally discovered, or explicitly invoked;
- which tasks need it and which must not trigger it;
- whether deterministic tooling can enforce the behavior instead.

Completion criterion: the document has a clear consumer and load path, and conditional branches have explicit triggers.

## 2. Put guidance at the narrowest effective layer

Use this order:

1. Formatter, linter, type system, tests, hooks, or runtime checks for deterministic rules.
2. `AGENTS.md` or equivalent for short invariants relevant to nearly every task in that scope.
3. A model-invoked skill for conditional behavior the agent must discover itself.
4. A manual-only skill for explicit, uncommon, expensive, or high-side-effect workflows.
5. A referenced file for branch-specific detail, long examples, templates, or API material.

Keep the authoritative rule in one place and point to it where inheritance is reliable. Concisely repeat a safety or capability boundary when a consumer cannot reliably inherit the authoritative layer; keep its rationale and detailed procedure in the source of truth.

Promote recurrence to the smallest reviewed durable mechanism: static text becomes a prompt, repeated reasoning a skill, deterministic action a script or tool, and a dependency graph a workflow. Do not silently create skills, memory, or schedules.

Completion criterion: behavior rules have authoritative locations, required safety boundaries reach every consumer, and nothing loads more broadly than needed.

## 3. Write precise pointers

A skill description or instruction that points to another document must name:

- what the target contains;
- the distinct conditions that require reading it;
- important exclusions that prevent false activation.

Prefer concrete task language over broad phrases such as “best practices,” “when relevant,” or “help with code.” Keep descriptions short because model-invoked skill descriptions are always present in context.

Completion criterion: a reader can predict both when the pointer fires and when it stays inactive.

## 4. Structure executable guidance

Put the normal path first. Use ordered steps when order matters. End each step with a checkable completion criterion based on an artifact, command result, decision, or observable state.

Move detail behind a reference only when some branches do not need it. Keep safety constraints and branch-selection rules visible before the branch is taken.

State positive target behavior. Retain explicit prohibitions for security, destructive operations, publication authority, and other boundaries where ambiguity is unsafe.

Completion criterion: the agent can determine its next action and when the workflow is finished without inventing missing policy.

## 5. Prune instruction debt

Before simplifying existing instructions, inventory their required outputs, meaningful user decisions, domain procedures, evidence, and safety boundaries. Preserve those behaviors or identify an active authoritative replacement. Shorter text is not an improvement if it drops part of the intended task. Keep the normal path of one explicitly invoked workflow in its entrypoint; use a router for genuinely distinct branches.

Remove or relocate:

- facts cheaply discoverable from source, configuration, or `--help`;
- commands copied from package metadata without added context;
- duplicate or contradictory rules;
- examples likely to become stale;
- vague encouragement that does not change behavior;
- implementation details irrelevant to the document's consumer.

Keep reasons that cannot be recovered from the environment, especially safety decisions and surprising constraints.

Completion criterion: each remaining instruction changes behavior or preserves non-discoverable context.

## 6. Apply the target runtime's mechanics

For Pi skills, read `references/pi-skill-mechanics.md` before changing frontmatter, paths, invocation behavior, or references. For Codex instructions or skills, read `references/codex-mechanics.md`. Read both only when the same artifact must work in both runtimes; do not transfer tool names or metadata semantics without checking the consumer.

## 7. Validate

- Parse required frontmatter and verify the skill name matches its directory.
- Verify every referenced local file exists and resolves relative to the skill directory.
- Check descriptions for trigger overlap with installed skills.
- Run checks for the affected artifact and load path, plus repository-required checks. Run the full suite only when required or when affected behavior justifies it.
- Inspect the final diff for duplicated policy, secrets, machine-local paths, and stale harness terminology.

Completion criterion: syntax and references pass, activation boundaries are distinct, and the diff contains no duplicated or leaked configuration.
