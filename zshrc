# Fig pre block. Keep at the top of this file.
[[ -f "$HOME/.fig/shell/zshrc.pre.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.pre.zsh"

# ============================================
# ZSH Configuration (fish-like features)
# ============================================

# Environment variables (PATH, EDITOR, Go, etc. set in zshenv)
export PAGER="less"
export BAT_PAGER="less -RF"
export MANPAGER="less"
export DISABLE_INSTALLATION_CHECKS="1"
export DISABLE_AUTOUPDATER="1"

# History settings
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY          # Share history between sessions
setopt HIST_IGNORE_DUPS       # Don't record duplicates
setopt HIST_IGNORE_SPACE      # Don't record commands starting with space
setopt HIST_REDUCE_BLANKS     # Remove extra blanks

# Shell options
setopt AUTO_CD                # Type directory name to cd into it
setopt CORRECT                # Offer to fix typos
setopt CDABLE_VARS            # cd into named directories
setopt AUTO_PUSHD             # cd pushes onto directory stack
setopt PUSHD_IGNORE_DUPS      # No duplicates in dir stack

# Vi mode
bindkey -v                    # Vi keybindings
export KEYTIMEOUT=1           # Faster mode switching

# Prefix-based history search (type partial command, then up/down)
autoload -U history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey "^[[A" history-beginning-search-backward-end  # Up arrow
bindkey "^[[B" history-beginning-search-forward-end   # Down arrow
bindkey "^P" history-beginning-search-backward-end    # Ctrl+P
bindkey "^N" history-beginning-search-forward-end     # Ctrl+N

# Clipboard command detection
if [[ "$OSTYPE" == "darwin"* ]]; then
    COPY_CMD="pbcopy"
elif command -v wl-copy &>/dev/null; then
    COPY_CMD="wl-copy"
elif command -v xclip &>/dev/null; then
    COPY_CMD="xclip -selection clipboard"
elif command -v xsel &>/dev/null; then
    COPY_CMD="xsel --clipboard --input"
fi

# Aliases
alias ls='eza --icons'
alias ll='eza -la --icons --git'
alias tree='eza --tree --icons'
alias cat='bat'
alias ..='cd ..'
alias ...='cd ../..'
alias nvim='NVIM_LEETCODE_MODE=0 command nvim'
alias leetvim='NVIM_LEETCODE_MODE=1 command nvim'

# Keep CLI-only settings out of the config shared with the older ChatGPT app.
alias codex='codex -c features.context_management.experimental_mode=true'

# Resolve managed rc symlinks so upgrades need no additional configuration link.
if [[ "$OSTYPE" != darwin* ]]; then
    source "${${(%):-%x}:A:h}/scripts/lib/shell-open.sh"
fi

# Herdr agent multiplexer. Run `pi` in a pane; the integration reports agent state.
alias hm='herdr'
alias hml='herdr session list'
alias hmk='herdr session stop'
pit() {
    if [[ -n "$HERDR_PANE_ID" ]]; then
        command pi "$@"
        return
    fi
    herdr
}


copy() {
    local content
    if (( $# > 0 )); then
        content=$(command cat "$@") || return
    else
        content=$(command cat) || return
    fi
    printf '%s' "${${content##[[:space:]]}%%[[:space:]]}" | ${COPY_CMD:-pbcopy}
}

teessh() {
    local ts logfile
    ts="$(date +%Y_%m_%d_%H:%M:%S)"
    logfile="/tmp/nudge_client-ssh-${ts}.log"
    command ssh "$@" | tee -- "$logfile"
}

# Completion
fpath=(~/.zfunc $fpath)
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select                    # Tab menu selection
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'   # Case-insensitive completion

# micromamba shell integration (activate/deactivate)
command -v micromamba &>/dev/null && eval "$(micromamba shell hook -s zsh)"

command -v starship &>/dev/null && eval "$(starship init zsh)"


# ============================================
# Plugins
# ============================================

BREW_PREFIX=""
command -v brew &>/dev/null && BREW_PREFIX="$(brew --prefix 2>/dev/null)"

# Autosuggestions (right arrow to accept)
[[ -f "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# fzf (Ctrl+R for history, Ctrl+T for files)
[[ -f "$BREW_PREFIX/opt/fzf/shell/completion.zsh" ]] && source "$BREW_PREFIX/opt/fzf/shell/completion.zsh"
[[ -f "$BREW_PREFIX/opt/fzf/shell/key-bindings.zsh" ]] && source "$BREW_PREFIX/opt/fzf/shell/key-bindings.zsh"
[[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh

# Syntax highlighting must load after other widgets.
[[ -f "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$BREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# zoxide (use 'z' instead of 'cd')
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# thefuck (type 'fuck' to correct previous command)
command -v thefuck &>/dev/null && eval "$(thefuck --alias)"

# OrbStack integration
[[ -f ~/.orbstack/shell/init.zsh ]] && source ~/.orbstack/shell/init.zsh

# opam initialized in zshenv

# Fig post block. Keep at the bottom of this file.
[[ -f "$HOME/.fig/shell/zshrc.post.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.post.zsh"

# LM Studio PATH set in zshenv

ulimit -u 4000 2>/dev/null

# Machine-specific overrides (not tracked in git)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# bun completions
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Activate compiler flags as well as PATH in bare development shells.
if [[ -f "$HOME/.config/dotfiles/bare-env.sh" ]]; then
    source "$HOME/.config/dotfiles/bare-env.sh"
    [[ "${CONDA_PREFIX:-}" == "$DOTFILES_BARE_ROOT/env" ]] || micromamba activate "$DOTFILES_BARE_ROOT/env"
fi
