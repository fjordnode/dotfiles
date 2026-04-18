# MUST be set BEFORE oh-my-zsh loads to prevent title changes
DISABLE_AUTO_TITLE="true"

# Core oh-my-zsh setup
export ZSH="$HOME/.oh-my-zsh"

# zsh-opencode-tab configuration (must be set before plugins load)
export Z_OC_TAB_OPENCODE_MODEL="anthropic/claude-haiku-4-5"

# Plugins
plugins=(
  git
  z                              # Jump to frequent directories
  fzf                            # Fuzzy finder integration
  sudo                           # Double ESC to add sudo
  extract                        # Extract any archive
  command-not-found              # Suggest packages to install
  colored-man-pages              # Better man page readability
  aliases                        # 'acs' to list all aliases
  zsh-completions
  history-substring-search
  zsh-autosuggestions
  zsh-syntax-highlighting
  fzf-tab                        # Better tab completion with fzf
  zsh-opencode-tab               # AI-powered command generation (# comment<TAB>)
)
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
source "$ZSH/oh-my-zsh.sh"

# Editor and terminal settings
export EDITOR=nvim
export TERM=xterm-256color
export LS_COLORS="$LS_COLORS:ow=01;36:tw=01;34:"
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

# Omarchy bash aliases and functions (tmux layouts, git shortcuts, etc.)
export OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
source "$OMARCHY_PATH/default/bash/aliases"
source "$OMARCHY_PATH/default/bash/functions"

# Aliases (overrides omarchy defaults where needed)
alias c='clear'
alias ll='ls -lah --color=auto'
alias la='ls -A'
alias v='nvim'
alias zv='znvim'
alias mosh="MOSH_TITLE_NOPREFIX=1 mosh --predict=never"
# Cloudflare Tunnel management
TUNNEL_ID="ca41a301-707f-48bf-bfc2-5181247d8875"
CF_CONFIG="/mnt/cache/appdata/cloudflared/config.yml"

tunnel-add() {
  if grep -q "hostname: $1.denshi.dev" "$CF_CONFIG" 2>/dev/null; then
    echo "⚠️  $1.denshi.dev already exists in config.yml"
    return 1
  fi
  docker run --rm --user 0:0 -v /mnt/cache/appdata/cloudflared:/root/.cloudflared cloudflare/cloudflared:latest tunnel route dns $TUNNEL_ID "$1.denshi.dev"
  echo ""
  echo "✅ DNS added. Paste this into $CF_CONFIG (before the catch-all):"
  echo ""
  echo "  - hostname: $1.denshi.dev"
  echo "    service: https://traefik:443"
  echo "    originRequest:"
  echo "      noTLSVerify: true"
  echo ""
  echo "Then run: docker restart cloudflared"
}

tunnel-remove() {
  echo "To remove $1.denshi.dev:"
  echo ""
  echo "1. Remove the entry from $CF_CONFIG"
  echo "2. Run: docker restart cloudflared"
  echo "3. Delete the CNAME record in Cloudflare dashboard (DNS → $1.denshi.dev)"
  echo ""
  echo "   Or via API:"
  echo "   curl -X DELETE \"https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records/RECORD_ID\""
}

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

# Keybindings - history substring search
bindkey -M emacs '^[[A' history-substring-search-up
bindkey -M emacs '^[[B' history-substring-search-down

# Load custom functions
[ -f ~/.local/bin/rm-safety ] && source ~/.local/bin/rm-safety
source "$HOME/dotfiles/shell/functions/dotfiles-check.zsh"
source "$HOME/dotfiles/shell/functions/fuzzy-listing.zsh"
source "$HOME/dotfiles/shell/functions/fuzzy-nvim.zsh"

# Completion settings
setopt globdots
zstyle ':completion:*' special-dirs false

# Starship prompt
eval "$(starship init zsh)"

# Theme reload via FIFO — safe alternative to SIGUSR1 (won't kill tmux/TUIs)
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

# Default file permissions
umask 002

# opencode
export PATH=/home/hugo/.opencode/bin:$PATH
export PATH="$HOME/.local/npm-global/bin:$PATH"

# bun completions
[ -s "/home/hugo/.bun/_bun" ] && source "/home/hugo/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
