---
name: why
description: Investigate why code, configuration, architecture, thresholds, or operational behavior was chosen. Use for rationale, historical decisions, and post-diagnosis questions about why a prior regression, fix, or constraint arose, including “why is X this way” or “why did we choose Y.” Do not use for a mechanical walkthrough, active bug diagnosis, or unsupported speculation about author intent.
---

# Why

Reconstruct rationale from durable evidence and state how much the evidence supports. This skill is self-contained, read-only, and does not invoke another skill.

## 1. Define the decision

Restate the concrete thing whose rationale is in question:

- the current behavior or structure;
- the likely decision boundary and alternatives;
- the relevant time range when known;
- whether the user needs original intent, current justification, or both.

Original intent and present-day justification can differ. Do not substitute one for the other.

Completion criterion: the investigation names one decision or bounded cluster of related decisions.

## 2. Search sources in evidence order

Use the strongest available sources, stopping when the question is answered confidently:

1. Current code, tests, configuration, schemas, comments that explain why, and generated constraints.
2. `git log`, `git blame`, `git show`, rename history, and neighboring commits.
3. ADRs, design documents, plans, incident reports, changelogs, and repository documentation.
4. Linked issues and pull requests through read-only repository tooling when available.
5. Runtime measurements or external specifications when the rationale depends on observed behavior or a third-party contract.

Treat commit messages and comments as claims that may be stale. Cross-check them against the resulting code and later changes. Do not search private chat, analytics, infrastructure, or unrelated external systems unless the user explicitly authorizes that source and it is necessary.

Completion criterion: each important claim has a source, or the absence of evidence is explicit.

## 3. Trace history when needed

If current authoritative evidence answers the question, return that reason with its source. Build a timeline only when the user asks about evolution or later changes affect the rationale. Identify:

- the state before the change;
- the pressure, failure, requirement, or constraint that prompted it;
- alternatives recorded or implied by the diff;
- the selected change and its consequences;
- later modifications that preserved, weakened, or invalidated the rationale.

Avoid intent claims based only on code shape. A plausible explanation is not historical evidence.

Completion criterion: the sequence distinguishes contemporary evidence from later interpretation.

## 4. Grade conclusions

Label substantive conclusions as:

- **Documented fact:** a primary source states it directly and later evidence does not contradict it.
- **Supported inference:** several concrete facts point to it, but no primary source states the intent.
- **Unknown:** available evidence does not justify a conclusion.

Include confidence only when it helps the user decide what to do. Explain what missing source would change the conclusion.

Completion criterion: no inference is presented as documented author intent.

## 5. Answer the user's decision

Lead with the answer and its strongest source. Include the following only where needed:

1. the concise answer;
2. the evidence timeline with path, commit, issue, PR, or specification citations;
3. constraints that still apply today;
4. assumptions that no longer hold;
5. unresolved questions and the cheapest next source to inspect.

If the current implementation has outlived its original rationale, say so directly. Do not edit files, comments, ADRs, issues, or commits as part of this investigation unless the user separately authorizes that work.
