#!/usr/bin/env zsh
# List a zoxide-selected directory with eza.

_zlist() {
  local mode=$1 query=${2:-} level=${3:-2} dir
  command -v zoxide >/dev/null 2>&1 || { print -u2 'zoxide is not installed'; return 127; }
  command -v eza >/dev/null 2>&1 || { print -u2 'eza is not installed'; return 127; }

  if [[ -n $query ]]; then dir=$(zoxide query "$query" 2>/dev/null)
  else dir=$(zoxide query -i)
  fi
  [[ -n $dir && -d $dir ]] || return 1

  case "$mode" in
    short) eza --icons --color=always --group-directories-first -- "$dir" ;;
    long)  eza -l --icons --color=always --group-directories-first --git -- "$dir" ;;
    all)   eza -la --icons --color=always --group-directories-first --git -- "$dir" ;;
    tree)  eza --tree --icons --color=always --group-directories-first --level="$level" -- "$dir" ;;
  esac
}

zls() { _zlist short "${1:-}"; }
zll() { _zlist long "${1:-}"; }
zla() { _zlist all "${1:-}"; }
zlt() {
  if [[ ${1:-} == <-> ]]; then _zlist tree '' "$1"
  else _zlist tree "${1:-}" "${2:-2}"
  fi
}
