# zshenv: sourced for ALL zsh invocations (interactive, non-interactive, scripts).
# Critical for mosh-server over SSH from iPad - ensures tools are on PATH
# even before zshrc runs. Keep this lean: PATH + env vars only.

# Homebrew
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
    eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
fi

# User scripts
export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"

# Cargo/Rust
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Go
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
export PATH="$PATH:$GOBIN"

# opam/OCaml
[[ -r "$HOME/.opam/opam-init/init.zsh" ]] && source "$HOME/.opam/opam-init/init.zsh" >/dev/null 2>/dev/null

# micromamba
export MAMBA_ROOT_PREFIX="$HOME/micromamba"

# LM Studio CLI
[[ -d "$HOME/.lmstudio/bin" ]] && export PATH="$PATH:$HOME/.lmstudio/bin"

# Editor defaults
export EDITOR="nvim"
export VISUAL="nvim"
export KUBE_EDITOR="nvim"
export K9S_EDITOR="nvim"
export XDG_CONFIG_HOME="$HOME/.config"
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"

# pi-cursor-sdk: keep Cursor models inside pi's tool/workflow environment.
export PI_CURSOR_SETTING_SOURCES="${PI_CURSOR_SETTING_SOURCES:-none}"
export PI_CURSOR_EXPOSE_BUILTIN_TOOLS="${PI_CURSOR_EXPOSE_BUILTIN_TOOLS:-1}"

# Workstation additions retain this shared shell baseline.
[[ -f "$HOME/.config/dotfiles/workstation.zsh" ]] && source "$HOME/.config/dotfiles/workstation.zsh"

# Machine-specific overrides (not tracked in git)
[[ -f ~/.zshenv.local ]] && source ~/.zshenv.local

# Machine-local environment (not tracked)
[[ -f "$HOME/.config/dotfiles/env.sh" ]] && source "$HOME/.config/dotfiles/env.sh"

# User-local terminal profile, when installed.
[[ -f "$HOME/.config/dotfiles/bare-env.sh" ]] && source "$HOME/.config/dotfiles/bare-env.sh"
