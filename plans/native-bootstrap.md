# Native bootstrap, independent extras, and complete uninstall

## Outcome and authority

Replace the Conda-based bootstrap with native host packages, a Bash-first environment, pinned Pi configuration, and the bundled Neovim configuration. Extras remain explicitly selected. Uninstall must remove bootstrap-associated personal data so the setup can be used on borrowed machines.

The user authorized orchestrating this plan to completion, committing, and pushing bootstrap and the coordinated installer pins. Requirements below are accepted unless marked **open** or **proposed**. Native migration has not yet started. This does not authorize testing uninstall against live personal data or changing a remote machine.

Both repositories are in scope: `~/Projects/bootstrap` owns the shared implementation, and `~/dotfiles` must consume and propagate its changed behavior. Consumer integration includes code and tests, not merely updating `bootstrap.lock`.

Inspected baseline: bootstrap `24c2cb2c9e018689efa12dc4bfb857e296ab7299`. The earlier Conda package-name fix in `packages/bare.txt`, `tests/bare_install_test.sh`, and `README.md` is uncommitted and superseded. Reconcile those exact edits in the first implementation slice; do not publish them as the requested solution. Preserve unrelated dotfiles work, including `agent-planning-feedback.md`.

## 1. Installation contract

### Core and extras

| Group | Default contents | Boundary |
|---|---|---|
| CLI tools | Git, Delta, GitHub CLI, OpenSSH client, tmux, Herdr, ripgrep, fd, fzf, bat, eza, zoxide, jq, less, curl | Native packages where available; no automatic SSH server, machine registration, or service activation |
| Pi | Pinned upstream `@earendil-works/pi-coding-agent`, Node/Bun, shared settings, instructions, agents, prompts, theme, extensions, and skills | Do not substitute a fork or alter authentication/model preferences implicitly |
| Neovim | `neovim` (native first), compatible Tree-sitter CLI, required C compiler, bundled configuration, parser/plugin defaults, keybindings, and interview-mode support | Use the supported upstream parser-build workflow; validate the complete version combination and preserve local editor state during install/update |
| Shell | First-class Bash configuration and portable shared environment/helpers | Preserve the existing login shell; no dependency on Zsh, Starship, Conda, or an activation shell |
| Language extras | C, C++, Rust, Go, Python/uv, TypeScript, Elixir/Erlang, Zig | Installing a language never implicitly selects an LSP |
| LSP extras | clangd, rust-analyzer, gopls, BasedPyright, Ruff, TypeScript Language Server, Bash Language Server, ElixirLS, ZLS | Independently selectable without the target language/toolchain |
| Other extras | Zsh and its plugins, Starship, Codex, just, wget, unzip, ShellCheck, Ruff CLI, Headroom, search/usage backends | Explicit opt-in; an installed Pi integration does not select its external application/service |

The Pi package set remains the configured immutable sources: `pi-subagents`, `pi-web-access`, `pi-privileged-operations`, `pi-sub-limits`, `pi-effort`, and `pi-unveil`. Repository extensions and shared skills remain installed. An unavailable optional backend must be reported accurately rather than treated as a core installation failure or silently installed.

Node/Bun are core runtime dependencies, not optional language development selections. Bootstrap must not require or explicitly install Python for core setup. Replace Python-based installer/configuration helpers before removing Python from base installation and doctor checks. Do not remove existing system Python, including Python used by the host package manager. Python used only by repository tests may remain a development dependency.

### Package and shell policy

Use apt on supported Ubuntu/Debian releases, dnf on Fedora, pacman on Arch, and Homebrew on macOS. No Conda and no implicit Linuxbrew fallback. The user approved direct upstream installation when a native package is absent or its version is unusable. Follow the project's official installation instructions, use versioned/checksum-verified artifacts where available, and record ownership for uninstall. This is not permission to add arbitrary third-party repositories or AUR packages.

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
| Package removal | Part of `./install.sh uninstall` | Preview/confirm eligible bootstrap-added package removal by default; preserve pre-existing/shared packages |

Selections must persist across retries and updates. Running the core installer again must not remove explicitly installed extras. Reject unknown selectors before any mutation. Package removal defaults are settled; finalize compatible flag names when recording the public command contract.

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
| Native packages added by bootstrap | Record package identity and pre-install presence/version | Remove eligible additions in the confirmed uninstall; never assume a package is still exclusively used by bootstrap |

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
5. Remove owned wrappers, downloaded artifacts, sources, and caches once no retained configuration depends on them. Remove eligible bootstrap-added native packages by default as part of the confirmed cleanup plan, after checking the package manager's proposed dependency effects.
6. Verify that enrolled sensitive state and active writers are absent. Remove cleanup/control state last. On failure, report remaining resources and retain only the minimal non-secret recovery state needed to retry; do not report complete cleanup.

Native package upgrades are not an exact host rollback mechanism. Do not automatically downgrade system packages, run blanket autoremove, remove shared runtimes, or remove packages that predated bootstrap. The user approved removal of eligible bootstrap-added packages by default, with a preview and confirmation and protection for unrelated dependents.

Uninstall is not secure erasure. It cannot erase host snapshots, administrator copies, system audit logs, remote provider records, or data after host access is lost. Prefer short-lived, per-host credentials. Explain provider-side revocation; do not revoke a shared/global credential automatically. Isolation makes cleanup ownership tractable but does not protect secrets from an untrusted host administrator.

## 4. Existing code and proposed structure

| Current owner | Migration work |
|---|---|
| `install.sh`, `configure.sh`, `packages/catalog.json` | Native dispatch, separate selections, prerequisite checks, uninstall entry point |
| `scripts/lib/install/bare.sh` | Replace Conda installation and combined language/LSP routing; retain compatible command aliases deliberately |
| `scripts/lib/install/managed-files.sh` | Preserve existing backup/atomic-replacement behavior while adding ownership recording and inverse operations |
| `scripts/lib/install/configuration.sh` | Replace Python helpers, make application paths explicit, register owned integrations |
| `scripts/lib/install/neovim.sh`, `neovim/bootstrap.lua` | Preserve bundled configuration and local state on updates; selected-server configuration and verification |
| `scripts/bare-env.sh`, `scripts/dev-shell`, `bashrc`, `zshrc`, `zshenv` | Retire Conda hooks and activation dependency; implement Bash-first and optional prompt/shell integration |
| Existing install/configuration/runtime tests | Preserve migration/backup/lock coverage; replace assumptions that Conda, Python, or Zsh always exist |
| Dotfiles `install.sh`, `scripts/bootstrap`, `scripts/lib/install/bootstrap.sh`, and `scripts/lib/install/managed-files.sh` | Adapt shared installer/configuration entry points, package routing, and helper contracts to the native bootstrap; remove obsolete assumptions without copying shared implementation |
| Dotfiles `tests/install_test.sh`, `tests/bootstrap_integration_test.py`, `tests/bootstrap_cache_test.py`, and `scripts/validate` | Exercise the new shared contracts, existing overlays, offline paths, native package selection, and snapshot consumption |
| `bootstrap.sh`, dotfiles `bootstrap.lock` | Publish matching verified snapshots only in the authorized release slice |

Proposed implementation modules: a native package catalog/backend, a Node-based state/configuration helper, and an uninstall coordinator. Keep privileged package operations separate from user configuration and cleanup. Prefer Node standard-library APIs; no new Python runtime, inheritance hierarchy, generic plugin framework, or second persisted selection schema.

The installation record should include schema version, installation ID, selected components, enrolled roots, operation status, resource identities, prior package presence, and restoration references. Define bounds, path validation, schema migration, and recovery invariants before implementation. Record the public CLI and persisted-state/security decisions in a short ADR once settled.

Dotfiles' existing package dispatcher is native on Arch but otherwise largely uses Homebrew. It is not a complete apt/dnf implementation to copy. Shared implementation belongs in public bootstrap; dotfiles consumes it without restoring private duplicates.

Trace dotfiles' default, complete, terminal, bare/native, link/offline, Pi, Neovim, language, and LSP paths against the changed shared contract. Shared core components must use the same native package and version policy through both repositories. Translate explicitly requested workstation selections into the new selection model; do not silently reintroduce Python, Zsh, Starship, coupled LSP/toolchains, or Mason auto-installs through a consumer wrapper. Preserve machine-local overlays, explicit user settings, and unrelated workstation features. If an existing private feature needs an extra, make that dependency explicit instead of expanding the shared core.

Installation ownership must distinguish bootstrap-managed resources from dotfiles-only or jointly used workstation resources. A bootstrap uninstall must not infer ownership of all workstation state because dotfiles imports its helpers. Test this boundary before sharing uninstall entry points.

## 5. Decisions to settle before dependent work

| Decision | Established constraint | Recommended starting point |
|---|---|---|
| Supported distro releases | Stock packages may be too old; Ubuntu 24.04 Neovim/Node do not satisfy the configured software | Probe candidate versions per supported release/architecture; fail clearly rather than silently substituting sources |
| Missing packages and third-party repositories | No Conda or Linuxbrew fallback; native package management requested | **Settled:** direct upstream installation is allowed for absent or unusably old native packages; follow official project instructions |
| Neovim parser dependencies | User permits core dependencies; upstream research confirms compilation is the supported approach | **Settled:** compiler and compatible Tree-sitter CLI are core editor dependencies; retain the current parser features and keep LSP/toolchain selections independent |
| Credential/project enrollment | Default uninstall deletes associated personal data, not unrelated data | Prove isolated defaults and define explicit adoption for existing shared resources |
| Native package uninstall | System packages can become shared dependencies | **Settled:** remove eligible bootstrap-added packages by default in the confirmed cleanup; preserve pre-existing packages and protect unrelated dependents |

Evidence for version gates: [Ubuntu 24.04 Neovim](https://packages.ubuntu.com/noble/neovim) lists 0.9.5; [LazyVim requirements](https://www.lazyvim.org/) require Neovim >=0.11.2 with LuaJIT; bundled `neovim/README.md` documents 0.12-dependent mode switching. [Ubuntu 24.04 Node.js](https://packages.ubuntu.com/noble/nodejs) lists 18.19.1; inspected upstream Pi 0.85.1 declares Node >=22.19.0. These observations do not establish availability for other releases. Recheck live candidates during implementation.

### Research: Tree-sitter compilation is the supported setup

The user clarified that compiler size/presence is not the concern; the question is whether local compilation is correct. Research supports retaining the normal parser workflow rather than removing editor features or introducing a new prebuilt-parser distribution.

| Primary source | Exact supporting passage or code | Consequence |
|---|---|---|
| [LazyVim requirements](https://www.lazyvim.org/) | “tree-sitter-cli and a C compiler for nvim-treesitter” | These are documented editor dependencies, independent of LSP selection |
| [Pinned nvim-treesitter README](https://github.com/nvim-treesitter/nvim-treesitter/blob/2f5d4c3f3c675962242096bcc8e586d76dd72eb2/README.md) | “a C compiler in your path”; CLI “0.26.1 or later, installed via your package manager, not npm” | Validate compatible native compiler/CLI availability; use the approved official fallback policy when necessary |
| [Pinned LazyVim configuration](https://github.com/LazyVim/LazyVim/blob/fca0af57cc3851b14f96a795a9c9bfafc5096dd1/lua/lazyvim/plugins/treesitter.lua) | `TS.install(install, { summary = true })` for missing parsers; `TS.update(nil, { summary = true })` on plugin build | This is inherited upstream behavior, not custom bootstrap compilation |
| [Pinned nvim-treesitter README](https://github.com/nvim-treesitter/nvim-treesitter/blob/2f5d4c3f3c675962242096bcc8e586d76dd72eb2/README.md) | “only guaranteed to work with specific versions of language parsers” | Arbitrary prebuilt parsers are not interchangeable with the plugin's required revisions |
| [Neovim Tree-sitter documentation](https://neovim.io/doc/user/treesitter/) | Parsers are libraries under `parser/{lang}.*`; Neovim exposes earliest/latest supported parser ABI versions | Prebuilt libraries are supported by Neovim, but a replacement distribution must also match platform, ABI, grammar and queries |

Implementation requirement: include the required parser-build dependencies as core editor dependencies. Resolve the configured parser set from the effective plugin configuration, install/update missing or incompatible parsers during bootstrap, wait for completion with a bounded timeout, and verify parser loading/highlighting before reporting readiness. Reuse compatible installed parsers; do not force compilation on every startup or unchanged reinstall. Install Tree-sitter CLI through a suitable native package or an approved official upstream artifact, not npm/Bun. Do not introduce a custom prebuilt-parser distribution or disable existing parser features.

The C compiler is an explicit editor dependency, not an implicit selection of a C development bundle or LSP. An explicitly selected C toolchain must reuse that compatible compiler rather than install a duplicate. Track compiler/CLI ownership and parser build/cache roots so uninstall applies the same eligible-package and personal-state cleanup rules.

Version caveat: the pinned nvim-treesitter README targets Neovim 0.12/nightly, while general LazyVim documentation gives a lower minimum. Validate the actual Neovim/plugin/CLI combination in clean runtime tests; the generic LazyVim minimum alone is insufficient. Prebuilt distributions are an alternative, not a requirement or a demonstrated drop-in replacement for this pinned setup.

## 6. Implementation slices and acceptance

Each slice is an end-to-end increment. Do not expand onto an unsettled destructive, persisted-format, or package-source decision. Routine reversible implementation choices do not require repeated approval.

| Slice | Deliverable | Required evidence |
|---|---|---|
| 1. Ownership and isolation | Settle cleanup boundaries; probe application state locations; implement one recorded configuration change and its inverse | Fresh install, repeat install, uninstall, repeat uninstall, interruption before/after activation, foreign-path refusal, and no retained enrolled sensitive data |
| 2. Native core | Package backends/catalog; core selection; Python-free configuration; Bash-first startup | Clean native hosts, missing privilege/version failures before configuration, no Conda/Python dependency, tools resolve outside the old environment, no login-shell change |
| 3. Pi and Neovim | Pinned Pi/packages/skills and usable bundled editor through owned paths, with core parser-build dependencies and completed parser setup | Real discovery/startup without provider calls; clean-home parser installation and highlighting/folding; compiler/CLI/plugin version compatibility; unchanged reruns do not rebuild parsers; local editor state survives updates; optional backends do not trigger installs |
| 4. Independent extras | Separate toolchain/LSP/tool selection and persistent selection state | Each direction tested independently; server-only cases without target language; missing prerequisites reported; no Mason downloads; real Neovim LSP attachment checks |
| 5. Dotfiles consumer integration | Update shared call sites, package routing, explicit selections, overlays, and contract tests in `~/dotfiles` | Default/terminal/link/offline and targeted command paths consume the new bootstrap correctly; local overlays survive; no copied shared implementation or obsolete Conda/Python/shell assumptions |
| 6. Legacy migration and full uninstall | Recognize existing managed installs, replace old hooks, and complete the inverse operations across both consumers | Existing Conda install, half-installed state, edited/shared files, symlink escapes, credential-store entries, writer recreation, project enrollment, native package preservation/removal previews, and protection for dotfiles-only/shared resources |
| 7. Integration and delivery | Documentation, platform checks, final review, publication | Full checks in both repositories, actual native runtime journeys, security/persistence review, verified archive and matching installer pins |

Legacy migration must not delete the old bare prefix wholesale: it contains separate Bun/Rust installations and may contain user additions. Determine which resources can be adopted, moved, or explicitly enrolled. Preserve required access during migration, then remove superseded enrolled copies so successful uninstall does not leave an old credential/cache copy behind.

## 7. Verification matrix

| Boundary | Cases |
|---|---|
| Platforms | Supported Ubuntu/Debian and Fedora releases, Arch, Apple Silicon macOS; other architectures only when sources are verified |
| Privileges | Existing packages without elevation, approved package installation, missing privilege, refused elevation; configuration-only commands remain unprivileged |
| Shells | Bash without Zsh/Starship; existing Zsh; explicit Zsh/Starship selections; Bash/Zsh interactive startup and ordinary command execution |
| Selection inputs | Missing/empty/unknown/duplicate selectors; independent languages and LSPs; existing selections preserved on update |
| Core | Pi version/package/skill discovery, Herdr CLI integration without registration, Neovim startup/config/keybindings, real parser installation/loading/highlighting/folding, no provider authentication or model calls in tests |
| Parser builds | Missing compiler or incompatible CLI fails clearly; supported Neovim/plugin/CLI tuple; bounded download/build failure; clean install succeeds; unchanged reinstall reuses parsers; plugin/parser updates remain compatible; no npm Tree-sitter CLI or automatic LSP selection |
| LSPs | Real initialize/attach/capability checks; deterministic response/diagnostic where practical; absent runtime; missing project dependencies; unselected executable on PATH remains inactive |
| Ownership | Pre-existing files/packages, foreign roots, explicit project enrollment, modified owned private state, modified shared host files, moved paths, symlinks, corrupted/unknown manifest versions |
| Recovery | Fault injection around write/activation/recording/deletion; overlapping runs rejected; repeat install/uninstall; no false success after partial cleanup |
| Sensitive cleanup | Sentinel credentials, history, sessions, project files, Neovim state, caches, logs, and backup copies disappear; unrelated sentinels survive; no writer recreates removed state |
| Native packages | Existing package preserved, bootstrap-added package identified, dependency-removal expansion blocked/reviewed, no blanket autoremove or downgrade |
| Dotfiles consumer | Shared native dispatch, separate toolchain/LSP choices, Bash-first behavior, preserved workstation/local overlays, offline no-fetch behavior, selected Neovim server integration, and uninstall ownership boundaries |

Use disposable homes and native containers/VMs; macOS integration needs a native runner. Do not run destructive cleanup against the developer's home, another user's account, live credentials, or a real project to prove the tests.

Mocked package managers prove dispatch/retry behavior, not package availability. Verify representative real artifacts and resolved candidates. A headless Neovim exit alone does not prove LSP readiness. Do not claim secure erasure from filesystem absence.

Run bootstrap `./scripts/validate` and dotfiles validation against the coordinated bootstrap source, then against the selected snapshot before delivery. Retain existing relevant config/link/Neovim tests. Security-sensitive ownership and uninstall implementation receives focused independent reviews, including an alternate-model review; the parent accepts the integrated result and resolves all P0/P1 findings before publication.

## 8. Completion and release boundary

Completion means the three core groups work without Conda, default Python, Zsh, or Starship; extras remain independent; selected LSPs are verified in Neovim; and confirmed uninstall removes all enrolled personal state without harming unrelated resources. Unsupported hosts and incomplete cleanup have explicit, non-success outcomes.

The user authorized committing and pushing this migration across bootstrap and dotfiles. First validate the coordinated work using `DOTFILES_BOOTSTRAP_SOURCE` against the implementation worktree. Push the verified bootstrap runtime, fetch/hash its public archive, and advance both `bootstrap.sh` and dotfiles `bootstrap.lock` to that runtime. Then run dotfiles validation without the development override to prove the published snapshot works through the real consumer. Publish the consumer changes and pins only after that check passes. Keep runtime/consumer/pin commits coherent and separate from unrelated changes, and preserve local authentication during any authorized activation.

## 9. Bootstrap implementation progress

Bootstrap-owned slices 1, 2, 3, 4, 6, and the local portion of 7 are implemented on `pi/bootstrap/native-bootstrap-78907ef9`. The implementation includes the versioned ownership record and inverse operations, native backends/catalog, Node runtime helpers, Bash-first profile, isolated Pi/Neovim state, explicit extras, real parser and LSP checks, guarded legacy migration, project enrollment, package dependency previews, and retryable uninstall. Tests use disposable homes; no host package manager or live personal state was mutated. A real disposable Neovim 0.12.5 run compiled the effective parser set, verified highlight/folding, reused identical parser artifacts on retry, and attached BasedPyright through the bundled selected-server configuration.

Slice 5 remains owned by the dependent dotfiles worker. Publication-only slice 7 fields (`bootstrap.sh` `REVISION` and `ARCHIVE_SHA256`, plus the dotfiles lock) intentionally remain unchanged until the coordinated runtime is public and its codeload archive hash is known. Linux/macOS CI gates are runnable evidence; local package-manager availability is not claimed from mocked dispatch tests.
