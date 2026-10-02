# shellcheck shell=bash
# Sourced by Bash and Zsh; both support the ${var//pattern/replacement} expansion used below.
# Environment for every shell and launcher. Everything bootstrap writes lives under
# BOOTSTRAP_ROOT so uninstall can delete it; tools/ holds programs, private/ holds
# credentials, sessions, history, and caches.
export BOOTSTRAP_ROOT="${BOOTSTRAP_ROOT:-$HOME/.local/share/bootstrap}"
_tools="$BOOTSTRAP_ROOT/tools"
_private="$BOOTSTRAP_ROOT/private"

export BUN_INSTALL="$_tools/bun" BUN_INSTALL_CACHE_DIR="$_private/cache/bun"
export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$_private/cache/bun-transpiler"
export CARGO_HOME="$_tools/cargo" RUSTUP_HOME="$_tools/rustup"
export GOPATH="$_tools/go" GOBIN="$_tools/bin" GOMODCACHE="$_tools/go/pkg/mod"
export GOCACHE="$_private/cache/go-build" GOENV="$_private/go/env"
export UV_CACHE_DIR="$_private/cache/uv" UV_PYTHON_INSTALL_DIR="$_tools/python"
export UV_PYTHON_BIN_DIR="$_tools/bin" UV_TOOL_DIR="$_tools/uv-tools" UV_TOOL_BIN_DIR="$_tools/bin"
export MIX_HOME="$_private/mix" HEX_HOME="$_private/hex" MIX_INSTALL_DIR="$_tools/mix-install"

export PI_CODING_AGENT_DIR="$_private/pi/agent" PI_CODING_AGENT_SESSION_DIR="$_private/pi/sessions"
export GH_CONFIG_DIR="$_private/gh"
export TMUX_TMPDIR="$_private/tmux" LESSHISTFILE="$_private/less/history" _ZO_DATA_DIR="$_private/zoxide"
export STARSHIP_CONFIG="$BOOTSTRAP_ROOT/repo/config/starship.toml" STARSHIP_CACHE="$_private/cache/starship"
export RIPGREP_CONFIG_PATH="$BOOTSTRAP_ROOT/repo/config/ripgrep"
export EDITOR=hx VISUAL=hx PAGER=less BAT_PAGER='less -RF' MANPAGER=less

# Machine-specific environment, for example from the private dotfiles repository.
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/bootstrap/env.sh" ]; then . "${XDG_CONFIG_HOME:-$HOME/.config}/bootstrap/env.sh"; fi

# Defaults that the machine-specific file may set first. An existing CODEX_HOME, such as a
# workstation's ~/.codex or ~/.claude, is kept; uninstall then removes only the links bootstrap put there.
export CODEX_HOME="${CODEX_HOME:-$_private/codex}" CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$_private/claude}"
# Claude Code keys its keychain login to any explicit CLAUDE_CONFIG_DIR, so its default home stays
# implicit; otherwise an existing ~/.claude login would no longer be found.
if [ "$CLAUDE_CONFIG_DIR" = "$HOME/.claude" ]; then unset CLAUDE_CONFIG_DIR; fi
# Agents are pinned in catalog.tsv; their own updaters would move them off the pin.
export DISABLE_AUTOUPDATER=1

# Bootstrap's tools go first even when macOS path_helper or other profile files reordered PATH,
# so every re-source moves them to the front rather than skipping ones already present.
_path=":$PATH:"
for _dir in "$CARGO_HOME/bin" "$BUN_INSTALL/bin" "$_tools/bin"; do
    _path=":$_dir${_path//":$_dir:"/:}"
done
_path="${_path#:}"
export PATH="${_path%:}"
unset _tools _private _dir _path
