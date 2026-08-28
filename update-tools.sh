#!/usr/bin/env bash
# Update applications installed outside the system package manager by bootstrap.sh.
set -Eeuo pipefail

DRY_RUN=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: ./update-tools.sh [--dry-run] [--yes]

Updates only applications managed by this dotfiles bootstrap under ~/.local,
plus existing uv, Herdr, and Pi installations. OS-managed packages remain the
responsibility of apt, pacman, dnf, zypper, or Homebrew.

Options:
  --dry-run   Show what would be updated
  -y, --yes   Skip confirmation
  -h, --help  Show this help
EOF
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '[update-tools] ERROR: Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[[ ${EUID:-$(id -u)} -ne 0 ]] || { printf '[update-tools] ERROR: Do not run as root.\n' >&2; exit 1; }

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
BOOTSTRAP="$SCRIPT_DIR/bootstrap.sh"
[[ -f $BOOTSTRAP ]] || { printf '[update-tools] ERROR: Missing %s\n' "$BOOTSTRAP" >&2; exit 1; }

export PATH="$HOME/.local/bin:$HOME/.local/share/pi-node/current/bin:$PATH"
MANAGED_ROOT="$HOME/.local/share/dotfiles-tools"
PACKAGES=()
ACTIONS=()

for tool in starship bat eza fd fzf neovim ripgrep yazi zoxide; do
  [[ -d $MANAGED_ROOT/$tool ]] && PACKAGES+=("$tool")
done
command -v uv >/dev/null 2>&1 && PACKAGES+=(uv)
command -v herdr >/dev/null 2>&1 && PACKAGES+=(herdr)
command -v pi >/dev/null 2>&1 && PACKAGES+=(pi)
if command -v nvim >/dev/null 2>&1 && [[ -d $HOME/.config/nvim ]]; then ACTIONS+=(nvim-plugins); fi

if ((${#PACKAGES[@]} == 0 && ${#ACTIONS[@]} == 0)); then
  printf '[update-tools] No bootstrap-managed applications were found.\n'
  exit 0
fi

if ((${#PACKAGES[@]})); then
  printf 'Bootstrap-managed applications to update:\n'
  printf '  - %s\n' "${PACKAGES[@]}"
fi
if ((${#ACTIONS[@]})); then
  printf 'Related application data to update:\n'
  printf '  - Neovim plugins\n'
fi
printf '\nSystem packages and dotfiles are not updated by this command.\n'

if [[ $DRY_RUN != 1 && $ASSUME_YES != 1 ]]; then
  [[ -r /dev/tty && -w /dev/tty ]] || {
    printf '[update-tools] ERROR: No terminal available; use --yes or --dry-run.\n' >&2
    exit 1
  }
  printf '\nProceed? [y/N] ' >/dev/tty
  IFS= read -r answer </dev/tty || answer=''
  [[ $answer == y || $answer == Y ]] || { printf '[update-tools] Cancelled.\n'; exit 0; }
fi

if ((${#PACKAGES[@]})); then package_list=$(printf '%s ' "${PACKAGES[@]}"); package_list=${package_list% }; else package_list=none; fi
if ((${#ACTIONS[@]})); then action_list=$(printf '%s ' "${ACTIONS[@]}"); action_list=${action_list% }; else action_list=none; fi

SETUP=desktop \
NONINTERACTIVE=1 \
DRY_RUN="$DRY_RUN" \
UPDATE_MODE=1 \
PACKAGES="$package_list" \
CONFIGS=none \
ACTIONS="$action_list" \
bash "$BOOTSTRAP"
