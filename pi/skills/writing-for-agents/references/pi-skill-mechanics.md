# Pi skill mechanics

Use Pi's current skill contract and installed layout.

## Discovery locations

Pi discovers global skills under `~/.pi/agent/skills/` and `~/.agents/skills/`. Trusted projects may provide `.pi/skills/` or `.agents/skills/`. A configured package or `settings.json` skill path can also provide skills.

A directory skill contains `SKILL.md`. Resolve sibling scripts, references, and assets relative to that directory.

## Frontmatter

Required:

```yaml
---
name: lowercase-hyphenated-name
description: Specific behavior and trigger conditions.
---
```

The name must be 1–64 lowercase letters, numbers, or hyphens, with no leading, trailing, or consecutive hyphens. Keep the directory name identical for portability.

A model-invoked skill omits `disable-model-invocation`. Its description is always visible to the model, so include precise trigger branches and exclusions.

A manual-only skill uses:

```yaml
disable-model-invocation: true
```

Pi then hides it from automatic model discovery while retaining `/skill:<name>` invocation. Use this for uncommon, expensive, destructive, publication-capable, or interview-driven workflows.

## Progressive disclosure

Pi initially loads skill names and descriptions. The agent reads `SKILL.md` after a trigger, then follows relative references as needed. Keep branch selection, safety boundaries, and the normal execution path in `SKILL.md`; move branch-specific detail and long templates into references.

## Validation

Confirm:

- required frontmatter parses;
- name and directory match;
- description is non-empty and at most 1024 characters;
- local references exist;
- no installed skill has the same name;
- automatic triggers do not substantially overlap;
- copied third-party content preserves its license and pinned provenance.
