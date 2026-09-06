---
name: blast-radius
description: Assess what a proposed or completed code change could break beyond its diff and prove the assumptions that make it safe. Use when the user asks “what could this break,” requests blast-radius or impact analysis, or asks for proof that a specific change is safe across API, data, configuration, concurrency, persistence, or external-system boundaries. Do not invoke merely because a nontrivial change is being reviewed or prepared for shipping.
---

# Blast radius

Trace hidden coupling beyond direct references and prove the load-bearing safety claims with executable evidence. This skill is self-contained and does not invoke another skill.

## 1. State the changed contract

Read the proposed change or actual diff. Describe what callers, stored data, external systems, operators, and users observe differently. Include deleted behavior and changed defaults, not only new code.

Identify the boundary crossed:

- public or internal API;
- serialized, database, cache, or wire format;
- configuration, environment, feature flag, or deployment behavior;
- concurrency, ordering, retry, cancellation, or lifecycle behavior;
- filesystem, network, process, or third-party contract;
- user-visible behavior.

Completion criterion: the changed observable contract is explicit.

## 2. Trace direct and hidden dependents

Find definitions, references, callers, tests, and configuration consumers. Then inspect coupling that symbol search misses:

- another language or service reading the same bytes;
- schema, migration, generated code, or fixture assumptions;
- reflection, registration, naming conventions, and string keys;
- scheduling and lifecycle order;
- cached or persisted state created by an older version;
- deployment skew and rollback behavior;
- undocumented behavior encoded in tests or operational scripts;
- dependency behavior at the pinned version, including local patches.

Search absence is evidence only when the search covered every relevant representation and scope.

Completion criterion: each plausible propagation path is confirmed, cleared, or explicitly unverified.

## 3. Identify the load-bearing safety claims

Most risk collapses around one or two facts, such as:

- all consumers accept the new representation;
- an operation affects only already-inactive entries;
- initialization always precedes use;
- retries are idempotent;
- old and new versions can coexist;
- the changed path executes only behind a disabled flag.

Write each claim as a falsifiable statement. Rank claims by the impact if false and the uncertainty in current evidence.

Completion criterion: the assessment names the smallest set of facts on which safety depends.

## 4. Prove the important claims

Use the strongest cheap evidence available:

1. exact source or specification citation;
2. a traced bad case showing it cannot reach the failure;
3. a focused script or test using the real shipped code;
4. a bounded reproduction in the running product.

Default to source inspection and existing isolated tests. Prefer temporary proof scripts outside the repository. Add a project test only when the task already authorizes implementation and the test protects lasting behavior. Bound iterations, time, concurrency, network access, and output.

Before executing a probe, establish that it runs in a disposable environment. Do not call configured external APIs, use networked services, mutate persistent local data, exercise a user's live session, or run a command with externally observable effects without explicit approval for that exact probe. Never probe production or shared systems.

Mark a claim unproven when the required environment or evidence is unavailable. Do not round confidence up because the explanation sounds plausible.

Completion criterion: every high-impact safety claim has executable evidence or an explicit unproven status.

## 5. Report for a decision

Return:

- **Changed contract:** the actual observable difference.
- **Safety claims:** each claim, evidence level, and proof result.
- **Confirmed risks:** failure mechanism, affected consumer, likelihood, impact, and cheapest detection.
- **Cleared paths:** what was investigated and why it is safe.
- **Before shipping:** the smallest checks that would catch the important failure.
- **Residual uncertainty:** unavailable evidence or environments.

Do not publish, merge, push, deploy, or modify review state. The assessment provides evidence; it does not grant release authority.
