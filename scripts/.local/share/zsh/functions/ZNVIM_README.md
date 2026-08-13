# ZNVIM - Intelligent Fuzzy File Finder & Editor

A powerful command-line tool that combines zoxide's frecency-based directory tracking with smart pattern matching to instantly open files from anywhere in your filesystem.

## Installation

### Prerequisites
```bash
# Install required dependencies
brew install zoxide neovim fzf

# Optional but recommended for syntax-highlighted previews
brew install bat

# Enable zoxide in your shell (.zshrc)
eval "$(zoxide init zsh)"
```

### Setup
```bash
# Source the function in your .zshrc
source ~/.local/share/zsh/functions/fuzzy-nvim.zsh

# Or use the shorter alias
alias zvim='znvim'
```

## Core Concepts

ZNVIM leverages **zoxide's frecency algorithm** - it searches directories you visit frequently and recently first. The more you use a directory, the higher priority it gets in search results.

## Usage Patterns

### 1. Finding Files by Name
```bash
# Find any config.json in your frequently-used directories
zvim config.json

# Find .env files across all your projects
zvim .env

# Find that README you were working on
zvim README.md
```

### 2. Smart Path Matching
Use partial directory names with filenames:
```bash
# Find docker-compose.yml in a directory containing "plex"
zvim plex/docker

# Find nginx.conf in a directory containing "nginx"
zvim nginx/conf

# Smart matching: "doc" expands to match "docker-compose.yml"
zvim media/doc
```

### 3. Relative Paths
Navigate from your current location:
```bash
# Open file in current directory
zvim ./package.json

# Open file in parent directory
zvim ../README.md

# Navigate up multiple levels
zvim ../../config/settings.yml
```

### 4. Wildcard Patterns
**Must be quoted** to prevent shell expansion:
```bash
# Find all markdown files in Downloads
zvim 'dow/*.md'

# Find all TypeScript files in any Projects subdirectory
zvim 'proj/**/*.ts'

# Find all JSON files in tracked directories
zvim '*.json'

# Find all test files
zvim '*test*.js'
```

### 5. Fuzzy Directory Matching
Directory patterns are matched fuzzily and case-insensitively:
```bash
# "dow" matches "Downloads"
zvim dow/report.pdf

# "doc" matches "Documents"
zvim doc/notes.txt

# "proj" matches "Projects"
zvim proj/index.html
```

## Environment Variables

### Exclude Patterns
Skip unwanted directories during search:
```bash
# Default excludes
export ZNVIM_EXCLUDE="node_modules:.git:dist:build:target:.cache:.next:coverage:__pycache__"

# Add your own (colon-separated)
export ZNVIM_EXCLUDE="node_modules:.git:vendor:tmp"
```

### Disable Preview
For faster selection on slow systems:
```bash
# Disable file preview in fzf
export ZNVIM_NO_PREVIEW=1
```

## Pro Tips

### 1. Build Your Frecency Database
The more you navigate with zoxide, the better ZNVIM works:
```bash
# Use zoxide to jump around
z projects
z dotfiles
z downloads

# Or manually add important directories
zoxide add ~/Projects/important-project
zoxide add ~/Documents/notes
```

### 2. Common Workflows

**Quick Config Edits:**
```bash
# Edit your zsh config from anywhere
zvim .zshrc

# Jump to nvim config
zvim nvim/init.lua

# Find any docker-compose file
zvim docker-compose
```

**Project Navigation:**
```bash
# If you have a project called "myapp"
zvim myapp/package.json
zvim myapp/README
zvim 'myapp/**/*.test.js'
```

**Documentation Search:**
```bash
# Find all markdown docs in a project
zvim 'proj/*.md'

# Find API documentation
zvim api/swagger
```

### 3. Fallback Directories
When zoxide doesn't have a match, ZNVIM searches these common locations:
- `~/Downloads`
- `~/Desktop`
- `~/Documents`
- `~/Projects`
- `~` (home)
- `.` (current directory)

### 4. FZF Selection Tips
When multiple files match:
- Use arrow keys or `Ctrl-J/K` to navigate
- Type to filter results further
- `Enter` to open selected file
- `Esc` to cancel

### 5. Debugging Search Issues
```bash
# Check which directories zoxide knows about
zoxide query -l | head -20

# See zoxide's ranking for directories
zoxide query -s | head -20

# Manually boost a directory's score
cd ~/important/project && zoxide add .
```

## Examples by Use Case

### Web Development
```bash
# Find package.json in any project
zvim package.json

# Find all TypeScript config files
zvim tsconfig

# Find test files in current project
zvim './src/**/*.test.ts'

# Jump to a specific component
zvim components/Header
```

### System Administration
```bash
# Edit nginx configs
zvim nginx/sites-available

# Find docker compose files
zvim docker-compose

# Browse systemd services
zvim 'systemd/*.service'

# Quick edit of ssh config
zvim .ssh/config
```

### Note Taking
```bash
# Find today's notes
zvim notes/2024

# Find all markdown files
zvim '*.md'

# Quick journal access
zvim journal/
```

### Dotfiles Management
```bash
# Quick access to configs
zvim .zshrc
zvim .gitconfig
zvim kitty/kitty.conf
zvim tmux/tmux.conf
```

## Performance Tips

1. **Cache Warming**: Visit your important directories with `cd` or `z` to build zoxide's database
2. **Exclude Large Dirs**: Add heavy directories to `ZNVIM_EXCLUDE`
3. **Use Specific Patterns**: More specific patterns = faster searches
4. **Disable Preview**: Set `ZNVIM_NO_PREVIEW=1` for instant selection

## Troubleshooting

### "No files found"
- Check if the directory is in zoxide: `zoxide query -l | grep dirname`
- Navigate to the directory once: `cd /path/to/dir`
- Try a broader pattern or wildcard

### Slow Performance
- Exclude large directories: `export ZNVIM_EXCLUDE="node_modules:.git:dist"`
- Disable preview: `export ZNVIM_NO_PREVIEW=1`
- Use more specific search patterns

### Wrong File Opens
- ZNVIM returns files in frecency order (most frequently/recently used first)
- Use more specific patterns to narrow results
- Use the full path if needed: `zvim specific/project/file.txt`

## Advanced Patterns

```bash
# Hidden files in home
zvim '~/.*rc'

# All shell scripts
zvim '**/*.sh'

# Config files in .config
zvim '.config/*/config'

# Test files but not in node_modules (already excluded)
zvim '**/test/*.js'

# Multiple extension search
zvim '*.{yml,yaml}'
```

## Integration Ideas

### Git Workflow
```bash
# Quick edit of changed files
git status --short | awk '{print $2}' | xargs -I {} zvim {}
```

### Project Launcher
```bash
# Add to your .zshrc
function proj() {
  zvim "$1/README.md"
}
# Usage: proj myproject
```

### Config Switcher
```bash
# Add to your .zshrc
function conf() {
  case "$1" in
    vim) zvim nvim/init.lua ;;
    zsh) zvim .zshrc ;;
    git) zvim .gitconfig ;;
    tmux) zvim tmux.conf ;;
    *) echo "Unknown config: $1" ;;
  esac
}
```

## Why ZNVIM?

- **No More `cd` Navigation**: Open files directly from anywhere
- **Smart Matching**: Partial names and fuzzy matching just work
- **Frecency-Based**: Prioritizes your frequently-used directories
- **Fast**: Caches zoxide results and excludes unnecessary directories
- **Flexible**: Supports wildcards, relative paths, and smart patterns
- **Visual**: Colored output and file previews (with bat)

Stop navigating, start editing!
