#!/usr/bin/env bash
# Destructive-path smoke tests run only inside temporary HOME directories.
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
BOOTSTRAP="$ROOT/bootstrap.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { printf '[test] FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf '[test] PASS: %s\n' "$*"; }

bash -n "$BOOTSTRAP" "$ROOT/update-tools.sh"
if command -v zsh >/dev/null 2>&1; then zsh -n "$ROOT/zsh/.zshrc"; fi
pass 'shell syntax'

mkdir -p "$TMP/bin" "$TMP/home"
cat >"$TMP/bin/pacman" <<'EOF'
#!/bin/sh
case "$1" in
  -Si|-Q) exit 0 ;;
  *) printf 'simulated package-manager failure\n' >&2; exit 42 ;;
esac
EOF
cat >"$TMP/bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
chmod +x "$TMP/bin/pacman" "$TMP/bin/sudo"
TEST_PATH="$TMP/bin:/usr/bin:/bin"

output=$(HOME="$TMP/home" PATH="$TEST_PATH" "$BOOTSTRAP" \
  --dry-run --non-interactive --setup cli \
  --packages none --configs none --actions none 2>&1)
[[ $output == *'No warnings or skipped operations.'* ]] || fail 'empty dry-run summary was missing'
[[ $output != *'obsolete dotfiles-owned link'* ]] || fail 'cleanup ran without being selected'
pass 'empty dry run has no hidden cleanup'

if command -v apt-get >/dev/null 2>&1 && ! command -v pacman >/dev/null 2>&1; then
  mkdir -p "$TMP/apt-bin"
  cat >"$TMP/apt-bin/apt-cache" <<'EOF'
#!/bin/sh
printf 'curl:\n  Candidate: (none)\n'
EOF
  cat >"$TMP/apt-bin/apt-get" <<EOF
#!/bin/sh
touch "$TMP/apt-get-was-called"
exit 99
EOF
  chmod +x "$TMP/apt-bin/apt-cache" "$TMP/apt-bin/apt-get"
  set +e
  output=$(HOME="$TMP/home" PATH="$TMP/apt-bin:/usr/bin:/bin" "$BOOTSTRAP" \
    --non-interactive --setup cli \
    --packages curl --configs none --actions none 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] || fail "unavailable APT preflight returned $status instead of 1"
  [[ ! -e $TMP/apt-get-was-called ]] || fail 'APT metadata was mutated before availability validation'
  [[ $output == *'unavailable in the current APT metadata'* ]] || fail 'APT preflight error was unclear'
  pass 'APT availability is validated before metadata mutation'
fi

if command -v script >/dev/null 2>&1 && script --version 2>&1 | grep -q 'util-linux' && command -v apt-get >/dev/null 2>&1 && ! command -v pacman >/dev/null 2>&1; then
  # --setup cli skips the setup-type screen, so the first `a` reaches the
  # package checklist directly.
  mkdir -p "$TMP/pty-home"
  set +e
  output=$(printf 'a\n\n\n' | HOME="$TMP/pty-home" TERM=xterm \
    script -qefc "$BOOTSTRAP --dry-run --setup cli" /dev/null 2>&1)
  status=$?
  set -e
  output=${output//$'\r'/}
  [[ $status == 0 ]] || fail "interactive select-all dry run returned $status"
  package_line=$(printf '%s\n' "$output" | grep '^  Packages:' | tail -1)
  [[ $package_line == *'unzip'* && $package_line == *'uv'* ]] || fail 'a did not select the complete CLI package list'
  pass 'interactive a selects all items'
else
  printf '[test] SKIP: interactive select-all (util-linux script on APT host required)\n'
fi

set +e
output=$(HOME="$TMP/home" PATH="$TEST_PATH" "$BOOTSTRAP" \
  --non-interactive --setup cli \
  --packages curl --configs none --actions none 2>&1)
status=$?
set -e
[[ $status == 42 ]] || fail "fatal package failure returned $status instead of 42"
[[ $output == *'Installation summary'* ]] || fail 'fatal package failure omitted final summary'
[[ $output == *'Unexpected command failure'* ]] || fail 'fatal package failure was not recorded'
pass 'fatal errors reach the final summary'

mkdir -p "$TMP/home/.config" "$TMP/home/.local/bin"
ln -s '/missing/unrelated-tmux-config' "$TMP/home/.config/tmux"
ln -s '/missing/dotfiles/scripts/.local/bin/tmux-scratch' "$TMP/home/.local/bin/tmux-scratch"
HOME="$TMP/home" PATH="$TEST_PATH" "$BOOTSTRAP" \
  --non-interactive --setup cli \
  --packages none --configs none --actions cleanup-obsolete-links >/dev/null
[[ -L $TMP/home/.config/tmux ]] || fail 'cleanup removed an unrelated dangling link'
[[ ! -L $TMP/home/.local/bin/tmux-scratch ]] || fail 'cleanup kept a recognized obsolete link'
pass 'cleanup is explicit and ownership checked'

mkdir -p "$TMP/home/.oh-my-zsh"
printf 'keep me\n' >"$TMP/home/.oh-my-zsh/partial"
set +e
output=$(HOME="$TMP/home" PATH="$TEST_PATH" "$BOOTSTRAP" \
  --non-interactive --setup cli \
  --packages none --configs none --actions oh-my-zsh 2>&1)
status=$?
set -e
[[ $status == 2 ]] || fail "partial clone warning returned $status instead of 2"
[[ -f $TMP/home/.oh-my-zsh/partial ]] || fail 'partial clone directory was overwritten'
[[ $output == *'not a valid Git checkout'* ]] || fail 'partial clone was not reported'
pass 'partial clone directories are preserved and reported'

mkdir -p "$TMP/stow-bin" "$TMP/stow-home"
cat >"$TMP/stow-bin/stow" <<'EOF'
#!/bin/sh
if [ "$1" = --simulate ]; then
  if [ -e "$HOME/.gitconfig" ] || [ -L "$HOME/.gitconfig" ]; then
    printf '%s\n' \
      'WARNING! stowing git would cause conflicts:' \
      '  * existing target is neither a link nor a directory: .gitconfig' \
      'All operations aborted.' >&2
    exit 1
  fi
  exit 0
fi
exit 0
EOF
chmod +x "$TMP/stow-bin/stow"
printf 'alternate diagnostic config\n' >"$TMP/stow-home/.gitconfig"
HOME="$TMP/stow-home" PATH="$TMP/stow-bin:$TEST_PATH" BACKUP_CONFLICTS=1 "$BOOTSTRAP" \
  --non-interactive --setup cli \
  --packages none --configs git --actions none >/dev/null
backup_file=$(find "$TMP/stow-home/.local/state/dotfiles-backups" -type f -path '*/git/.gitconfig' -print -quit)
[[ -n $backup_file ]] || fail 'alternate Stow conflict diagnostic was not backed up'
[[ $(<"$backup_file") == 'alternate diagnostic config' ]] || fail 'alternate Stow backup content changed'
pass 'alternate Stow conflict diagnostics are parsed safely'

if command -v stow >/dev/null 2>&1; then
  rm -rf "$TMP/home"
  mkdir -p "$TMP/home"
  printf 'first local config\n' >"$TMP/home/.gitconfig"
  HOME="$TMP/home" PATH="$TEST_PATH" BACKUP_CONFLICTS=1 "$BOOTSTRAP" \
    --non-interactive --setup cli \
    --packages none --configs git --actions none >/dev/null
  [[ -L $TMP/home/.gitconfig ]] || fail 'Git config was not stowed after backup'
  first_count=$(find "$TMP/home/.local/state/dotfiles-backups" -mindepth 1 -maxdepth 1 -type d | wc -l)

  rm "$TMP/home/.gitconfig"
  printf 'second local config\n' >"$TMP/home/.gitconfig"
  HOME="$TMP/home" PATH="$TEST_PATH" BACKUP_CONFLICTS=1 "$BOOTSTRAP" \
    --non-interactive --setup cli \
    --packages none --configs git --actions none >/dev/null
  second_count=$(find "$TMP/home/.local/state/dotfiles-backups" -mindepth 1 -maxdepth 1 -type d | wc -l)
  [[ $first_count == 1 && $second_count == 2 ]] || fail 'conflict backup roots were not unique'
  pass 'Stow conflicts use unique backups and retry safely'
else
  printf '[test] SKIP: Stow conflict backup (stow unavailable)\n'
fi

printf '[test] All smoke tests passed.\n'
