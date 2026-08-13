#!/usr/bin/env zsh
# Index important config directories with zoxide for quick access

index_configs() {
  echo "📁 Indexing config directories for znvim..."
  
  # List of important directories to index
  local dirs=(
    "$HOME/.config"
    "$HOME/.config/nvim"
    "$HOME/.config/tmux"
    "$HOME/.config/alacritty"
    "$HOME/.config/kitty"
    "$HOME/.config/zsh"
    "$HOME/.config/git"
    "$HOME/dotfiles"
    "$HOME/.local/share"
    "$HOME/.local/bin"
  )
  
  for dir in "${dirs[@]}"; do
    if [ -d "$dir" ]; then
      # Add to zoxide database by "visiting" it
      zoxide add "$dir" 2>/dev/null && echo "  ✓ Indexed: $dir"
    fi
  done
  
  echo "✅ Config directories indexed!"
}

# Run this function occasionally or on demand
# index_configs
