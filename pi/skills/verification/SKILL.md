---
name: verification
description: Select and exercise the affected behavior or integration boundary, tie evidence to the tested workspace, and separate worker feedback from parent acceptance. Use for code behavior changes, defects, reliability claims, integrations, and final acceptance. Simple prose or preference edits need their focused artifact or consumer check, not a separate verification workflow.
---

# Verification

Choose evidence for the claim, not a fixed ceremony. Global and repository instructions own authorization and completion policy; this skill explains how to exercise the affected boundary.

## Select the boundary

Identify the intended outcome, changed workspace, affected runtime surfaces, risks, and required repository checks. Use the strongest necessary practical boundary:

1. parse, lint, type, policy, or artifact checks;
2. focused behavior or defect reproduction;
3. controlled materialization and integration;
4. runtime user or service journey;
5. bounded performance, concurrency, fuzz, or flake sampling;
6. authorized read-only installed or production observation.

A parser cannot prove a setting is consumed. A stubbed integration can prove control flow but not external service compatibility or real latency. State those distinctions rather than inflating the claim. Avoid unrelated suites and repeat checks only after relevant changes, failures, or material evidence gaps, or when the repository requires them.

## Establish the problem before the fix

Define expected behavior and inventory existing coverage before production edits. For defects, reuse the smallest reproducer or add one durable case, observe RED, implement the causal fix, then observe GREEN. If no check or journey reproduces the symptom, continue diagnosis or report the gap without speculative production changes.

For other code behavior changes, add problem-first coverage only for uncovered behavior and invariants. Adequately covered refactors add no tests. Mechanical preference/config edits need a parse or actual consumer check, not a manufactured failing snapshot. Behavioral and security-sensitive configuration changes use the same evidence standards as code.

For new or changed deterministic input contracts, retain only relevant distinguishable rows: accepted values, limits, one step outside, absent input, explicit `undefined`, `null`, non-finite and fractional values, and wrong primitive types. Each retained row needs executable evidence, which may already exist. Do not change expectations solely to agree with an implementation.

A reproducible command or runtime journey can substitute for a conventional test. Implementation-first work is a regression check, not TDD. Performance and reliability claims need a baseline and the same journey afterward.

## Accept the integrated result

Workers use the fastest sufficient inner loop. The root parent independently runs and inspects the authoritative affected boundary on the final integrated workspace. Checked child evidence is useful feedback, not runtime proof. Review does not replace this acceptance step.

Keep evidence bound to repository, revision, and the tested changes. Use existing receipt IDs when available; do not introduce receipt machinery just for a simple edit. Treat receipts as immutable attempt facts, not authority. Distinguish assertion failures, execution errors, unsupported tools, cancellations, and timeouts.

Report exercised behavior, inspected artifacts, exact outcomes, and residual gaps. Once the affected checks pass, finish within the authorized scope. Add a repository-owned runtime adapter only after repeated setup or interaction failures show that it would remove a recurring evidence gap.
