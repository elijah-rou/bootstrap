---
name: separate-before-serializing-shared-state
description: Design or debug concurrent runtime actors that may mutate the same file, key, row, queue, branch, cache, or state object. Use when choosing between partitioning, a single writer, transactions, compare-and-swap, or locks. Do not use for immutable sharing, ordinary sequential access, or coding-agent worktree orchestration already governed by the parent delegation policy.
---

# Separate before serializing shared state

Remove unnecessary shared mutation before adding coordination. When one shared invariant is real, enforce it structurally. This skill is self-contained and does not invoke another skill.

## 1. Map actors and write sets

For every actor, identify:

- the state it reads;
- the state it writes;
- the operation's ownership boundary;
- the invariant that allegedly requires shared mutation;
- the merge or reporting consumer.

Distinguish shared access from shared mutation. Many readers do not require serialization. Two writers changing different logical facts in one document still share a physical write target.

Completion criterion: overlapping write sets and the invariant behind each overlap are explicit.

## 2. Try separation first

Ask whether the actors publish independent facts. If so, give each actor a separately owned resource, such as:

- one file or state directory per owner;
- partitioned keys, rows, queues, or namespaces;
- immutable events or append-only records;
- separate branches or generation directories;
- per-worker temporary outputs merged later.

Merge at the read, reporting, indexing, or explicitly owned aggregation boundary. Define missing, stale, and conflicting partitions there.

For partitioned resources, define the ownership lifecycle, maximum active partitions and storage, retention, and bounded cleanup. Cleanup must verify ownership before deletion. Bound aggregation work so partitioning does not replace lock contention with unbounded scans or retained state.

Do not split state when correctness requires one atomic invariant across the values. Separation that moves the race into an unowned merge step is not a fix.

Completion criterion: every remaining shared write is justified by a named invariant that cannot be represented with independent ownership, and separated resources have bounded lifecycle management.

## 3. Choose structural coordination

For genuine shared mutation, choose the smallest mechanism that preserves the invariant:

- a single-writer actor or serialized phase;
- a database transaction;
- compare-and-swap with a version or generation;
- a bounded lock or lease;
- an atomic append or replacement supported by the storage system.

Define:

- the linearization point;
- lock or transaction scope;
- ordering when multiple resources are acquired;
- timeout, cancellation, and retry behavior;
- stale-owner and crash recovery;
- fairness and backpressure requirements;
- what readers may observe during an update.

Conventions, comments, timing assumptions, and “these normally do not overlap” are not concurrency control.

Completion criterion: the selected mechanism and storage guarantees establish the shared invariant under overlap and interruption.

## 4. Bound failure and contention

Estimate actor count, update frequency, critical-section duration, retry rate, and maximum queued work. Avoid an unbounded retry loop or lock wait. Keep blocking work outside critical sections where correctness permits it.

Fail loudly on programmer invariants. At runtime, return actionable timeout, conflict, or stale-owner errors without corrupting state.

Completion criterion: contention and retry resources have explicit limits and failure behavior.

## 5. Verify adversarial schedules

Test or model:

- simultaneous first writes;
- read-modify-write overlap;
- a crash while ownership is held;
- stale lock or lease recovery;
- retry after an ambiguous outcome;
- reader behavior during updates;
- high-contention bounds.

Use deterministic barriers, fault injection, race detectors, or storage-level concurrency tests when available. Bound iterations, time, actor count, retries, storage, network access, and output. Run destructive or failure-injection checks only in a disposable environment. Do not exercise shared infrastructure, production, live credentials, or persistent user state without explicit approval.

Do not infer safety from several successful unsynchronized runs.

Completion criterion: the invariant survives the important interleavings, and the evidence exercises the actual coordination mechanism within declared resource bounds.
