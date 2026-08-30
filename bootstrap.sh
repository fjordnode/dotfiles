#!/usr/bin/env bash
# Interactive, conflict-safe dotfiles bootstrap for Arch Linux and other common systems.
set -Eeuo pipefail

if ! ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3))); then
  # A downloaded script can transparently switch to Homebrew Bash on macOS.
  # A piped script cannot be replayed, so its error explains the required command.
  if [[ ${OSTYPE:-} == darwin* ]]; then
    for bash_candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
      if [[ -x $bash_candidate ]] && "$bash_candidate" -c '((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3)))'; then
        script_path=${BASH_SOURCE[0]:-}
        if [[ -n $script_path && -f $script_path ]]; then
          PATH="${bash_candidate%/*}:$PATH" exec "$bash_candidate" "$script_path" "$@"
        fi
      fi
    done
  fi
  printf '[bootstrap] ERROR: Bash 4.3 or newer is required (found %s). On macOS, install Homebrew Bash and invoke this script with it.\n' "$BASH_VERSION" >&2
  exit 1
fi
unset bash_candidate script_path

REPO="${REPO:-https://github.com/fjordnode/dotfiles.git}"
DEST="${DEST:-$HOME/dotfiles}"
DRY_RUN="${DRY_RUN:-0}"
NONINTERACTIVE="${NONINTERACTIVE:-0}"
PACKAGES_INPUT="${PACKAGES:-}"
CONFIGS_INPUT="${CONFIGS:-}"
ACTIONS_INPUT="${ACTIONS:-}"
SETUP_INPUT="${SETUP:-}"
UPDATE_MODE="${UPDATE_MODE:-0}"
BACKUP_CONFLICTS="${BACKUP_CONFLICTS:-0}"
ISSUES=()
NOTICES=()
FATAL_ERROR=''
LAST_ERROR=''
SUMMARY_ENABLED=0
SUMMARY_PRINTED=0

say() { printf '[bootstrap] %s\n' "$*"; }
warn() {
  printf '[bootstrap] WARNING: %s\n' "$*" >&2
  ISSUES+=("$*")
}
die() {
  FATAL_ERROR=$*
  printf '[bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}
command_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [options]

By default, opens interactive checklists. Use Space to toggle, arrows or j/k to
move, a to toggle all, Enter to accept, and q to cancel.

Options:
  --setup MODE        Catalog mode: cli or desktop
  --packages LIST     Comma- or space-separated package IDs
  --configs LIST      Comma- or space-separated Stow package names
  --actions LIST      Optional post-install actions
  --non-interactive   Do not open checklists (all three lists are required)
  --backup-conflicts  Back up conflicting Stow targets instead of skipping them
  --dry-run           Print the plan and run Stow simulations; change nothing
  -h, --help          Show this help

Environment equivalents: SETUP, PACKAGES, CONFIGS, ACTIONS,
NONINTERACTIVE=1, BACKUP_CONFLICTS=1, DRY_RUN=1, REPO, and DEST. Use "none" for an empty list.

Examples:
  ./bootstrap.sh
  ./bootstrap.sh --dry-run
  ./bootstrap.sh --non-interactive \
    --packages 'git stow zsh neovim' \
    --configs 'git zsh nvim' \
    --actions none
EOF
}

while (($#)); do
  case "$1" in
    --setup) [[ $# -ge 2 ]] || die '--setup needs a value'; SETUP_INPUT=$2; shift 2 ;;
    --packages) [[ $# -ge 2 ]] || die '--packages needs a value'; PACKAGES_INPUT=$2; shift 2 ;;
    --configs) [[ $# -ge 2 ]] || die '--configs needs a value'; CONFIGS_INPUT=$2; shift 2 ;;
    --actions) [[ $# -ge 2 ]] || die '--actions needs a value'; ACTIONS_INPUT=$2; shift 2 ;;
    --non-interactive) NONINTERACTIVE=1; shift ;;
    --backup-conflicts) BACKUP_CONFLICTS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ ${EUID:-$(id -u)} -ne 0 ]] || die 'Do not run this script as root. It installs dotfiles for the current user.'
[[ -n ${HOME:-} && -d $HOME ]] || die 'HOME is not set to a valid directory.'
export PATH="$HOME/.local/bin:$PATH"

OS=unknown
PM=unknown
if [[ ${OSTYPE:-} == darwin* ]]; then
  OS=macos
  command_exists brew && PM=brew
elif [[ ${OSTYPE:-} == linux* ]]; then
  OS=linux
  if command_exists pacman; then PM=pacman
  elif command_exists apt-get; then PM=apt
  elif command_exists dnf; then PM=dnf
  elif command_exists zypper; then PM=zypper
  fi
fi
[[ $PM != unknown ]] || die 'Supported package manager not found (pacman, apt, dnf, zypper, or Homebrew).'

DISTRO_ID=''
if [[ $OS == linux && -r /etc/os-release ]]; then
  DISTRO_ID=$(awk -F= '$1 == "ID" {gsub(/^"|"$/, "", $2); print $2; exit}' /etc/os-release)
fi

# Items are grouped by category and alphabetized within each category.
PACKAGE_IDS=(
  curl git stow unzip
  starship zsh
  openssh
  bat btop eza fd file fzf jq less procps ripgrep yazi zoxide
  build-tools github-cli herdr neovim nodejs npm pi uv
  bluez brightnessctl cliphist firefox ghostty hypridle hyprland hyprlock kitty
  networkmanager niri pavucontrol playerctl portal-gnome portal-gtk
  portal-hyprland satty wl-clipboard wtype xwayland-satellite
)
PACKAGE_LABELS=(
  'HTTP transfer tool' 'version control' 'dotfile symlink manager' 'archive extractor'
  'prompt' 'shell'
  'SSH client and tools'
  'cat with syntax highlighting' 'process and resource monitor' 'modern ls' 'file finder' 'file type detector' 'fuzzy finder' 'JSON processor' 'pager' 'process utilities' 'text search' 'file manager' 'directory jumper'
  'compiler and build tools' 'GitHub CLI' 'Herdr terminal workspace manager' 'editor' 'JavaScript runtime' 'Node package manager' 'Pi coding agent' 'Python project manager'
  'Bluetooth tools' 'backlight control' 'clipboard history' 'web browser' 'Ghostty terminal' 'Hyprland idle daemon' 'compositor' 'screen locker' 'Kitty terminal'
  'network manager' 'compositor' 'audio volume control' 'media control' 'GNOME desktop portal' 'GTK desktop portal'
  'Hyprland desktop portal' 'screenshot editor' 'Wayland clipboard tools' 'Wayland typing tool' 'Xwayland integration'
)
PACKAGE_CATEGORIES=(
  Bootstrap Bootstrap Bootstrap Bootstrap
  Shell Shell
  Terminal
  CLI CLI CLI CLI CLI CLI CLI CLI CLI CLI CLI CLI
  Development Development Development Development Development Development Development Development
  Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop Desktop
)
PACKAGE_DEFAULTS=()
for package_id in "${PACKAGE_IDS[@]}"; do
  case "$package_id" in curl|git|stow|zsh) PACKAGE_DEFAULTS+=(1) ;; *) PACKAGE_DEFAULTS+=(0) ;; esac
done
unset package_id

CONFIG_IDS=(zsh starship git nvim eza bat yazi scripts herdr agents claude pi ghostty kitty niri hypr noctalia vpn-split)
CONFIG_LABELS=(
  'Zsh shell config' 'Starship config'
  'Git config' 'Neovim config'
  'eza config' 'bat themes' 'Yazi config' 'portable scripts/functions'
  'Herdr config' 'shared agent skills' 'Claude config' 'Pi config'
  'Ghostty config' 'Kitty config' 'Niri desktop config' 'Hyprland desktop config' 'Noctalia config' 'VPN split-tunnel helpers (advanced)'
)
CONFIG_CATEGORIES=(Shell Shell Development Development CLI CLI CLI CLI AI AI AI AI Desktop Desktop Desktop Desktop Desktop Desktop)
CONFIG_DEFAULTS=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

ACTION_IDS=(oh-my-zsh zsh-plugins default-shell nvim-plugins cleanup-obsolete-links)
ACTION_LABELS=(
  'clone Oh My Zsh' 'clone optional Zsh plugins' 'change login shell to Zsh' 'install missing Neovim plugins'
  'remove obsolete links owned by these dotfiles'
)
ACTION_CATEGORIES=(Shell Shell Shell Development Maintenance)
ACTION_DEFAULTS=(0 0 0 0 0)
if [[ $PM == apt ]]; then
  ACTION_IDS+=(system-upgrade)
  ACTION_LABELS+=('update APT metadata and upgrade installed packages')
  ACTION_CATEGORIES+=(System)
  ACTION_DEFAULTS+=(0)
fi

package_supported_on_pm() {
  local id=$1
  case "$PM:$id" in
    # These are not available from the standard Debian 13 repositories. Their
    # configs remain selectable for users who install them separately.
    apt:ghostty|apt:hypridle|apt:hyprland|apt:hyprlock|apt:niri|apt:portal-hyprland|apt:satty|apt:xwayland-satellite) return 1 ;;
    # Linux-only integration packages do not have Homebrew formulae.
    brew:build-tools|brew:procps|brew:networkmanager|brew:bluez|brew:brightnessctl|brew:pavucontrol|brew:wtype|brew:cliphist|brew:niri|brew:xwayland-satellite|brew:portal-gnome|brew:portal-gtk|brew:hyprland|brew:hyprlock|brew:hypridle|brew:portal-hyprland) return 1 ;;
    *) return 0 ;;
  esac
}

UNSUPPORTED_PACKAGE_IDS=()
filter_package_manager_catalog() {
  local i
  local -a ids=() labels=() categories=() defaults=()
  for ((i=0; i<${#PACKAGE_IDS[@]}; i++)); do
    if ! package_supported_on_pm "${PACKAGE_IDS[i]}"; then
      UNSUPPORTED_PACKAGE_IDS+=("${PACKAGE_IDS[i]}")
      continue
    fi
    ids+=("${PACKAGE_IDS[i]}")
    labels+=("${PACKAGE_LABELS[i]}")
    categories+=("${PACKAGE_CATEGORIES[i]}")
    defaults+=("${PACKAGE_DEFAULTS[i]}")
  done
  PACKAGE_IDS=("${ids[@]}")
  PACKAGE_LABELS=("${labels[@]}")
  PACKAGE_CATEGORIES=("${categories[@]}")
  PACKAGE_DEFAULTS=("${defaults[@]}")
}
filter_package_manager_catalog

FULL_PACKAGE_IDS=("${PACKAGE_IDS[@]}")
FULL_PACKAGE_LABELS=("${PACKAGE_LABELS[@]}")
FULL_PACKAGE_CATEGORIES=("${PACKAGE_CATEGORIES[@]}")
FULL_PACKAGE_DEFAULTS=("${PACKAGE_DEFAULTS[@]}")
FULL_CONFIG_IDS=("${CONFIG_IDS[@]}")
FULL_CONFIG_LABELS=("${CONFIG_LABELS[@]}")
FULL_CONFIG_CATEGORIES=("${CONFIG_CATEGORIES[@]}")
FULL_CONFIG_DEFAULTS=("${CONFIG_DEFAULTS[@]}")

contains_id() {
  local needle=$1; shift
  local item
  for item in "$@"; do [[ $item == "$needle" ]] && return 0; done
  return 1
}

UI_ACTIVE=0
ui_leave() {
  if [[ ${UI_ACTIVE:-0} == 1 ]]; then
    printf '\033[?25h\033[?1049l' >&3 2>/dev/null || true
    exec 3>&- 2>/dev/null || true
    UI_ACTIVE=0
  fi
}

print_installation_summary() {
  [[ ${SUMMARY_PRINTED:-0} == 0 ]] || return 0
  SUMMARY_PRINTED=1
  printf '\n========== Installation summary ==========\n'
  if ((${#NOTICES[@]})); then
    printf 'Completed with backups/notices:\n'
    for message in "${NOTICES[@]}"; do printf '  - %s\n' "$message"; done
  fi
  if ((${#ISSUES[@]})); then
    printf 'Warnings, errors, or skipped operations:\n'
    for message in "${ISSUES[@]}"; do printf '  - %s\n' "$message"; done
    printf 'Review the messages above; rerunning the bootstrap is safe.\n'
  else
    printf 'No warnings or skipped operations.\n'
  fi
}

record_unexpected_error() {
  local status=$1 line=$2
  LAST_ERROR="Unexpected command failure at bootstrap.sh:$line (exit $status)."
}

bootstrap_exit() {
  local status=$1
  trap - EXIT
  ui_leave || true
  if [[ ${SUMMARY_ENABLED:-0} == 1 && ${SUMMARY_PRINTED:-0} == 0 ]]; then
    if [[ -n ${FATAL_ERROR:-} ]]; then
      ISSUES+=("Fatal error: $FATAL_ERROR")
    elif [[ -n ${LAST_ERROR:-} ]]; then
      ISSUES+=("$LAST_ERROR")
    elif ((status != 0)); then
      ISSUES+=("Bootstrap stopped unexpectedly (exit $status).")
    fi
    print_installation_summary
  fi
  exit "$status"
}

trap 'record_unexpected_error "$?" "$LINENO"' ERR
trap 'bootstrap_exit "$?"' EXIT

ui_enter() {
  [[ -r /dev/tty && -w /dev/tty ]] || die 'No terminal available. Use --non-interactive with explicit lists.'
  exec 3<>/dev/tty
  printf '\033[?1049h\033[?25l' >&3
  UI_ACTIVE=1
  trap 'ui_leave; exit 130' INT TERM HUP
}

parse_selection() {
  local input=$1; shift
  local -a valid=("$@") values=()
  local value normalized
  [[ $input == none ]] && { SELECTED=(); return; }
  normalized=${input//,/ }
  read -r -a values <<< "$normalized"
  SELECTED=()
  for value in "${values[@]}"; do
    contains_id "$value" "${valid[@]}" || die "Unknown selection: $value"
    contains_id "$value" "${SELECTED[@]}" || SELECTED+=("$value")
  done
}

checklist() {
  local title=$1 ids_name=$2 labels_name=$3 categories_name=$4 defaults_name=$5
  local -n ids=$ids_name labels=$labels_name categories=$categories_name defaults=$defaults_name
  local -a checked=("${defaults[@]}")
  local cursor=0 key rest i rows cols page_size start end used cost previous_category available display_label help_line

  GO_BACK=0
  [[ $UI_ACTIVE == 1 ]] || ui_enter
  # Cache dimensions for this checklist. Running tput on every keypress adds
  # visible latency; a rerun picks up any terminal resize.
  rows=$(tput lines <&3 2>/dev/null || printf '24')
  cols=$(tput cols <&3 2>/dev/null || printf '80')
  [[ $rows =~ ^[0-9]+$ ]] || rows=24
  [[ $cols =~ ^[0-9]+$ ]] || cols=80
  while true; do
    # One continuous categorized list. On short terminals it scrolls as a
    # unified viewport rather than switching to a category-only page.
    # Keep one row unused: writing a newline in the bottom-right cell makes
    # many terminals scroll and leaves redraw artifacts.
    page_size=$((rows-7)); ((page_size < 6)) && page_size=6
    start=0
    while true; do
      used=0
      end=$start
      previous_category=''
      while ((end < ${#ids[@]})); do
        cost=1
        [[ ${categories[end]} == "$previous_category" ]] || ((cost++))
        ((used + cost <= page_size)) || break
        used=$((used+cost))
        previous_category=${categories[end]}
        end=$((end+1))
      done
      ((cursor < end || end == ${#ids[@]})) && break
      start=$((start+1))
    done

    # Do not clear before drawing: that creates a visible blank frame. Return
    # home and overwrite the previous frame instead.
    printf '\033[H\033[2K%s\n\033[2K\n' "$title" >&3
    help_line='Space:toggle | j/k:move | a:all | Enter:accept | Esc:back | q:quit'
    ((${#help_line} > cols-2)) && help_line=${help_line:0:cols-2}
    printf '\033[2K  %s\n\033[2K\n' "$help_line" >&3
    previous_category=''
    available=$((cols-31)); ((available < 8)) && available=8
    for ((i=start; i<end; i++)); do
      if [[ ${categories[i]} != "$previous_category" ]]; then
        printf '\033[2K  \033[1;35m%s\033[0m\n' "${categories[i]}" >&3
        previous_category=${categories[i]}
      fi
      printf '\033[2K' >&3
      if ((i == cursor)); then printf '  \033[36m>\033[0m ' >&3; else printf '    ' >&3; fi
      if ((checked[i])); then printf '[\033[32mx\033[0m] ' >&3; else printf '[ ] ' >&3; fi
      display_label=${labels[i]}
      ((${#display_label} > available)) && display_label="${display_label:0:available-1}~"
      printf '%-19s %s\n' "${ids[i]}" "$display_label" >&3
    done
    # Clear only stale content below/after the newly drawn frame.
    printf '\033[2K\n\033[2K  Showing items %d-%d of %d\033[J' "$((start+1))" "$end" "${#ids[@]}" >&3
    IFS= read -rsn1 key <&3 || key=''
    case "$key" in
      '') break ;;
      ' ') checked[cursor]=$((1-checked[cursor])) ;;
      j) cursor=$((cursor+1)); ((cursor>=${#ids[@]})) && cursor=0 ;;
      k) cursor=$((cursor-1)); ((cursor<0)) && cursor=$((${#ids[@]}-1)) ;;
      a)
        # Select everything unless everything is already selected; only then
        # does a second press clear the list.
        local target=0
        for i in "${checked[@]}"; do
          if ((i == 0)); then target=1; break; fi
        done
        for ((i=0; i<${#checked[@]}; i++)); do checked[i]=$target; done
        ;;
      q) ui_leave; die 'Cancelled by user.' ;;
      $'\e')
        IFS= read -rsn2 -t 0.15 rest <&3 || rest=''
        case "$rest" in
          '[A') cursor=$((cursor-1)); ((cursor<0)) && cursor=$((${#ids[@]}-1)) ;;
          '[B') cursor=$((cursor+1)); ((cursor>=${#ids[@]})) && cursor=0 ;;
          '') GO_BACK=1; break ;;
        esac
        ;;
    esac
  done
  SELECTED=()
  for ((i=0; i<${#ids[@]}; i++)); do ((checked[i])) && SELECTED+=("${ids[i]}") || true; done
  return 0
}

choose_setup() {
  local cursor=0 key rest
  [[ ${SETUP_MODE:-cli} == desktop ]] && cursor=1
  [[ $UI_ACTIVE == 1 ]] || ui_enter
  while true; do
    printf '\033[H\033[2KChoose setup type\n\033[2K\n' >&3
    printf '\033[2K  CLI hides graphical desktop applications and configs.\n' >&3
    printf '\033[2K  Desktop shows the complete catalog.\n\033[2K\n' >&3
    if ((cursor == 0)); then
      printf '\033[2K  \033[36m>\033[0m \033[1mCLI\033[0m      Terminal, shell, editor, and development tools\n' >&3
      printf '\033[2K    Desktop  Complete catalog including graphical/Wayland tools\n' >&3
    else
      printf '\033[2K    CLI      Terminal, shell, editor, and development tools\n' >&3
      printf '\033[2K  \033[36m>\033[0m \033[1mDesktop\033[0m  Complete catalog including graphical/Wayland tools\n' >&3
    fi
    printf '\033[2K\n\033[2K  arrows/j/k: move | Enter: accept | q: quit\033[J' >&3
    IFS= read -rsn1 key <&3 || key=''
    case "$key" in
      '') break ;;
      j|k|' ') cursor=$((1-cursor)) ;;
      q) ui_leave; die 'Cancelled by user.' ;;
      $'\e')
        IFS= read -rsn2 -t 0.15 rest <&3 || rest=''
        if [[ $rest == '[A' || $rest == '[B' ]]; then cursor=$((1-cursor)); fi
        ;;
    esac
  done
  if ((cursor == 0)); then SETUP_MODE=cli; else SETUP_MODE=desktop; fi
}

restore_full_catalog() {
  PACKAGE_IDS=("${FULL_PACKAGE_IDS[@]}"); PACKAGE_LABELS=("${FULL_PACKAGE_LABELS[@]}")
  PACKAGE_CATEGORIES=("${FULL_PACKAGE_CATEGORIES[@]}"); PACKAGE_DEFAULTS=("${FULL_PACKAGE_DEFAULTS[@]}")
  CONFIG_IDS=("${FULL_CONFIG_IDS[@]}"); CONFIG_LABELS=("${FULL_CONFIG_LABELS[@]}")
  CONFIG_CATEGORIES=("${FULL_CONFIG_CATEGORIES[@]}"); CONFIG_DEFAULTS=("${FULL_CONFIG_DEFAULTS[@]}")
}

filter_cli_catalog() {
  local i
  local -a ids=() labels=() categories=() defaults=()
  for ((i=0; i<${#PACKAGE_IDS[@]}; i++)); do
    [[ ${PACKAGE_CATEGORIES[i]} == Desktop ]] && continue
    ids+=("${PACKAGE_IDS[i]}"); labels+=("${PACKAGE_LABELS[i]}")
    categories+=("${PACKAGE_CATEGORIES[i]}"); defaults+=("${PACKAGE_DEFAULTS[i]}")
  done
  PACKAGE_IDS=("${ids[@]}"); PACKAGE_LABELS=("${labels[@]}")
  PACKAGE_CATEGORIES=("${categories[@]}"); PACKAGE_DEFAULTS=("${defaults[@]}")

  ids=(); labels=(); categories=(); defaults=()
  for ((i=0; i<${#CONFIG_IDS[@]}; i++)); do
    [[ ${CONFIG_CATEGORIES[i]} == Desktop ]] && continue
    ids+=("${CONFIG_IDS[i]}"); labels+=("${CONFIG_LABELS[i]}")
    categories+=("${CONFIG_CATEGORIES[i]}"); defaults+=("${CONFIG_DEFAULTS[i]}")
  done
  CONFIG_IDS=("${ids[@]}"); CONFIG_LABELS=("${labels[@]}")
  CONFIG_CATEGORIES=("${categories[@]}"); CONFIG_DEFAULTS=("${defaults[@]}")
}

config_for_package() {
  case "$1" in
    zsh|git|starship|eza|bat|yazi|herdr|pi|kitty|ghostty|niri) echo "$1" ;;
    neovim) echo nvim ;;
    hyprland) echo hypr ;;
  esac
}

select_matching_config_defaults() {
  local package config i
  CONFIG_DEFAULTS=()
  for ((i=0; i<${#CONFIG_IDS[@]}; i++)); do CONFIG_DEFAULTS+=(0); done
  for package in "${SELECTED_PACKAGES[@]}"; do
    config=$(config_for_package "$package")
    [[ -n $config ]] || continue
    for ((i=0; i<${#CONFIG_IDS[@]}; i++)); do
      [[ ${CONFIG_IDS[i]} == "$config" ]] && CONFIG_DEFAULTS[i]=1 || true
    done
  done
  return 0
}

selection_to_defaults() {
  local ids_name=$1 defaults_name=$2; shift 2
  local -n ids=$ids_name defaults=$defaults_name
  local -a chosen=("$@")
  local i
  defaults=()
  for ((i=0; i<${#ids[@]}; i++)); do
    if contains_id "${ids[i]}" "${chosen[@]}"; then defaults+=(1); else defaults+=(0); fi
  done
}

if [[ -n $SETUP_INPUT && $SETUP_INPUT != cli && $SETUP_INPUT != desktop ]]; then
  die "Unknown setup type: $SETUP_INPUT (expected cli or desktop)"
fi

validate_package_input_support() {
  local input=$1 normalized value
  local -a values=()
  [[ -n $input && $input != none ]] || return 0
  normalized=${input//,/ }
  read -r -a values <<< "$normalized"
  for value in "${values[@]}"; do
    if contains_id "$value" "${UNSUPPORTED_PACKAGE_IDS[@]}"; then
      die "Package $value is not available through the detected $PM package source; install it separately and select its config if wanted."
    fi
  done
}
validate_package_input_support "$PACKAGES_INPUT"

if [[ $NONINTERACTIVE == 1 ]]; then
  SETUP_MODE=${SETUP_INPUT:-desktop}
  restore_full_catalog
  if [[ $SETUP_MODE == cli ]]; then filter_cli_catalog; fi
  [[ -n $PACKAGES_INPUT && -n $CONFIGS_INPUT && -n $ACTIONS_INPUT ]] || \
    die '--non-interactive requires --packages, --configs, and --actions (use none for an empty list).'
  parse_selection "$PACKAGES_INPUT" "${PACKAGE_IDS[@]}"; SELECTED_PACKAGES=("${SELECTED[@]}")
  parse_selection "$CONFIGS_INPUT" "${CONFIG_IDS[@]}"; SELECTED_CONFIGS=("${SELECTED[@]}")
  parse_selection "$ACTIONS_INPUT" "${ACTION_IDS[@]}"; SELECTED_ACTIONS=("${SELECTED[@]}")
else
  stage=0
  wizard_done=0
  while [[ $wizard_done == 0 ]]; do
    case "$stage" in
      0)
        if [[ -n $SETUP_INPUT ]]; then SETUP_MODE=$SETUP_INPUT; else choose_setup; fi
        restore_full_catalog
        if [[ $SETUP_MODE == cli ]]; then filter_cli_catalog; fi
        if declare -p SELECTED_PACKAGES >/dev/null 2>&1; then
          selection_to_defaults PACKAGE_IDS PACKAGE_DEFAULTS "${SELECTED_PACKAGES[@]}"
        fi
        stage=1
        ;;
      1)
        package_selection_before=$(printf '%s\n' "${SELECTED_PACKAGES[@]-}")
        if [[ -n $PACKAGES_INPUT ]]; then
          parse_selection "$PACKAGES_INPUT" "${PACKAGE_IDS[@]}"; GO_BACK=0
        else
          checklist 'Select system packages to install' PACKAGE_IDS PACKAGE_LABELS PACKAGE_CATEGORIES PACKAGE_DEFAULTS
        fi
        SELECTED_PACKAGES=("${SELECTED[@]}")
        selection_to_defaults PACKAGE_IDS PACKAGE_DEFAULTS "${SELECTED_PACKAGES[@]}"
        if [[ $GO_BACK == 1 ]]; then
          if [[ -z $SETUP_INPUT ]]; then stage=0; else stage=1; fi
          continue
        fi
        package_selection_after=$(printf '%s\n' "${SELECTED_PACKAGES[@]}")
        if [[ $package_selection_before == "$package_selection_after" ]] && declare -p SELECTED_CONFIGS >/dev/null 2>&1; then
          selection_to_defaults CONFIG_IDS CONFIG_DEFAULTS "${SELECTED_CONFIGS[@]}"
        else
          select_matching_config_defaults
        fi
        stage=2
        ;;
      2)
        if [[ -n $CONFIGS_INPUT ]]; then
          parse_selection "$CONFIGS_INPUT" "${CONFIG_IDS[@]}"; GO_BACK=0
        else
          checklist 'Select configs to link with GNU Stow' CONFIG_IDS CONFIG_LABELS CONFIG_CATEGORIES CONFIG_DEFAULTS
        fi
        SELECTED_CONFIGS=("${SELECTED[@]}")
        selection_to_defaults CONFIG_IDS CONFIG_DEFAULTS "${SELECTED_CONFIGS[@]}"
        if [[ $GO_BACK == 1 ]]; then stage=1; continue; fi
        stage=3
        ;;
      3)
        if [[ -n $ACTIONS_INPUT ]]; then
          parse_selection "$ACTIONS_INPUT" "${ACTION_IDS[@]}"; GO_BACK=0
        else
          checklist 'Select optional setup actions (none are required)' ACTION_IDS ACTION_LABELS ACTION_CATEGORIES ACTION_DEFAULTS
        fi
        SELECTED_ACTIONS=("${SELECTED[@]}")
        selection_to_defaults ACTION_IDS ACTION_DEFAULTS "${SELECTED_ACTIONS[@]}"
        if [[ $GO_BACK == 1 ]]; then stage=2; continue; fi
        wizard_done=1
        ;;
    esac
  done
  ui_leave
fi

is_selected_package() { contains_id "$1" "${SELECTED_PACKAGES[@]}"; }
is_selected_config() { contains_id "$1" "${SELECTED_CONFIGS[@]}"; }
is_selected_action() { contains_id "$1" "${SELECTED_ACTIONS[@]}"; }

package_name() {
  local id=$1
  if [[ $PM == apt && $id == firefox && $DISTRO_ID == debian ]]; then
    echo firefox-esr
    return 0
  fi
  case "$PM:$id" in
    pacman:github-cli) echo github-cli ;; pacman:build-tools) echo base-devel ;; pacman:procps) echo procps-ng ;; pacman:bluez) printf '%s\n' bluez bluez-utils ;; pacman:yazi) printf '%s\n' yazi ttf-nerd-fonts-symbols ;;
    apt:starship|apt:bat|apt:eza|apt:fd|apt:fzf|apt:neovim|apt:ripgrep|apt:yazi|apt:zoxide) return 0 ;;
    apt:github-cli) echo gh ;; apt:build-tools) echo build-essential ;; apt:openssh) echo openssh-client ;; apt:procps) echo procps ;; apt:networkmanager) echo network-manager ;;
    dnf:github-cli) echo gh ;; dnf:build-tools) echo gcc make ;; dnf:fd) echo fd-find ;; dnf:neovim) echo neovim ;; dnf:openssh) echo openssh-clients ;; dnf:procps) echo procps-ng ;;
    zypper:github-cli) echo gh ;; zypper:build-tools) echo gcc make ;; zypper:neovim) echo neovim ;; zypper:openssh) echo openssh ;; zypper:procps) echo procps ;;
    brew:github-cli) echo gh ;; brew:neovim) echo neovim ;; brew:openssh) echo openssh ;;
    *:portal-gnome) echo xdg-desktop-portal-gnome ;; *:portal-gtk) echo xdg-desktop-portal-gtk ;; *:portal-hyprland) echo xdg-desktop-portal-hyprland ;;
    *:herdr|*:pi|*:uv) return 0 ;;
    *:build-tools) echo gcc make ;;
    *) echo "$id" ;;
  esac
}

SYSTEM_PACKAGES=()
for id in "${SELECTED_PACKAGES[@]}"; do
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    if contains_id "$name" "${SYSTEM_PACKAGES[@]}"; then continue; fi
    SYSTEM_PACKAGES+=("$name")
  done < <(package_name "$id")
done

validate_current_apt_metadata() {
  [[ $PM == apt ]] || return 0
  local phase=${1:-current} package candidate
  local -a unavailable=()
  command_exists apt-cache || die 'apt-cache is required to validate the selected APT packages.'
  for package in "${SYSTEM_PACKAGES[@]}"; do
    candidate=$(apt-cache policy "$package" 2>/dev/null | awk '$1 == "Candidate:" {print $2; exit}' || true)
    [[ -n $candidate && $candidate != '(none)' ]] || unavailable+=("$package")
  done
  if ((${#unavailable[@]})); then
    if [[ $phase == current ]]; then
      die "Selected packages are unavailable in the current APT metadata: ${unavailable[*]}. Run sudo apt-get update, then rerun; no changes were made."
    else
      die "Selected packages are unavailable after refreshing APT metadata: ${unavailable[*]}. No packages were installed."
    fi
  fi
}

preflight_system_packages() {
  local package
  local -a unavailable=()
  if [[ $PM == apt ]]; then
    validate_current_apt_metadata current
  elif [[ $PM == pacman ]]; then
    for package in "${SYSTEM_PACKAGES[@]}"; do
      pacman -Si "$package" >/dev/null 2>&1 || pacman -Q "$package" >/dev/null 2>&1 || unavailable+=("$package")
    done
  fi
  ((${#unavailable[@]} == 0)) || die "Selected packages are unavailable in the current $PM metadata: ${unavailable[*]}. Update the package metadata normally, then rerun; no changes were made."
}

planned_command_available() {
  local command_name=$1 package_id=$2
  command_exists "$command_name" || is_selected_package "$package_id"
}

preflight_dependencies() {
  local id
  if [[ $PM == apt ]]; then
    for id in starship bat eza fd fzf neovim ripgrep yazi zoxide; do
      if is_selected_package "$id" && ! planned_command_available curl curl; then
        die "curl is required for the selected upstream $id install; select curl and rerun."
      fi
    done
  fi
  for id in uv herdr pi; do
    if is_selected_package "$id" && ! planned_command_available curl curl; then
      die "curl is required to install $id; select curl and rerun."
    fi
  done
  if ((${#SELECTED_CONFIGS[@]})) && ! planned_command_available stow stow; then
    die 'GNU Stow is required for selected configs; select stow and rerun.'
  fi
  if ((${#SELECTED_CONFIGS[@]})) && [[ -z $SOURCE_DIR ]] && ! planned_command_available git git; then
    die 'Git is required to clone the selected configs; select git and rerun.'
  fi
  if { is_selected_action oh-my-zsh || is_selected_action zsh-plugins; } && ! planned_command_available git git; then
    die 'Git is required for the selected Zsh setup actions; select git and rerun.'
  fi
  if is_selected_action default-shell && ! planned_command_available zsh zsh; then
    die 'Zsh is required for the default-shell action; select zsh and rerun.'
  fi
  if is_selected_action nvim-plugins && ! planned_command_available nvim neovim; then
    die 'Neovim is required for the nvim-plugins action; select neovim and rerun.'
  fi
  if [[ $DRY_RUN != 1 && $PM != brew ]] && { ((${#SYSTEM_PACKAGES[@]})) || is_selected_action system-upgrade; } && ! command_exists sudo; then
    die "sudo is required for the selected $PM system operation."
  fi
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)
SOURCE_DIR=''
REPO_PLAN='not needed (no configs selected)'
if ((${#SELECTED_CONFIGS[@]})); then
  if [[ -n $SCRIPT_DIR && -e $SCRIPT_DIR/.git && -f $SCRIPT_DIR/bootstrap.sh ]]; then
    SOURCE_DIR=$SCRIPT_DIR
    REPO_PLAN="use current checkout: $SOURCE_DIR"
  elif [[ -e $DEST/.git ]]; then
    SOURCE_DIR=$DEST
    REPO_PLAN="use existing checkout without updating it: $DEST"
  elif [[ -e $DEST ]]; then
    die "$DEST exists but is not a Git checkout; refusing to overwrite it."
  else
    REPO_PLAN="clone $REPO into $DEST"
  fi
fi

preflight_system_packages
preflight_dependencies

join_or_none() {
  if (($#)); then
    printf '%s' "$1"
    shift
    if (($#)); then printf ', %s' "$@"; fi
  else
    printf 'none'
  fi
}
printf '\nPlan for %s (%s):\n' "$OS" "$PM"
printf '  Setup:     %s\n' "$SETUP_MODE"
printf '  Packages:  %s\n' "$(join_or_none "${SELECTED_PACKAGES[@]}")"
printf '  Configs:   %s\n' "$(join_or_none "${SELECTED_CONFIGS[@]}")"
printf '  Actions:   %s\n' "$(join_or_none "${SELECTED_ACTIONS[@]}")"
printf '  Repository: %s\n' "$REPO_PLAN"
if [[ $PM == apt ]] && ((${#SYSTEM_PACKAGES[@]})); then
  printf '  APT metadata: refresh before installing selected APT packages\n'
fi
[[ $DRY_RUN == 1 ]] && printf '  Mode:      DRY RUN (no changes)\n'

if [[ $NONINTERACTIVE != 1 && $DRY_RUN != 1 ]]; then
  exec 3<>/dev/tty
  printf '\nProceed with exactly this plan? [y/N] ' >&3
  IFS= read -r answer <&3 || answer=''
  exec 3>&-
  [[ $answer == y || $answer == Y ]] || die 'Cancelled; nothing was changed.'
fi

# From this point onward the selected plan is being executed. Any fatal error
# is repeated by the EXIT trap in the final summary.
SUMMARY_ENABLED=1

APT_UPDATED=0
run_apt_system_upgrade() {
  is_selected_action system-upgrade || return 0
  [[ $PM == apt ]] || return 0
  if [[ $DRY_RUN == 1 ]]; then
    say '[dry-run] Would run: sudo apt-get update && sudo apt-get upgrade -y (preserving existing config files)'
    APT_UPDATED=1
    return 0
  fi
  command_exists sudo || die 'sudo is required for the selected APT system upgrade.'
  say 'Updating APT metadata...'
  sudo apt-get update
  APT_UPDATED=1
  say 'Upgrading installed APT packages (existing config files are preserved)...'
  sudo apt-get upgrade -y -o Dpkg::Options::=--force-confold
  say 'Finished APT system upgrade.'
}
run_apt_system_upgrade

run_package_install() {
  ((${#SYSTEM_PACKAGES[@]})) || return 0
  if [[ $DRY_RUN == 1 ]]; then
    printf '[dry-run] Would install with %s: %s\n' "$PM" "${SYSTEM_PACKAGES[*]}"
    return 0
  fi
  local -a elevate=()
  if [[ $PM != brew ]]; then
    command_exists sudo || die "sudo is required to install packages with $PM."
    elevate=(sudo)
  fi
  say "Installing selected packages with $PM (already-installed packages are kept)."
  case "$PM" in
    pacman)
      if [[ $NONINTERACTIVE == 1 ]]; then
        "${elevate[@]}" pacman -S --needed --noconfirm "${SYSTEM_PACKAGES[@]}"
      else
        [[ -r /dev/tty && -w /dev/tty ]] || die 'A terminal is required for Pacman confirmation; use --non-interactive for automation.'
        say 'Pacman package/provider choices and its final confirmation follow on the terminal.'
        "${elevate[@]}" pacman -S --needed "${SYSTEM_PACKAGES[@]}" </dev/tty >/dev/tty 2>&1
      fi
      ;;
    apt)
      if [[ $APT_UPDATED != 1 ]]; then "${elevate[@]}" apt-get update; fi
      validate_current_apt_metadata refreshed
      "${elevate[@]}" apt-get install -y "${SYSTEM_PACKAGES[@]}"
      ;;
    dnf) "${elevate[@]}" dnf install -y "${SYSTEM_PACKAGES[@]}" ;;
    zypper) "${elevate[@]}" zypper --non-interactive install "${SYSTEM_PACKAGES[@]}" ;;
    brew) brew install "${SYSTEM_PACKAGES[@]}" ;;
  esac
}
run_package_install

release_asset_url() {
  local json=$1 asset=$2 url
  while IFS= read -r url; do
    [[ ${url##*/} == "$asset" ]] && { printf '%s\n' "$url"; return 0; }
  done < <(printf '%s' "$json" | sed -n 's/.*"browser_download_url": "\([^"]*\)".*/\1/p')
  return 1
}

managed_tool_link() {
  local source=$1 name=$2 destination="$HOME/.local/bin/$2" current=''
  mkdir -p "$HOME/.local/bin"
  if [[ -L $destination ]]; then current=$(readlink "$destination"); fi
  if [[ -e $destination || -L $destination ]]; then
    if [[ $current != "$HOME/.local/share/dotfiles-tools/"* ]]; then
      warn "Keeping unmanaged file; $name was installed but not linked: $destination"
      return 0
    fi
  fi
  ln -sfn "$source" "$destination"
}

install_github_tool() {
  local id=$1 asset=$2 tag=$3 json=$4
  shift 4
  local -a binaries=("$@")
  local url checksum_url tmp archive extract binary found install_dir expected actual all_installed=1
  url=$(release_asset_url "$json" "$asset") || die "Upstream release asset not found for $id: $asset"
  install_dir="$HOME/.local/share/dotfiles-tools/$id/$tag"
  for binary in "${binaries[@]}"; do [[ -x $install_dir/$binary ]] || all_installed=0; done
  if [[ $all_installed == 1 ]]; then
    for binary in "${binaries[@]}"; do managed_tool_link "$install_dir/$binary" "$binary"; done
    say "Upstream $id $tag is already installed."
    return 0
  fi
  tmp=$(mktemp -d)
  archive="$tmp/$asset"
  extract="$tmp/extract"
  mkdir -p "$extract" "$install_dir"
  say "Installing upstream $id $tag..."
  curl -fL --retry 3 -o "$archive" "$url"

  checksum_url=$(release_asset_url "$json" "$asset.sha256" || true)
  if [[ -n $checksum_url ]]; then
    curl -fsSL -o "$archive.sha256" "$checksum_url"
    expected=$(awk 'NR==1 {print $1}' "$archive.sha256")
    actual=$(sha256sum "$archive" | awk '{print $1}')
    [[ -n $expected && $actual == "$expected" ]] || { rm -rf "$tmp"; die "Checksum verification failed for $id."; }
  fi

  case "$asset" in
    *.tar.gz) tar -xzf "$archive" -C "$extract" ;;
    *.deb) command_exists dpkg-deb || { rm -rf "$tmp"; die 'dpkg-deb is required to extract the Yazi release.'; }; dpkg-deb -x "$archive" "$extract" ;;
    *) rm -rf "$tmp"; die "Unsupported release archive: $asset" ;;
  esac
  for binary in "${binaries[@]}"; do
    found=$(find "$extract" -type f -name "$binary" -print -quit)
    [[ -n $found ]] || { rm -rf "$tmp"; die "Binary $binary was missing from $asset."; }
    install -m 755 "$found" "$install_dir/$binary"
    managed_tool_link "$install_dir/$binary" "$binary"
  done
  rm -rf "$tmp"
}

install_neovim_release() {
  local asset=$1 tag=$2 json=$3 url tmp archive extract install_dir install_parent stage
  url=$(release_asset_url "$json" "$asset") || die "Official Neovim release asset not found: $asset"
  install_dir="$HOME/.local/share/dotfiles-tools/neovim/$tag"
  if [[ -x $install_dir/bin/nvim && -d $install_dir/share/nvim/runtime ]]; then
    managed_tool_link "$install_dir/bin/nvim" nvim
    say "Upstream Neovim $tag is already installed."
    return 0
  fi

  install_parent=${install_dir%/*}
  mkdir -p "$install_parent"
  tmp=$(mktemp -d)
  if ! stage=$(mktemp -d "$install_parent/.install.XXXXXX"); then
    rm -rf "$tmp"
    die "Could not create a Neovim staging directory under $install_parent."
  fi
  archive="$tmp/$asset"
  extract="$tmp/extract"
  say "Installing upstream Neovim $tag..."
  if ! (
    set -Euo pipefail
    trap 'rm -rf "$tmp" "$stage"' EXIT
    mkdir -p "$extract" || exit 1
    curl -fL --retry 3 -o "$archive" "$url" || exit 1
    tar -xzf "$archive" -C "$extract" || exit 1
    nvim_binary=$(find "$extract" -type f -path '*/bin/nvim' -print -quit)
    [[ -n $nvim_binary ]] || exit 1
    release_root=${nvim_binary%/bin/nvim}
    cp -a "$release_root/." "$stage/" || exit 1
    [[ -x $stage/bin/nvim && -d $stage/share/nvim/runtime ]] || exit 1
    XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data" \
      XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" \
      "$stage/bin/nvim" --headless --clean -i NONE +qa || exit 1
    rm -rf "$install_dir" || exit 1
    mv "$stage" "$install_dir" || exit 1
  ); then
    die "Neovim $tag could not be downloaded, validated, and installed atomically."
  fi
  managed_tool_link "$install_dir/bin/nvim" nvim
}

install_upstream_apt_tools() {
  [[ $PM == apt ]] || return 0
  local machine rust_arch go_arch id repo json tag version asset
  machine=$(uname -m)
  case "$machine" in
    x86_64) rust_arch=x86_64; go_arch=amd64 ;;
    aarch64|arm64) rust_arch=aarch64; go_arch=arm64 ;;
    *)
      for id in starship bat eza fd fzf neovim ripgrep yazi zoxide; do
        is_selected_package "$id" && warn "Upstream $id is not mapped for architecture: $machine"
      done
      return 0
      ;;
  esac

  for id in starship bat eza fd fzf neovim ripgrep yazi zoxide; do
    is_selected_package "$id" || continue
    case "$id" in
      starship) repo=starship/starship ;;
      bat) repo=sharkdp/bat ;;
      eza) repo=eza-community/eza ;;
      fd) repo=sharkdp/fd ;;
      fzf) repo=junegunn/fzf ;;
      neovim) repo=neovim/neovim ;;
      ripgrep) repo=BurntSushi/ripgrep ;;
      yazi) repo=sxyazi/yazi ;;
      zoxide) repo=ajeetdsouza/zoxide ;;
    esac
    if [[ $DRY_RUN == 1 ]]; then
      say "[dry-run] Would install the latest upstream $id release from github.com/$repo into ~/.local"
      continue
    fi
    command_exists curl || die 'curl is required for upstream tools; select curl and rerun.'
    json=$(curl -fsSL --retry 3 "https://api.github.com/repos/$repo/releases/latest")
    tag=$(printf '%s' "$json" | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -1)
    [[ -n $tag ]] || die "Could not resolve the latest release for $id."
    version=${tag#v}
    case "$id" in
      starship) asset="starship-$rust_arch-unknown-linux-gnu.tar.gz"; install_github_tool "$id" "$asset" "$tag" "$json" starship ;;
      bat) asset="bat-v$version-$rust_arch-unknown-linux-gnu.tar.gz"; install_github_tool "$id" "$asset" "$tag" "$json" bat ;;
      eza) asset="eza_$rust_arch-unknown-linux-gnu.tar.gz"; install_github_tool "$id" "$asset" "$tag" "$json" eza ;;
      fd) asset="fd-v$version-$rust_arch-unknown-linux-gnu.tar.gz"; install_github_tool "$id" "$asset" "$tag" "$json" fd ;;
      fzf) asset="fzf-$version-linux_$go_arch.tar.gz"; install_github_tool "$id" "$asset" "$tag" "$json" fzf ;;
      neovim)
        if [[ $rust_arch == x86_64 ]]; then asset='nvim-linux-x86_64.tar.gz'; else asset='nvim-linux-arm64.tar.gz'; fi
        install_neovim_release "$asset" "$tag" "$json"
        ;;
      ripgrep)
        if [[ $rust_arch == x86_64 ]]; then asset="ripgrep-$version-x86_64-unknown-linux-musl.tar.gz"; else asset="ripgrep-$version-aarch64-unknown-linux-gnu.tar.gz"; fi
        install_github_tool "$id" "$asset" "$tag" "$json" rg
        ;;
      yazi) asset="yazi-$rust_arch-unknown-linux-gnu.deb"; install_github_tool "$id" "$asset" "$tag" "$json" yazi ya ;;
      zoxide) asset="zoxide-$version-$rust_arch-unknown-linux-musl.tar.gz"; install_github_tool "$id" "$asset" "$tag" "$json" zoxide ;;
    esac
  done
}
install_upstream_apt_tools

install_official_uv() {
  is_selected_package uv || return 0
  if [[ $DRY_RUN == 1 ]]; then
    if [[ $UPDATE_MODE == 1 ]] && command_exists uv; then
      say '[dry-run] Would update uv with: uv self update'
    else
      say '[dry-run] Would install uv with: curl -LsSf https://astral.sh/uv/install.sh | sh'
    fi
    return 0
  fi
  if command_exists uv; then
    if [[ $UPDATE_MODE == 1 ]]; then
      say "Updating uv from $(command -v uv)..."
      uv self update
    else
      say "uv is already installed: $(command -v uv)"
    fi
    return 0
  fi
  command_exists curl || die 'curl is required to install uv; select curl and rerun.'
  say 'Installing uv from astral.sh...'
  curl -LsSf https://astral.sh/uv/install.sh | sh
}
install_official_uv

install_official_herdr() {
  is_selected_package herdr || return 0
  if [[ $DRY_RUN == 1 ]]; then
    if command_exists herdr; then
      say '[dry-run] Would update Herdr with: herdr update'
    else
      say '[dry-run] Would install Herdr with: curl -fsSL https://herdr.dev/install.sh | sh'
    fi
    return 0
  fi
  if command_exists herdr; then
    say "Updating Herdr from $(command -v herdr)..."
    herdr update
    return 0
  fi
  command_exists curl || die 'curl is required to install Herdr; select curl and rerun.'
  say 'Installing Herdr from herdr.dev...'
  curl -fsSL https://herdr.dev/install.sh | sh
}
install_official_herdr

install_official_pi() {
  is_selected_package pi || return 0
  if [[ $DRY_RUN == 1 ]]; then
    if [[ $UPDATE_MODE == 1 ]] && command_exists pi; then
      say '[dry-run] Would update Pi with: pi update'
    else
      say '[dry-run] Would install Pi with: curl -fsSL https://pi.dev/install.sh | sh'
    fi
    return 0
  fi
  if command_exists pi; then
    if [[ $UPDATE_MODE == 1 ]]; then
      say "Updating Pi from $(command -v pi)..."
      pi update
    else
      say "Pi is already installed: $(command -v pi)"
    fi
    return 0
  fi
  command_exists curl || die 'curl is required to install Pi; select curl and rerun.'
  say 'Installing Pi from pi.dev...'
  curl -fsSL https://pi.dev/install.sh | sh
}
install_official_pi

if ((${#SELECTED_CONFIGS[@]})) && [[ -z $SOURCE_DIR ]]; then
  if [[ $DRY_RUN == 1 ]]; then
    say "[dry-run] Would clone $REPO into $DEST (the script never pulls an existing checkout)."
  else
    command_exists git || die 'Git is needed to clone the repository; select the git package and rerun.'
    say "Cloning $REPO into $DEST"
    git clone --recurse-submodules "$REPO" "$DEST"
    SOURCE_DIR=$DEST
  fi
fi

cleanup_obsolete_links() {
  local entry target expected_suffix link_target
  local -a obsolete_links=(
    "$HOME/.config/tmux|tmux/.config/tmux"
    "$HOME/.local/bin/tmux-scratch|scripts/.local/bin/tmux-scratch"
    "$HOME/.local/share/zsh/functions/ZNVIM_README.md|scripts/.local/share/zsh/functions/ZNVIM_README.md"
    "$HOME/.local/share/zsh/functions/fuzzy-nvim.zsh|scripts/.local/share/zsh/functions/fuzzy-nvim.zsh"
    "$HOME/.local/share/zsh/functions/index-config.zsh|scripts/.local/share/zsh/functions/index-config.zsh"
    "$HOME/.local/share/zsh/functions/index-configs.zsh|scripts/.local/share/zsh/functions/index-configs.zsh"
  )
  for entry in "${obsolete_links[@]}"; do
    IFS='|' read -r target expected_suffix <<< "$entry"
    [[ -L $target && ! -e $target ]] || continue
    link_target=$(readlink "$target" 2>/dev/null || true)
    if [[ $link_target != *"$expected_suffix" ]]; then
      NOTICES+=("Kept unrelated dangling link: $target")
      continue
    fi
    if [[ $DRY_RUN == 1 ]]; then
      say "[dry-run] Would remove obsolete dotfiles-owned link: $target"
    else
      rm -- "$target"
      NOTICES+=("Removed obsolete dotfiles-owned link: $target")
    fi
  done
}

BACKUP_ROOT=''
ensure_backup_root() {
  local parent
  [[ -n $BACKUP_ROOT ]] && return 0
  parent="$HOME/.local/state/dotfiles-backups"
  mkdir -p "$parent"
  BACKUP_ROOT=$(mktemp -d "$parent/$(date +%Y%m%d-%H%M%S)-XXXXXX")
}

backup_package_conflicts() {
  local config=$1 stow_output=$2 line relative source_file target backup_target count=0
  local -a moved_relatives=()
  while IFS= read -r line; do
    [[ $line == *'existing target '* ]] || continue
    relative=${line#*existing target }
    if [[ $relative == is*': '* ]]; then
      relative=${relative##*: }
    else
      relative=${relative%% since *}
    fi
    relative=${relative%$'\r'}
    [[ -n $relative && $relative != /* && $relative != .. && $relative != ../* && $relative != */../* && $relative != */.. ]] || continue
    contains_id "$relative" "${moved_relatives[@]}" && continue
    source_file="$SOURCE_DIR/$config/$relative"
    [[ -f $source_file || -L $source_file ]] || continue
    target="$HOME/$relative"
    [[ -e $target || -L $target ]] || continue
    if [[ -e $target && $target -ef $source_file ]]; then
      continue
    fi
    [[ ! -d $target || -L $target ]] || continue
    ensure_backup_root
    backup_target="$BACKUP_ROOT/$config/$relative"
    mkdir -p "$(dirname "$backup_target")"
    [[ ! -e $backup_target && ! -L $backup_target ]] || die "Refusing to overwrite an existing conflict backup: $backup_target"
    mv -- "$target" "$backup_target"
    moved_relatives+=("$relative")
    count=$((count+1))
  done <<< "$stow_output"
  BACKED_UP_COUNT=$count
}

compact_stow_failure() {
  local output=$1 compact
  compact=$(printf '%s\n' "$output" | awk '/^WARNING!|^  \* |^All operations aborted\.|^ERROR:/')
  if [[ -n $compact ]]; then printf '%s\n' "$compact"; else printf '%s\n' "$output" | tail -20; fi
}

should_backup_stow_conflicts() {
  local config=$1 answer=''
  [[ $DRY_RUN == 1 ]] && return 1
  [[ $BACKUP_CONFLICTS == 1 ]] && return 0
  [[ $NONINTERACTIVE == 1 ]] && return 1
  printf '\nConfig %s conflicts with existing files.\n' "$config" >/dev/tty
  printf 'Back up only those conflicting targets and retry? [y/N] ' >/dev/tty
  IFS= read -r answer </dev/tty || answer=''
  [[ $answer == y || $answer == Y ]]
}

APPLIED_CONFIGS=()
stow_configs() {
  ((${#SELECTED_CONFIGS[@]})) || return 0
  local config stow_output
  if [[ -z $SOURCE_DIR ]]; then
    if [[ $DRY_RUN == 1 ]]; then
      for config in "${SELECTED_CONFIGS[@]}"; do
        say "[dry-run] Would conflict-check and stow config after cloning: $config"
      done
    fi
    return 0
  fi
  command_exists stow || die 'GNU Stow is needed to apply configs; select the stow package and rerun.'
  cd "$SOURCE_DIR"
  for config in "${SELECTED_CONFIGS[@]}"; do
    [[ -d $config ]] || { warn "Config package is absent, skipping: $config"; continue; }
    local -a options=(-v --restow -t "$HOME")
    [[ $config == agents || $config == pi ]] && options+=(--no-folding)
    say "Checking $config for conflicts..."
    if ! stow_output=$(stow --simulate "${options[@]}" "$config" 2>&1); then
      if should_backup_stow_conflicts "$config"; then
        backup_package_conflicts "$config" "$stow_output"
        if ((BACKED_UP_COUNT > 0)); then
          NOTICES+=("Backed up $BACKED_UP_COUNT conflicting target(s) for $config under $BACKUP_ROOT/$config")
          say "Backed up $BACKED_UP_COUNT conflict(s); checking $config again..."
          if ! stow_output=$(stow --simulate "${options[@]}" "$config" 2>&1); then
            stow_output=$(compact_stow_failure "$stow_output")
            warn "Config $config still conflicts after backup and was skipped:"$'\n'"$stow_output"
            continue
          fi
        else
          stow_output=$(compact_stow_failure "$stow_output")
          warn "Config $config conflicts but no safe file targets could be identified; it was skipped:"$'\n'"$stow_output"
          continue
        fi
      else
        stow_output=$(compact_stow_failure "$stow_output")
        warn "Config $config was skipped because existing targets conflict:"$'\n'"$stow_output"
        continue
      fi
    fi
    if [[ $DRY_RUN == 1 ]]; then
      say "[dry-run] Stow check passed: $config"
    else
      say "Applying config: $config"
      if stow_output=$(stow "${options[@]}" "$config" 2>&1); then
        APPLIED_CONFIGS+=("$config")
        say "Applied config: $config"
      else
        warn "Applying config $config failed after its conflict check:"$'\n'"$stow_output"
      fi
    fi
  done
}
stow_configs

build_bat_cache() {
  is_selected_config bat || return 0
  if [[ $DRY_RUN == 1 ]]; then
    say '[dry-run] Would build the bat theme cache after applying the bat config.'
    return 0
  fi
  contains_id bat "${APPLIED_CONFIGS[@]}" || return 0
  command_exists bat || { warn 'Bat config was applied, but bat is unavailable; theme cache was not built.'; return 0; }
  say 'Building bat theme cache...'
  if bat cache --build; then say 'Built bat theme cache.'; else warn 'Failed to build the bat theme cache.'; fi
}
build_bat_cache

normalize_github_repo() {
  local value=${1%.git}
  value=${value#https://github.com/}
  value=${value#http://github.com/}
  value=${value#git@github.com:}
  value=${value#ssh://git@github.com/}
  printf '%s\n' "${value%/}"
}

valid_expected_checkout() {
  local url=$1 destination=$2 origin expected_repo origin_repo tracked_file
  command_exists git || return 1
  git -C "$destination" rev-parse --verify HEAD >/dev/null 2>&1 || return 1
  origin=$(git -C "$destination" remote get-url origin 2>/dev/null || true)
  [[ -n $origin ]] || return 1
  expected_repo=$(normalize_github_repo "$url")
  origin_repo=$(normalize_github_repo "$origin")
  [[ $origin_repo == "$expected_repo" ]] || return 1
  tracked_file=$(git -C "$destination" ls-tree -r --name-only HEAD 2>/dev/null | awk 'NR == 1 {print; exit}' || true)
  [[ -n $tracked_file && ( -e $destination/$tracked_file || -L $destination/$tracked_file ) ]] || return 1
  if [[ $expected_repo == ohmyzsh/ohmyzsh && ! -f $destination/oh-my-zsh.sh ]]; then
    return 1
  fi
}

clone_if_missing() {
  local url=$1 destination=$2 existing=''
  if [[ -d $destination ]]; then
    if valid_expected_checkout "$url" "$destination"; then
      say "Already present: $destination"
      return 0
    fi
    existing=$(find "$destination" -mindepth 1 -print -quit 2>/dev/null || true)
    if [[ -n $existing ]]; then
      warn "Keeping an existing directory that is not a valid Git checkout; $url was not cloned: $destination"
      return 0
    fi
    if [[ $DRY_RUN == 1 ]]; then
      say "[dry-run] Would replace the empty directory and clone $url to $destination"
      return 0
    fi
    rmdir "$destination"
  elif [[ -e $destination || -L $destination ]]; then
    warn "Keeping an existing non-directory; $url was not cloned: $destination"
    return 0
  fi
  if [[ $DRY_RUN == 1 ]]; then say "[dry-run] Would clone $url to $destination"; else git clone --quiet --depth=1 "$url" "$destination"; fi
}

run_actions() {
  local action
  # Use a stable order so dependencies (Oh My Zsh before its plugins) work even
  # when a non-interactive list is supplied in a different order.
  for action in "${ACTION_IDS[@]}"; do
    contains_id "$action" "${SELECTED_ACTIONS[@]}" || continue

    # Dry-run describes the complete selected plan. Do not silently omit an
    # action merely because its package/config has not been installed yet.
    if [[ $DRY_RUN == 1 ]]; then
      case "$action" in
        oh-my-zsh) clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" ;;
        zsh-plugins)
          local dry_custom=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
          clone_if_missing https://github.com/zsh-users/zsh-completions "$dry_custom/plugins/zsh-completions"
          clone_if_missing https://github.com/zsh-users/zsh-autosuggestions "$dry_custom/plugins/zsh-autosuggestions"
          clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting "$dry_custom/plugins/zsh-syntax-highlighting"
          clone_if_missing https://github.com/Aloxaf/fzf-tab "$dry_custom/plugins/fzf-tab"
          clone_if_missing https://github.com/alberti42/zsh-opencode-tab "$dry_custom/plugins/zsh-opencode-tab"
          ;;
        default-shell) say '[dry-run] Would change the login shell to the installed Zsh path.' ;;
        nvim-plugins)
          if [[ $UPDATE_MODE == 1 ]]; then
            say '[dry-run] Would sync/update Neovim plugins if Neovim and its config are available.'
          else
            say '[dry-run] Would install missing Neovim plugins if Neovim and its config are available.'
          fi
          ;;
        cleanup-obsolete-links) cleanup_obsolete_links ;;
      esac
      continue
    fi

    case "$action" in
      oh-my-zsh)
        command_exists git || { warn 'Skipping Oh My Zsh: git is unavailable.'; continue; }
        clone_if_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
        ;;
      zsh-plugins)
        command_exists git || { warn 'Skipping Zsh plugins: git is unavailable.'; continue; }
        local custom=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
        [[ -d $HOME/.oh-my-zsh || $DRY_RUN == 1 ]] || { warn 'Skipping Zsh plugins: install Oh My Zsh first.'; continue; }
        clone_if_missing https://github.com/zsh-users/zsh-completions "$custom/plugins/zsh-completions"
        clone_if_missing https://github.com/zsh-users/zsh-autosuggestions "$custom/plugins/zsh-autosuggestions"
        clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting "$custom/plugins/zsh-syntax-highlighting"
        clone_if_missing https://github.com/Aloxaf/fzf-tab "$custom/plugins/fzf-tab"
        clone_if_missing https://github.com/alberti42/zsh-opencode-tab "$custom/plugins/zsh-opencode-tab"
        ;;
      nvim-plugins)
        command_exists nvim && [[ -d $HOME/.config/nvim ]] || { warn 'Skipping Neovim plugins: nvim/config unavailable.'; continue; }
        local lazy_command lazy_description
        if [[ $UPDATE_MODE == 1 ]]; then
          lazy_command='+Lazy! sync'
          lazy_description='Syncing/updating Neovim plugins'
        else
          lazy_command='+Lazy! install'
          lazy_description='Installing missing Neovim plugins'
        fi
        say "$lazy_description (maximum 5 minutes)..."
        if command_exists timeout; then
          if ! timeout --foreground 300s nvim --headless "$lazy_command" +qa; then
            warn "Neovim plugin operation failed or timed out; rerun later with: nvim --headless \"$lazy_command\" +qa"
          fi
        elif ! nvim --headless "$lazy_command" +qa; then
          warn "Neovim plugin operation failed; rerun later with: nvim --headless \"$lazy_command\" +qa"
        fi
        say 'Finished Neovim plugin action.'
        ;;
      cleanup-obsolete-links)
        cleanup_obsolete_links
        ;;
      default-shell)
        command_exists zsh || { warn 'Skipping login shell change: zsh is unavailable.'; continue; }
        local zsh_path login_user current_shell
        zsh_path=$(command -v zsh)
        login_user=$(id -un)
        if command_exists getent; then
          current_shell=$(getent passwd "$login_user" | awk -F: '{print $7}' || true)
        else
          current_shell=$(awk -F: -v user="$login_user" '$1 == user {print $7}' /etc/passwd 2>/dev/null || true)
        fi
        if [[ $current_shell == "$zsh_path" ]]; then
          say "Login shell is already $zsh_path."
        elif command_exists sudo && sudo -n true 2>/dev/null; then
          say "Changing login shell to $zsh_path using cached sudo..."
          if sudo -n chsh -s "$zsh_path" "$login_user" </dev/null; then
            say 'Changed login shell.'
          else
            warn "Could not change the login shell; run manually: chsh -s $zsh_path"
          fi
        else
          warn "Skipped login shell change because non-interactive sudo is unavailable; run manually: chsh -s $zsh_path"
        fi
        ;;
    esac
  done
}
run_actions

say 'Completed.'
[[ -n $SOURCE_DIR ]] && say "Repository: $SOURCE_DIR"
[[ $DRY_RUN == 1 ]] && say 'Dry-run mode made no changes.'
say 'Existing checkouts are never updated automatically; run git pull yourself after reviewing changes.'

# Keep the final screen actionable even when earlier output was long.
print_installation_summary
if ((${#ISSUES[@]})); then exit 2; fi
