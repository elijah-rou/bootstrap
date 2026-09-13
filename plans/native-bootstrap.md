# Native bootstrap, independent extras, and complete uninstall

## Outcome and authority

Replace the Conda-based bootstrap with native host packages, a Bash-first environment, pinned Pi configuration, and the bundled Neovim configuration. Extras remain explicitly selected. Uninstall must remove bootstrap-associated personal data so the setup can be used on borrowed machines.

This document is the implementation plan requested by the user. Requirements below are accepted unless marked **open** or **proposed**. No native migration or uninstall has been implemented. This planning request does not authorize executing an uninstall, changing a remote machine, or publishing the migration.

Inspected baseline: bootstrap `24c2cb2c9e018689efa12dc4bfb857e296ab7299`. The earlier Conda package-name fix in `packages/bare.txt`, `tests/bare_install_test.sh`, and `README.md` is uncommitted and superseded. Reconcile those exact edits in the first implementation slice; do not publish them as the requested solution. Preserve unrelated dotfiles work, including `agent-planning-feedback.md`.

## 1. Installation contract

### Core and extras

| Group | Default contents | Boundary |
|---|---|---|
| CLI tools | Git, Delta, GitHub CLI, OpenSSH client, tmux, Herdr, ripgrep, fd, fzf, bat, eza, zoxide, jq, less, curl | Native packages where available; no automatic SSH server, machine registration, or service activation |
| Pi | Pinned upstream `@earendil-works/pi-coding-agent`, Node/Bun, shared settings, instructions, agents, prompts, theme, extensions, and skills | Do not substitute a fork or alter authentication/model preferences implicitly |
| Neovim | Native `neovim`, bundled configuration, plugin defaults, keybindings, and interview-mode support | Validate the version needed by the complete configuration; preserve local editor state during install/update |
| Shell | First-class Bash configuration and portable shared environment/helpers | Preserve the existing login shell; no dependency on Zsh, Starship, Conda, or an activation shell |
| Language extras | C, C++, Rust, Go, Python/uv, TypeScript, Elixir/Erlang, Zig | Installing a language never implicitly selects an LSP |
| LSP extras | clangd, rust-analyzer, gopls, BasedPyright, Ruff, TypeScript Language Server, Bash Language Server, ElixirLS, ZLS | Independently selectable without the target language/toolchain |
| Other extras | Zsh and its plugins, Starship, Codex, just, wget, unzip, ShellCheck, Ruff CLI, Headroom, search/usage backends | Explicit opt-in; an installed Pi integration does not select its external application/service |

The Pi package set remains the configured immutable sources: `pi-subagents`, `pi-web-access`, `pi-privileged-operations`, `pi-sub-limits`, `pi-effort`, and `pi-unveil`. Repository extensions and shared skills remain installed. An unavailable optional backend must be reported accurately rather than treated as a core installation failure or silently installed.

Node/Bun are core runtime dependencies, not optional language development selections. Bootstrap must not require or explicitly install Python for core setup. Replace Python-based installer/configuration helpers before removing Python from base installation and doctor checks. Do not remove existing system Python, including Python used by the host package manager. Python used only by repository tests may remain a development dependency.

### Package and shell policy

Use apt on supported Ubuntu/Debian releases, dnf on Fedora, pacman on Arch, and Homebrew on macOS. No Conda and no implicit Linuxbrew fallback. A missing native package or insufficient candidate version is an explicit outcome, not permission to install from an arbitrary repository, AUR package, or download script.

Disable optional package recommendations/weak dependencies where necessary to prevent unselected extras from being installed. Keep required native dependencies explicit in the transaction preview; if a core package requires a supposedly optional language, resolve that conflict before installation.

Package names and executable names are separate catalog fields. For example, GitHub CLI uses `github-cli` on Arch; Ubuntu's `fd-find` supplies `fdfind`. Compatibility links belong in an owned user bin directory and must not replace unrelated executables.

Keep shared PATH/environment and portable helpers separate from shell-specific completions, keybindings, and prompts. Configure Bash fully, not as a degraded Zsh fallback. Zsh and Starship are independent extras; an existing Zsh user must not be switched to Bash. No `chsh` during ordinary installation.

### Proposed command surface

These commands are design targets, not currently implemented options. Retain existing compatible entry points where practical and document deliberate changes.

| Intent | Proposed interface | Contract |
|---|---|---|
| Install core | `./install.sh` | Reconcile only core plus previously recorded explicit selections |
| Add toolchains | `./install.sh --languages rust python` | Add selected toolchains, not their LSPs |
| Add servers | `./install.sh --lsp rust-analyzer basedpyright` | Install/configure/check selected servers without silently adding target toolchains |
| Add other tools | `./install.sh --tools zsh starship codex` | Add only selected extras and declared dependencies |
| Configure only | `./configure.sh ...` / offline link entry points | No package installation, fetching, or privilege escalation |
| Inspect readiness | `./install.sh doctor` | Report selected components, versions, configuration, and missing prerequisites |
| Preview cleanup | `./install.sh uninstall --dry-run` | Read-only exact cleanup plan and conflicts; no secret values |
| Uninstall | `./install.sh uninstall` | Confirm destructive cleanup of enrolled personal data and owned artifacts |
| Optional package removal | `./install.sh uninstall --packages` | Separately preview/confirm eligible native package removal |

Selections must persist across retries and updates. Running the core installer again must not remove explicitly installed extras. Reject unknown selectors before any mutation. Final flag names and package-removal defaults are open until the public command contract is recorded.

## 2. Selected LSPs must work in Neovim

The current `neovim/bootstrap.lua` enables servers based on executable availability and disables Mason installation. Replace availability-only activation with **explicit selection plus readiness**. A server found incidentally on PATH is not automatically selected.

Keep one catalog mapping each selector to its package/source, executable and arguments, Neovim server ID, filetypes, project-root rules, and prerequisites. Generate or consume the Neovim selection data from that catalog rather than maintaining independent name maps in the installer and Lua configuration. Preserve local server settings where they do not conflict with selection policy.

For each selected server:

1. Resolve its supported installation source and verify required server runtimes. Do not infer permission to install the target language/compiler.
2. Install the server and write owned selection/configuration state.
3. Start real headless Neovim with a bounded fixture project for the relevant filetype.
4. Verify the expected client starts, completes initialization, attaches to the fixture buffer, and answers a suitable request or publishes an expected diagnostic when the server supports a deterministic fixture.
5. Exercise ordinary startup to prove unselected servers and Mason installers do not run.

Distinguish `installed`, `configured`, `verified`, and `blocked by prerequisite`. Neither binary presence nor a clean process exit proves a functioning LSP. Missing project dependencies may limit features even after a successful basic attachment; report that distinction.

LSP-only installation must work for independent servers such as BasedPyright or a standalone rust-analyzer binary. Some servers need additional runtime/toolchain components for useful operation. Report the exact missing prerequisite; never claim readiness or silently install a language. ElixirLS specifically needs Elixir/OTP. A server's implementation dependency, such as TypeScript used by TypeScript Language Server, must be declared separately from selecting a language development bundle.

## 3. Reversibility and personal-data cleanup

### Ownership, not filename guessing

Before mutation, record the prior state and intended operation in a versioned, validated installation record. Distinguish:

| Resource class | Install/update behavior | Uninstall behavior |
|---|---|---|
| Pre-existing host files/packages | Preserve or make an explicit reversible configuration change | Restore recorded originals where safe; do not delete unrelated host resources |
| Shared configuration touched by bootstrap | Record exact managed blocks/links/content and original locations | Undo matching changes; conflicts require explicit resolution and prevent a complete-cleanup claim |
| Bootstrap-owned private state | Keep under verified owned roots where supported | Delete by default, including user modifications within that owned state |
| Enrolled existing personal resources | Require explicit enrollment and cleanup scope | Delete the enrolled scope after preview/confirmation |
| Native packages added by bootstrap | Record package identity and pre-install presence/version | Removal policy is separate; never assume the package is still exclusively used by bootstrap |

Private-state cleanup includes credentials, Pi/Herdr sessions, enrolled project copies, mutable Neovim state, plugin caches, generated history, logs, configuration containing personal data, and bootstrap-created copies/backups of that data. Do not preserve these merely because the user modified them. Do not make automatic exports or retained backups during uninstall; export is explicitly requested and its destination must be disclosed.

A project used as the current working directory is not automatically enrolled for deletion. Project enrollment must identify exact owned roots and show the destructive cleanup contract before adoption. Never delete `$HOME`, filesystem roots, arbitrary current repositories, shared workspaces, or another user's files by inference.

### Prove isolation before relying on it

Prefer dedicated bootstrap-owned roots for application state and disposable project copies. Use supported application environment/profile APIs, not an undocumented assumption that one directory contains everything. Probe Pi, Herdr, Bun, Neovim, Git/GitHub authentication, and shell history to inventory all writes. Account for temporary files, caches, credential helpers/keychains, multiplexer sessions, and subprocesses.

Where applications use shared stores, implement narrowly scoped cleanup adapters or block adoption until ownership is explicit. Record references needed for cleanup, never credential values in the installation journal. If a tool cannot be isolated or cleaned reliably, surface that limitation before credentials or sensitive work are placed there.

Record originals and operation state before each external effect; commit resulting identity after verification. Interrupted install/uninstall must reconcile from observed state rather than assume the previous step finished. Reject concurrent mutating operations with a bounded, ownership-aware lock. Do not delete locks merely because their recorded PID is absent.

### Uninstall order and completion

1. Resolve the installation record, validate every target, and present the destructive preview. Refuse ambiguous ownership.
2. Stop only bootstrap-owned writers, processes, and tmux/Herdr/Pi sessions. Run cleanup outside those sessions, or refuse until they are stopped, so they cannot recreate credentials/history after deletion.
3. Remove enrolled credentials from files and supported credential stores, then enrolled project copies and private application state. Do not follow symlinks outside validated roots.
4. Undo owned shell/configuration integrations and restore pre-bootstrap host configuration. Remove bootstrap-created duplicate backups after restoration. Resolve shared-file conflicts rather than silently retaining sensitive remnants.
5. Remove owned wrappers, downloaded artifacts, sources, and caches once no retained configuration depends on them. Apply separately confirmed native package removals only after checking the package manager's proposed dependency effects.
6. Verify that enrolled sensitive state and active writers are absent. Remove cleanup/control state last. On failure, report remaining resources and retain only the minimal non-secret recovery state needed to retry; do not report complete cleanup.

Native package upgrades are not an exact host rollback mechanism. Do not automatically downgrade system packages, run blanket autoremove, remove shared runtimes, or remove packages that predated bootstrap. **Proposed default:** leave native packages installed; offer separately confirmed removal of eligible bootstrap-added packages. The user has not yet confirmed this package-removal policy.

Uninstall is not secure erasure. It cannot erase host snapshots, administrator copies, system audit logs, remote provider records, or data after host access is lost. Prefer short-lived, per-host credentials. Explain provider-side revocation; do not revoke a shared/global credential automatically. Isolation makes cleanup ownership tractable but does not protect secrets from an untrusted host administrator.

## 4. Existing code and proposed structure

| Current owner | Migration work |
|---|---|
| `install.sh`, `configure.sh`, `packages/bare.txt` | Native dispatch, separate selections, prerequisite checks, uninstall entry point |
| `scripts/lib/install/bare.sh` | Replace Conda installation and combined language/LSP routing; retain compatible command aliases deliberately |
| `scripts/lib/install/managed-files.sh` | Preserve existing backup/atomic-replacement behavior while adding ownership recording and inverse operations |
| `scripts/lib/install/configuration.sh` | Replace Python helpers, make application paths explicit, register owned integrations |
| `scripts/lib/install/neovim.sh`, `neovim/bootstrap.lua` | Preserve bundled configuration and local state on updates; selected-server configuration and verification |
| `scripts/bare-env.sh`, `scripts/dev-shell`, `bashrc`, `zshrc`, `zshenv` | Retire Conda hooks and activation dependency; implement Bash-first and optional prompt/shell integration |
| Existing install/configuration/runtime tests | Preserve migration/backup/lock coverage; replace assumptions that Conda, Python, or Zsh always exist |
| `bootstrap.sh`, dotfiles `bootstrap.lock` | Publish matching verified snapshots only in the authorized release slice |

Proposed implementation modules: a native package catalog/backend, a Node-based state/configuration helper, and an uninstall coordinator. Keep privileged package operations separate from user configuration and cleanup. Prefer Node standard-library APIs; no new Python runtime, inheritance hierarchy, generic plugin framework, or second persisted selection schema.

The installation record should include schema version, installation ID, selected components, enrolled roots, operation status, resource identities, prior package presence, and restoration references. Define bounds, path validation, schema migration, and recovery invariants before implementation. Record the public CLI and persisted-state/security decisions in a short ADR once settled.

Dotfiles' existing package dispatcher is native on Arch but otherwise largely uses Homebrew. It is not a complete apt/dnf implementation to copy. Shared implementation belongs in public bootstrap; dotfiles consumes it without restoring private duplicates.

## 5. Decisions to settle before dependent work

| Decision | Established constraint | Recommended starting point |
|---|---|---|
| Supported distro releases | Stock packages may be too old; Ubuntu 24.04 Neovim/Node do not satisfy the configured software | Probe candidate versions per supported release/architecture; fail clearly rather than silently substituting sources |
| Missing packages and third-party repositories | No Conda or Linuxbrew fallback; native package management requested | No automatic new repositories, taps, AUR packages, or release downloads without an approved source policy; retain separately approved existing application installers |
| Neovim parser dependencies | Parser builds need a C compiler/tree-sitter CLI, while language toolchains are optional | Decide whether these are explicit core editor dependencies or optional with clearly documented parser limitations |
| Credential/project enrollment | Default uninstall deletes associated personal data, not unrelated data | Prove isolated defaults and define explicit adoption for existing shared resources |
| Native package uninstall | System packages can become shared dependencies | Separate confirmed removal from default personal-data/config cleanup |

Evidence for version gates: [Ubuntu 24.04 Neovim](https://packages.ubuntu.com/noble/neovim) lists 0.9.5; [LazyVim requirements](https://www.lazyvim.org/) require Neovim >=0.11.2 with LuaJIT; bundled `neovim/README.md` documents 0.12-dependent mode switching. [Ubuntu 24.04 Node.js](https://packages.ubuntu.com/noble/nodejs) lists 18.19.1; inspected upstream Pi 0.85.1 declares Node >=22.19.0. These observations do not establish availability for other releases. Recheck live candidates during implementation.

## 6. Implementation slices and acceptance

Each slice is an end-to-end increment. Do not expand onto an unsettled destructive, persisted-format, or package-source decision. Routine reversible implementation choices do not require repeated approval.

| Slice | Deliverable | Required evidence |
|---|---|---|
| 1. Ownership and isolation | Settle cleanup boundaries; probe application state locations; implement one recorded configuration change and its inverse | Fresh install, repeat install, uninstall, repeat uninstall, interruption before/after activation, foreign-path refusal, and no retained enrolled sensitive data |
| 2. Native core | Package backends/catalog; core selection; Python-free configuration; Bash-first startup | Clean native hosts, missing privilege/version failures before configuration, no Conda/Python dependency, tools resolve outside the old environment, no login-shell change |
| 3. Pi and Neovim | Pinned Pi/packages/skills and usable bundled editor through owned paths | Real discovery/startup without provider calls; local editor state survives updates; native editor meets requirements; optional backends do not trigger installs |
| 4. Independent extras | Separate toolchain/LSP/tool selection and persistent selection state | Each direction tested independently; server-only cases without target language; missing prerequisites reported; no Mason downloads; real Neovim LSP attachment checks |
| 5. Legacy migration and full uninstall | Recognize existing managed installs, replace old hooks, and complete the inverse operations | Existing Conda install, half-installed state, edited/shared files, symlink escapes, credential-store entries, writer recreation, project enrollment, native package preservation/removal previews |
| 6. Integration and delivery | Documentation, platform checks, final review, optional publication | Full repository checks, actual native runtime journeys, security/persistence review, verified archive and matching installer pins when publication is authorized |

Legacy migration must not delete the old bare prefix wholesale: it contains separate Bun/Rust installations and may contain user additions. Determine which resources can be adopted, moved, or explicitly enrolled. Preserve required access during migration, then remove superseded enrolled copies so successful uninstall does not leave an old credential/cache copy behind.

## 7. Verification matrix

| Boundary | Cases |
|---|---|
| Platforms | Supported Ubuntu/Debian and Fedora releases, Arch, Apple Silicon macOS; other architectures only when sources are verified |
| Privileges | Existing packages without elevation, approved package installation, missing privilege, refused elevation; configuration-only commands remain unprivileged |
| Shells | Bash without Zsh/Starship; existing Zsh; explicit Zsh/Starship selections; Bash/Zsh interactive startup and ordinary command execution |
| Selection inputs | Missing/empty/unknown/duplicate selectors; independent languages and LSPs; existing selections preserved on update |
| Core | Pi version/package/skill discovery, Herdr CLI integration without registration, Neovim startup/config/keybindings, no provider authentication or model calls in tests |
| LSPs | Real initialize/attach/capability checks; deterministic response/diagnostic where practical; absent runtime; missing project dependencies; unselected executable on PATH remains inactive |
| Ownership | Pre-existing files/packages, foreign roots, explicit project enrollment, modified owned private state, modified shared host files, moved paths, symlinks, corrupted/unknown manifest versions |
| Recovery | Fault injection around write/activation/recording/deletion; overlapping runs rejected; repeat install/uninstall; no false success after partial cleanup |
| Sensitive cleanup | Sentinel credentials, history, sessions, project files, Neovim state, caches, logs, and backup copies disappear; unrelated sentinels survive; no writer recreates removed state |
| Native packages | Existing package preserved, bootstrap-added package identified, dependency-removal expansion blocked/reviewed, no blanket autoremove or downgrade |

Use disposable homes and native containers/VMs; macOS integration needs a native runner. Do not run destructive cleanup against the developer's home, another user's account, live credentials, or a real project to prove the tests.

Mocked package managers prove dispatch/retry behavior, not package availability. Verify representative real artifacts and resolved candidates. A headless Neovim exit alone does not prove LSP readiness. Do not claim secure erasure from filesystem absence.

Run bootstrap `./scripts/validate` and dotfiles validation against the coordinated bootstrap source, then against the selected snapshot before delivery. Retain existing relevant config/link/Neovim tests. Security-sensitive ownership and uninstall implementation receives focused independent reviews, including an alternate-model review; the parent accepts the integrated result and resolves all P0/P1 findings before publication.

## 8. Completion and release boundary

Completion means the three core groups work without Conda, default Python, Zsh, or Starship; extras remain independent; selected LSPs are verified in Neovim; and confirmed uninstall removes all enrolled personal state without harming unrelated resources. Unsupported hosts and incomplete cleanup have explicit, non-success outcomes.

After implementation and verification, obtain or reuse explicit authorization for the new publication scope. Push the verified bootstrap runtime, fetch/hash its public archive, and advance both `bootstrap.sh` and dotfiles `bootstrap.lock` to that runtime. Verify the snapshot consumer paths. Keep runtime/pin commits separate from unrelated changes and preserve local authentication during any authorized activation.

This deliverable is the plan only. Creating it does not change native packages, run an uninstall, access a remote machine, or publish changes.
