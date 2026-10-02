# shellcheck shell=bash
# Aliases and functions shared by the Bash and Zsh configurations.

if command -v eza >/dev/null; then
    alias ls='eza --icons=always'
    alias ll='eza -la --icons=always --git'
    alias tree='eza --tree --icons=always'
fi
command -v bat >/dev/null && alias cat='bat'
alias ..='cd ..'
alias ...='cd ../..'
alias hm='herdr' hml='herdr session list' hmk='herdr session stop'

# Pi inside a Herdr pane, so the integration can report agent state; otherwise open Herdr.
pit() {
    if [[ -n "${HERDR_PANE_ID:-}" ]]; then command pi "$@"; else herdr; fi
}

copy() {
    local command_name
    if [[ "$OSTYPE" == darwin* ]]; then command_name=pbcopy
    elif command -v wl-copy >/dev/null; then command_name=wl-copy
    elif command -v xclip >/dev/null; then command_name='xclip -selection clipboard'
    else printf 'No clipboard command available\n' >&2; return 1; fi
    if [[ $# -gt 0 ]]; then command cat -- "$@" | $command_name; else command cat | $command_name; fi
}

if [[ "$OSTYPE" != darwin* ]]; then . "$BOOTSTRAP_ROOT/repo/shell/open.sh"; fi
