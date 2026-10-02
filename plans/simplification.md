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
   because `bootstrap.lock` must name a commit GitHub serves.
   1. Before changing anything: run dotfiles `scripts/bootstrap fetch`; keep `snapshots/` until
      step 7 passes (it is the rollback path). The Firecrawl key was purged on 2026-10-02.
   2. Quit every terminal, tmux server, Herdr, Pi, and Neovim. Running shells keep
      `NVIM_APPNAME=bootstrap-nvim` and old PATHs.
   3. Optionally `snapshots/6ee84fb…/install.sh migration retire --yes` to delete the legacy
      `~/.pi/agent` with the old safeguards. Every legacy session is already in
      `private/pi/sessions` (review B checked).
   4. Move aside (`mv`, not `rm`) the snapshot symlinks the new installer must edit or relink:
      `~/.bashrc`, `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.tmux.conf`, `~/.config/starship.toml`,
      `~/.config/dotfiles/`, and the old launchers in `~/.local/bin` (`pi`, `piw`, `pi-workspace`,
      `pih`, `pi-headroom`, `dev-shell`, `modelusage`, and their `.bak.*` links). Remove the old
      `bare-env.sh` and `workstation/zshenv` lines from `~/.bash_profile` and the snapshot include
      from `~/.gitconfig`.
   5. Run dotfiles `./install.sh` (bootstrap with zsh, starship, tmux, codex plus overlays), then
      `./install.sh link`.
   6. Neovim now uses `~/.config/nvim` (dotfiles `neovim/`, which carries the live lockfile) and
      reinstalls plugins into `~/.local/share/nvim`; run `:Lazy restore` once.
   7. Verify in a new terminal: `type -a pi piw node codex gh` shows `tools/bin` first;
      `echo $CODEX_HOME $PI_CODING_AGENT_DIR` gives `~/.codex` and the private Pi root;
      `ssh localhost 'command -v pi; echo $CODEX_HOME'`; a Herdr pane runs `pi`; `gh auth status`
      and `git ls-remote` (approve the keychain prompt for the new gh binary once); both
      repositories' `doctor`.
   8. Clean up: `~/.config/bootstrap-nvim`, `~/.local/share/bootstrap-nvim`,
      `~/.local/share/bootstrap/{neovim,private/neovim,tools/tools,snapshots}`, dangling links in
      `tools/bin`, `~/.local/state/bootstrap/`, and the moved-aside files from step 4.
   Known gap: the Meridian LaunchAgent PATH has no `tools/bin`; check whether it starts `pi`.

7. [ ] agent-kit split (2026-10-02): instructions, skills, Pi extensions, and Claude mods moved to
   the public `elijah-rou/agent-kit` (Claude mods ported to Bun TypeScript). Pi, Claude, Codex, and
   Herdr became opt-in tools. Remaining: promote branch `agent-kit-split`; dotfiles selects
   `pi claude herdr`, sets `CLAUDE_CONFIG_DIR=~/.claude`, adds a `claude-settings.json` overlay, and
   points its checks at `tools/agent-kit`; the cutover also removes old links in
   `private/pi/agent/{extensions,skills,prompts,themes}`, `~/.claude`, and `~/.agents/skills` that
   point into the `claude-port` worktree or old snapshots, then retires that worktree.

## Evidence (2026-10-02, branch `simplify`)

- Round-trip (install, rerun, doctor, signed-in gh, uninstall, HOME and package diff) passed on
  ubuntu:24.04 and debian:13 without sudo, ubuntu:24.04 as root with every selection, fedora:42 as
  root, and macOS with a disposable HOME. Elixir and ElixirLS passed in an earlier Ubuntu run.
- CI (run 37045320285, commit 48ba133) passed the round-trip natively on ubuntu:24.04 (root with
  every selection, and without sudo), debian:13, fedora:42, archlinux, and macOS, plus static
  checks. CI found and fixed three leftovers local runs missed: Homebrew's download cache,
  `~/.homebrew`, and the `/root/.ssh` that Arch's systemd-tmpfiles creates.
- Bun gate: Pi 1.0.0 with all extensions and packages reached a provider request under Bun;
  basedpyright, typescript-language-server, and bash-language-server run through the `node`
  wrapper. Interactive Pi TUI was not exercised.
- Dotfiles: its validator passes against this branch; a disposable macOS HOME ran dotfiles
  `bare`, `link --offline`, `bare-doctor`, and `uninstall`; bootstrap removed everything it
  owned and only dotfiles-owned links remained.
- `pi/tests/lsp-diagnostics.test.mjs` settle test: failed 6 of 6 concurrent full-suite runs on
  `main` and 0 of 6 after giving it a load-independent timeout.
- Review: two independent reviews (install/purge safety; dotfiles contract and cutover). Their P0/P1
  findings were fixed in `36361bf` and dotfiles; `tests/uninstall_edges.sh` fails on the pre-fix
  commit and passes after. Round-trips reran green on Ubuntu (root and user), Fedora, and macOS.

## Open items

- Resolved: piw stays here; `pi-headroom` and `modelusage` move to dotfiles. Helix finds its
  runtime through the symlink. Herdr is pinned by binary. Herdr no longer forces zsh.
- Pi config still uses per-file links inside the private root; they need no state records.
