# Source snapshot

Initial runtime imported from dotfiles commit `9ffe95556fba7cb5a2d43450d81d333aa544a692`.

This repository contains the selected terminal, Pi, Codex, Neovim setup, and bare
installer files. It has no runtime dependency on the private dotfiles repository.
Workstation installers, secrets, local overlays, account state, desktop configs,
and source history are excluded.

The public Git config omits local checkout URL rewrites. Shell startup omits
the unrelated Moshi token loader. Pi omits the Anthropic
override for the workstation-only Meridian proxy. Optional local web search still
requires a separately configured service. Language toolchains and their LSPs are
opt-in here. The bare installer adds a
managed Neovim overlay that disables automatic Mason downloads and uses selected
servers from PATH. Workstation configuration leaves that overlay disabled.

The bundled Neovim configuration was recovered from local `lazyvim-config`
revision `dc95d822dbc28cec770f07cc669f7aeaa198b755`, including its seven previously
unpublished LeetCode-mode commits. The owner approved including the local remote
clipboard helper and the explicit file-picker binding. The committed plugin lock
is the public seed; machine-local plugin-lock updates were not imported. Runtime
code was adapted for portable timeouts and writable state outside snapshots.
No Git history, authentication files, or local account state was imported.

Bootstrap now owns the shared baseline, configuration helpers and their tests.
The private dotfiles repository consumes a pinned public snapshot through
`configure.sh`, retaining workstation package installation, services, credentials
and overlays. Public configuration never sources the private installer or
requires its checkout.
