---
name: make-operations-idempotent
description: Design mutating commands, installers, reconcilers, startup jobs, and processing loops that may be retried or interrupted so repeated execution converges safely. Use when an operation can run after partial completion, crash, timeout, or duplicate delivery. Do not use for pure reads, ordinary one-shot local edits, or irreversible operations that require explicit confirmation instead of retry semantics.
---

# Make operations idempotent

Design retryable operations as reconciliation from observed state to one declared end state. This skill is self-contained and does not invoke another skill.

## 1. Define convergence

State:

- the desired end state;
- the resources this operation owns and may change;
- external effects that cannot be rolled back or repeated safely;
- whether concurrent runs are permitted, serialized, or rejected;
- the identity that distinguishes duplicate work from new work.

Do not define success as “the command returned zero.” Define the observable state that must hold afterward.

Completion criterion: one postcondition describes success for the first run, every retry, and recovery from partial state.

## 2. Inventory interruption points

List each state transition and externally visible effect. For every meaningful boundary, determine the state seen if execution stops immediately before or after it.

Classify effects as:

- naturally repeatable;
- create-if-absent or replace-if-different;
- requiring an idempotency key, generation, or compare-and-swap;
- requiring compensation or manual recovery;
- unsafe to retry automatically.

Do not make an operation appear idempotent by swallowing errors or accepting an ambiguous half-finished state.

Completion criterion: every effect has explicit duplicate and interrupted-run behavior.

## 3. Reconcile from current state

Observe before mutating. Compare owned resources by authoritative identity and content, not merely creation order, timestamps, or process names.

Prefer:

- atomic replacement over in-place partial writes;
- deterministic names and idempotency keys over duplicate creation;
- adopt, repair, or replace decisions based on verified state;
- generation markers when old and new state can coexist;
- bounded stale-resource recovery with verified ownership;
- one explicit recovery path for effects that cannot be made repeatable.

Never delete, kill, adopt, or overwrite a resource based only on a stale PID, broad name match, or path that the operation does not demonstrably own. Preserve user-modified or externally owned state unless the contract explicitly authorizes replacement.

Completion criterion: any recognized prior state maps deterministically to repair, no-op, replace, reject, or approved manual recovery.

## 4. Define concurrency behavior

If concurrent runs are possible, choose an explicit structural policy or the smallest necessary combination:

- operations commute because they own separate resources;
- one run holds a bounded lock or lease;
- updates use a transaction or compare-and-swap;
- later duplicates observe and reuse the first result.

Specify ownership, timeout, stale detection, and crash recovery for locks or leases. Instructions to “avoid running twice” are not concurrency control.

Completion criterion: two overlapping runs cannot silently lose updates, duplicate irreversible effects, or corrupt the target state.

## 5. Verify retry and recovery

In a disposable environment, test:

1. an initial run from absent state;
2. an immediate second run;
3. repair from representative partial states at each meaningful transition;
4. concurrent execution when supported, or safe explicit rejection of overlap;
5. stale lock, lease, or temporary-file recovery;
6. failure of external effects without false success.

Bound fault injection, iterations, time, concurrency, network access, and output. Do not exercise production, shared infrastructure, live credentials, or persistent user state without explicit approval.

Completion criterion: every tested start state converges to the same declared postcondition or fails with a precise, recoverable error.
