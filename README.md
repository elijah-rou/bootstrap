# bootstrap

Sets up a terminal development environment on a machine you may not own, and removes it again.

```sh
git clone https://github.com/elijah-rou/bootstrap.git ~/bootstrap
~/bootstrap/install.sh
# ...work...
~/bootstrap/install.sh uninstall
rm -rf ~/bootstrap
```

Supported hosts: glibc Linux on x86_64 or aarch64, and Apple Silicon macOS. Prerequisites are git,
curl, tar, gzip, and sha256sum or shasum. No sudo is needed for the core install.

## What install does

- Downloads pinned, checksum-verified binaries into `~/.local/share/bootstrap/tools`:
  Bun, Pi, Herdr, evil-helix (`hx`), ripgrep, fd, fzf, bat, eza, zoxide, jq, delta, and gh
  (eza comes from Homebrew on macOS, where no release binary exists).
  Bun is the only JavaScript runtime; `node` runs Bun.
- Keeps credentials, sessions, history, and caches in `~/.local/share/bootstrap/private`.
  Pi, Codex, gh, shell history, tmux sockets, and tool caches all point there.
- Adds marked blocks to `~/.bashrc`, the Bash login profile, and `~/.gitconfig`, and links Helix,
  Herdr, Pi router, and git-ignore configuration. Existing files it would replace are moved to
  `*.bootstrap-backup`.
- Records each change in `~/.local/share/bootstrap/state.tsv`.

Rerunning `install.sh` converges: it updates to the pinned versions in `catalog.tsv` and
reinstalls recorded selections. `install.sh link` reapplies only the configuration, offline.

## Selections

```sh
./install.sh --languages rust go python --lsp rust-analyzer gopls basedpyright --tools zsh tmux
```

`./install.sh --help` lists every name. Selections are remembered. Most come from user-space
downloads; a few (C/C++ compilers, Elixir, clangd on Linux, tmux, zsh) need the system package
manager and therefore root, sudo, or Homebrew. Without those they are reported as unavailable.

Language servers are found on `PATH` by Helix; `config/helix/languages.toml` holds the overrides.

## Uninstall

`./install.sh uninstall` signs gh out of every account (removing keyring tokens), stops Herdr
and tmux servers it started, and purges the system packages it installed. Then it removes its
blocks and links, restores backups, deletes caches and directories it created, and deletes the
bootstrap root. Packages and files that existed before install are left alone, and so is a file
you put in place of one of its links. Use `--yes` when not on a terminal.

Package removal comes first and never cascades: if something installed since depends on a
package, or the account can no longer run sudo, uninstall stops before changing anything else.
Any failure keeps `state.tsv`, so fixing the cause and rerunning finishes the job.

Uninstall cannot reach copies made by others with access to the machine, provider-side sessions,
or machine snapshots. On a machine you do not control, prefer short-lived or narrowly scoped
credentials. A `CODEX_HOME` set before install is used as is, so Codex credentials there are not
purged. Worktrees made with `piw` (under `~/piw-worktrees`) are your work and are kept.

## Local customization

Install reads optional files from `~/.config/bootstrap/`: `env.sh`, `bashrc`, `zshrc`,
`gitconfig`, `pi-settings.json`, and `pi-models.json` (merged over `pi/settings.json` and
`pi/models.json`). The private dotfiles repository links its workstation additions there.

## Maintenance

- `scripts/pin NAME VERSION` moves a catalog entry to a new version and records its checksums.
- `scripts/validate` runs static checks, the offline link and uninstall edge cases, and the Pi
  configuration tests (needs Node, shellcheck, and Python).
- `tests/container.sh IMAGE root|user [install arguments...]` runs the install, rerun, doctor,
  and uninstall round-trip in a container and fails if HOME or the package list changed.
  `tests/roundtrip.sh` does the same on the current machine for a disposable account.
