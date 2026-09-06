# Agent runner contract

Choose the runner from the target repository's existing tooling. Consult its current official documentation when generating the workflow; do not copy stale commands from an example.

## Required isolation

- Use a trusted, ephemeral runner or container and a fresh checkout.
- Pin the agent CLI, runtime, actions, and setup dependencies to reviewed immutable versions.
- Give the agent filesystem access only to its isolated checkout plus bounded temporary output paths.
- Do not provide a GitHub write token, persisted checkout credential, cloud credential, signing key, or deployment credential to the agent process.
- Use a dedicated, spend-limited model credential. Set explicit time, turn, output, and cost limits supported by the runner.
- Treat repository files, generated measurements, issue text, PR bodies, and comments as untrusted data rather than instructions.
- Capture the final response separately from stdout/stderr logs.

The agent edits the isolated checkout and returns:

```text
/tmp/agent-report.md
/tmp/agent-status.txt
```

A later deterministic step validates the patch and may upload it as an artifact. Automatic branch or PR publication requires a separately approved publisher job with minimum repository permissions.

## Selection and outcomes

The controller writes its selection and measurement-based reason to `/tmp/controller-output.md`, and one status line to `/tmp/controller-status.txt`: `selected`, `no-change`, or `blocked`. Run the actuator only for `selected`. An empty selection is not permission to find other work. A fused controller/actuator keeps the same decisions inside its single invocation.

The actuator writes its report and one status line to `/tmp/agent-status.txt`: `changed`, `no-change`, `blocked`, or `failed`. `no-change` needs evidence that the selected work is already satisfied or requires no edit; lack of authority or an unresolved decision is `blocked`. Command failures, missing or invalid outputs, and failed validation are `failed`, regardless of the agent's declared status.

Use the capture step in `references/workflow-template.yml` to cross-check command outcomes, validation, and patch contents. It writes `/tmp/loop-status.txt`; only `changed` with successful validation and a nonempty patch is eligible for the separately authorized publisher. Successful `no-change` requires an empty patch. Blocked and failed runs remain unsuccessful and retain evidence, including any partial patch. Upload available reports and measurements even after earlier steps fail; cancellation or runner loss may prevent upload.

## Codex

Use the installed upstream Codex CLI and check its current `exec --help`. The following command shape is supported by Codex 0.147.0; it is not a version pin or proof of unattended authentication:

```bash
codex --ask-for-approval never exec \
  --sandbox workspace-write \
  --ephemeral \
  --model '<approved-model>' \
  --output-last-message /tmp/agent-report.md \
  - < /tmp/agent-prompt.md
```

Run this inside the required isolated runner above, with an externally enforced deadline. `never` means operations requiring approval must fail, not that they are preapproved. Do not use a sandbox-bypass flag. Capture logs separately; a report file alone does not establish successful execution or validation.

Use a clean, reviewed Codex home and environment for automation. User/project configuration, skills, hooks, MCP servers, and Git credential helpers can change authority; review them before the run. A local ChatGPT sign-in is not permission to copy the user's auth file into CI. Establish an approved credential and enforceable usage budget before enabling unattended runs; report unavailable turn/cost controls instead of claiming the CLI supplies them.

Record the exact upstream CLI/runtime versions, model, workspace and network permissions, authentication scope, deadline, output bounds, and proof that repository write credentials are absent. Native sandboxing supplements rather than replaces the isolated runner and separate publisher.

## Pi

Pi supports non-interactive print mode. Install a reviewed pinned Pi build, select a pinned model, and pass the prompt through stdin rather than shell interpolation:

```bash
pi --print \
  --no-session \
  --approve \
  --model '<provider>/<model>:<thinking>' \
  --tools read,bash,edit,write,grep,find,ls \
  < /tmp/agent-prompt.md \
  > /tmp/agent-report.md
```

Pi does not provide an operating-system sandbox. Run it inside the isolated runner/container described above. `--approve` trusts project-local Pi resources; use `--no-approve` instead when those resources are not part of the reviewed loop design.

Record the exact pinned Pi source and version, model, output extraction, workspace permissions, credential scope, spend limit, timeout, and proof that repository write credentials are absent from the Pi environment.

## Deterministic patch capture

After validation, capture tracked and untracked non-ignored changes without committing or pushing:

```bash
git add --intent-to-add --all
git diff --binary --no-ext-diff HEAD > /tmp/agent.patch
git reset --quiet
```

An empty patch is valid only with an evidenced `no-change` outcome; do not infer success from emptiness alone. Store the base commit SHA and checked loop outcome beside the patch. A publisher must reject non-`changed` outcomes, failed runs, empty patches, or an artifact whose expected base no longer matches.
