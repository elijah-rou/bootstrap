# Codex setup

`./install.sh` installs Codex, links these instructions and the shared skills in
`skills.txt`, and supplies `config.toml` only when no local configuration exists.
Authentication and existing model preferences stay on the machine.

`./install.sh codex-link` relinks instructions and skills offline. It preserves
custom skills and reports conflicting definitions instead of choosing between
them. Start a fresh Codex session after relinking.

Skill sources and their license notices live in [pi/skills](../pi/skills).
