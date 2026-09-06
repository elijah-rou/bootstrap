# Shared agent skills

Pi loads this library directly. Codex exports the reviewed selection in
[`codex/skills.txt`](../../codex/skills.txt) through the standard shared skill directory;
see [the Codex guide](../../codex/README.md). Runtime-specific behavior stays in explicit
branches, so the two consumers do not need separate copies.

The `show-me` and `design-control-loop` skills are adapted from
[humanlayer/skills](https://github.com/humanlayer/skills) at commit
`3c2629142c5d437428269b1b722b08c0b87f574d`.

Local adaptations narrow automatic invocation, use portable skill paths, require an
approved control-loop design before implementation, and tighten workflow safety.
The upstream MIT license is preserved in `HUMANLAYER-LICENSE`.

The `writing-for-agents` and `diagnosing-bugs` skills are adapted from
[mattpocock/skills](https://github.com/mattpocock/skills) at commit
`6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`.

Local adaptations support Pi and Codex skill contracts, narrow automatic triggers, remove
foreign-harness orchestration and implicit publication, and keep application debugging
separate from the coredump workflow. The upstream MIT license is
preserved in `POCOCK-LICENSE`.

The `unslop`, `technical-writing`, `how`, `why`, `blast-radius`,
`make-operations-idempotent`, `separate-before-serializing-shared-state`, and
`type-system-discipline` skills are adapted from
[cursor/plugins](https://github.com/cursor/plugins/tree/main/pstack/skills) at commit
`68836ddaf5697224520f1847d90cdb90ca8babaa`.

Local adaptations use narrow automatic triggers, remove Cursor tools, model routing,
MCP assumptions, cross-skill invocation, and publication behavior, and preserve evidence
and source boundaries. The upstream MIT license is preserved in `PSTACK-LICENSE`.

The `technology-selection`, `source-grounded-research`, and `verification` skills are original to this repository.

The `feature-shaping` skill is original to this repository. Its risk-scaled design workflow
is informed by HumanLayer's
[Why Software Factories Fail](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents/blob/main/wsff.md)
and Maciej Dziuba's
[Software Factory Playbook gist](https://gist.github.com/Maciejdziuba/88890d7e0eeefa5a8738bbe9fd5e20b8).
Neither source is vendored.

Every installed skill owns a self-contained primary workflow and may read references within
its own directory. Global agent policy may run `unslop` as a separate final pass over an
artifact's prose; the primary skill does not invoke it from within its workflow.
