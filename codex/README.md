# Codex setup

`./install.sh --tools codex` installs Codex under the bootstrap root with
`CODEX_HOME` in its private directory, unless `CODEX_HOME` is already set (for
example by a workstation overlay). It links the instructions and native tool notes
from agent-kit's `codex/`, copies `config.toml` when none exists, and links the
skills named in agent-kit's `codex/skills.txt` into `~/.agents/skills`, keeping any
existing skill of the same name.
