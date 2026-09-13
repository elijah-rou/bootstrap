# bootstrap

Native, Bash-first terminal, Pi 0.85.1, Herdr, and bundled Neovim setup. The installer supports apt on Debian/Ubuntu, dnf on Fedora, pacman on Arch, and Homebrew on Apple Silicon macOS. It does not use Conda or Linuxbrew and does not require Python at runtime.

## Install

From a checkout:

```sh
./install.sh
```

Install or repair only pinned Pi and its Node/Bun runtime, configuration, extensions, skills, and launchers:

```sh
./install.sh pi
```

This targeted command does not install terminal core, Herdr, Neovim, parser/compiler dependencies, or shell configuration. Its component readiness is recorded independently, so a failed or partial run cannot claim full bootstrap readiness.

The public launcher downloads a pinned archive, verifies its SHA-256, then dispatches the same commands. `REVISION` and `ARCHIVE_SHA256` in `bootstrap.sh` are publication fields and intentionally remain unchanged until this runtime is published.

Core includes Git, Delta, GitHub CLI, the OpenSSH client, tmux, Herdr, ripgrep, fd, fzf, bat, eza, zoxide, jq, less, curl, Node, Bun, Neovim 0.12.5 or newer, Tree-sitter CLI 0.26 or newer, and a C compiler. Native packages are tried first. Node, Neovim, and Tree-sitter have pinned, checksum-verified official artifact fallbacks where stock versions are unusable. Bun uses its native package where available or its versioned official npm package in the owned prefix. No server/service, login-shell change, provider authentication, language toolchain, LSP, Zsh, or prompt is selected implicitly.

Run commands in the configured profile without an activation shell:

```sh
~/.local/bin/dev-shell bash
~/.local/bin/dev-shell pi --version
```

`scripts/bare-env.sh` is the shared path contract used by installation, offline configuration, and ordinary configured Bash/Zsh sessions. The profile isolates Pi configuration/sessions and Neovim data/cache/state, including workstation overlay mode; normal `pi` and `nvim` commands use it without `dev-shell` activation. Overlays do not implicitly select Zsh, Starship, Mason, or LSPs. Herdr's supported state root is `~/.config/herdr`; bootstrap adopts it only when absent, empty, or provably from an earlier managed config. Existing personal Herdr state blocks installation instead of being silently enrolled.

## Independent selections

Selections persist in the versioned installation record and survive core retries:

```sh
./install.sh --languages rust python
./install.sh --lsp rust-analyzer basedpyright
./install.sh --tools zsh starship codex
```

Languages: `c`, `cpp`, `rust`, `go`, `python` (uv), `typescript`, `elixir`, `zig`.

LSPs: `clangd`, `rust-analyzer`, `gopls`, `basedpyright`, `ruff`, `typescript-language-server`, `bash-language-server`, `elixirls`, `zls`.

Tools: `zsh`, `starship`, `codex`, `just`, `wget`, `unzip`, `shellcheck`, `ruff`, `headroom`.

Installing a language does not install its LSP, and installing an LSP does not grant permission to install the target toolchain. Missing implementation/runtime prerequisites are reported as blocked. Each successful LSP selection is written from `packages/catalog.json`, then real headless Neovim must initialize and attach the expected client and receive a protocol response. Mason and incidental PATH discovery remain disabled.

Neovim synchronizes pinned plugins, resolves the effective nvim-treesitter parser set, waits for compilation, and checks parser loading, highlighting queries, and folding. Unchanged reruns reuse installed parsers.

## Doctor, configuration, migration, and uninstall

```sh
./install.sh doctor
./configure.sh all --overlay /absolute/workstation --legacy-root /absolute/old-checkout
./install.sh migrate-legacy --yes
./install.sh enroll-project /absolute/path/below/home --yes
./install.sh uninstall --dry-run
./install.sh uninstall --yes
```

`configure.sh` is offline and unprivileged and selects no packages. It accepts `terminal`, `pi`, `codex`, `neovim`, or `all`, ordered `--overlay ABS_DIR` values, and one `--legacy-root ABS_DIR`. It needs Node, not Python. Overlay precedence remains unchanged, while workstation and bare Neovim profiles share the enrolled runtime/app roots and writable local state.

Legacy migration requires a provable managed profile. It copies legacy Pi state into the isolated profile and enrolls the exact old Pi root for cleanup. It deliberately preserves the old `~/.local/share/dotfiles/bare` prefix because separate Bun/Rust installations or user additions may live there. Ambiguous symlinks or unrelated Herdr state are refused.

Uninstall validates the journal, rejects path/symlink escapes and live recorded writers, previews destructive roots and eligible native packages, removes enrolled credentials/sessions/projects/caches/backups, restores exact pre-install shared files, and removes bootstrap-added packages only after dependency previews. Pre-existing and shared packages are preserved; no autoremove or downgrade is used. Changed shared files stop cleanup and retain recovery state for a retry. Repeated uninstall is successful. Uninstall is not secure erasure and cannot remove remote provider data, host snapshots, administrator copies, or audit logs. Revoke short-lived host credentials provider-side when appropriate.

## Development

```sh
PATH="/path/to/node/bin:/path/to/test-python/bin:$PATH" PYTHONUNBUFFERED=1 ./scripts/validate
bash tests/real_nvim_lsp_test.sh
```

Python is permitted for repository tests only. The validator checks native dispatch, ownership/recovery/uninstall, shell syntax, offline configuration, Pi/Codex contracts, and Neovim selection policy. The real LSP gate requires Neovim 0.12.5 and BasedPyright. Native package availability is also exercised by the Linux/macOS CI matrix; mocked package-manager tests prove dispatch but are not treated as availability evidence.
