#!/usr/bin/env bash
# dotfiles bootstrap: fresh Linux/macOS => apply my configs
set -Eeuo pipefail

REPO="${REPO:-https://github.com/fjordnode/dotfiles.git}"
DEST="${DEST:-$HOME/dotfiles}"

# Flags you can override
INSTALL_STARSHIP="${INSTALL_STARSHIP:-1}"
INSTALL_OMZ="${INSTALL_OMZ:-1}"
SET_DEFAULT_SHELL="${SET_DEFAULT_SHELL:-1}"
FULL_INSTALL="${FULL_INSTALL:-1}"
PROFILE="${PROFILE:-cli}"
INSTALL_NOCTALIA_V5_DEPS="${INSTALL_NOCTALIA_V5_DEPS:-0}"

say() { printf '[bootstrap] %s\n' "$*"; }

profile_is() {
  local p
  for p in "$@"; do
    [ "$PROFILE" = "$p" ] && return 0
  done
  return 1
}

wants_desktop() { profile_is desktop-niri desktop-hypr desktop asahi; }
wants_niri() { profile_is desktop-niri desktop asahi; }
wants_hypr() { profile_is desktop-hypr desktop asahi; }
wants_noctalia_v5_deps() { [ "$INSTALL_NOCTALIA_V5_DEPS" = 1 ] && wants_desktop; }

# Keep this package list in sync with wants_desktop/wants_niri/wants_hypr above.
packages_for_profile() {
  case "$PROFILE" in
    cli)
      printf '%s\n' zsh tmux git nvim starship eza bat yazi scripts
      ;;
    dev)
      printf '%s\n' zsh tmux git nvim starship eza bat yazi scripts claude
      ;;
    desktop-niri)
      printf '%s\n' zsh tmux git nvim starship eza bat yazi scripts claude kitty ghostty niri noctalia noctalia-v5
      ;;
    desktop-hypr)
      printf '%s\n' zsh tmux git nvim starship eza bat yazi scripts claude kitty ghostty hypr noctalia noctalia-v5
      ;;
    desktop)
      printf '%s\n' zsh tmux git nvim starship eza bat yazi scripts claude kitty ghostty niri hypr noctalia noctalia-v5
      ;;
    asahi)
      printf '%s\n' zsh tmux git nvim starship eza bat yazi scripts claude kitty ghostty niri hypr noctalia noctalia-v5 vpn-split
      ;;
    *)
      say "Unknown PROFILE=$PROFILE"
      say "Supported profiles: cli, dev, desktop-niri, desktop-hypr, desktop, asahi"
      exit 1
      ;;
  esac
}

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
  OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS="linux"
fi

# 0) Pre-auth sudo once (if present and not root)
if [ "$EUID" -ne 0 ] && command -v sudo >/dev/null 2>&1; then 
  sudo -v || true
fi

# 1) Install deps
install_pkgs() {
  local PKGS_CORE="bash git stow zsh curl wget unzip"
  local PKGS_DEV=""
  local PKGS_DESKTOP_COMMON=""
  local PKGS_DESKTOP_OPTIONAL=""
  local PKGS_NIRI=""
  local PKGS_HYPR=""
  local PKGS_NOCTALIA_V5_DEPS=""
  
  # Determine if we need sudo
  local CMD_PREFIX=""
  if [ "$EUID" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    CMD_PREFIX="sudo"
  fi
  
  if [ "$OS" = "macos" ]; then
    # macOS with Homebrew
    # First ensure Homebrew is installed
    if ! command -v brew >/dev/null 2>&1; then
      say "Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      
      # Add Homebrew to PATH for Apple Silicon Macs
      if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
    fi
    
    if [ "$FULL_INSTALL" = 1 ]; then
      # Skip tools already in macOS: openssh, less, jq, python3
      PKGS_DEV="tmux tree gh ripgrep fd neovim htop fzf bat eza zoxide"
      say "Installing packages with Homebrew..."
      brew install $PKGS_CORE $PKGS_DEV
      if wants_desktop; then
        say "Desktop profiles are Wayland/Linux-oriented; skipping desktop packages on macOS."
      fi
    else
      say "Installing core packages with Homebrew..."
      brew install $PKGS_CORE
    fi
    
  elif [ "$OS" = "linux" ]; then
    # Linux distributions
    if [ "$FULL_INSTALL" = 1 ]; then
      # Install ALL the packages we have in Dockerfile
      if   command -v apt    >/dev/null 2>&1; then
        # Critical packages (guaranteed to be in repos)
        PKGS_DEV_CRITICAL="tmux tree openssh-client less file build-essential procps htop jq python3 python3-pip fzf"
        # Optional packages (might not be in older repos - bat, eza, zoxide, gh, ripgrep, fd-find, neovim)
        PKGS_DEV_OPTIONAL="gh ripgrep fd-find neovim bat eza zoxide"
        PKGS_DESKTOP_COMMON="wl-clipboard brightnessctl playerctl pavucontrol network-manager bluez"
        PKGS_DESKTOP_OPTIONAL="wtype cliphist kitty firefox satty ghostty"
        PKGS_NIRI="niri xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk"
        PKGS_HYPR="hyprland hyprlock hypridle xdg-desktop-portal-hyprland"
        PKGS_NOCTALIA_V5_DEPS="meson g++ just libwayland-dev wayland-protocols libegl-dev libgles-dev libfreetype-dev libfontconfig-dev libcairo2-dev libpango1.0-dev libharfbuzz-dev libxkbcommon-dev libglib2.0-dev libsdbus-c++-dev libpipewire-0.3-dev libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev libcurl4-openssl-dev libwebp-dev librsvg2-dev libqalculate-dev libxml2-dev libjemalloc-dev"

        $CMD_PREFIX apt update && $CMD_PREFIX apt install -y $PKGS_CORE $PKGS_DEV_CRITICAL
        # Try optional packages - continue even if some fail
        $CMD_PREFIX apt install -y $PKGS_DEV_OPTIONAL 2>/dev/null || say "Some optional packages unavailable, continuing..."
        if wants_desktop; then
          $CMD_PREFIX apt install -y $PKGS_DESKTOP_COMMON 2>/dev/null || say "Some desktop packages unavailable, continuing..."
          for pkg in $PKGS_DESKTOP_OPTIONAL; do $CMD_PREFIX apt install -y "$pkg" 2>/dev/null || say "Optional desktop package unavailable: $pkg"; done
        fi
        if wants_niri; then
          for pkg in $PKGS_NIRI; do $CMD_PREFIX apt install -y "$pkg" 2>/dev/null || say "Optional Niri package unavailable: $pkg"; done
        fi
        if wants_hypr; then
          for pkg in $PKGS_HYPR; do $CMD_PREFIX apt install -y "$pkg" 2>/dev/null || say "Optional Hyprland package unavailable: $pkg"; done
        fi
        if wants_noctalia_v5_deps; then
          for pkg in $PKGS_NOCTALIA_V5_DEPS; do $CMD_PREFIX apt install -y "$pkg" 2>/dev/null || say "Optional Noctalia v5 build dependency unavailable: $pkg"; done
        fi
        # Fix fd name on Debian/Ubuntu
        [ -f /usr/bin/fdfind ] && $CMD_PREFIX ln -sf /usr/bin/fdfind /usr/local/bin/fd
        
      elif command -v dnf    >/dev/null 2>&1; then 
        PKGS_DEV="tmux tree gh openssh-clients less file ripgrep fd-find gcc make neovim procps-ng htop jq python3 python3-pip fzf bat eza zoxide"
        PKGS_DESKTOP_COMMON="wl-clipboard brightnessctl playerctl pavucontrol NetworkManager bluez"
        PKGS_DESKTOP_OPTIONAL="wtype cliphist kitty firefox satty ghostty"
        PKGS_NIRI="niri xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk"
        PKGS_HYPR="hyprland hyprlock hypridle xdg-desktop-portal-hyprland"
        PKGS_NOCTALIA_V5_DEPS="meson gcc-c++ just wayland-devel wayland-protocols-devel libEGL-devel mesa-libGLES-devel freetype-devel fontconfig-devel cairo-devel pango-devel harfbuzz-devel libxkbcommon-devel glib2-devel sdbus-cpp-devel pipewire-devel pam-devel polkit-devel libcurl-devel libwebp-devel librsvg2-devel libqalculate-devel libxml2-devel jemalloc-devel"
        $CMD_PREFIX dnf install -y $PKGS_CORE $PKGS_DEV
        if wants_desktop; then
          $CMD_PREFIX dnf install -y $PKGS_DESKTOP_COMMON 2>/dev/null || say "Some desktop packages unavailable, continuing..."
          for pkg in $PKGS_DESKTOP_OPTIONAL; do $CMD_PREFIX dnf install -y "$pkg" 2>/dev/null || say "Optional desktop package unavailable: $pkg"; done
        fi
        if wants_niri; then
          for pkg in $PKGS_NIRI; do $CMD_PREFIX dnf install -y "$pkg" 2>/dev/null || say "Optional Niri package unavailable: $pkg"; done
        fi
        if wants_hypr; then
          for pkg in $PKGS_HYPR; do $CMD_PREFIX dnf install -y "$pkg" 2>/dev/null || say "Optional Hyprland package unavailable: $pkg"; done
        fi
        if wants_noctalia_v5_deps; then
          for pkg in $PKGS_NOCTALIA_V5_DEPS; do $CMD_PREFIX dnf install -y "$pkg" 2>/dev/null || say "Optional Noctalia v5 build dependency unavailable: $pkg"; done
        fi
        
      elif command -v pacman >/dev/null 2>&1; then 
        PKGS_DEV="tmux tree github-cli openssh less file ripgrep fd base-devel neovim procps-ng htop jq python python-pip fzf bat eza zoxide"
        PKGS_DESKTOP_COMMON="wl-clipboard brightnessctl playerctl pavucontrol networkmanager bluez bluez-utils"
        PKGS_DESKTOP_OPTIONAL="wtype cliphist kitty firefox satty ghostty"
        PKGS_NIRI="niri xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk"
        PKGS_HYPR="hyprland hyprlock hypridle xdg-desktop-portal-hyprland"
        PKGS_NOCTALIA_V5_DEPS="meson gcc just wayland wayland-protocols libglvnd freetype2 fontconfig cairo pango harfbuzz libxkbcommon glib2 sdbus-cpp pipewire polkit pam curl libwebp librsvg libqalculate libxml2 jemalloc"
        $CMD_PREFIX pacman -Sy --needed --noconfirm $PKGS_CORE $PKGS_DEV
        if wants_desktop; then
          $CMD_PREFIX pacman -S --needed --noconfirm $PKGS_DESKTOP_COMMON 2>/dev/null || say "Some desktop packages unavailable, continuing..."
          for pkg in $PKGS_DESKTOP_OPTIONAL; do $CMD_PREFIX pacman -S --needed --noconfirm "$pkg" 2>/dev/null || say "Optional desktop package unavailable: $pkg"; done
        fi
        if wants_niri; then
          for pkg in $PKGS_NIRI; do $CMD_PREFIX pacman -S --needed --noconfirm "$pkg" 2>/dev/null || say "Optional Niri package unavailable: $pkg"; done
        fi
        if wants_hypr; then
          for pkg in $PKGS_HYPR; do $CMD_PREFIX pacman -S --needed --noconfirm "$pkg" 2>/dev/null || say "Optional Hyprland package unavailable: $pkg"; done
        fi
        if wants_noctalia_v5_deps; then
          for pkg in $PKGS_NOCTALIA_V5_DEPS; do $CMD_PREFIX pacman -S --needed --noconfirm "$pkg" 2>/dev/null || say "Optional Noctalia v5 build dependency unavailable: $pkg"; done
        fi
        
      elif command -v zypper >/dev/null 2>&1; then 
        PKGS_DEV="tmux tree gh openssh less file ripgrep fd gcc make neovim procps htop jq python3 python3-pip fzf bat eza zoxide"
        PKGS_DESKTOP_COMMON="wl-clipboard brightnessctl playerctl pavucontrol NetworkManager bluez"
        PKGS_DESKTOP_OPTIONAL="wtype cliphist kitty firefox satty ghostty"
        PKGS_NIRI="niri xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk"
        PKGS_HYPR="hyprland hyprlock hypridle xdg-desktop-portal-hyprland"
        $CMD_PREFIX zypper --non-interactive in $PKGS_CORE $PKGS_DEV
        if wants_desktop; then
          $CMD_PREFIX zypper --non-interactive in $PKGS_DESKTOP_COMMON 2>/dev/null || say "Some desktop packages unavailable, continuing..."
          for pkg in $PKGS_DESKTOP_OPTIONAL; do $CMD_PREFIX zypper --non-interactive in "$pkg" 2>/dev/null || say "Optional desktop package unavailable: $pkg"; done
        fi
        if wants_niri; then
          for pkg in $PKGS_NIRI; do $CMD_PREFIX zypper --non-interactive in "$pkg" 2>/dev/null || say "Optional Niri package unavailable: $pkg"; done
        fi
        if wants_hypr; then
          for pkg in $PKGS_HYPR; do $CMD_PREFIX zypper --non-interactive in "$pkg" 2>/dev/null || say "Optional Hyprland package unavailable: $pkg"; done
        fi
        if wants_noctalia_v5_deps; then
          say "Noctalia v5 build dependency installation is not mapped for zypper yet."
          say "Install v5 dependencies manually from: https://docs.noctalia.dev/v5/getting-started/installation"
        fi
      else
        say "No supported package manager. Install packages manually."
        exit 1
      fi
    else
      # Minimal install - just core packages
      if   command -v apt    >/dev/null 2>&1; then $CMD_PREFIX apt update && $CMD_PREFIX apt install -y $PKGS_CORE
      elif command -v dnf    >/dev/null 2>&1; then $CMD_PREFIX dnf install -y $PKGS_CORE
      elif command -v pacman >/dev/null 2>&1; then $CMD_PREFIX pacman -Sy --needed $PKGS_CORE
      elif command -v zypper >/dev/null 2>&1; then $CMD_PREFIX zypper --non-interactive in $PKGS_CORE
      fi
    fi
  else
    say "Unsupported OS: $OSTYPE"
    exit 1
  fi
}

# Check if we need to install packages
need=0
if [ "$FULL_INSTALL" = 1 ]; then
  # Check for critical tools only (don't require optional packages like bat, eza, zoxide)
  for c in git stow zsh curl wget unzip tmux tree less htop jq python3 fzf; do
    # Skip tools not needed on macOS (built-in or not checked)
    if [ "$OS" = "macos" ] && [[ "$c" =~ ^(file|less|jq|python3)$ ]]; then continue; fi
    command -v "$c" >/dev/null 2>&1 || need=1
  done
  if wants_desktop; then
    for c in wl-copy brightnessctl playerctl pavucontrol kitty firefox satty; do
      command -v "$c" >/dev/null 2>&1 || need=1
    done
  fi
  if wants_niri; then
    for c in niri wtype cliphist; do
      command -v "$c" >/dev/null 2>&1 || need=1
    done
  fi
  if wants_hypr; then
    for c in Hyprland hyprctl; do
      command -v "$c" >/dev/null 2>&1 || need=1
    done
  fi
  if wants_noctalia_v5_deps; then
    need=1
  elif [ "$INSTALL_NOCTALIA_V5_DEPS" = 1 ]; then
    say "INSTALL_NOCTALIA_V5_DEPS=1 only applies to desktop profiles; ignoring for PROFILE=$PROFILE."
  fi
else
  for c in git stow zsh curl wget unzip; do
    command -v "$c" >/dev/null 2>&1 || need=1
  done
fi
[ "$need" = 1 ] && install_pkgs

# 2) Clone or update repo
if [ ! -d "$DEST/.git" ]; then
  say "Cloning $REPO to $DEST"
  git clone --recurse-submodules "$REPO" "$DEST"
else
  say "Updating repo at $DEST"
  git -C "$DEST" pull --ff-only
fi

# 3) Apply dotfiles with stow BEFORE installing oh-my-zsh
# This ensures OUR configs are in place first
cd "$DEST"
PKGS=""
PKG_DIRS=()
while IFS= read -r pkg; do
  PKG_DIRS+=("$pkg")
done < <(packages_for_profile)

for d in "${PKG_DIRS[@]}"; do
  if [ -d "$d" ]; then
    PKGS="$PKGS $d"
  fi
done

PKGS="${PKGS# }"  # Trim leading space

if [ -n "$PKGS" ]; then
  say "Applying dotfiles: $PKGS"
  # Remove any existing config files that might interfere (they're probably from old installs)
  [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ] && mv "$HOME/.zshrc" "$HOME/.zshrc.backup"
  
  # Apply our configs
  stow -v -R -t "$HOME" $PKGS
else
  say "No stow packages found. Check your dotfiles structure."
fi

# 4) NOW install oh-my-zsh (AFTER stowing, so it sees our .zshrc exists)
if [ "$INSTALL_OMZ" = 1 ]; then
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    say "Installing Oh My Zsh..."
    # Just clone it, don't run the installer (which would overwrite .zshrc)
    git clone --quiet --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  fi

  # Install custom plugins if missing
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  [ ! -d "$ZSH_CUSTOM/plugins/zsh-completions" ] && \
    git clone --quiet https://github.com/zsh-users/zsh-completions "$ZSH_CUSTOM/plugins/zsh-completions"
  [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && \
    git clone --quiet https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && \
    git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  [ ! -d "$ZSH_CUSTOM/plugins/fzf-tab" ] && \
    git clone --quiet https://github.com/Aloxaf/fzf-tab "$ZSH_CUSTOM/plugins/fzf-tab"
  [ ! -d "$ZSH_CUSTOM/plugins/zsh-opencode-tab" ] && \
    git clone --quiet https://github.com/alberti42/zsh-opencode-tab "$ZSH_CUSTOM/plugins/zsh-opencode-tab"
fi

# 5) Install Starship prompt
if [ "$INSTALL_STARSHIP" = 1 ] && ! command -v starship >/dev/null 2>&1; then
  say "Installing Starship..."

  if [ "$OS" = "macos" ]; then
    brew install starship
  else
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi
fi

# 6) Install Neovim plugins
if command -v nvim >/dev/null 2>&1 && [ -d "$HOME/.config/nvim" ]; then
  say "Installing Neovim plugins..."
  nvim --headless "+Lazy! sync" +qa 2>/dev/null || true
fi

# 7) Install TPM (Tmux Plugin Manager)
if command -v tmux >/dev/null 2>&1 && [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
  say "Installing TPM (Tmux Plugin Manager)..."
  mkdir -p "$HOME/.config/tmux/plugins"
  git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
fi

# 8) Build bat theme cache
if command -v bat >/dev/null 2>&1 && [ -d "$HOME/.config/bat/themes" ]; then
  say "Building bat theme cache..."
  bat cache --build >/dev/null 2>&1 || true
fi

# 9) Make zsh the default shell - skip if root or in container
if [ "$SET_DEFAULT_SHELL" = 1 ] && [ "$EUID" -ne 0 ] && [ "$SHELL" != "$(command -v zsh)" ]; then
  if [ "$OS" = "macos" ]; then
    # On macOS, add Homebrew's zsh to allowed shells if needed
    ZSH_PATH="$(command -v zsh)"
    if ! grep -q "^$ZSH_PATH$" /etc/shells; then
      say "Adding $ZSH_PATH to /etc/shells"
      echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
    fi
    say "Setting default shell to zsh (new sessions only)"
    chsh -s "$ZSH_PATH" || true
  elif command -v chsh >/dev/null 2>&1; then
    say "Setting default shell to zsh (new sessions only)"
    if [ -n "${USER:-}" ]; then
      chsh -s "$(command -v zsh)" "$USER" || true
    else
      chsh -s "$(command -v zsh)" || true
    fi
  fi
fi

say "Done! Open a new shell or run: exec zsh"

# Show what was installed
if [ "$FULL_INSTALL" = 1 ]; then
  say "Full development environment installed"
else
  say "Minimal install complete. Run with FULL_INSTALL=1 for all dev tools."
fi

if wants_desktop && [ -d "$HOME/.config/noctalia-v5-test" ]; then
  say "Noctalia v5 is alpha and is not installed by this bootstrap."
  say "Install/update it manually from: https://docs.noctalia.dev/v5/getting-started/installation"
  say "Optional: rerun with INSTALL_NOCTALIA_V5_DEPS=1 to install known build deps."
fi

# macOS-specific post-install notes
if [ "$OS" = "macos" ]; then
  say "Note: On macOS, some tools may require additional setup:"
  say "  - If on Apple Silicon, ensure /opt/homebrew/bin is in your PATH"
  say "  - You may need to restart your terminal for all changes to take effect"
fi
