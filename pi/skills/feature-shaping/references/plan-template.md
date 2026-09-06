# Feature plan template

Adapt this template to the repository. Remove sections that are not applicable, but preserve the status, approval, uncertainty, slice, and resume information needed to continue safely.

````markdown
# <Feature name>

## Status

- Track: combined design | interview
- Intended outcome: draft | approved | reopened | not applicable
- System architecture: draft | approved | reopened | not applicable
- Program design: draft | approved | reopened | not applicable
- Slice plan: draft | approved | reopened
- Current slice: not started | <slice number and name> | complete
- User checkpoints: none | <explicitly requested boundaries>

## Authority

- User request: <issue, prompt, or short statement>
- Existing approved artifacts: <paths or none>
- Compatibility obligations: <public behavior or none>

## Intended outcome

### Problem

<Problem in user, operator, or system terms.>

### Outcome and acceptance evidence

<Observable result and how success will be judged.>

### Constraints and non-goals

- <Constraint>
- Not doing: <non-goal>

### Representative behavior

<Main workflow, failure behavior, and mockup paths when applicable.>

## Current-system evidence

- `<path or symbol>`: <current behavior relevant to the design>
- `<test or command>`: <what it establishes>

## System architecture

### Fit and boundaries

<Existing modules, services, owners, and affected boundaries.>

### Contracts and data

<Contract sketches, persisted data, query shape, migration, compatibility, and rollback.>

### Flow

<Short sequence or call flow for the main and failure paths.>

### External and operational effects

<External systems, configuration names, deployment, observability, or none. Never record secret values.>

### Alternatives

1. <Alternative and why it loses>

## Program design

### File-tree diff

```diff
<important files and ownership changes>
```

### Key types and signatures

```text
<types and signatures without implementation bodies>
```

### Call stacks

```text
<entrypoint to boundary for main and failure paths>
```

### State, invariants, and bounds

<State ownership and important invariants, or not applicable.>

### Test strategy

- `<test name>`: <observable behavior proved>

### Least-confident decisions

1. <Decision most worth challenging before implementation>

## Vertical slices

| Slice | Inspectable behavior | Verification | Status |
|---|---|---|---|
| 1. <name> | <end-to-end result> | <command or observation> | pending |
| 2. <name> | <increment> | <command or observation> | pending |

## Decisions and deviations

- <Approved or reopened decision, rationale, and affected phase>

## Verification results

- <Slice or final command, result, and inspected behavior>

## Resume

- Next action: <first unapproved phase or incomplete slice>
- Blockers: <decision or none>
- Relevant paths: <small set needed to resume>
````
