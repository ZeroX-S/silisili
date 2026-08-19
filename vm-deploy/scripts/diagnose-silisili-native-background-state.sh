#!/bin/sh
set -eu

pid=$(pgrep -f '^/usr/bin/silisili-native' | head -1)
test -n "$pid"
events=$(journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true)
top_pid=$(runuser -u defaultuser -- env \
    XDG_RUNTIME_DIR=/run/user/100000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
    gdbus call --session --dest org.nemomobile.lipstick --object-path / \
        --method org.nemomobile.compositor.privateTopmostWindowProcessId \
    2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)

count() {
    printf '%s\n' "$events" | grep -Fc "$1" || true
}

printf 'background_state=ready|pid=%s|top_pid=%s|mode_cover=%s|idle_logo=%s|active_layout=%s|decoded_frames=%s|cover_presented=%s|cover_texture_shared=%s|pip_shown=%s|foreground_false=%s\n' \
    "$pid" "${top_pid:-unknown}" \
    "$(count 'configurable background presentation ready mode "cover"')" \
    "$(count 'native cover: idle logo ready')" \
    "$(count 'native cover: active layout ready')" \
    "$(count 'native cover video: decoded shared-texture frame available')" \
    "$(count 'native cover video: live shared-texture frame presented')" \
    "$(count 'native cover video: scene graph shares persistent video texture true')" \
    "$(count 'native system PiP: shown over system interface')" \
    "$(count 'native system PiP: Lipstick foreground state foreground false')"
printf '%s\n' "$events" | grep -E \
    'native system PiP: Lipstick foreground state|native cover video: (scene graph|live shared-texture frame presented|presentation swap cadence)|native hardware video: shared-texture frame checkpoint' \
    | tail -40 || true
