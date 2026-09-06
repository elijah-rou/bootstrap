---
name: feature-shaping
description: Resolve consequential design uncertainty before broad feature or refactor implementation. Use when unsettled behavior, public contracts, persisted data, cross-system flow, UI interaction, or hard-to-reverse architecture could make rework expensive. Skip bounded fixes, mechanical edits, approved designs, and documentation-only design deliverables.
---

# Feature shaping

Resolve decisions while they are cheap to change. The user owns product and hard-to-reverse choices; current code establishes existing behavior. This skill supplies design methods, not additional approval gates for work the user has already authorized.

## Choose the depth

Inspect repository instructions, status, relevant implementation and tests before asking design questions. Identify settled requirements, existing planning conventions, and consequential unknowns.

- **Direct:** requirements are settled and the work is bounded or reversible. Continue with implementation and affected verification; no plan is required.
- **Combined design:** consequential questions remain. Resolve outcome, system fit, program shape, and slices in one plan. Ask for the outstanding decisions together, then implement within the resulting authorization.
- **Interview:** the user requests staged design reviews, or a specific unresolved decision prevents the next design step. Work through that decision with the user. Do not turn every section into a mandatory approval stop.

Choose by uncertainty and consequences, not file count. For expensive-to-reverse work whose consequential decisions cannot be reviewed coherently together, offer staged human design review. Do not impose phase-by-phase approval or fixed slice checkpoints when the design and implementation scope are already settled. An approved implementation plan, including an audit-fix plan that explicitly authorizes implementation, can supply existing authority. Approval to audit alone does not authorize mutation. Reuse settled design rather than repeating it.

## Record only useful design

For consequential combined design or interview work, maintain a persistent decision-and-slice plan that can stand alone as resume context. An adequate existing approved artifact satisfies this requirement; direct work remains plan-free. Use the repository's planning convention, or read `references/plan-template.md` and create `plans/<feature-slug>.md` when none exists. Omit inapplicable sections. Record approved, open, reopened, and completed items separately so another session can resume without a transcript.

Resolve applicable concerns in this order, combining those already understood:

1. **Outcome:** intended behavior, acceptance evidence, non-goals, compatibility, and representative failure behavior. Use a disposable visual only when it settles an uncertain interaction.
2. **System fit:** affected owners, contracts, data and migration, external effects, end-to-end flow, strongest alternatives, and assumptions requiring a probe.
3. **Program shape:** important files, key types/signatures, success and failure paths, state ownership, bounds, and tests. Show enough to challenge consequential placement decisions, not every private helper.
4. **Slices:** small end-to-end increments with observable outcomes and the affected checks. Exercise the most consequential uncertain path early. Each increment leaves working behavior unless an approved migration requires another boundary.

Ask only for unresolved product, contract, data, security, or hard-to-reverse architecture decisions and any checkpoints the user requested. Silence is not approval of a new decision. Reversible implementation details within the agreed scope remain the agent's responsibility.

## Implement through acceptance

Keep the plan current, then continue through the authorized slices. After each slice, inspect the changed behavior and affected checks, record material evidence or deviations, and keep the diff available. Do not stop automatically after Slice 1 or every few slices.

Pause when new evidence invalidates an approved decision, a blocker exceeds the authorized scope, or a requested checkpoint is reached. State the smallest decision or evidence needed to continue. Fix ordinary failures caused by the change within the existing scope.

Continue in the same session while context is usable. Compact or start fresh only when needed or requested, with the current plan as the handoff. A context reset does not revoke existing authorization.

## Resume and finish

On resume, read the plan and only the referenced artifacts needed for the next incomplete item. Check current code and workspace state for drift; reopen a decision only when evidence warrants it.

At completion, verify the integrated changed path under the repository's verification policy. Reuse valid current evidence; do not rerun unchanged checks merely to close a planning phase. Record outcomes, residual gaps, and accepted deviations, then mark the plan complete. Follow repository policy for ADRs, publication, and cleanup; do not create extra artifacts just to complete a template.
