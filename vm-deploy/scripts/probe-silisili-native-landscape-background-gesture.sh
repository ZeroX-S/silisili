#!/bin/sh
set -eu

run_id=${1:-"landscape-background-$(date +%Y%m%d-%H%M%S)"}
app_pid=$(pgrep -f '^/usr/bin/silisili-native' | head -1)
test -n "$app_pid"
test -x /tmp/bonito-direct-touch

top_pid() {
    runuser -u defaultuser -- env \
        XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        gdbus call --session --dest org.nemomobile.lipstick --object-path / \
            --method org.nemomobile.compositor.privateTopmostWindowProcessId \
        2>/dev/null | grep -oE '[0-9]+' | tail -1
}

test "$(top_pid)" = "$app_pid"
/tmp/bonito-direct-touch swipe 540 2157 540 1257 500 25
sleep 2
if test "$(top_pid)" != "$app_pid"; then
    printf 'landscape_background_gesture=ready|run=%s|pid=%s|physical_edge=portrait-bottom|swipe=540,2157-540,1257\n' \
        "$run_id" "$app_pid"
    printf 'sailfish_test=ready|run=%s|package=none|pid=%s|checks=2/2\n' \
        "$run_id" "$app_pid"
    exit 0
fi

/tmp/bonito-direct-touch swipe 540 3 540 903 500 25
sleep 2
if test "$(top_pid)" != "$app_pid"; then
    printf 'landscape_background_gesture=ready|run=%s|pid=%s|physical_edge=portrait-top|swipe=540,3-540,903\n' \
        "$run_id" "$app_pid"
    printf 'sailfish_test=ready|run=%s|package=none|pid=%s|checks=2/2\n' \
        "$run_id" "$app_pid"
    exit 0
fi

printf 'sailfish_test=failed|run=%s|reason=landscape-background-gesture-not-mapped|evidence=topmost-pid-%s\n' \
    "$run_id" "$(top_pid)"
exit 1
