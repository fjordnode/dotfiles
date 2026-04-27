#!/usr/bin/env sh

# Start the first available polkit authentication agent.
agents="
hyprpolkitagent
/usr/lib/polkit-kde-authentication-agent-1
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
/usr/libexec/polkit-gnome-authentication-agent-1
/usr/lib/polkit-gnome-authentication-agent-1
/usr/lib/mate-polkit/polkit-mate-authentication-agent-1
/usr/lib/lxpolkit
/usr/lib/xfce-polkit/xfce-polkit
"

for agent in $agents; do
    if [ -x "$agent" ]; then
        exec "$agent"
    fi

    resolved="$(command -v "$agent" 2>/dev/null || true)"
    if [ -n "$resolved" ]; then
        exec "$resolved"
    fi
done

printf '%s\n' "No polkit authentication agent found." >&2
exit 0
