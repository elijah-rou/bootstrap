# bootstrap

Shared terminal, Pi and Codex configuration, with a user-local installer for
machines without my SSH keys. Everything needed to start is public and fetched
over HTTPS. GitHub and AI provider login happen separately, after installation.

## Install

Supports glibc Linux on x86_64/ARM64 and Apple Silicon macOS. You need a writable
home, Bash, curl, awk and a SHA-256 tool. Linux also needs `getconf`; macOS needs
Xcode Command Line Tools already installed. No sudo or Homebrew is required.

Download and run the launcher; Git is not needed yet:

```sh
curl -fL https://raw.githubusercontent.com/elijah-rou/bootstrap/main/bootstrap.sh -o bootstrap.sh && bash bootstrap.sh
~/.local/bin/dev-shell
```

The launcher downloads a specific public commit, verifies the archive's SHA-256,
and retains it under `~/.local/share/bootstrap/snapshots/`. Keep that directory:
your configuration links point into it. The launcher reuses a completed snapshot
on retry. `bash bootstrap.sh fetch` downloads and verifies it without installing
packages; `bash bootstrap.sh preflight` then checks host prerequisites.

Tools live under `~/.local/share/dotfiles/bare`. Existing configuration replaced
by links is backed up. Your login shell, existing Codex preferences and
authentication stay in place. If you cloned this repo over HTTPS instead, run
`./install.sh` from the checkout.

## What you get

| Area | Included |
|---|---|
| Terminal | Bash/Zsh configuration, Starship, tmux, zoxide |
| Tools | Git, delta, gh, SSH client, ripgrep, fd, fzf, bat, eza, jq |
| Neovim | [My LazyVim configuration](https://github.com/elijah-rou/lazyvim-config), downloaded over HTTPS; plugins install on first launch |
| Agents | Pi with my theme, extensions, prompts, agents and shared skills; Herdr and its Pi integration |

Bun installs all JavaScript packages, including Pi, optional Codex and LSPs.
Node remains a runtime dependency: Pi's pinned subagent extension explicitly
launches Node child processes. Python supports the configuration helpers.
Language development tools and LSPs are opt-in. The managed
Neovim overlay disables Mason downloads and uses available servers from PATH.

Prime, Meridian, Headroom, Docker, desktop apps and services are not installed.
Local web search and desktop clipboard features need host support or separate
setup. The optional `/usage` integration requires ccusage tools. The Headroom
launcher is retained for hosts where Headroom is installed separately.

## Update Herdr separately

From a checkout, run `./install.sh herdr`. This installs or updates Herdr, installs its Pi
integration when Pi is available, and writes Zsh completions. It does not start
a service, configure SSH or Tailscale, or register any `herdr machine` entries.
Machine registration remains an explicit user action.

## Add optional tools

After the base setup, use `--tools` or `-t`:

```sh
bash bootstrap.sh --tools codex just wget
bash bootstrap.sh -t unzip
```

Codex installation also links its instructions and skills, preserving existing
preferences and authentication. `just`, `wget` and `unzip` install independently.
The Elixir selection includes `unzip` because ElixirLS needs it. Existing copies
of optional tools are preserved when you rerun the base install.

## Add language toolchains

After the base setup, select any combination with `--languages` or `-l`:

```sh
bash bootstrap.sh --languages c
bash bootstrap.sh --languages cpp rust go
bash bootstrap.sh -l elixir zig
```

Each selection installs its language tools and matching LSP:

| Selection | Language tools | LSP |
|---|---|---|
| `c` | C compiler, make, pkg-config | clangd |
| `cpp` | C++ compiler, make, pkg-config | clangd |
| `rust` | rustup, Cargo, rust-src, rustfmt, Clippy, C linker | Rust Analyzer |
| `go` | Go | gopls |
| `python` | uv, Ruff; Python is already available | BasedPyright, Ruff |
| `typescript` | TypeScript; Node is already available, also supports JavaScript | TypeScript Language Server |
| `bash` | ShellCheck; Bash is a host prerequisite | Bash Language Server |
| `elixir` | Elixir 1.20.4, Erlang/OTP 29.0.6, Mix | ElixirLS 0.31.1 |
| `zig` | Zig 0.16.0 | ZLS 0.16.0 |

[ElixirLS](https://github.com/elixir-lsp/elixir-ls/releases/tag/v0.31.1) compiles
into Mix's cache during installation, requiring network access. Its release
archive and the platform-specific [ZLS binaries](https://github.com/zigtools/zls/releases/tag/0.16.0)
are checksum-verified. Zig and ZLS use matching releases. No source checkout in
`~/Projects` is needed. Existing toolchains and LSPs are not removed.

Use `dev-shell` for builds so compiler variables are active:

```sh
dev-shell cargo test
```

Some Neovim plugins compile native code. Add `c` if a plugin or parser needs a
compiler. The installer does not build every plugin or install every language
selected in the editor's configuration.

## Check, retry and update

`bash bootstrap.sh doctor` checks tools, the Neovim config link, Pi's version and the
Pi subagent package revision. It does not test provider login, all plugin/LSP
operations or project builds.

Rerun `bash bootstrap.sh` to finish a partial setup. Clean Neovim checkouts update;
local edits are preserved. An interrupted run can leave an install lock: confirm
no installer is running before removing the exact lock directory in the error.
An incomplete environment or unexpected checkout is reported for manual recovery.

To update, download the launcher again and rerun it. New launchers can select a
new snapshot; earlier snapshots remain in place. Cloned checkouts update with
`git pull --ff-only`. Package versions can advance; this is a personal development environment, not a reproducible
build image. `bash bootstrap.sh link` relinks configuration offline; `codex-link` only
relinks Codex instructions and shared skills.

## Configure an existing workstation

Bootstrap owns the shared shell, Pi and Codex baseline and the helpers that
apply it. A workstation repository can consume a pinned public snapshot and
supply its own packages, desktop services, credentials and configuration overlays.
The default bare installation remains independent of that workstation repository.

From a checkout or retained snapshot, run:

```sh
./configure.sh all \
  --overlay /absolute/path/to/workstation \
  --overlay /absolute/path/to/local \
  --legacy-root /absolute/path/to/previous-dotfiles
```

`configure.sh` requires Python 3 and accepts `terminal`, `pi`, `codex`, `neovim`
or `all`. It only writes user configuration. It does not install packages, access
the network, change the login shell, activate the bare environment or install the
Neovim Mason override. Neovim configuration only relinks an existing checkout.

Each `--overlay` directory must exist. Paths must be absolute and cannot be `/`.
Repeated overlays apply from low to high precedence, after the public baseline.
An overlay may omit any of these files:

| Overlay file | Behavior |
|---|---|
| `gitconfig` | Included after the public Git configuration, in overlay order |
| `env.sh` | Sourced by Bash and Zsh, in overlay order |
| `zshenv` | Sourced as workstation additions to the public Zsh baseline |
| `repos.conf` | The highest-precedence existing file supplies the repository list |
| `pi-settings.json`, `pi-models.json` | Objects merge recursively; arrays and scalar values replace earlier values |

The generated Git and shell files refer to their original sources, so retain the
snapshot and overlay directories. Pi settings and models are materialized as
local files. Pi authentication and Codex preferences, hooks and authentication
remain untouched. The Pi target also links `pi-workspace`, `piw` and the Headroom
launcher; the terminal target links `modelusage`.

The optional `--legacy-root` identifies known links from a previous managed
checkout. It can name a directory that no longer exists. Configuration migrates
or removes matching managed links and preserves unrelated links. Existing files
replaced by configuration are backed up. Retries reuse matching output; overlapping
runs fail with a lock path to inspect before retrying.

Package installation stays separate:

```sh
./install.sh neovim       # Clone or update the workstation editor checkout
./install.sh pi-packages  # Install packages from materialized Pi settings
./install.sh pi-version   # Print the pinned Pi CLI version
./install.sh pi-check     # Check repository, rendered and installed subagent pins
```

`neovim` honors `NVIM_CONFIG_REPO_URL` and `NVIM_CONFIG_CHECKOUT_DIR`, preserving
local edits. Its default checkout is
`$XDG_DATA_HOME/dotfiles/lazyvim-config`, with `~/.local/share` as the data-home
fallback. This workstation command does not add the bare Mason override.

## Development

From a cloned checkout, run `./scripts/validate`. Tests use temporary homes,
stub package installation and exercise local Git checkouts. The validator includes
all `pi/tests/*.test.mjs` files, offline configuration and Codex linking checks.
CI runs these checks on Linux and macOS, plus installed Pi and Codex consumer
checks on Linux using isolated dependencies installed by Bun.

Installed consumer checks are opt-in locally. Set these paths to your test
dependencies, then run `./scripts/validate --runtime` with Bun and Codex on PATH:

| Variable | Installed source |
|---|---|
| `PI_FAST_RUNTIME_SOURCE` | The pinned `@earendil-works/pi-coding-agent` package directory |
| `PI_BASH_OPERATIONS_TEST_RUNTIME_PATH` | Its `dist/core/tools/bash.js` |
| `PI_SKILLS_TEST_RUNTIME_PATH` | Its `dist/core/skills.js` |
| `PI_WEB_ACCESS_SSRF_MODULE` | `pi-web-access/ssrf-protection.ts` |
| `PI_SUBAGENTS_TEST_RUNTIME_SOURCE` | The subagent checkout pinned in `pi/settings.json` |

Without those paths, the default run reports skipped installed Pi checks.
Runtime checks exercise loaders, package contracts, subprocess cancellation,
provider request serialization and native Codex discovery without provider
requests or authentication.

After installing optional language tools, the separate bare-environment smoke
test exercises selected compilers and LSP initialization:

```sh
dev-shell python3 tests/bare_runtime_test.py c rust python typescript bash
```

Select only languages you installed; add `--codex` to check its optional CLI.
This journey requires an installed bare environment and is not part of default CI.

When publishing runtime changes, push the tested runtime commit first, then update
`REVISION` and `ARCHIVE_SHA256` in `bootstrap.sh` to that commit and its codeload
archive digest. The downloaded archive is verified; existing extracted snapshots
are trusted local files, so use a separate checkout for development.

[SOURCE.md](SOURCE.md) records the initial import and current ownership boundary.
