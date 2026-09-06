# Example Control Loop: React Doctor

One fully worked loop, to make the taxonomy concrete. **This is an illustration, not a template.** A real loop from a production monorepo, it drives React code quality in a single app. Your loop's set point, sensor, controller, and actuator will look different — copy the *shape*, not the specifics.

It is a useful example because the sensor and controller come almost entirely from an existing, configurable tool, so the whole loop is small. This example uses Pi; for a Codex actuator, use the Codex branch of `references/agent-runner-templates.md` while retaining the same isolation, evidence, and publication boundaries.

## Set point

`apps/riptide-ui` stays free of high-impact React issues (lint, accessibility, correctness, architecture). A direction more than a fixed threshold: each run leaves the app a little healthier.

## Sensor — `react-doctor` + `doctor.config.ts`

The [`react-doctor`](https://github.com/millionco/react-doctor) CLI scans the app and reports prioritized issues; `doctor.config.ts` configures which rules run and which paths/rules are ignored. It runs locally exactly as it does in CI:

```bash
bunx react-doctor@<reviewed-version> --project '@example/riptide-ui' --diff false --yes
```

Chosen because it is repeatable, configurable, and lives outside the editor/lint config so a stray inline comment can't quietly switch it off — a trade-off that mattered *for this team*, not a requirement of all sensors.

## Controller — fused with the sensor

There is no separate controller: `react-doctor` returns "the top 3 rules by impact," and the loop's policy is "fix up to 5 issues from those top 3 rules this run." That selection logic lives in the actuator's prompt. This is the **sensor + controller blur** — one tool plus a small policy does both jobs.

## Actuator — Pi + a repo-local skill

A headless Pi run uses the repo's self-contained `react-doctor` skill. Its per-issue loop gives the agent three honest options: **fix**, **ignore** (add to `doctor.config.ts` with a reason), or **skip** (leave for a human). It validates each change before leaving the combined patch uncommitted:

```bash
bun run typecheck
bun run quality
bunx react-doctor@<reviewed-version> --project '@example/riptide-ui' --diff false --yes
```

## Disturbances + dampener

**Disturbance:** teammates ship React code continuously while the loop runs.

**Dampener:** a second workflow (`react-doctor.yml`) runs on every pull request and on pushes to `main`. It diffs against the merge base and comments on only the *newly introduced* issues. It is **advisory by default** (never red-Xes a teammate's PR), with a documented path to graduate to blocking once the team trusts the signal. This keeps the problem from getting worse while the scheduled loop chips away at it.

## The loop — `agent-react-doctor.yml`

A manually dispatched workflow runs the loop and produces a patch artifact plus the agent's final report. After reviewed manual runs establish reliability, the team may add a daily schedule and a separately authorized deterministic PR publisher. Because the sensor, controller, and actuator are fused into one agent step here, the workflow does not invent three separate steps. A loop with a deterministic standalone sensor and controller would use discrete steps.

## Human on the loop

- `.github/agent-memory/react-doctor.md` is loaded into Pi every run with standing feedback such as “avoid effects when derived state is sufficient” and “do not globally ignore a rule when only specific files need an exemption.”
- Maintainers review each patch or PR and update the memory file through ordinary reviewed commits when feedback should affect future runs. Untrusted PR content is never injected automatically into the privileged agent context.

## Flow control

Every PR is labeled `agent-react-doctor`. Scheduled runs no-op when an open PR with that label already exists, so there is at most one open PR per loop; manual dispatch bypasses the gate.

## What to take from this

- **Reusable shape:** set point → sensor → controller → actuator under disturbances, plus a dampener, reviewed memory, and bounded work-in-progress.
- **Not reusable:** `react-doctor`, the example commands, the “top 3 rules / 5 fixes” policy, and the `riptide-ui` scope. Those are tailored to this repo; yours come from the interview.
