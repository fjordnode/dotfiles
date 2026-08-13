#!/usr/bin/env zsh
# =============================================================================
# Fuzzy Directory Listing Functions
# =============================================================================
#
# Enhanced directory listing that combines zoxide (smart directory jumping) 
# with eza (modern ls replacement) to list directories without changing location.
#
# Dependencies:
# - zoxide: Smart directory jumping based on frecency
# - eza: Modern ls replacement with icons and git integration
#
# Functions:
# - zls [query]: List directory contents (basic view)
# - zll [query]: Long listing with git status and details
# - zla [query]: All files including hidden, with git status
# - zlt [query] [level]: Tree view with configurable depth
#
# Usage Examples:
#   zls                 # Interactive directory picker
#   zls proj            # List ~/Projects directory  
#   zll documents       # Long list ~/Documents
#   zla dotfiles        # All files in ~/dotfiles
#   zlt                 # Interactive tree picker (depth 2)
#   zlt proj            # Tree view of ~/Projects
#   zlt 3               # Tree view of current dir (depth 3)
#   zlt nvim 4          # Tree view of nvim config (depth 4)
#
# Features:
# - Uses zoxide database for smart directory matching
# - Interactive fzf picker when no argument provided
# - Colorful output with icons and git status
# - Groups directories first for better readability
#
# =============================================================================

# Fuzzy directory listing functions
function zls() {
  # Check for required dependencies
  if ! command -v zoxide >/dev/null 2>&1; then
    echo "❌ Error: zoxide is not installed. Install it with: brew install zoxide"
    return 1
  fi
  if ! command -v eza >/dev/null 2>&1; then
    echo "❌ Error: eza is not installed. Install it with: brew install eza"
    return 1
  fi
  
  local dir
  if [ $# -eq 0 ]; then
    # No arguments - use zi to pick directory interactively
    dir=$(zoxide query -i)
  else
    # Use argument as zoxide query
    dir=$(zoxide query "$1" 2>/dev/null)
  fi
  
  if [ -n "$dir" ]; then
    echo "📁 Listing: $dir"
    eza --icons --color=always --group-directories-first "$dir"
  fi
}

function zll() {
  # Check for required dependencies
  if ! command -v zoxide >/dev/null 2>&1; then
    echo "❌ Error: zoxide is not installed. Install it with: brew install zoxide"
    return 1
  fi
  if ! command -v eza >/dev/null 2>&1; then
    echo "❌ Error: eza is not installed. Install it with: brew install eza"
    return 1
  fi
  
  local dir
  if [ $# -eq 0 ]; then
    dir=$(zoxide query -i)
  else
    dir=$(zoxide query "$1" 2>/dev/null)
  fi
  
  if [ -n "$dir" ]; then
    echo "📁 Long listing: $dir"
    eza -l --icons --color=always --group-directories-first --git "$dir"
  fi
}

function zla() {
  # Check for required dependencies
  if ! command -v zoxide >/dev/null 2>&1; then
    echo "❌ Error: zoxide is not installed. Install it with: brew install zoxide"
    return 1
  fi
  if ! command -v eza >/dev/null 2>&1; then
    echo "❌ Error: eza is not installed. Install it with: brew install eza"
    return 1
  fi
  
  local dir
  if [ $# -eq 0 ]; then
    dir=$(zoxide query -i)
  else
    dir=$(zoxide query "$1" 2>/dev/null)
  fi
  
  if [ -n "$dir" ]; then
    echo "📁 All files: $dir"
    eza -la --icons --color=always --group-directories-first --git "$dir"
  fi
}

function zlt() {
  # Check for required dependencies
  if ! command -v zoxide >/dev/null 2>&1; then
    echo "❌ Error: zoxide is not installed. Install it with: brew install zoxide"
    return 1
  fi
  if ! command -v eza >/dev/null 2>&1; then
    echo "❌ Error: eza is not installed. Install it with: brew install eza"
    return 1
  fi
  
  local dir level=2
  
  # Parse arguments: zlt [query] [level]
  if [ $# -eq 0 ]; then
    dir=$(zoxide query -i)
  elif [ $# -eq 1 ]; then
    # Check if argument is a number (level) or directory query
    if [[ "$1" =~ ^[0-9]+$ ]]; then
      dir=$(pwd)
      level="$1"
    else
      dir=$(zoxide query "$1" 2>/dev/null)
    fi
  else
    dir=$(zoxide query "$1" 2>/dev/null)
    level="$2"
  fi
  
  if [ -n "$dir" ]; then
    echo "🌳 Tree view: $dir (level $level)"
    eza --tree --icons --color=always --level="$level" --group-directories-first "$dir"
  fi
}
