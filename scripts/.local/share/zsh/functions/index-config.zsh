#!/usr/bin/env zsh
# Index all .config subdirectories into zoxide for znvim to find

index_config() {
  echo "📁 Indexing .config directories..."
  local count=0
  
  # Find all directories in .config and add them to zoxide
  while IFS= read -r dir; do
    zoxide add "$dir" 2>/dev/null
    ((count++))
  done < <(find "$HOME/.config" -type d 2>/dev/null)
  
  # Also index dotfiles directories
  if [ -d "$HOME/dotfiles" ]; then
    while IFS= read -r dir; do
      zoxide add "$dir" 2>/dev/null
      ((count++))
    done < <(find "$HOME/dotfiles" -type d 2>/dev/null)
  fi
  
  echo "✅ Indexed $count directories!"
}

# Create a quick alias for re-indexing
alias zindex='index_config'

# Don't auto-run - only provide the command
