# bootstrap

Native, Bash-first terminal, Pi 0.87.0, Herdr, and bundled Neovim setup. The installer supports apt on Debian/Ubuntu, dnf on Fedora, pacman on Arch, and Homebrew on Apple Silicon macOS. It does not use Conda or Linuxbrew and does not require Python at runtime.

## Install

From a checkout:

```sh
./install.sh
```

Bun installs Node-based packages on every platform, including Pi, Codex, TypeScript, and Node-based language servers. Node remains the execution runtime where required. Pi readiness checks verify that its self-update command uses the owned Bun installation; they do not perform an update or rewrite preserved personal settings. Existing npm installations outside the owned roots are preserved.

Install or repair only pinned Pi and its Node/Bun runtime, configuration, extensions, skills, and launchers:

```sh
./install.sh pi
```

This targeted command does not install terminal core, Herdr, Neovim, parser/compiler dependencies, or shell configuration. Its component readiness is recorded independently, so a failed or partial run cannot claim full bootstrap readiness.

The public launcher downloads a pinned archive, verifies its SHA-256, then dispatches the same commands. `REVISION` and `ARCHIVE_SHA256` in `bootstrap.sh` are publication fields and intentionally remain unchanged until this runtime is published. Before updating them, `node scripts/release-pin.mjs FULL_40_HEX_REVISION DOWNLOADED_ARCHIVE.tar.gz` verifies that the revision is a local commit, every archive entry carries that full revision prefix, and reports the actual SHA-256. It never guesses a digest or changes the publication pin.

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
./install.sh migration inspect
./install.sh migration prepare
./install.sh migration readiness
# After the operator stops Pi/Neovim, Herdr, and other writers:
./install.sh migration transfer --yes
./install.sh migration activate --yes
./install.sh migration verify
./install.sh migration retire --yes
./install.sh enroll-project /absolute/path/below/home --yes
./install.sh uninstall --dry-run
./install.sh uninstall --yes
```

`configure.sh` is offline and unprivileged and selects no packages. It accepts `terminal`, `pi`, `codex`, `neovim`, or `all`, ordered `--overlay ABS_DIR` values, and one `--legacy-root ABS_DIR`. It needs Node, not Python. Overlay precedence remains unchanged, while workstation and bare Neovim profiles share the enrolled runtime/app roots and writable local state.

Legacy migration is an explicit `inspect -> prepare -> transfer -> activate -> verify -> retire` lifecycle. Read the JSON inspection report before confirming transfer. `prepare` records the source inventory, installs core tools and the owned Pi CLI, and prepares and tests bundled Neovim privately. It does not switch shell hooks, launchers, shared configuration, or legacy state. Existing bundled Neovim profile, lockfile, extras, and writable JSON settings are preserved; external configurations, additional customizations, and unprepared LSP selections block preparation rather than being overwritten. A preparation inventory can be refreshed before transfer starts. Interrupted transfers retain their original recovery inventory.

`migration readiness` executes the real catalog core commands' availability checks, Node >=22.19.0, Neovim >=0.12.0, Tree-sitter >=0.26.1, the owned Pi CLI's exact 0.87.0 version, Herdr's version command, and headless bundled Neovim startup with a verification receipt. It returns `{schemaVersion:1, ready:true, phase, profiles:{pi,sessions,gh,neovim}}` only on success. Activation repeats these probes before switching any links. Preparation uses native packages when needed and verified private fallbacks; it does not require an already activated profile.

Transfer requires `--yes` and operator-owned quiescence. It maps `~/.pi/agent/sessions` to the private session root and preserves the entire previous Pi settings and personal-file inventory. GH file configuration moves into `private/gh`; its original configured source remains recorded across activated shells. OS keychain entries are neither extracted nor deleted. Files copy only into absent or identical destinations, including modes. Internal Pi links are remapped, completed-snapshot managed links are retargeted, and unknown external links or nonidentical destinations block before copying. Inspection discloses enrollment of the supported `~/.config/herdr` root for deletion on uninstall; transfer confirmation enrolls it without moving it, stopping Herdr, or overwriting its configuration.

Activation, rollback, and retirement require `--yes`; migration never stops writers automatically. Activation replaces only absent or proven managed Bash/Zsh hooks and Pi launchers (including `pih`), preserves a non-Conda Bash login profile with a reversible hook, selects the verified Neovim configuration, and switches the environment marker last. Custom shell files require explicit operator resolution. The installation journal owns all shared-target originals and restoration, including migration rollback and later uninstall.

Verification accepts legitimate post-cutover token, settings, and session writes and records a fresh quiescent receipt. Retirement requires that receipt to remain current. Rollback instead requires the immutable transfer baseline, refusing post-cutover additions, deletions, or changes rather than losing them. Retirement deletes only the legacy Pi root. Old GH configuration, Neovim configuration, tool prefixes, and external targets remain outside retirement. `migrate-legacy --yes` remains a compatibility notice, not an all-at-once migration.

Uninstall validates the journal, rejects path/symlink escapes and live processes identified by the owned runtime/profile, previews destructive roots and eligible native packages, removes enrolled credentials/sessions/projects/caches/backups, restores exact pre-install shared files, and removes bootstrap-added packages only after dependency previews. Pre-existing and shared packages are preserved; no autoremove or downgrade is used. Apt/dnf cleanup uses exact-name dpkg/RPM removal with dependency checks, not an expanding frontend transaction. Dpkg conffiles can remain and are reported; they are not blanket-purged. Dry-run does not stop servers or create cleanup locks/journals. Real cleanup targets only enrolled multiplexer sockets. Changed shared files stop cleanup and retain recovery state for a retry. One already-running Node controller completes all package effects and restoration checks even when its own runtime is removed; recovery state is deleted last. Repeated uninstall is successful. Uninstall is not secure erasure and cannot remove remote provider data, host snapshots, administrator copies, or audit logs. Revoke short-lived host credentials provider-side when appropriate.

## Development

```sh
# Requires the native core tools already available on PATH.
bash tests/prepare_migration_runtime.sh "$HOME/bootstrap-test-fixture"
BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE="$HOME/bootstrap-test-fixture" \
  PATH="/path/to/node/bin:/path/to/test-python/bin:$PATH" PYTHONUNBUFFERED=1 ./scripts/validate
bash tests/real_nvim_lsp_test.sh
# Requires preinstalled core commands, supported runtime versions, and Herdr:
bash tests/prepare_migration_runtime.sh /absolute/absent-fixture
BOOTSTRAP_MIGRATION_RUNTIME_FIXTURE=/absolute/absent-fixture python3 tests/migration_lifecycle_test.py
```

Migration activation tests require this cold-built real runtime fixture; without it, runtime-dependent cases are explicitly skipped. No CLI or Neovim validator is substituted.

Selected Python installs uv and a usable native Python 3 interpreter, or a uv-managed interpreter when native Python is unavailable. System Python is preserved. Selected Codex uses the private runtime root for auth, sessions, and configuration; unselected `~/.codex` and offline instruction-only links are not adopted.

The runtime sets documented npm, uv, Go, Mix, and Hex cache/configuration paths under enrolled roots. Go telemetry is different: Go does not support an environment override for its directory. Before Go or gopls runs, bootstrap enrolls the exact fresh OS telemetry directory. Pre-existing telemetry state blocks the selection unless explicitly enrolled; it is not silently adopted.

GitHub CLI login can store credentials in the shared OS credential store. `GH_CONFIG_DIR` does not isolate those entries, and bootstrap does not remove them. Installation does not authenticate. Stored GitHub CLI credentials are outside the cleanup guarantee until a storage policy is selected.

Python is permitted for repository tests only. The validator checks native dispatch, ownership/recovery/uninstall, shell syntax, offline configuration, Pi/Codex contracts, and Neovim selection policy. The real LSP gate requires Neovim 0.12.5 and BasedPyright. CI defines clean native Node/Bun/Pi/eza install-and-cleanup journeys for Ubuntu, Debian, Fedora, and Arch, plus verified binary/Pi smoke tests on Linux and macOS. Run `bash tests/native_artifact_smoke.sh --pi` for a disposable binary-only smoke. `bash tests/native_toolchain_smoke.sh --elixirls` checks real cache writes, managed Python, pinned ElixirLS cold preparation, and a prepared LSP attachment when Elixir/OTP and Neovim are already available. Native package mutation tests require an explicitly disposable CI environment; mocked package-manager tests are not availability evidence.
