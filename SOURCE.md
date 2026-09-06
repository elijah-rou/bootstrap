# Source snapshot

Initial runtime imported from dotfiles commit `9ffe95556fba7cb5a2d43450d81d333aa544a692`.

This repository contains the selected terminal, Pi, Codex, Neovim setup, and bare
installer files. It has no runtime dependency on the private dotfiles repository.
Workstation installers, secrets, local overlays, account state, desktop configs,
and source history are excluded.

The public Git config omits local checkout URL rewrites. Shell startup omits
the unrelated Moshi token loader. Pi omits the Anthropic
override for the workstation-only Meridian proxy. Optional local web search still
requires a separately configured service. Language toolchains and their LSPs are opt-in here. A managed Neovim overlay
disables automatic Mason downloads and uses the selected servers from PATH.

Consolidation with dotfiles is intentionally deferred. The copied helpers remain
recognizable so a later ownership decision does not require reconstructing them.
