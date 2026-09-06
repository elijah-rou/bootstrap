---
name: design-control-loop
description: Interview the user to design an agentic control loop (sensor, controller, actuator under disturbances) tailored to their codebase, then build locally runnable components and an optional scheduled coding-agent workflow.
disable-model-invocation: true
---

# Design Control Loop

Use this skill when a user wants to drive some property of their codebase toward a target with small, low-risk, reviewable changes on a schedule — an **agentic control loop**.

Your job is to **interview the user, design the loop _with_ them, and then build it for them**. This skill is self-contained: read only its named local references and do not invoke another skill. The design must be tailored to *their* codebase and the tooling they already use. There is no fixed toolset and no template to reproduce: propose options grounded in what you find in the repo, discuss trade-offs, agree on a design, then implement it.

## The mental model

Borrow from control theory. The codebase is a dynamic system being changed continuously (by teammates, dependencies, and generated code — the **disturbances**). A control loop drives it toward a desired state instead of all at once:

- **Set point** — the desired end state for some property of the codebase.
- **Sensor** — measures the current state, producing the gap to the set point.
- **Controller** — decides the next small, low-risk change from that measurement.
- **Actuator** — a coding agent that applies the selected change in an isolated workspace and returns a reviewable patch and evidence.
- The result feeds back into the next run. A human stays *on* the loop to steer it.

If these concepts are unfamiliar or terminology obstructs a design choice, read `references/control-loop-taxonomy.md` and explain the relevant concepts. Otherwise, proceed with the design. Use `references/example-control-loop.md` when a worked example helps; treat it as an illustration, not a blueprint.

## How to run this skill

- **Read the repo before you ask** (Phase A). Come to the interview with proposals, not a blank form.
- **Tailor every component.** The right sensor, controller, and actuator depend entirely on the user's problem and stack. The lists in the references are examples to spark discussion, never a checklist to push.
- **Make each component runnable locally and standalone before wiring it into CI** (Phase D). The workflow should only orchestrate pieces the user can already run by hand.
- **Capture the agreed design in writing** before building, so the user can correct it cheaply.
- **Resume from settled decisions.** Read an existing approved design and continue from its first incomplete phase; do not repeat completed interviews or approvals.
- **Preserve authority boundaries.** Creating skills or memory, changing credentials, publishing, and enabling schedules require approval. Implement only the outputs covered by the agreed design; do not infer operational authority from permission to design the loop.

## Outputs

Create or update the approved outputs in the target repo, tailored to the agreed design:

- The **sensor** and **controller** as version-controlled commands/scripts the user can run locally.
- A repo-local `SKILL.md` — the **actuator** skill capturing the agent's judgement. Use `.agents/skills/<skill-name>/SKILL.md` for Codex or shared skills; retain `.pi/skills/<skill-name>/SKILL.md` for an established Pi-only layout.
- The recurring **workflow** that runs the loop and produces a reviewable patch artifact. Add automatic PR publication only after its credential and trust boundaries are approved.
- A **memory/feedback file** that carries standing feedback between runs.
- Optionally, a **dampener** (regression gate) that keeps the problem from getting worse while the loop improves it.

## Workflow

### Phase A — Understand the system

Use `references/example-control-loop.md` only when an example would clarify an unfamiliar loop.

Read before asking setup questions:

- Existing CI: `.github/workflows/*.yml`, `.github/actions/**`, or the repo's non-GitHub CI config — runner, checkout, dependency install, cache, and PR conventions.
- Package manager files (`package.json`, `bun.lock`, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, …).
- Existing validation scripts: typecheck, lint, test, quality, format, and package-scoped commands.
- Existing `.agents/skills`, `.pi/skills`, and agent loops (workflows, `agent-memory`, and glue-script locations) to mirror conventions instead of inventing new ones.
- The static-analysis, linting, codegen, and test tooling already in the repo — these are the most likely raw material for a sensor.
- Discover packages, services, and repo purpose at a high level.

Completion criterion: you can name the repo's package manager, install command, likely validation commands, CI platform, and any existing loop conventions. You understand the packages/services/applications it contains at a high level.

### Phase B — Design the loop with the user

Use `references/control-loop-taxonomy.md` when unfamiliar terminology obstructs a design choice, and `references/example-control-loop.md` when an example helps. Read `references/agent-runner-templates.md` when selecting the runner and credential boundary.

Design the loop with the user. Work through each unresolved component below, starting with the set point. Propose options grounded in Phase A and explain trade-offs rather than mandating a choice. Record the decisions as you go.

1. **Set point.** What property are we driving, and to what target? Examples: an invariant ("no procedures use the old pattern"), a threshold ("test coverage ≥ X in these packages"), or a direction ("reduce occurrences each run"). Also pin the **scope**: which directories/packages the loop may change, and which it may only read.

2. **Sensor.** How will the loop measure the gap to the set point? Inspect the codebase and the user's existing tooling and propose the options that fit *their* stack — a static-analysis or lint tool, a structural/AST search, a test suite, a type checker, a telemetry or error query, a custom script, or even an agent-based check. Discuss the trade-offs that matter to them (stability, cost, repeatability, and whether the measurement can be silently disabled) instead of mandating any property. Aim for a measurement the controller can act on repeatably.

3. **Controller.** How will the loop choose the next increment from the measurement, sized to stay low-risk and reviewable? Design this *with* the user: how to prioritize targets, how big one increment is, and what "one reviewable unit of work" means here. A controller can be anything from fully deterministic (a script that selects the next target) to fully agentic (an agent that decides from natural-language criteria), and it may be **fused** with the sensor or the actuator. The controller is the part you will **tune over time** from loop output — start simple and expect to revise it.

4. **Actuator.** A coding agent plus a repo-local skill applies the change.
   - **Agent + credentials.** Select the approved upstream Codex or Pi release, model, bounded credential/usage arrangement, and matching headless command from `references/agent-runner-templates.md`. Local subscription sign-in does not establish an approved unattended CI credential or spend limit.
   - **Golden patterns first.** Before automating, establish what a good change looks like: ask the user whether existing patterns in the codebase should be followed, and inspect the code to find them. Capture these in the actuator skill (Phase C).
   - **Validation.** Decide which commands must pass before the agent finalizes its uncommitted patch (propose these from Phase A and confirm).

5. **Disturbances + dampener (offer).** Name what changes the system outside the loop (teammates shipping concurrently, dependency bumps, generated code). Then **offer** a dampener: a check that keeps the measured problem from getting worse while the scheduled loop chips away at it — for example a PR check that compares the sensor's output against a baseline and surfaces (or eventually blocks) newly introduced deviations. This is optional; some loops do not need one.

Completion criterion: a short written design naming the set point, sensor, controller, actuator (agent + skill + validation), and disturbances/dampener — with each component something the user can run locally.

Get explicit approval of the written design and implementation scope before creating or modifying implementation files. If that design and scope are already approved, continue without asking again.

### Phase C — Build the actuator skill

**Read the following references:** `references/skill-template.md`, `references/example-skill.md`, `references/response-template.md`.

Write a repo-local skill that captures the actuator's judgement for this task. It can use repo-specific paths, package names, and conventions since it lives in the repository.

- Make the generated actuator self-contained. Put ordered behavior in `SKILL.md` as steps with checkable completion criteria; move long templates and examples into sibling reference files, not other skills.
- Encode the golden patterns from Phase B4 so the agent follows established conventions.
- Keep one source of truth for each rule; do not repeat the same guidance in the skill, the prompt, and the memory file.
- Include a response template (e.g. `references/response-template.md`) defining how the agent formats its final output, which becomes the PR body. Instruct the skill to read and follow it.
- Use `references/skill-template.md` as the skeleton and `references/example-skill.md` as a concrete example. See https://agentskills.io/specification for the skill spec.

**IMPORTANT:** the `name` in the skill's frontmatter must match its directory slug: a skill named `migrate-foo` lives at `.agents/skills/migrate-foo/SKILL.md` for Codex/shared use, or `.pi/skills/migrate-foo/SKILL.md` in a Pi-only layout.

Completion criterion: the skill explains the job clearly enough that the agent can do it unattended, including how to format its final response.

### Phase D — Make each component runnable locally

**Read the following references:** `references/agent-runner-templates.md`.

Before any CI exists, land the sensor and controller as version-controlled commands or scripts (follow the repo's convention for where such scripts live), and verify the whole loop by hand in an isolated worktree:

- Run the **sensor** standalone and confirm it produces a stable, usable measurement.
- Run the **controller** on real sensor output and confirm it selects a sensible next increment.
- Run the **actuator** locally via its headless CLI command on a controller-selected target, and confirm it makes the change and passes validation.
- Exercise convergence, blocked selection, and execution failure using the outcomes in `references/agent-runner-templates.md`. A justified no-change run succeeds without a patch; blocked and failed runs retain evidence and cannot publish.

Only proceed to CI once each piece runs locally on its own. This keeps the loop debuggable and makes the workflow a thin orchestrator of things the user can already run.

Completion criterion: the user can run sensor, controller, and actuator locally and independently.

### Phase E — Wire the loop into CI

**Read the following references:** `references/workflow-template.yml`, `references/prompt-template.md`, `references/agent-runner-templates.md`.

Assemble the components into a recurring job. GitHub Actions is the default because it already has the code, secrets, version control, and scheduling/dispatch, but use whatever CI the repo uses.

Before enabling it, require least-privilege workflow permissions, immutable version pins for third-party actions and packages, bounded runtime and spend, and an isolated trusted runner. Never generate comment-driven agent execution or pass issue/PR content to a privileged agent.

- Run the loop as **discrete steps: sensor → controller → actuator**, then validate and capture a patch plus the agent's final report. When components are fused, collapse them to one step rather than inventing separation.
- Invoke the actuator only for selected work. Preserve explicit no-change, blocked, and failed outcomes and upload their available evidence; require successful validation and a nonempty patch before treating changed work as eligible for publication.
- Keep the agent job read-only with respect to repository APIs: do not expose GitHub write tokens or persisted checkout credentials to the agent. If automatic PR publication is approved, perform it in a separate deterministic job that consumes the patch, validates its base revision, and holds only the minimum required credential.
- Reusable logic can live in a custom composite action.
- Decide the **cadence** (daily, weekdays, weekly, monthly, manual-only, or custom cron) based on task risk and review burden.
- Interpolate the memory file (Phase F) into the actuator's context.
- Use `references/workflow-template.yml` as the base and `references/prompt-template.md` for the embedded prompt. Pull the agent run and response-extraction contract from `references/agent-runner-templates.md`; write the final response to `/tmp/agent-report.md`.

Completion criterion: the workflow can run from `workflow_dispatch` without relying on files that do not exist.

### Phase F — Put a human on the loop

**Read the following reference:** `references/memory-template.md`.

A scheduled loop drifts without steering. Add a version-controlled memory file, such as `.github/agent-memory/<task-slug>.md`, loaded deterministically after the controller on every run. Record permanent scope exclusions, known false-positive areas, and reviewer feedback that should change future selections. Do not store one-off instructions, untrusted PR content, or run logs.

Update memory through ordinary reviewed changes. Do not generate comment-driven agent execution by default: PR bodies and comments are untrusted input, even when a trusted maintainer later asks the agent to iterate.

Frame this as how the human tunes the controller and skill over time.

Completion criterion: standing feedback survives between runs through a short, reviewed memory file.

### Phase G — Flow control

**Read the following references:** `references/workflow-template.yml`.

Bound work-in-progress so the loop never produces artifacts or PRs faster than they can be reviewed. Start manual-only and use non-cancelling concurrency. If automatic publication is approved, default to one open PR per loop and make a deterministic preflight no-op while that bound is met.

Choose a task slug matching `[a-z0-9]+(?:-[a-z0-9]+)*`. Use it consistently for artifact, label, branch, workflow, and memory names; quote every generated shell path.

Completion criterion: concurrent runs cannot overlap, and any enabled publisher enforces the approved open-PR bound before launching the agent.

### Phase H — Validate, dry-run, and iterate faster

**Read the following references:** `references/workflow-template.yml`.

**Validate** the workflow YAML (`bunx js-yaml file.yml`, `python -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" file.yml`, or `yq`) and confirm every path named by the skill, workflow, and memory file exists or is created by this task.

**Dry-run.** Validate locally in an isolated worktree first. After the workflow reaches the repository's default branch through the normal reviewed process, use `workflow_dispatch` for the first live run. Do not add a temporary push trigger, push branches, or dispatch workflows without explicit user approval. Review any PR it opens before enabling a schedule.

**Ready to iterate faster** (once the loop is tuned and producing consistent, high-quality output): increase the schedule frequency; widen the controller's batch (e.g. select N targets per run); run the sense→control→actuate cycle N times per workflow run; or run the workflow multiple times and assign one PR to each teammate.

Completion criterion: the workflow YAML parses, all referenced files exist, and the loop has produced at least one reviewed patch artifact or PR.

## Reference Files

Each phase above names the references relevant to it — read each one when you reach that phase. Full index:

- `references/control-loop-taxonomy.md` — the control-loop components and design questions; use it when the concepts are unfamiliar or terminology needs clarification.
- `references/example-control-loop.md` — one fully worked loop, annotated component-by-component. An illustration, not a template.
- `references/agent-runner-templates.md` — shared isolation/output contract and runtime-specific headless commands; use only the chosen runtime's branch.
- `references/workflow-template.yml` — recurring loop workflow skeleton with discrete sensor/controller/actuator steps.
- `references/prompt-template.md` — embedded prompt structure for the actuator step.
- `references/memory-template.md` — memory/feedback file skeleton.
- `references/skill-template.md` — skeleton for the generated actuator skill.
- `references/response-template.md` — examples for the agent report and optional PR body.
- `references/example-skill.md` — a concrete example of a well-formed task skill.
