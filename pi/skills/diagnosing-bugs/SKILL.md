---
name: diagnosing-bugs
description: Diagnose hard, ambiguous, intermittent application bugs and performance regressions when the cause or reproduction path is not obvious. Use after routine error inspection is insufficient. Do not use for systemd coredumps, signal-level crash analysis, or a straightforward failure with an already-known fix.
---

# Diagnosing hard bugs

Find the cause through a bounded feedback loop, falsifiable hypotheses, and direct evidence. This skill is self-contained; read only its named local reference and do not invoke another skill. Do not start by editing production code.

## 1. Define the exact symptom

Record:

- expected and observed behavior;
- affected input, environment, version, and frequency;
- last known good state when available;
- evidence already collected and hypotheses already ruled out.

Read exact errors and the relevant control/data path. Redact credentials, authorization headers, tokens, personal data, and machine-specific secrets before quoting or saving output.

Completion criterion: one sentence distinguishes this bug from nearby failures.

## 2. Build the tightest practical feedback loop

Choose the smallest command or interaction that exercises the real symptom. Read `references/feedback-loops.md` for candidate loop shapes.

Prefer a loop that is:

- **specific**: fails on the reported symptom rather than any error;
- **repeatable**: deterministic, or with a measured reproduction rate for intermittent bugs;
- **fast**: narrow enough to run after each probe;
- **bounded**: explicit iteration, time, concurrency, and output limits;
- **agent-runnable** where practical.

Run it and capture the baseline. Static inspection may help construct the loop, but it is not evidence that a proposed fix works.

If no automated reproduction is practical, use the strongest available artifact or user-assisted observation. State what remains unverified and ask only for access or evidence the tools cannot obtain.

Completion criterion: a recorded command or bounded procedure has produced the symptom, or the missing reproduction capability is explicit.

## 3. Reproduce and minimize

Confirm the loop reaches the same failure the user reported. Minimize further only when it helps distinguish causes or produces a useful regression case. In a disposable local or test environment, remove inputs, services, configuration, and steps one at a time while rerunning the loop. Never disrupt shared or production services, data, traffic, or configuration without explicit approval.

For intermittent failures, improve and report the reproduction rate rather than claiming determinism. For performance regressions, record a baseline distribution or profiler/query-plan artifact instead of relying on a single timing.

Completion criterion: the smallest practical reproducer and its observed result are recorded.

## 4. Rank falsifiable hypotheses

Keep only hypotheses supported by current evidence, with at most five active alternatives. One is enough when the evidence already isolates a likely cause. For each, state:

```text
If <cause> is responsible, then <probe or controlled change> will produce <observable result>.
```

Rank them by evidence and cost to falsify. Test one variable at a time, starting with the cheapest discriminating probe. Update the ranking after each result; do not preserve a favored theory against contradictory evidence.

Ask the user only when domain knowledge or an unapproved product, architecture, security, or scope decision can materially change the investigation.

Completion criterion: evidence has falsified alternatives or isolated one causal mechanism.

## 5. Instrument narrowly

Prefer debugger or profiler inspection, then targeted boundary logs or counters. Tag temporary instrumentation with one unique marker such as `[DIAG-a4f2]` so cleanup is exhaustive.

Do not log secrets or broad payloads. Bound trace size and duration. For concurrency bugs, capture ordering, identities, timestamps, and state transitions at send/receive or lock boundaries.

Completion criterion: each probe maps to one hypothesis and produces a bounded observable result.

## 6. Lock the bug down before fixing

At the correct public seam, turn the minimized reproduction into a failing regression test and confirm it fails for the expected reason. If no honest test seam exists, record that architectural limitation instead of adding a shallow or implementation-coupled test.

Apply the smallest causal fix. Confirm:

1. the regression test passes, when an honest regression seam exists;
2. the original unminimized feedback loop passes;
3. focused adjacent tests and required repository checks pass.

Completion criterion: pre-fix failure and post-fix success are freshly observed against the same symptom; when no honest regression seam exists, the report identifies that gap explicitly.

## 7. Clean up and report

- Remove every tagged diagnostic statement and temporary harness not worth retaining.
- Preserve useful regression tests and reusable repro fixtures without secrets.
- State the root cause, why the fix addresses it, commands run with outcomes, and residual uncertainty.
- Leave commit, push, PR, deployment, and release actions inside the user's existing authority boundaries.

Completion criterion: no temporary instrumentation remains and the evidence trail supports the root-cause claim.
