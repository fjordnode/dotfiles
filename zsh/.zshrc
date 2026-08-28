# MUST be set BEFORE oh-my-zsh loads to prevent title changes
DISABLE_AUTO_TITLE="true"

# Core oh-my-zsh setup
export ZSH="$HOME/.oh-my-zsh"

# zsh-opencode-tab configuration (must be set before plugins load)
export Z_OC_TAB_OPENCODE_MODEL="anthropic/claude-haiku-4-5"

# Built-in Oh My Zsh plugins. Optional plugins are added only when installed,
# so this file also starts cleanly on a fresh machine.
plugins=(
  git
  z                              # Jump to frequent directories
  fzf                            # Fuzzy finder integration
  sudo                           # Double ESC to add sudo
  extract                        # Extract any archive
  command-not-found              # Suggest packages to install
  colored-man-pages              # Better man page readability
  aliases                        # 'acs' to list all aliases
  history-substring-search
)
ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"
[[ -d "$ZSH_CUSTOM/plugins/zsh-completions" ]] && plugins+=(zsh-completions)
[[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] && plugins+=(zsh-autosuggestions)
[[ -d "$ZSH_CUSTOM/plugins/fzf-tab" ]] && plugins+=(fzf-tab)
[[ -d "$ZSH_CUSTOM/plugins/zsh-opencode-tab" ]] && plugins+=(zsh-opencode-tab)
# Syntax highlighting should be loaded last.
[[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] && plugins+=(zsh-syntax-highlighting)

# PATH exports
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.local/nvim/bin:$PATH"

# FZF setup - auto-detect installation path
if [ -d "/opt/homebrew/opt/fzf" ]; then
  export FZF_BASE="/opt/homebrew/opt/fzf"  # macOS Apple Silicon
elif [ -d "/usr/local/opt/fzf" ]; then
  export FZF_BASE="/usr/local/opt/fzf"     # macOS Intel
elif [ -d "/usr/share/fzf" ]; then
  export FZF_BASE="/usr/share/fzf"         # Ubuntu/Debian
elif [ -d "/usr/share/doc/fzf" ]; then
  export FZF_BASE="/usr/share/doc/fzf"     # Some other Linux distros
fi

# Source private environment variables (API keys, etc.)
[ -f ~/.env ] && [ -r ~/.env ] && source ~/.env

# Source oh-my-zsh
[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# Editor and terminal settings
export EDITOR="${EDITOR:-nvim}"
export TERM="${TERM:-xterm-256color}"
export LS_COLORS="${LS_COLORS:-}:ow=01;36:tw=01;34:"
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

# Aliases
alias c='clear'
alias ll='ls -lah --color=auto'
alias la='ls -A'
alias v='nvim'
alias mosh="MOSH_TITLE_NOPREFIX=1 mosh --predict=never"

# Launch Yazi and enter the directory selected when it exits. Press Q in Yazi
# to exit without changing the current shell directory.
y() {
  if ! command -v yazi >/dev/null 2>&1; then
    print -u2 'yazi is not installed'
    return 127
  fi
  local tmp cwd
  tmp="$(mktemp -t 'yazi-cwd.XXXXXX')" || return
  command yazi "$@" --cwd-file="$tmp"
  cwd="$(command cat -- "$tmp")"
  command rm -f -- "$tmp"
  [[ -n "$cwd" && "$cwd" != "$PWD" && -d "$cwd" ]] && builtin cd -- "$cwd"
}

# Host-specific helpers
[ -f "$HOME/.config/zsh/host.zsh" ] && source "$HOME/.config/zsh/host.zsh"

# Terminal cleanup - prevents garbage output after SSH disconnects
cleanup_terminal() {
  printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l\033[?2004l'
  stty sane 2>/dev/null || true
}
trap cleanup_terminal EXIT TERM
alias fixterm='cleanup_terminal; tput rmcup 2>/dev/null; reset'

# fd/fdfind compatibility (Ubuntu/Debian use fdfind)
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  alias fd=fdfind
fi

# Modern tool aliases (if available)
if command -v eza >/dev/null 2>&1; then
  export EZA_CONFIG_DIR="$HOME/.config/eza"
  alias ls='eza --icons --color=always --group-directories-first'
  alias ll='eza -l --icons --color=always --group-directories-first --git'
  alias la='eza -la --icons --color=always --group-directories-first --git'
  alias lt='eza --tree --icons --color=always --level=2'
fi
command -v bat >/dev/null 2>&1 && export BAT_THEME="Catppuccin-mocha" && alias cat='bat'
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# History settings
HISTFILE="$HOME/.zsh_history"
HISTSIZE=200000
SAVEHIST=200000
setopt HIST_IGNORE_ALL_DUPS HIST_IGNORE_DUPS HIST_REDUCE_BLANKS SHARE_HISTORY EXTENDED_HISTORY INC_APPEND_HISTORY

# Completion caching
autoload -Uz compinit
compinit -C

# FZF configuration
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --no-ignore-vcs 2>/dev/null || fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Keybindings - only bind plugin widgets when they were loaded successfully.
if (( ${+widgets[history-substring-search-up]} )); then
  bindkey -M emacs '^[[A' history-substring-search-up
  bindkey -M emacs '^[[B' history-substring-search-down
fi

# Load custom functions
[ -f "$HOME/.local/share/shell-functions.sh" ] && source "$HOME/.local/share/shell-functions.sh"
[ -f ~/.local/bin/rm-safety ] && source ~/.local/bin/rm-safety
for function_file in "$HOME/.local/share/zsh/functions"/*.zsh(N); do
  [[ -r "$function_file" ]] && source "$function_file"
done
unset function_file

# Completion settings
setopt globdots
zstyle ':completion:*' special-dirs false

# Starship prompt
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# Theme reload via FIFO — safe alternative to SIGUSR1 (won't kill TUIs)
_theme_reload_setup() {
  local fifo="/tmp/zsh-reload-$$"
  [[ -p "$fifo" ]] || mkfifo "$fifo" 2>/dev/null
  exec {_reload_fd}<>"$fifo"

  _theme_reload_handler() {
    local dummy
    read -r dummy <&$_reload_fd 2>/dev/null
    zle .reset-prompt
    zle -R
  }

  zle -N _theme_reload_handler
  zle -F $_reload_fd _theme_reload_handler
  zshexit() { rm -f "/tmp/zsh-reload-$$" 2>/dev/null; }
}
_theme_reload_setup

# Set tab title to hostname: folder
precmd() {
  print -Pn "\e]0;%m: %1~\a"
}

# Load local customizations
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# Conservative default; host-specific overrides can go in ~/.zshrc.local.
umask 022

export PATH="$HOME/.local/npm-global/bin:$PATH"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Pi standalone installer (uses a stable `current` symlink)
[ -d "$HOME/.local/share/pi-node/current/bin" ] && export PATH="$HOME/.local/share/pi-node/current/bin:$PATH"

# opencode
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"
