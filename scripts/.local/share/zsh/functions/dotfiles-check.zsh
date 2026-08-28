#!/usr/bin/env zsh
# Manually report uncommitted or unpushed dotfile changes.

check_dotfiles_changes() {
  local directory=${DOTFILES_DIR:-$HOME/dotfiles} upstream ahead
  [[ -d $directory/.git ]] || { print -u2 "Not a Git checkout: $directory"; return 1; }

  if [[ -n $(git -C "$directory" status --porcelain) ]]; then
    print -P '%F{yellow}Dotfiles have uncommitted changes%f'
  fi

  upstream=$(git -C "$directory" rev-parse --abbrev-ref '@{u}' 2>/dev/null) || return 0
  ahead=$(git -C "$directory" rev-list --count "$upstream"..HEAD 2>/dev/null) || return 0
  (( ahead > 0 )) && print -P "%F{yellow}Dotfiles have $ahead unpushed commit(s)%f"
}
