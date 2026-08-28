# Small, portable shell helpers. Tool-specific helpers check their dependencies.

# SSH local port forwarding.
fip() {
  (( $# >= 2 )) || { print -u2 'Usage: fip <host> <port1> [port2 ...]'; return 1; }
  command -v ssh >/dev/null 2>&1 || { print -u2 'ssh is not installed'; return 127; }
  local host=$1 port
  shift
  for port in "$@"; do
    ssh -f -N -L "$port:localhost:$port" "$host" &&
      print "Forwarding localhost:$port -> $host:$port"
  done
}

dip() {
  (( $# > 0 )) || { print -u2 'Usage: dip <port1> [port2 ...]'; return 1; }
  command -v pkill >/dev/null 2>&1 || { print -u2 'pkill is unavailable (install procps)'; return 127; }
  local port
  for port in "$@"; do
    pkill -f -- "ssh.*-L $port:localhost:$port" &&
      print "Stopped forwarding port $port" || print "No forwarding on port $port"
  done
}

lip() {
  command -v pgrep >/dev/null 2>&1 || { print -u2 'pgrep is unavailable (install procps)'; return 127; }
  pgrep -af -- 'ssh.*-L [0-9]+:localhost:[0-9]+' || print 'No active forwards'
}

compress() {
  (( $# == 1 )) || { print -u2 'Usage: compress <path>'; return 1; }
  local source=${1%/}
  tar -czf "$source.tar.gz" -- "$source"
}

decompress() {
  (( $# == 1 )) || { print -u2 'Usage: decompress <archive.tar.gz>'; return 1; }
  tar -xzf "$1"
}

# Open Neovim in the current directory when no path is supplied.
n() {
  command -v nvim >/dev/null 2>&1 || { print -u2 'nvim is not installed'; return 127; }
  if (( $# == 0 )); then command nvim .; else command nvim "$@"; fi
}
