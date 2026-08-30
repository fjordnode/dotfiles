# Dotfiles Core

Portable CLI/development configuration managed with GNU Stow. The bootstrap is interactive and rerunnable. It supports Arch/CachyOS (`pacman`), Debian/Ubuntu, Fedora, and openSUSE; macOS requires both Homebrew and Homebrew Bash 4.3 or newer.

## Quick Install

For the safest flow, download and review the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/fjordnode/dotfiles/main/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh
```

Running it directly is also supported; the checklist reads from the terminal even when the script itself is piped:

```bash
curl -fsSL https://raw.githubusercontent.com/fjordnode/dotfiles/main/bootstrap.sh | bash
```

macOS ships an older Bash. Install Homebrew Bash first and use it explicitly, especially for a piped install:

```bash
brew install bash
curl -fsSL https://raw.githubusercontent.com/fjordnode/dotfiles/main/bootstrap.sh | "$(brew --prefix)/bin/bash"
```

The first screen selects the setup type:

- **CLI** (the safe default) hides graphical desktop applications and configs.
- **Desktop** shows the complete catalog supported by the detected package manager, including available Wayland and compositor tools. Configs remain selectable for applications installed separately.

Then use **Space** to select items, **↑/↓** (or `j`/`k`) to move, **Enter** to accept, **Esc** to return to the previous step, and `q` to cancel. Applications are grouped by category and alphabetized within each category. The remaining checklists cover:

1. system packages to install;
2. config packages to link with Stow—the matching configs for selected applications are preselected automatically;
3. optional setup actions such as an APT system upgrade, Oh My Zsh, changing the login shell, or removing obsolete links previously created by these dotfiles.

The config suggestions are only defaults: you can toggle any of them before continuing. An explicit `--configs` list remains authoritative in automated runs.

Before changing anything, the script validates required tools and checks selected packages against current APT or pacman metadata, prints the complete plan—including an APT metadata refresh when needed—and asks for confirmation. Fatal execution errors are repeated in the final installation summary. It does not:

- overwrite conflicting files or use `stow --adopt`; optional conflict backups are explicit and preserved under `~/.local/state`;
- pull or modify an existing Git checkout;
- install unselected package bundles;
- change the login shell unless selected;
- run plugin installers unless selected;
- run as root.

Stow first performs a simulation for each selected config. A conflicting config is skipped while the other selected configs continue.

### Arch/CachyOS

Arch packages use `pacman -S --needed` without a separate `pacman -Sy`, avoiding an unsafe partial-upgrade database refresh. Update the machine normally before bootstrapping if its package database is stale:

```bash
sudo pacman -Syu
./bootstrap.sh
```

Interactive Pacman transactions are attached directly to `/dev/tty`, so provider choices and the final `[Y/n]` confirmation remain visible even when the bootstrap was piped or launched through a terminal harness. Selecting Yazi explicitly installs the small `ttf-nerd-fonts-symbols` provider instead of asking users to choose among every Nerd Font package.

### Debian/Ubuntu package sources

APT is used for foundational and system-integrated packages. The optional **APT system upgrade** action runs `apt-get update` followed by `apt-get upgrade -y` before installing selected packages; it is disabled by default and preserves existing package configuration files. Fast-moving CLI tools—Starship, bat, eza, fd, fzf, Neovim, ripgrep, Yazi, and zoxide—come from their latest official GitHub release instead of Debian's older packages. They are installed version-by-version under `~/.local/share/dotfiles-tools/` and linked from `~/.local/bin/`.

The bootstrap does not add third-party APT repositories or overwrite an unmanaged file in `~/.local/bin`. Desktop applications unavailable from the standard APT metadata are omitted from the application selector, while their configs remain available. Release checksums are verified when an upstream release provides a matching `<asset>.sha256` file. Supported release architectures are x86-64 and ARM64.

### Dry run and automation

```bash
# Interactive preview; package installation and file changes are skipped
./bootstrap.sh --dry-run

# Fully explicit, non-interactive run
./bootstrap.sh --non-interactive \
  --packages 'git stow zsh neovim fzf ripgrep fd' \
  --configs 'git zsh nvim scripts' \
  --actions 'oh-my-zsh zsh-plugins nvim-plugins'
```

Use `none` for an empty list. Non-interactive mode requires all three lists, which prevents an omitted variable from unexpectedly selecting defaults; Pacman also receives `--noconfirm` in that mode. `PACKAGES`, `CONFIGS`, `ACTIONS`, `NONINTERACTIVE=1`, and `DRY_RUN=1` are equivalent environment controls.

Run the regression smoke tests after changing the bootstrap. Destructive-path checks use temporary home directories and fake package-manager commands:

```bash
tests/bootstrap-smoke.sh
```

The script requires Bash 4.3 or newer. Current Linux distributions satisfy this requirement. On macOS, install Homebrew Bash and invoke the script with `"$(brew --prefix)/bin/bash"`; stock macOS Bash 3.2 is unsupported.

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
- **git** - Git configuration and aliases
- **bat/eza/yazi** - CLI tool configuration
- **starship** - Cross-shell prompt
- **herdr** - Terminal workspace manager runtime and configuration
- **agents** - Shared `~/.agents/skills` used by Pi, Claude, and other compatible agents
- **claude** - Claude configuration, available as an explicit config selection
- **pi** - Pi coding-agent runtime plus settings, extensions, themes, and pinned package declarations; credentials and runtime state remain local
- **niri/hypr/noctalia** - Desktop configs, each selected independently
- **scripts** - Small shell helpers for SSH forwarding, archives, OSC 52, safer removal, and directory listing
- **vpn-split** - Advanced Linux-specific VPN helpers, never selected by default

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
├── git/
│   └── .gitconfig
├── starship/
│   └── .config/
│       └── starship.toml
├── bat/
├── eza/
├── yazi/
├── herdr/
│   └── .config/
│       └── herdr/
│           └── config.toml
├── agents/            # shared agent skills
├── claude/            # Claude config
├── pi/                # Pi config and custom resources
├── niri/              # Niri desktop config
├── hypr/              # Hyprland desktop config
├── noctalia/          # Noctalia V5 config
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

Dotfiles and applications update separately so a tool update never changes your configuration checkout unexpectedly.

Update the repository after reviewing its incoming changes:

```bash
cd ~/dotfiles
git pull --ff-only
./bootstrap.sh
```

Update applications installed under `~/.local` by the bootstrap, plus uv, Herdr, and Pi:

```bash
./update-tools.sh --dry-run
./update-tools.sh
```

The updater detects what this bootstrap previously installed, prints the plan, and asks for confirmation. It uses the same versioned release installer, updates Neovim plugins, and runs `uv self update`, `herdr update`, and `pi update`. Normal bootstrap runs only install missing Neovim plugins; they do not update existing plugins. It deliberately does not update OS-managed packages; use the native system workflow such as `sudo apt update && sudo apt upgrade` or `sudo pacman -Syu` for those.

## Customization

Host-specific Git settings belong in `~/.gitconfig.local`, which the tracked
Git config includes automatically. This keeps machine-only paths such as
`safe.directory` entries out of the portable repository.

### Environment Variables

For automation, `SETUP=cli|desktop`, `PACKAGES`, `CONFIGS`, and `ACTIONS` are supported; the lists accept comma- or space-separated IDs. Set all three lists together with `NONINTERACTIVE=1`. `DRY_RUN=1`, `REPO`, and `DEST` are also supported. Run `./bootstrap.sh --help` for examples.

### Herdr

Select the `herdr` application to run Herdr's official `curl -fsSL https://herdr.dev/install.sh | sh` installer. Its config is selected automatically. When Herdr is already available, bootstrap uses the built-in `herdr update` command instead.

### Pi

Select the `pi` application to run Pi's official `curl -fsSL https://pi.dev/install.sh | sh` installer. Its declarative `pi` config is selected automatically. The installer is skipped when `pi` is already available. Run `pi` and use `/login` separately on each machine; bootstrap never handles Pi authentication.

The Stow package deliberately uses `--no-folding`, keeping generated files such as `auth.json`, sessions, package checkouts, caches, and logs under the real `~/.pi/agent` directory rather than inside this repository. Pi auto-mode safety controls also remain machine-local and are excluded from Stow/Git. Shared skills are managed by the separate `agents` Stow package for reuse across coding agents.

### Adding New Configs

To add a new program's configuration:

1. Create a new directory in `~/dotfiles`
2. Mirror the expected structure from `$HOME`
3. Add its ID and label to the config checklist in `bootstrap.sh`

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

The `vpn-split` package is Linux-specific and is not selected by default. It stows:

- `~/.local/bin/novpn`
- `~/.local/bin/wg-split-up`
- `~/.local/bin/wg-split-down`
- `~/.local/bin/wg-kill-switch-off`
- `~/.local/bin/wg-status-proton`
- `~/.local/bin/wg-status-home`
- `~/.config/noctalia/wireguard-widgets.toml` and its scripted widget runtime
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

When a selected config conflicts with an existing real file, interactive runs offer to move only the conflicting targets into:

```text
~/.local/state/dotfiles-backups/<timestamp>/<stow-package>/
```

The bootstrap then repeats its Stow simulation before applying anything. It never uses `stow --adopt`. Declining the backup skips that config and records the exact conflict in the final installation summary.

For explicit non-interactive migrations:

```bash
BACKUP_CONFLICTS=1 NONINTERACTIVE=1 \
  PACKAGES=none CONFIGS=pi ACTIONS=none ./bootstrap.sh
```

You can also pass `--backup-conflicts` during an interactive or automated run.

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
- macOS (with Homebrew and Homebrew Bash 4.3+)
- Termux (Android)
- Docker containers
- Unraid (via Docker container)

## License

MIT
