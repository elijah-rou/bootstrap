---
name: technology-selection
description: Choose an implementation language, runtime, or frontend stack for a new project, standalone component, or explicitly approved rewrite. Use when multiple technologies are viable and the choice materially affects safety, performance, deployment, operations, or ecosystem fit. Do not use for ordinary changes in an existing codebase, forks without rewrite approval, or platforms that already mandate the technology.
---

# Technology selection

Choose the smallest technology stack that satisfies the system's real constraints. Do not turn an implementation task into a rewrite or stack debate.

## 1. Confirm that a choice exists

Identify:

- whether the codebase, platform, deployment target, or team already mandates a language or framework;
- whether this is a new project, a separately deployable component, or an explicitly approved rewrite;
- compatibility obligations to existing APIs, data, build tooling, packaging, and operations.

Preserve the incumbent technology when it can meet the requirements without disproportionate risk or complexity. Stop and use the mandated technology when no meaningful choice remains.

Completion criterion: the decision boundary and compatibility obligations are explicit.

## 2. Rank the constraints

Rank only constraints that can change the decision:

- correctness and memory-safety requirements;
- latency, throughput, memory, startup, and binary-size limits;
- concurrency and fault-tolerance model;
- required libraries, browser or runtime APIs, and platform support;
- deployment, cross-compilation, packaging, observability, and operational burden;
- team fluency and long-term maintenance cost;
- delivery time and expected lifetime of the component.

Use measured limits and named dependencies where available. Do not claim performance, safety, or ecosystem advantages without tying them to a requirement.

Completion criterion: the decisive constraints are ordered and supported by repository or platform evidence.

## 3. Apply the default preferences

Use these preferences only after mandatory constraints:

- **Zig:** systems or performance-critical work that needs explicit memory control when Rust's safety machinery would add disproportionate complexity.
- **Rust:** systems, safety-critical, or performance-critical work, and small standalone CLIs where strong compile-time guarantees justify the build cost.
- **Go:** services, infrastructure, and larger CLIs or TUIs that benefit from simple deployment and straightforward concurrency.
- **Gleam, Elixir, or OCaml:** concurrent, fault-tolerant, or typed functional systems when their runtime and ecosystem fit deployment requirements.
- **Python:** scripts, machine learning, data work, and prototypes where iteration speed matters more than distribution or tight resource bounds.
- **Bash:** small Unix utility scripts whose state, error handling, and portability remain easy to audit.
- **Internal frontends:** prefer server-rendered HTML with HTMX and the host language's templates before adding a browser application stack.
- **TypeScript or JavaScript:** use when browser or Node ecosystem requirements demand it; prefer Svelte, Astro, or Solid when a client framework is necessary.

Treat these as tie-breakers, not universal rankings.

Completion criterion: each surviving option satisfies every mandatory constraint before preferences are applied.

## 4. Make the decision auditable

Compare the strongest two options when more than one remains. State:

- why the selected option fits the decisive constraints;
- the concrete cost accepted by choosing it;
- why the runner-up loses for this component;
- what new fact would justify revisiting the choice.

Do not produce a broad technology survey. Record a short decision in the repository only when the choice has lasting architectural or operational consequences.

Completion criterion: one recommendation follows from named constraints, with a bounded reconsideration trigger.
