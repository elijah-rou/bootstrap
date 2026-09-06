---
name: technical-writing
description: Structure and revise durable technical documentation for working engineers. Use when the primary deliverable is a README, guide, tutorial, how-to, reference page, RFC, architecture or design document, or similar maintained artifact. Do not use for conversational codebase walkthroughs, model-facing instructions, code comments, short public copy, or raw investigation notes.
---

# Technical writing

Write technical documents that let a tired engineer find, understand, and apply correct information on the first read. This skill is self-contained and does not invoke another skill.

## 1. Establish the document contract

Identify:

- the reader and what they already know;
- the task or question the document must resolve;
- the authoritative code, configuration, command output, specification, or decision record;
- the document's dominant mode.

Use four modes:

- **Tutorial:** a learner completes a guided exercise and sees progress.
- **How-to:** a competent reader completes a specific task.
- **Reference:** a reader looks up exact facts, options, limits, and errors.
- **Explanation:** a reader understands a bounded concept, rationale, or trade-off.

A document may link to another mode. Split it only when mixed purposes make the normal reading path harder to follow.

Completion criterion: the reader, goal, source of truth, and dominant mode are explicit.

## 2. Organize for the reader's path

Put the common path first. Move prerequisites before the step they guard. Keep exceptions beside the relevant rule and link to secondary detail rather than interrupting the main path.

Use headings that state the point or task. Use numbered lists for sequences and bullets for unordered sets. Keep examples next to the claim they demonstrate.

For each mode:

- A tutorial starts with what the reader will build, produces an observable result early, and names expected output.
- A how-to starts with the goal and prerequisites, then gives only the decisions and steps needed to reach it.
- Reference mirrors the structure of the interface or system it documents and aims for complete, neutral lookup coverage.
- Explanation anchors on a real “why” question and covers constraints, alternatives, and consequences without turning into a procedure.

Completion criterion: a reader can follow the common path without searching across unrelated sections.

## 3. Use the system's real vocabulary

Name exact symbols, paths, flags, commands, UI labels, services, and domain terms. Do not replace a real name with a loose synonym. Derive inventories and counts from code or tooling when practical, and include the regeneration command when the value can drift.

Separate facts from recommendations. Cite the source for behavior that is not directly demonstrated by the document's commands or code references.

Completion criterion: every technical name resolves to the current implementation or an identified external source.

## 4. Write unambiguous instructions and explanations

- Name the actor: “the loader parses the file,” not “the file is parsed.”
- Put the condition before the action: “To remove the cache, stop the service first.”
- Give one instruction per numbered step.
- Keep “only,” “not,” and other modifiers beside the words they change.
- Replace ambiguous pronouns with the noun when two antecedents are possible.
- Use one term for one concept throughout the document.
- Prefer plain words and concrete mechanisms over abstract metaphor.
- Split sentences that require the reader to backtrack, but retain longer sentences that carry one coherent idea.

Completion criterion: each instruction has one interpretation and each explanation preserves its necessary condition or consequence.

## 5. Verify the document

Run safe, authorized commands and snippets whose behavior the edit introduces, changes, or calls into question. Check affected paths, links, option names, expected output, and version-sensitive claims against current source. Do not rerun unrelated examples in an existing guide or claim execution from syntax inspection alone.

Review the rendered structure when formatting matters. Remove stale examples, duplicated explanations, unsupported claims, and sections that serve a different audience or mode.

Completion criterion: affected executable material was freshly checked or explicitly marked unverified, and changed claims have recoverable sources.
