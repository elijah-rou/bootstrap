# bootstrap

My terminal setup for machines without my SSH keys. Everything needed to start
is public and fetched over HTTPS. GitHub and AI provider login happen separately,
after installation.

## Install

Supports glibc Linux on x86_64/ARM64 and Apple Silicon macOS. You need a writable
home, Bash, curl, awk and a SHA-256 tool. Linux also needs `getconf`; macOS needs
Xcode Command Line Tools already installed. No sudo or Homebrew is required.

With Git already available:

```sh
git clone https://github.com/elijah-rou/bootstrap.git "$HOME/.local/share/bootstrap"
cd "$HOME/.local/share/bootstrap"
./install.sh preflight
./install.sh
~/.local/bin/dev-shell
```

Keep the checkout: your configuration links point into it. Tools live under
`~/.local/share/dotfiles/bare`. Existing configuration replaced by links is backed
up. Your login shell, existing Codex preferences and authentication stay in place.

## What you get

| Area | Included |
|---|---|
| Terminal | Bash/Zsh configuration, Starship, tmux, zoxide |
| Tools | Git, delta, gh, SSH client, ripgrep, fd, fzf, bat, eza, jq, uv, Ruff, ShellCheck, just |
| Neovim | [My LazyVim configuration](https://github.com/elijah-rou/lazyvim-config), downloaded over HTTPS; plugins install on first launch |
| Agents | Pi with my theme, extensions, prompts, agents and shared skills; Codex; Herdr and its Pi integration |
| LSPs | Python, TypeScript, Bash and Rust Analyzer |

Node, Python, Bun and TypeScript are dependencies of these tools and LSPs, so they
remain in the base environment. Project language toolchains are opt-in. Rust
Analyzer is installed as a [standalone conda-forge package](https://anaconda.org/conda-forge/rust-analyzer).
Full Rust project analysis and builds need Cargo and Rust; add the Rust toolchain
when working on a Rust project.

Prime, Meridian, Headroom, Docker, desktop apps and services are not installed.
Local web search and desktop clipboard features need host support or separate
setup. The optional `/usage` integration requires ccusage tools. The Headroom
launcher is retained for hosts where Headroom is installed separately.

## Add language toolchains

After the base setup, select any combination:

```sh
./install.sh languages c
./install.sh languages cpp rust go
```

C and C++ include compiler activation, make and pkg-config. Rust uses rustup and
includes Cargo, rust-src, rustfmt, Clippy and a C linker. Go comes from conda-forge.
Node and Python are already available as base dependencies. No toolchain is
removed from an existing machine.

Use `dev-shell` for builds so compiler variables are active:

```sh
dev-shell cargo test
```

Some Neovim plugins compile native code. Add `c` if a plugin or parser needs a
compiler. The installer does not build every plugin or install every language
selected in the editor's configuration.

## Check, retry and update

`./install.sh doctor` checks tools, the Neovim config link, Pi's version and the
Pi subagent package revision. It does not test provider login, all plugin/LSP
operations or project builds.

Rerun `./install.sh` to finish a partial setup. Clean Neovim checkouts update;
local edits are preserved. An interrupted run can leave an install lock: confirm
no installer is running before removing the exact lock directory in the error.
An incomplete environment or unexpected checkout is reported for manual recovery.

Update this checkout with `git pull --ff-only`, then rerun the installer. Package
versions can advance; this is a personal development environment, not a reproducible
build image. `./install.sh link` relinks configuration offline; `codex-link` only
relinks Codex instructions and shared skills.

## Development

Run `./scripts/validate`. Tests use temporary homes, stub package installation and
exercise real local Git checkouts. CI runs the same checks on Linux and macOS.
They do not install a workstation or start provider sessions.

The initial runtime is a selected snapshot of my private dotfiles, with public
and portable defaults. Bootstrap runs independently. [SOURCE.md](SOURCE.md)
records the boundary; deciding how to consolidate the two repos comes next.
