# Fig pre block. Keep at the top of this file.
[[ -f "$HOME/.fig/shell/bashrc.pre.bash" ]] && builtin source "$HOME/.fig/shell/bashrc.pre.bash"

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

teessh() {
    local ts logfile
    ts="$(date +%Y_%m_%d_%H:%M:%S)"
    logfile="/tmp/nudge_client-ssh-${ts}.log"
    command ssh "$@" | tee -- "$logfile"
}

export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"

# Keep CLI-only settings out of the config shared with the older ChatGPT app.
alias codex='codex -c features.context_management.experimental_mode=true'

# Resolve managed rc symlinks so upgrades need no additional configuration link.
if [[ "$OSTYPE" != darwin* ]]; then
    source "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")/scripts/lib/shell-open.sh"
fi

# Fig post block. Keep at the bottom of this file.
[[ -f "$HOME/.fig/shell/bashrc.post.bash" ]] && builtin source "$HOME/.fig/shell/bashrc.post.bash"
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# LM Studio CLI
[[ -d "$HOME/.lmstudio/bin" ]] && export PATH="$PATH:$HOME/.lmstudio/bin"

# Machine-local environment (not tracked)
[[ -f "$HOME/.config/dotfiles/env.sh" ]] && source "$HOME/.config/dotfiles/env.sh"

# User-local terminal profile, when installed.
[[ -f "$HOME/.config/dotfiles/bare-env.sh" ]] && source "$HOME/.config/dotfiles/bare-env.sh"
if [[ $- == *i* && -f "$HOME/.config/dotfiles/bare-env.sh" && "${CONDA_PREFIX:-}" != "$DOTFILES_BARE_ROOT/env" ]]; then
    eval "$(micromamba shell hook --shell bash)"
    micromamba activate "$DOTFILES_BARE_ROOT/env"
fi
