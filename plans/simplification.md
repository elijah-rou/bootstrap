# Bootstrap simplification

## Goal

`ssh -> git clone -> ./install.sh -> done -> ./install.sh uninstall`. The repository stays small:
one installer script, one pin catalog, shell/Pi config, and one round-trip test. Uninstall is a
purge suitable for temporary or foreign boxes.

## Decisions (owner-approved 2026-10-02)

- Uninstall purges everything bootstrap created: tools, Pi/Codex/gh auth and sessions, shell
  history it redirected, packages it installed through the system package manager, and the
  runtime root. Pre-existing files it changed are restored.
- Keep the private-root relocation; it is what makes purge a directory delete.
- Delivery is `git clone`. No snapshot launcher, archive pins, or `snapshots/` directory.
- Bun is the only JavaScript runtime bootstrap installs. A `node` shim to Bun covers
  `#!/usr/bin/env node` entrypoints.
- Editor in core is evil-helix (prebuilt grammars; no compiler or plugin sync).
- Neovim/LazyVim and other genuinely optional personal setup move to the private dotfiles repo.
  Install-customizing selections (languages, LSPs, tools) stay here.
- tmux is optional. Herdr is the core multiplexer.
- Pi configuration stays in this repository; it is not converted to a Pi package.
- Migration code is removed after the workstation cutover. No new migration engine: on-disk
  data paths stay the same.

## Target design

Layout at runtime (unchanged data paths so the workstation needs no data migration):

```
~/.local/share/bootstrap/
  tools/            binaries, bun, cargo/rustup, go, uv, language archives; tools/bin on PATH
  private/          pi/agent, pi/sessions, gh, codex, bash/zsh history, tmux sockets (0700)
  state.tsv         one record per side effect, replayed in reverse by uninstall
```

Repository:

```
install.sh          install [--languages ..] [--lsp ..] [--tools ..] | doctor | uninstall [--yes]
catalog.tsv         name, version, platform, url, sha256, path in archive (no JSON parser needed)
shell/              env.sh (PATH and tool homes), bashrc, zshrc, starship.toml
config/             gitconfig, tmux.conf, herdr, helix, ripgrep
pi/  codex/         unchanged content; linking simplified
tests/roundtrip.sh  container journey: snapshot HOME + package list, install, doctor, uninstall, diff
```

Mechanisms:

- Core tools are pinned user-space release binaries (static/musl on Linux where offered):
  bun, herdr, evil-helix, rg, fd, fzf, bat, eza, zoxide, jq, delta, gh. Pi via `bun install`.
- System prerequisites (git, curl, tar, ssh, less) are checked, not installed. Selections that
  need the system package manager (C compiler, tmux, zsh, elixir) use it only when root or sudo is
  available; otherwise they report blocked. Packages added are recorded by diffing the installed
  package list before and after the transaction, and uninstall removes exactly that set.
- Shell integration appends a marked block to the existing rc files instead of replacing them;
  uninstall deletes the block. Whole-file replacement (with backup) only where a block is
  impossible.
- `state.tsv` records: `block FILE`, `link TARGET [BACKUP]`, `package BACKEND NAME`,
  `selection GROUP NAME`. Bash reads it; no Node helper.
- Uninstall order: `gh auth logout` per host, stop bootstrap's Herdr/tmux servers, replay
  `state.tsv` in reverse, remove recorded packages, delete the root, print the checkout path for
  manual removal.
- One lock (`mkdir` with PID file and stale-PID check).
- Doctor: command presence and versions only.
- Configuration precedence: flag, then `BOOTSTRAP_ROOT` environment variable, then default.

Contract for the private dotfiles repo: it pins a bootstrap commit, runs `install.sh`, then layers
its own files. Bootstrap's config sources optional local files (`~/.config/bootstrap/local.sh`,
`[include] ~/.config/bootstrap/local.gitconfig`, a Pi settings overlay) so dotfiles links files
instead of passing `--overlay` arguments.

Size budget: `install.sh` at most about 600 lines; `tests/` at most about 300 lines.

## Slices

1. [x] Spine: `install.sh` with root layout, `state.tsv`, lock, catalog downloads for core
   binaries, Bun plus node shim, Pi plus Pi config links, shell blocks, doctor, uninstall purge
   including gh logout. Acceptance: round-trip test passes in Ubuntu containers with and without
   sudo, leaving HOME and the package list identical to the baseline.
2. [x] Selections: languages, LSPs, tools from the catalog; system-package path with diff
   recording. Acceptance: round-trip with selections on Ubuntu, Fedora, Arch; macOS install and
   uninstall on the workstation in a disposable HOME.
3. [x] Bun-only gate: real Pi session with extensions and packages, Codex, and Node-shebang LSPs
   (basedpyright, bash-language-server, typescript-language-server) under the Bun shim.
4. [x] Delete the old machinery: `bootstrap.sh`, `configure.sh`, `scripts/state-helper.mjs`,
   migration helpers, snapshot ownership, readiness state, Neovim bundle, old tests, completed
   plans. Rewrite README and CI around the round-trip test.
5. [x] Dotfiles (local branch `bootstrap-simplify`, not pushed): Neovim, `pi-headroom`, and
   `modelusage` moved there; `bootstrap.lock` is a commit checked out by `scripts/bootstrap`;
   workstation and local overlays render into `~/.config/bootstrap/`; offline relink uses
   bootstrap's `install.sh link`; workstation keeps `CODEX_HOME=~/.codex`.
6. [ ] Workstation cutover with the owner present. Publishing the bootstrap branch comes first,
   because `bootstrap.lock` must name a commit GitHub serves. Then, with Pi, Herdr, and Neovim
   stopped:
   1. Optionally `~/.local/share/bootstrap/snapshots/6ee84fb…/install.sh migration retire --yes`
      to delete the legacy `~/.pi/agent` with the old safeguards.
   2. Replace the snapshot symlinks that the new installer must edit or relink: `~/.bashrc`,
      `~/.zshrc`, `~/.zshenv`, `~/.zprofile` (block edits refuse symlinked files), and remove old
      launchers in `~/.local/bin` (`pi`, `piw`, `pi-workspace`, `pih`, `pi-headroom`, `dev-shell`,
      `modelusage`, and their `.bak.*` links) and `~/.config/dotfiles/`.
   3. Run dotfiles `./install.sh` (bootstrap with zsh, starship, codex plus overlays), then
      `./install.sh link`.
   4. Neovim moves from the `bootstrap-nvim` app name to `~/.config/nvim`; plugins reinstall into
      `~/.local/share/nvim`. Remove `~/.config/bootstrap-nvim`, `~/.local/share/bootstrap-nvim`,
      `~/.local/share/bootstrap/neovim`, and `~/.local/share/bootstrap/private/neovim` afterwards.
   5. Remove `~/.local/state/bootstrap/{install.json,migration.json,neovim-backups}`, the
      `snapshots/` directory, and dangling links in `tools/bin`; run `./install.sh doctor` in
      both repositories.

## Evidence (2026-10-02, branch `simplify`)

- Round-trip (install, rerun, doctor, signed-in gh, uninstall, HOME and package diff) passed on
  ubuntu:24.04 and debian:13 without sudo, ubuntu:24.04 as root with every selection, fedora:42 as
  root, and macOS with a disposable HOME. Elixir and ElixirLS passed in an earlier Ubuntu run.
- Arch could not run locally: Bun `install` segfaults under amd64 emulation on Apple Silicon. CI
  runs it natively.
- Bun gate: Pi 1.0.0 with all extensions and packages reached a provider request under Bun;
  basedpyright, typescript-language-server, and bash-language-server run through the `node`
  wrapper. Interactive Pi TUI was not exercised.
- Dotfiles: its validator passes against this branch; a disposable macOS HOME ran dotfiles
  `bare`, `link --offline`, `bare-doctor`, and `uninstall`; bootstrap removed everything it
  owned and only dotfiles-owned links remained.
- `pi/tests/lsp-diagnostics.test.mjs` "fake LSP clean result settles before timeout" fails under
  heavy machine load on this branch and on `main`; it passes alone.

## Open items

- Resolved: piw stays here; `pi-headroom` and `modelusage` move to dotfiles. Helix finds its
  runtime through the symlink. Herdr is pinned by binary. Herdr no longer forces zsh.
- Pi config still uses per-file links inside the private root; they need no state records.
