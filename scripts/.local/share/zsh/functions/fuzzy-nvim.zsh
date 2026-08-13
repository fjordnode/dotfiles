#!/usr/bin/env zsh
# =============================================================================
# Intelligent Fuzzy File Finder and Editor (znvim)
# =============================================================================
#
# A revolutionary file finding and editing tool that combines frecency-based 
# directory tracking with smart pattern matching to open files from anywhere
# in your filesystem without remembering exact paths.
#
# Dependencies:
# - zoxide: Smart directory jumping based on frecency
# - nvim: Neovim text editor
# - fzf: Fuzzy finder for interactive selection
# - bat: Syntax highlighting for file previews (optional)
#
# Core Features:
# - Manual directory indexing: Index entire directory trees for searching
# - Smart path/pattern matching: "plex/doc" → "plex/docker-compose.yml"
# - Wildcard/glob support: "dow/*.md" → all markdown files in Downloads
# - Relative path support: "./config.json", "../README.md"
# - Exclude patterns: Automatically skips node_modules, .git, etc.
# - Prefix completion: "doc" matches "docker-compose.yml"
# - Case-insensitive matching: "dow" matches "Downloads"
# - Frecency-based search: Uses your directory visit history
# - Fallback search: Searches common directories if not in zoxide db
# - Interactive selection: Beautiful fzf interface with file previews
# - Direct editor integration: Opens files immediately in nvim
#
# Usage Patterns:
#
#   Manual indexing (for docker-compose setups, monorepos, etc):
#     znvim-index ~/compose         # Index all subdirectories
#     znvim-index ~/compose 2       # Index only 2 levels deep
#     znvim-index .                 # Index current directory tree
#
#   Exact filename anywhere:
#     znvim config.json         # Find config.json in any visited directory
#     znvim .env               # Find .env files across projects
#     znvim README.md          # Find README in any project
#
#   Smart path matching:
#     znvim plex/doc           # Find docker-compose.yml in plex directory
#     znvim nginx/conf         # Find config files in nginx directory
#     znvim media/env          # Find .env in media-related directory
#
#   Relative paths:
#     znvim ./config.json      # Open config.json in current directory
#     znvim ../README.md       # Open README.md in parent directory
#
#   Partial directory names:
#     znvim dow/file           # Search Downloads for file*
#     znvim doc/read           # Search Documents for read*
#     znvim proj/docker        # Search Projects for docker*
#
#   Wildcard patterns (MUST be quoted):
#     znvim 'dow/*.md'         # All markdown files in Downloads
#     znvim '*.json'           # All JSON files in tracked directories
#     znvim 'proj/*.ts'        # All TypeScript files in Projects
#     znvim '**/*.yml'         # All YAML files recursively
#
# Environment Variables:
#   ZNVIM_EXCLUDE - Colon-separated list of directories to exclude
#                   Default: "node_modules:.git:dist:build:target:.cache"
#   ZNVIM_NO_PREVIEW - Set to 1 to disable file preview in fzf
#
# Algorithm:
# 1. Handle relative paths directly if they start with ./ or ../
# 2. Parse query into directory pattern and filename pattern
# 3. Cache and search zoxide database for matching directories
# 4. Look for files matching the filename pattern in found directories
# 5. If no matches, search common directories (Downloads, Documents, etc.)
# 6. Present single match immediately or show fzf picker for multiple matches
# 7. Open selected file in nvim with full path displayed
#
# Examples:
#   znvim hu/.zsh           # Finds .zshrc, .zshenv in /Users/hugo/
#   znvim plex/docker       # Finds docker-compose.yml in plex container dir
#   znvim config.json       # Finds any config.json in visited directories
#   znvim ./test.sh         # Opens test.sh in current directory
#   znvim 'dow/*.md'        # Finds all .md files in Downloads (note quotes!)
#   znvim '*.yml'           # Finds all .yml files in tracked directories
#   znvim                   # Shows usage help
#
# Security:
# - Shows full file path before opening
# - Uses read-only search operations
# - Respects file permissions
# - No file modification during search
#
# =============================================================================

# Helper function to manually index a directory tree into zoxide
function znvim-index() {
  local target_dir="${1:-.}"
  local max_depth="${2:-3}"
  
  # Color codes
  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[0;33m'
  local BLUE='\033[0;34m'
  local NC='\033[0m'
  
  # Resolve to absolute path
  target_dir="$(cd "$target_dir" 2>/dev/null && pwd)"
  
  if [ ! -d "$target_dir" ]; then
    echo -e "${RED}❌ Error: Directory not found: $target_dir${NC}"
    return 1
  fi
  
  echo -e "${BLUE}📁 Indexing directory tree: $target_dir${NC}"
  echo -e "${YELLOW}   Max depth: $max_depth levels${NC}"
  
  local count=0
  local exclude_patterns="node_modules:.git:dist:build:target:.cache:.next:coverage:__pycache__"
  
  # Function to check if directory should be excluded
  function should_skip() {
    local dir="$1"
    local IFS=':'
    for pattern in ${=exclude_patterns}; do
      if [[ "$dir" == *"/$pattern" ]] || [[ "$dir" == *"/$pattern/"* ]]; then
        return 0
      fi
    done
    return 1
  }
  
  # Find all directories up to max_depth and add to zoxide
  while IFS= read -r dir; do
    if ! should_skip "$dir"; then
      zoxide add "$dir" 2>/dev/null
      count=$((count + 1))
      echo -e "   ${GREEN}✓${NC} $(basename "$dir")"
    fi
  done < <(find "$target_dir" -type d -maxdepth "$max_depth" 2>/dev/null)
  
  echo -e "${GREEN}✅ Indexed $count directories into zoxide${NC}"
  echo -e "${YELLOW}💡 Now you can use: zvim $(basename "$target_dir")/filename${NC}"
  
  # Show example usage for docker-compose setup
  if [ -f "$target_dir/docker-compose.yml" ] || find "$target_dir" -name "docker-compose.yml" -maxdepth 2 2>/dev/null | head -1 | grep -q .; then
    echo -e "\n${BLUE}Docker Compose detected! Example usage:${NC}"
    local containers=($(find "$target_dir" -maxdepth 2 -name "docker-compose.yml" -exec dirname {} \; 2>/dev/null | xargs -n1 basename | head -3))
    for container in "${containers[@]}"; do
      echo -e "   zvim $container/docker-compose"
    done
  fi
}

function znvim() {
  # Color codes for better UX
  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[0;33m'
  local BLUE='\033[0;34m'
  local NC='\033[0m' # No Color
  
  # Check for required dependencies
  if ! command -v zoxide >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: zoxide is not installed${NC}"
    echo "Install it with: $(command -v apt >/dev/null 2>&1 && echo 'sudo apt install zoxide' || echo 'brew install zoxide')"
    return 1
  fi
  if ! command -v nvim >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: nvim is not installed${NC}"
    echo "Install it with: $(command -v apt >/dev/null 2>&1 && echo 'sudo apt install neovim' || echo 'brew install neovim')"
    return 1
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: fzf is not installed${NC}"
    echo "Install it with: $(command -v apt >/dev/null 2>&1 && echo 'sudo apt install fzf' || echo 'brew install fzf')"
    return 1
  fi
  
  # Excluded directories (can be overridden by ZNVIM_EXCLUDE env var)
  local exclude_patterns="${ZNVIM_EXCLUDE:-node_modules:.git:dist:build:target:.cache:.next:coverage:__pycache__}"
  
  # Common directories to search when zoxide doesn't have results
  local common_dirs=(
    "$HOME/Downloads"
    "$HOME/Desktop" 
    "$HOME/Documents"
    "$HOME/Projects"
    "$HOME"
    "."
  )
  
  local query="$1"
  if [ -z "$query" ]; then
    echo "Usage: znvim <filename|path/pattern|path/wildcard>"
    echo ""
    echo "Examples:"
    echo "  znvim config.json              # Find config.json anywhere"
    echo "  znvim plex/docker-compose.yml  # Find in plex directory"
    echo "  znvim plex/doc                 # Smart match: plex/docker-compose.yml"
    echo "  znvim ./config.json            # Open config.json in current directory"
    echo "  znvim ../README.md             # Open README.md in parent directory"
    echo "  znvim 'dow/*.md'               # Find all .md files in Downloads"
    echo "  znvim 'proj/**/README.md'      # Find all README.md in Projects"
    echo ""
    echo "Environment variables:"
    echo "  ZNVIM_EXCLUDE='node_modules:.git'  # Directories to exclude"
    echo "  ZNVIM_NO_PREVIEW=1                  # Disable file preview"
    return 1
  fi
  
  # Handle relative paths (./file or ../file)
  if [[ "$query" == ./* ]] || [[ "$query" == ../* ]]; then
    local resolved_path="$(cd "$(dirname "$query")" 2>/dev/null && pwd)/$(basename "$query")"
    if [ -f "$resolved_path" ]; then
      echo -e "${GREEN}📝 Opening: $resolved_path${NC}"
      nvim "$resolved_path"
      return
    else
      echo -e "${RED}❌ File not found: $query${NC}"
      return 1
    fi
  fi
  
  # Cache zoxide directories for performance
  local zoxide_dirs=()
  while IFS= read -r dir; do
    zoxide_dirs+=("$dir")
  done < <(zoxide query -l 2>/dev/null)
  
  # Helper function to check if a path should be excluded
  function should_exclude() {
    local path="$1"
    local IFS=':'
    for pattern in ${=exclude_patterns}; do
      if [[ "$path" == *"/$pattern/"* ]] || [[ "$path" == *"/$pattern" ]]; then
        return 0  # Should exclude
      fi
    done
    return 1  # Should not exclude
  }
  
  # Helper function to search for files in a directory
  function search_files() {
    local dir="$1"
    local file_pattern="$2"
    local has_wildcard="$3"
    local found=()
    
    if [ ! -d "$dir" ] || ! [ -r "$dir" ]; then
      return
    fi
    
    setopt local_options null_glob
    
    if [[ "$has_wildcard" == true ]]; then
      # Use glob expansion for wildcard patterns
      setopt local_options nocasematch nocaseglob
      local glob_pattern="$dir/$file_pattern"
      for file in ${~glob_pattern}; do
        if [ -f "$file" ] && ! should_exclude "$file"; then
          found+=("$file")
        fi
      done
      unsetopt nocasematch nocaseglob
    else
      # Look for files that start with the pattern
      setopt local_options nocasematch nocaseglob
      for file in "$dir"/"$file_pattern"*; do
        if [ -f "$file" ] && ! should_exclude "$file"; then
          found+=("$file")
        fi
      done
      unsetopt nocasematch nocaseglob
      
      # Also try exact match
      if [ -f "$dir/$file_pattern" ] && ! should_exclude "$dir/$file_pattern"; then
        found+=("$dir/$file_pattern")
      fi
    fi
    
    unsetopt null_glob
    
    # Return found files
    for f in "${found[@]}"; do
      echo "$f"
    done
  }
  
  # Check if query contains wildcards
  local has_wildcard=false
  if [[ "$query" == *"*"* ]]; then
    has_wildcard=true
  fi
  
  # Handle dotfiles/hidden paths (e.g., .config/nvim/init.lua)
  if [[ "$query" == .* ]] && [[ "$query" != "./"* ]] && [[ "$query" != "../"* ]]; then
    # Check if it's a direct path in home directory
    if [ -f "$HOME/$query" ]; then
      echo -e "${GREEN}📝 Opening: $HOME/$query${NC}"
      nvim "$HOME/$query"
      return
    fi
    # Otherwise continue with normal search
  fi
  
  local found_files=()
  
  # Check if query contains a slash (path-like)
  if [[ "$query" == *"/"* ]]; then
    # Split into directory pattern and filename pattern
    local dir_pattern="${query%/*}"
    local file_pattern="${query##*/}"
    
    # Search in zoxide-tracked directories
    for dir in "${zoxide_dirs[@]}"; do
      # Check if directory matches the pattern (case-insensitive)
      if [[ "${dir:l}" == *"${dir_pattern:l}"* ]]; then
        while IFS= read -r file; do
          found_files+=("$file")
        done < <(search_files "$dir" "$file_pattern" "$has_wildcard")
      fi
    done
    
    # Search in common directories if not found
    if [ ${#found_files[@]} -eq 0 ]; then
      for base_dir in "${common_dirs[@]}"; do
        if [ -d "$base_dir" ]; then
          # Check subdirectories
          for subdir in "$base_dir"/*; do
            local subdir_name="${subdir##*/}"
            if [ -d "$subdir" ] && [[ "${subdir_name:l}" == *"${dir_pattern:l}"* ]]; then
              while IFS= read -r file; do
                found_files+=("$file")
              done < <(search_files "$subdir" "$file_pattern" "$has_wildcard")
            fi
          done
          
          # Check base directory itself
          local base_dir_name="${base_dir##*/}"
          if [[ "${base_dir_name:l}" == *"${dir_pattern:l}"* ]]; then
            while IFS= read -r file; do
              found_files+=("$file")
            done < <(search_files "$base_dir" "$file_pattern" "$has_wildcard")
          fi
        fi
      done
    fi
  else
    # Search for filename (with or without wildcards)
    
    # Search in zoxide directories
    for dir in "${zoxide_dirs[@]}"; do
      while IFS= read -r file; do
        found_files+=("$file")
      done < <(search_files "$dir" "$query" "$has_wildcard")
    done
    
    # Search in common directories if not found
    if [ ${#found_files[@]} -eq 0 ]; then
      for base_dir in "${common_dirs[@]}"; do
        while IFS= read -r file; do
          found_files+=("$file")
        done < <(search_files "$base_dir" "$query" "$has_wildcard")
      done
    fi
  fi
  
  # Remove duplicates using associative array
  local -A seen
  local unique_files=()
  for file in "${found_files[@]}"; do
    if [ -z "${seen[$file]}" ]; then
      unique_files+=("$file")
      seen[$file]=1
    fi
  done
  found_files=("${unique_files[@]}")
  
  # Display results
  case ${#found_files[@]} in
    0)
      echo -e "${RED}❌ No files matching '$query' found in tracked directories${NC}"
      echo -e "${YELLOW}💡 Try: nvim $query (to create it here)${NC}"
      ;;
    1)
      echo -e "${GREEN}📝 Opening: ${found_files[1]}${NC}"
      nvim "${found_files[1]}"
      ;;
    *)
      echo -e "${BLUE}📝 Found ${#found_files[@]} files matching '$query':${NC}"
      local choice
      local preview_cmd
      
      # Setup preview command based on availability and preferences
      if [ -n "$ZNVIM_NO_PREVIEW" ]; then
        preview_cmd=""
      elif command -v bat >/dev/null 2>&1; then
        preview_cmd="--preview=bat --color=always --style=header,grid --line-range :50 {}"
      else
        preview_cmd="--preview=head -50 {}"
      fi
      
      choice=$(printf '%s\n' "${found_files[@]}" | fzf --prompt="Select file to edit: " $preview_cmd)
      
      if [ -n "$choice" ]; then
        echo -e "${GREEN}📝 Opening: $choice${NC}"
        nvim "$choice"
      fi
      ;;
  esac
}
