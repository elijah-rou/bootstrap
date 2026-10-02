# Codex setup

`./install.sh --tools codex` installs Codex under the bootstrap root with
`CODEX_HOME` in its private directory. It links these instructions, copies
`config.toml` when none exists, and links the skills named in `skills.txt` into
`~/.agents/skills`, keeping any existing skill of the same name.

Skill sources and their license notices live in [pi/skills](../pi/skills).
