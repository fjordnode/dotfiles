# Dotfiles

Personal development environment configuration files managed with GNU Stow.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/fjordnode/dotfiles/main/bootstrap.sh | bash
```

### Termux (Android)

For Termux on Android devices:

```bash
curl -fsSL https://raw.githubusercontent.com/fjordnode/dotfiles/main/bootstrap-android.sh | bash
```

This will:
- Install all required packages using `pkg` (Termux package manager)
- Set up Android storage access
- Clone this repository to `~/dotfiles`
- Create symlinks using GNU Stow
- Install oh-my-zsh with plugins (autosuggestions, syntax-highlighting, completions)
- Install Starship prompt
- Create zsh launcher script (since `chsh` is not available)
- Configure Termux-specific optimizations

## Manual Installation

If you prefer to see what's happening:

### Linux/macOS

```bash
# Download the bootstrap script
curl -fsSL https://raw.githubusercontent.com/fjordnode/dotfiles/main/bootstrap.sh > bootstrap.sh

# Review it
cat bootstrap.sh

# Run it
bash bootstrap.sh
```

### Termux (Android)

```bash
# Download the Termux bootstrap script
curl -fsSL https://raw.githubusercontent.com/fjordnode/dotfiles/main/bootstrap-android.sh > bootstrap-android.sh

# Review it
cat bootstrap-android.sh

# Run it
bash bootstrap-android.sh
```

## What's Included

- **zsh** - Shell configuration with oh-my-zsh
- **nvim** - Neovim configuration with Lazy.nvim and plugins
- **tmux** - Terminal multiplexer configuration  
- **git** - Git configuration and aliases
- **bat** - Syntax highlighting with Catppuccin themes
- **starship** - Cross-shell prompt
- **shell** - Additional shell utilities (rm-safety)
- **vpn-split** - Linux-only WireGuard split tunneling, `novpn`, and kill-switch scripts

## Directory Structure

```
dotfiles/
├── zsh/
│   └── .zshrc
├── nvim/
│   └── .config/
│       └── nvim/
│           ├── init.lua
│           └── lua/
├── tmux/
│   └── .tmux.conf
├── git/
│   └── .gitconfig
├── starship/
│   └── .config/
│       └── starship.toml
└── shell/
    └── .rm-safety.sh
```

## Managing Dotfiles

After installation, your config files are symlinked from `~/dotfiles`. To update configs:

1. Edit the files in `~/dotfiles/[package]/`
2. Commit and push changes:
```bash
cd ~/dotfiles
git add .
git commit -m "Update configs"
git push
```

## Updating

To update your dotfiles on another machine:

```bash
cd ~/dotfiles
git pull
stow -R -t "$HOME" zsh tmux git nvim shell kitty starship eza vpn-split
```

## Customization

### Environment Variables

The bootstrap script supports several environment variables:

```bash
# Skip full install (only core packages)
FULL_INSTALL=0 bash bootstrap.sh

# Skip oh-my-zsh installation
INSTALL_OMZ=0 bash bootstrap.sh

# Skip starship installation  
INSTALL_STARSHIP=0 bash bootstrap.sh

# Skip setting zsh as default shell
SET_DEFAULT_SHELL=0 bash bootstrap.sh
```

### Adding New Configs

To add a new program's configuration:

1. Create a new directory in `~/dotfiles`
2. Mirror the expected structure from `$HOME`
3. Add to stow command in bootstrap.sh

Example for adding vim config:
```bash
cd ~/dotfiles
mkdir -p vim
mv ~/.vimrc vim/.vimrc
stow -t "$HOME" vim
git add vim
git commit -m "Add vim configuration"
```

### VPN Split Tunnel Package

The `vpn-split` package is Linux-specific. It stows:

- `~/.local/bin/novpn`
- `~/.local/bin/wg-split-up`
- `~/.local/bin/wg-split-down`
- `~/.local/bin/wg-kill-switch-off`
- `~/.local/bin/wg-status-proton`
- `~/.local/bin/wg-status-home`
- `~/.local/bin/wg-toggle-proton`
- `~/.local/bin/wg-toggle-home`
- `~/.config/systemd/user/novpn.slice`
- `~/.config/systemd/user/novpn-anchor.service`
- `~/.local/share/wg-split-tunnel/50-wg-split-tunnel`
- `~/.local/share/wg-split-tunnel/wg-split-tunnel.md`

Root-managed files still need a manual install step:

```bash
sudo install -m 755 ~/.local/share/wg-split-tunnel/50-wg-split-tunnel \
  /etc/NetworkManager/dispatcher.d/50-wg-split-tunnel
```

You may also want to name table `26642` in `/etc/iproute2/rt_tables`:

```bash
echo '26642 novpn' | sudo tee -a /etc/iproute2/rt_tables
```

## Troubleshooting

### Stow Conflicts

If stow reports conflicts, remove the existing files first:
```bash
rm ~/.zshrc ~/.tmux.conf  # etc
cd ~/dotfiles
stow -t "$HOME" zsh tmux git nvim shell kitty starship eza vpn-split
```

### Missing Plugins

If zsh plugins aren't working:
```bash
git clone https://github.com/zsh-users/zsh-completions ~/.oh-my-zsh/custom/plugins/zsh-completions
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
```

### Neovim Issues

If Neovim plugins aren't installed:
```bash
nvim --headless "+Lazy! sync" +qa
```

## Supported Systems

- Linux (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE)
- macOS (with Homebrew)
- Termux (Android)
- Docker containers
- Unraid (via Docker container)

## License

MIT
