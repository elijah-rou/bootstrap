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

Core includes Git, Delta, GitHub CLI, the OpenSSH client, tmux, Herdr, ripgrep, fd, fzf, bat, eza, zoxide, jq, less, curl, Node >=22.19.0, Bun, Neovim 0.12.5 or newer, Tree-sitter CLI >=0.26.1, and a C compiler. Native packages are tried first. Node, Neovim, Tree-sitter, and Linux eza have pinned, checksum-verified official artifact fallbacks where stock packages are absent or unusable. Bun uses a native package or a directly downloaded official `@oven/bun-<platform>` binary archive, never the npm placeholder or package lifecycle scripts. Downloaded Bun and Node binaries run version checks before activation. No server/service, login-shell change, provider authentication, language toolchain, LSP, Zsh, or prompt is selected implicitly.

Run commands in the configured profile without an activation shell:

```sh
~/.local/bin/dev-shell bash
~/.local/bin/dev-shell pi --version
```

`scripts/bare-env.sh` is the shared path contract used by installation, offline configuration, and ordinary configured Bash/Zsh sessions. The profile isolates Pi configuration/sessions and Neovim data/cache/state, including workstation overlay mode; normal `pi` and `nvim` commands use it without `dev-shell` activation. Pi-only installs include a self-contained `~/.local/bin/pi` entrypoint; it invokes the owned CLI and passes the private session directory explicitly. Core adds a reversible Bash login-profile integration without changing the login shell. Overlays do not implicitly select Zsh, Starship, Mason, or LSPs. Herdr's supported state root is `~/.config/herdr`; bootstrap adopts it only when absent, empty, or provably from an earlier managed config. Existing personal Herdr state blocks installation instead of being silently enrolled.

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

Uninstall validates the journal, rejects path/symlink escapes and live processes identified by the owned runtime/profile, previews destructive roots and eligible native packages, removes enrolled credentials/sessions/projects/caches/backups, restores exact pre-install shared files, and removes bootstrap-added packages only after dependency previews. Pre-existing and shared packages are preserved; no autoremove or downgrade is used. Apt/dnf cleanup uses exact-name dpkg/RPM removal with dependency checks, not an expanding frontend transaction. Dpkg conffiles can remain and are reported; they are not blanket-purged. See [ownership tradeoffs](docs/ADR-002-native-ownership.md). Dry-run does not stop servers or create cleanup locks/journals. Real cleanup targets only enrolled multiplexer sockets. Changed shared files stop cleanup and retain recovery state for a retry. One already-running Node controller completes all package effects and restoration checks even when its own runtime is removed; recovery state is deleted last. Repeated uninstall is successful. Uninstall is not secure erasure and cannot remove remote provider data, host snapshots, administrator copies, or audit logs. Revoke short-lived host credentials provider-side when appropriate.

## Development

```sh
PATH="/path/to/node/bin:/path/to/test-python/bin:$PATH" PYTHONUNBUFFERED=1 ./scripts/validate
bash tests/real_nvim_lsp_test.sh
```

Selected Python installs uv and a usable native Python 3 interpreter, or a uv-managed interpreter when native Python is unavailable. System Python is preserved. Selected Codex uses the private runtime root for auth, sessions, and configuration; unselected `~/.codex` and offline instruction-only links are not adopted.

The runtime sets documented npm, uv, Go, Mix, and Hex cache/configuration paths under enrolled roots. Go telemetry is different: Go does not support an environment override for its directory. Before Go or gopls runs, bootstrap enrolls the exact fresh OS telemetry directory. Pre-existing telemetry state blocks the selection unless explicitly enrolled; it is not silently adopted.

GitHub CLI login can store credentials in the shared OS credential store. `GH_CONFIG_DIR` does not isolate those entries, and bootstrap does not remove them. Installation does not authenticate. Stored GitHub CLI credentials are outside the cleanup guarantee until a storage policy is selected.

Python is permitted for repository tests only. The validator checks native dispatch, ownership/recovery/uninstall, shell syntax, offline configuration, Pi/Codex contracts, and Neovim selection policy. The real LSP gate requires Neovim 0.12.5 and BasedPyright. CI defines clean native Node/Bun/Pi/eza install-and-cleanup journeys for Ubuntu, Debian, Fedora, and Arch, plus verified binary/Pi smoke tests on Linux and macOS. Run `bash tests/native_artifact_smoke.sh --pi` for a disposable binary-only smoke. `bash tests/native_toolchain_smoke.sh --elixirls` checks real cache writes, managed Python, pinned ElixirLS cold preparation, and a prepared LSP attachment when Elixir/OTP and Neovim are already available. Native package mutation tests require an explicitly disposable CI environment; mocked package-manager tests are not availability evidence.
