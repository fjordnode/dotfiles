#!/usr/bin/env zsh
# ~/.config/rm-safety.sh
# Safe rm wrapper with size info and single confirmation

### MAIN RM FUNCTION ###
rm() {
  local args=("$@")
  local force=0
  
  # Check for -f flag
  for arg in "$@"; do
    [[ "$arg" =~ f ]] && force=1
  done
  
  # If force flag, just run normal rm
  if [[ $force -eq 1 ]]; then
    /bin/rm "$@"
    return $?
  fi
  
  # Get total size and count of what we're about to delete
  local total_size count=0
  local yellow="\033[1;33m"
  local reset="\033[0m"
  
  # Count valid targets and get total size
  for target in "$@"; do
    if [[ ! "$target" =~ ^- ]] && [[ -e "$target" ]]; then
      ((count++))
    fi
  done
  
  # If no valid targets, just pass through
  if [[ $count -eq 0 ]]; then
    /bin/rm "$@"
    return $?
  fi
  
  # Calculate total size (suppress errors)
  total_size=$(du -sh $@ 2>/dev/null | tail -1 | awk '{print $1}')
  
  # Build prompt based on what we're deleting
  local prompt="${yellow}Delete"
  
  if [[ $count -eq 1 ]]; then
    # Single file - show its name
    local name
    for target in "$@"; do
      [[ ! "$target" =~ ^- ]] && [[ -e "$target" ]] && name="$target" && break
    done
    prompt+=" $name"
  else
    prompt+=" $count items"
  fi
  
  [[ -n "$total_size" ]] && prompt+=" (${total_size})"
  prompt+="? [y/N]: ${reset}"
  
  # Single confirmation for everything
  echo -en "$prompt"
  if read -q confirm; then
    echo  # New line
    /bin/rm "$@"
  else
    echo  # New line
    echo "Cancelled"
    return 1
  fi
}

### ALIASES ###
alias rmf='/bin/rm -rf'  # Force remove without confirmation
alias rmsafe='rm'         # Explicit safe rm
alias rmreal='/bin/rm'    # Real rm without wrapper

### HELP FUNCTION ###
rm-help() {
  cat <<'EOF'
Custom rm wrapper with safety features:
  
Commands:
  rm        - Remove with confirmation (shows size)
  rm -f     - Force remove (no confirmation)
  rmf       - Alias for /bin/rm -rf
  rmreal    - Direct access to /bin/rm
  
The wrapper shows:
  - Yellow confirmation prompt
  - Total size of files to delete
  - Single confirmation for multiple files
  
Config location: ~/.config/rm-safety.sh
EOF
}
