#!/bin/bash

runtime_state_dir() {
    printf '/run/wg-split-tunnel\n'
}

state_file() {
    local state_home="$HOME/.local/state"
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        state_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)/.local/state"
    fi
    printf '%s/wg-killswitch-active\n' "$state_home"
}

preferred_tunnel_file() {
    printf '%s/active-full-tunnel\n' "$(runtime_state_dir)"
}

read_preferred_tunnel() {
    local file
    local iface

    file="$(preferred_tunnel_file)"
    [ -r "$file" ] || return 1
    iface="$(tr -d '\r\n' < "$file")"
    [ -n "$iface" ] || return 1
    printf '%s\n' "$iface"
}

cgroup_path() {
    local dir
    for dir in /sys/fs/cgroup/user.slice/user-*.slice/user@*.service/novpn.slice; do
        [ -d "$dir" ] || continue
        printf '%s\n' "${dir#/sys/fs/cgroup/}"
        return 0
    done
    return 1
}

iface_is_up() {
    local iface="${1:-}"
    [ -n "$iface" ] || return 1
    ip link show "$iface" up &>/dev/null
}

configured_endpoint() {
    local iface="${1:-}"
    local endpoint=""
    local profile="/etc/NetworkManager/system-connections/${iface}.nmconnection"

    if iface_is_up "$iface"; then
        endpoint=$(wg show "$iface" endpoints 2>/dev/null | awk 'NR==1 && $2 != "(none)" { print $2 }')
    fi

    if [ -z "$endpoint" ] && [ -r "$profile" ]; then
        endpoint=$(awk -F= '/^endpoint=/{print $2; exit}' "$profile")
    fi

    printf '%s\n' "$endpoint"
}

endpoint_rule() {
    local iface="${1:-}"
    local endpoint="${2:-}"
    local prefix="${3:-wg-split}"
    local host="" port="" ip=""

    [ -n "$endpoint" ] || return 0

    if [[ "$endpoint" =~ ^\[([0-9A-Fa-f:]+)\]:([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
        printf '        ip6 daddr %s udp dport %s counter accept comment "wg peer %s"\n' "$host" "$port" "$iface"
        return 0
    fi

    if [[ "$endpoint" =~ ^([^:]+):([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    else
        echo "${prefix}: cannot parse endpoint for $iface: $endpoint" >&2
        return 1
    fi

    if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        ip="$host"
    else
        ip=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1 { print $1 }')
    fi

    if [ -z "$ip" ]; then
        echo "${prefix}: cannot resolve endpoint host for $iface: $host" >&2
        return 1
    fi

    printf '        ip daddr %s udp dport %s counter accept comment "wg peer %s"\n' "$ip" "$port" "$iface"
}
