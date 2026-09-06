---
name: how
description: Explain how a codebase subsystem works, including runtime flow, data movement, ownership, placement, and layering. Use for code walkthroughs and questions such as “how does X work,” “where should this live,” or “which package owns this.” Do not use for historical rationale or motivation, active bug diagnosis, or a request that only needs a visual.
---

# How

Build a working mental model from the source code, then explain it at the level needed to change the subsystem safely. This skill is self-contained and does not invoke another skill.

## 1. Bound the question

State the narrowest interpretation that answers the user. Identify whether they need:

- a subsystem overview;
- a request, event, or data-flow trace;
- ownership or placement guidance;
- an architectural critique.

For ambiguity that does not change risk, proceed with a stated interpretation. Ask when different interpretations lead to materially different systems or recommendations.

Completion criterion: every explanation has a scope boundary; flow questions also have a named entry point and endpoint, while placement questions have an ownership anchor.

## 2. Trace the implementation

Start from real entry points such as commands, routes, event handlers, exported functions, jobs, or UI actions. Trace only the branches needed to answer the question; stop when the requested flow or ownership is established. Relevant concerns include:

- control flow and decision points;
- data shapes and transformations;
- state ownership and lifetime;
- external boundaries and adapters;
- errors, retries, cancellation, and cleanup;
- configuration and feature gates;
- observable outputs and side effects.

Read the implementation rather than inferring behavior from filenames or type names. Use symbol-aware definition and reference tools where available. For a broad subsystem, split reconnaissance into bounded read-only lanes only when their scopes are genuinely distinct.

Completion criterion: every load-bearing transition from trigger to observable effect has a source citation or is marked unknown.

## 3. Reconcile the model

Check that callers and callees agree on invariants, units, ordering, nullability, ownership, and failure behavior. Resolve contradictions by reading the authoritative implementation or running a bounded read-only probe. Do not smooth over conflicting evidence.

Separate:

- behavior directly established by source or execution;
- architectural interpretation;
- unresolved gaps.

Completion criterion: no part of the stated flow depends on an uncited guess presented as fact.

## 4. Explain for use

Use only the sections the question needs; a direct ownership answer may need just a path and rationale:

1. **Overview:** what the subsystem does and its boundary.
2. **Key concepts:** only the types and abstractions needed for the flow.
3. **Flow:** trigger to effect, including decisions and state changes.
4. **Where it lives:** the small set of files and symbols a maintainer should open first.
5. **Gotchas:** non-obvious ordering, coupling, failure, or configuration behavior.
6. **Unknowns:** evidence that was unavailable or contradictory.

Cite exact paths and symbols. Include code only when it communicates a contract more clearly than prose. Use a diagram only when topology, sequence, or state transitions are easier to understand visually.

Completion criterion: a maintainer can name where to start, how the flow proceeds, and which invariants must survive a change.

## 5. Critique only when requested

Explain the current system before judging it. Tie each criticism to an observed maintenance, correctness, performance, testing, or ownership cost. Distinguish:

- act now;
- consider when the area next changes;
- valid but low-value observation;
- unsupported concern.

Do not turn a walkthrough into unsolicited redesign.

Completion criterion: recommendations, when requested, cite the current mechanism and the concrete cost they address.
