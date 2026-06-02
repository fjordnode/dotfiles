# Dotfiles Core

Portable CLI/development configuration managed with GNU Stow. The default install is safe for headless systems, SSH-only hosts, containers, and general Linux/macOS machines.

Desktop/Wayland configuration is opt-in through profiles and should eventually live in a separate `dotfiles-desktop` repo. Fedora Asahi hardware/system recovery should stay in `asahi-dotfiles`.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/fjordnode/dotfiles/main/bootstrap.sh | bash
```

The default profile is `cli` and only stows portable terminal/dev config.

### Profiles

```bash
# Portable CLI/dev config only
PROFILE=cli bash bootstrap.sh

# CLI/dev plus AI tool config
PROFILE=dev bash bootstrap.sh

# Explicit desktop installs
PROFILE=desktop-niri bash bootstrap.sh
PROFILE=desktop-hypr bash bootstrap.sh
PROFILE=desktop bash bootstrap.sh

# Transitional Asahi profile; system recovery belongs in asahi-dotfiles
PROFILE=asahi bash bootstrap.sh
```

Profile packages:

- `cli`: `zsh`, `tmux`, `git`, `nvim`, `starship`, `eza`, `bat`, `yazi`, `scripts`
- `dev`: `cli` plus `claude`
- `desktop-niri`: `dev` plus `kitty`, `ghostty`, `niri`, `noctalia`, `noctalia-v5`
- `desktop-hypr`: `dev` plus `kitty`, `ghostty`, `hypr`, `noctalia`, `noctalia-v5`
- `desktop`: both desktop compositor configs
- `asahi`: transitional profile with desktop config and `vpn-split`; Asahi hardware/system recovery lives in `~/asahi-dotfiles`

Desktop profiles also install the main runtime packages they depend on when the system package manager is supported. On Arch/CachyOS, `PROFILE=desktop-niri` installs common Wayland/Niri tools such as `wl-clipboard`, `cliphist`, `wtype`, `brightnessctl`, `playerctl`, `pavucontrol`, `kitty`, `firefox`, `satty`, and available Niri portal/session packages.

Noctalia v5 note: this repo tracks config and a `noctalia-v5` launcher wrapper, but does not install the alpha v5 shell itself. Install or update v5 from upstream docs: <https://docs.noctalia.dev/v5/getting-started/installation>. If you are building v5 from source, you can ask the bootstrap to install known build dependencies with `INSTALL_NOCTALIA_V5_DEPS=1 PROFILE=desktop-niri bash bootstrap.sh`.

Fresh CachyOS/Niri desktop example:

```bash
curl -fsSL https://raw.githubusercontent.com/fjordnode/dotfiles/main/bootstrap.sh | PROFILE=desktop-niri bash
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
- **bat/eza/yazi** - CLI tool configuration
- **starship** - Cross-shell prompt
- **claude** - AI tool configuration, installed by `PROFILE=dev` or desktop profiles
- **niri/hypr/noctalia** - Desktop-only config, installed only by explicit desktop profiles
- **scripts** - Portable helper scripts used by shell, tmux, and Neovim profiles
- **vpn-split** - Transitional Linux-specific VPN helpers, installed only by `PROFILE=asahi`

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
├── bat/
├── eza/
├── yazi/
├── claude/            # dev profile
├── niri/              # desktop profiles
├── hypr/              # desktop profiles
├── noctalia*/         # desktop profiles
├── scripts/           # portable helper scripts
└── vpn-split/         # asahi transitional profile
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
PROFILE=cli ./bootstrap.sh
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

# Install a specific profile
PROFILE=desktop-niri bash bootstrap.sh
```

### Adding New Configs

To add a new program's configuration:

1. Create a new directory in `~/dotfiles`
2. Mirror the expected structure from `$HOME`
3. Add it to the correct profile in `bootstrap.sh`

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

The `vpn-split` package is Linux-specific and is not part of the default `cli` profile. It stows:

- `~/.local/bin/novpn`
- `~/.local/bin/wg-split-up`
- `~/.local/bin/wg-split-down`
- `~/.local/bin/wg-kill-switch-off`
- `~/.local/bin/wg-status-proton`
- `~/.local/bin/wg-status-home`
- `~/.local/bin/wg-status-killswitch`
- `~/.local/bin/wg-toggle-proton`
- `~/.local/bin/wg-toggle-home`
- `~/.local/bin/wg-toggle-killswitch`
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

If stow reports conflicts, move the existing files aside first:
```bash
mv ~/.zshrc ~/.zshrc.backup
mv ~/.tmux.conf ~/.tmux.conf.backup
cd ~/dotfiles
PROFILE=cli ./bootstrap.sh
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
