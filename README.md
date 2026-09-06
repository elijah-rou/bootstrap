# bootstrap

My terminal setup for machines without my SSH keys. Everything needed to start
is public and fetched over HTTPS. GitHub and AI provider login happen separately,
after installation.

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
| Tools | Git, delta, gh, SSH client, ripgrep, fd, fzf, bat, eza, jq, just |
| Neovim | [My LazyVim configuration](https://github.com/elijah-rou/lazyvim-config), downloaded over HTTPS; plugins install on first launch |
| Agents | Pi with my theme, extensions, prompts, agents and shared skills; Codex; Herdr and its Pi integration |

Node, Python and Bun remain in the base environment because the installer and
agent tools use them. Language development tools and LSPs are opt-in. The managed
Neovim overlay disables Mason downloads and uses available servers from PATH.

Prime, Meridian, Headroom, Docker, desktop apps and services are not installed.
Local web search and desktop clipboard features need host support or separate
setup. The optional `/usage` integration requires ccusage tools. The Headroom
launcher is retained for hosts where Headroom is installed separately.

## Add language toolchains

After the base setup, select any combination:

```sh
bash bootstrap.sh languages c
bash bootstrap.sh languages cpp rust go
bash bootstrap.sh languages elixir zig
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

## Development

From a cloned checkout, run `./scripts/validate`. Tests use temporary homes, stub package installation and
exercise real local Git checkouts. CI runs the same checks on Linux and macOS.
They do not install a workstation or start provider sessions.

When publishing runtime changes, push the tested runtime commit first, then update
`REVISION` and `ARCHIVE_SHA256` in `bootstrap.sh` to that commit and its codeload
archive digest. The downloaded archive is verified; existing extracted snapshots
are trusted local files, so use a separate checkout for development.

The initial runtime is a selected snapshot of my private dotfiles, with public
and portable defaults. Bootstrap runs independently. [SOURCE.md](SOURCE.md)
records the boundary; deciding how to consolidate the two repos comes next.
