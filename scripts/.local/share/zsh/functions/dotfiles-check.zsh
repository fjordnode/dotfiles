#!/usr/bin/env zsh
# =============================================================================
# Dotfiles Git Status Checker
# =============================================================================
# 
# Provides visual warnings when dotfiles have uncommitted changes or unpushed commits.
# Helps prevent losing configuration changes and maintains sync with remote repository.
#
# Features:
# - Shows ⚠ warning for uncommitted changes (modified, added, deleted files)
# - Shows ⬆ warning for unpushed commits ahead of origin
# - Integrates with prompt via precmd hook
# - Only checks if dotfiles directory is a git repository
#
# Usage:
# - Automatically runs before each prompt
# - Manually call: check_dotfiles_changes
#
# =============================================================================

# Dotfiles tracking warning function
function check_dotfiles_changes() {
    local dfdir="$HOME/dotfiles"
    # Only check if the repo exists
    [[ -d "$dfdir/.git" ]] || return
    # Check for uncommitted changes
    if [[ -n "$(git -C "$dfdir" status --porcelain)" ]]; then
        print -P "%F{yellow}⚠ Dotfiles have uncommitted changes%f"
    else
        # Check if upstream branch exists and if local is ahead
        local upstream
        upstream=$(git -C "$dfdir" rev-parse --abbrev-ref @{u} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            # Check if local branch is ahead of upstream
            local ahead
            ahead=$(git -C "$dfdir" rev-list --count "$upstream"..HEAD 2>/dev/null)
            if [[ "$ahead" -gt 0 ]]; then
                print -P "%F{yellow}⬆ Dotfiles have $ahead commit(s) not pushed to GitHub%f"
            fi
        fi
    fi
}
