# Shared Bash-first interactive configuration.
[[ -f "$HOME/.fig/shell/bashrc.pre.bash" ]] && builtin source "$HOME/.fig/shell/bashrc.pre.bash"

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
export PATH="$HOME/.local/bin:$PATH"
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"
export PAGER=less BAT_PAGER='less -RF' MANPAGER=less
export EDITOR=nvim VISUAL=nvim

alias ls='eza --icons=always'
alias ll='eza -la --icons=always --git'
alias tree='eza --tree --icons=always'
alias cat='bat'
alias nvim='NVIM_LEETCODE_MODE=0 command nvim'
alias leetvim='NVIM_LEETCODE_MODE=1 command nvim'
alias codex='codex -c features.context_management.experimental_mode=true'

copy() {
    local command_name
    if [[ "$OSTYPE" == darwin* ]]; then command_name=pbcopy
    elif command -v wl-copy >/dev/null; then command_name=wl-copy
    elif command -v xclip >/dev/null; then command_name='xclip -selection clipboard'
    else printf 'No clipboard command available\n' >&2; return 1; fi
    if [[ $# -gt 0 ]]; then command cat -- "$@" | $command_name; else command cat | $command_name; fi
}
teessh() { local logfile="/tmp/nudge_client-ssh-$(date +%Y_%m_%d_%H:%M:%S).log"; command ssh "$@" | tee -- "$logfile"; }
pit() { if [[ -n "${HERDR_PANE_ID:-}" ]]; then command pi "$@"; else herdr; fi; }

if [[ "$OSTYPE" != darwin* ]]; then
    source "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")/scripts/lib/shell-open.sh"
fi
[[ -f "$HOME/.config/dotfiles/env.sh" ]] && source "$HOME/.config/dotfiles/env.sh"
[[ -f "$HOME/.config/dotfiles/bare-env.sh" ]] && source "$HOME/.config/dotfiles/bare-env.sh"
if [[ $- == *i* ]]; then
    command -v zoxide >/dev/null && eval "$(zoxide init bash)"
    if [[ -L "$HOME/.config/starship.toml" ]] && command -v starship >/dev/null; then eval "$(starship init bash)"; fi
fi
[[ -f "$HOME/.fig/shell/bashrc.post.bash" ]] && builtin source "$HOME/.fig/shell/bashrc.post.bash"
