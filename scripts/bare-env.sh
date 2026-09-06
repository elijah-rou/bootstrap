# Sourced by Bash/Zsh. The bare profile installs this link only on opted-in hosts.
export DOTFILES_BARE_ROOT="$HOME/.local/share/dotfiles/bare"
export MAMBA_ROOT_PREFIX="$DOTFILES_BARE_ROOT/mamba"
export CARGO_HOME="$DOTFILES_BARE_ROOT/cargo"
export RUSTUP_HOME="$DOTFILES_BARE_ROOT/rustup"
export BUN_INSTALL="$DOTFILES_BARE_ROOT/bun"
# Retain the old npm prefix for tools installed before the Bun migration.
export npm_config_prefix="$DOTFILES_BARE_ROOT/npm"
export PATH="$DOTFILES_BARE_ROOT/bin:$CARGO_HOME/bin:$BUN_INSTALL/bin:$npm_config_prefix/bin:$DOTFILES_BARE_ROOT/env/bin:$HOME/.local/bin:$PATH"
export EDITOR=nvim
export VISUAL=nvim
