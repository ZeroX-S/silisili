#!/bin/sh
set -eu

# Capture the real Sailfish Cover for a fixed VOD.  The script intentionally
# leaves image interpretation to the caller; it only establishes playback,
# backgrounds the app, and uploads the phone-created PNG.

run_id=${SILISILI_COVER_CAPTURE_RUN_ID:-"cover-capture-$(date +%Y%m%d-%H%M%S)"}
upload_url=${SILISILI_COVER_CAPTURE_URL:-http://192.168.2.20:18103}
upload_name=${SILISILI_COVER_CAPTURE_NAME:-silisili-native-cover-current.png}
test_bvid=${SILISILI_COVER_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_COVER_TEST_CID:-37630051884}
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf

application_pids() {
    pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true
}

stop_application() {
    for process_id in $(application_pids); do
        kill -TERM "$process_id" 2>/dev/null || true
    done
    sleep 2
    rm -f /tmp/silisili-native-defaultuser.lock
}

set_cover_mode() {
    if grep -q '^backgroundPresentationMode=' "$settings"; then
        sed -i 's/^backgroundPresentationMode=.*/backgroundPresentationMode=cover/' \
            "$settings"
    else
        printf 'backgroundPresentationMode=cover\n' >>"$settings"
    fi
    chown defaultuser:defaultuser "$settings" 2>/dev/null || true
}

top_pid() {
    runuser -u defaultuser -- env \
        XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        gdbus call --session --dest org.nemomobile.lipstick --object-path / \
            --method org.nemomobile.compositor.privateTopmostWindowProcessId \
        2>/dev/null | grep -oE '[0-9]+' | tail -1
}

test -x /usr/bin/silisili-native
test -x /tmp/bonito-direct-touch
test -x /tmp/bonito-uinput-camera-key
test -f "$settings"
case "$upload_name" in
    *.png) ;;
    *) exit 64 ;;
esac
case "$upload_name" in
    *[!A-Za-z0-9._-]*) exit 64 ;;
esac

stop_application
set_cover_mode
mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --set-never-blank=enabled >/dev/null

runuser -u defaultuser -- env \
    HOME=/home/defaultuser \
    XDG_RUNTIME_DIR=/run/user/100000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
    WAYLAND_DISPLAY=../../display/wayland-0 \
    QT_QPA_PLATFORM=wayland \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=history-resume \
    SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=80 \
    SILISILI_NATIVE_TEST_START_POSITION=14 \
    /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
        --id=cn.silisili.native --single-instance /usr/bin/silisili-native \
    >/tmp/silisili-native-cover-capture-"$run_id".log 2>&1

attempt=0
pid=
while test "$attempt" -lt 80; do
    set -- $(application_pids)
    if test "$#" -eq 1; then
        pid=$1
        journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null \
            | grep -F 'native cover: active layout ready' >/dev/null && break
    fi
    sleep 0.25
    attempt=$((attempt + 1))
done
test -n "$pid"
test "$attempt" -lt 80

if test "$(top_pid || true)" = "$pid"; then
    /tmp/bonito-direct-touch swipe 3 1080 900 1080 500 25
fi

attempt=0
while test "$attempt" -lt 80; do
    if test "$(top_pid || true)" != "$pid"; then
        break
    fi
    sleep 0.25
    attempt=$((attempt + 1))
done
test "$attempt" -lt 80

/tmp/bonito-uinput-camera-key screenshot
sleep 2
shot=$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1)
test -n "$shot"
curl -fsS -X PUT --data-binary @"$shot" "$upload_url/$upload_name"
printf 'native_cover_capture=ready|run=%s|pid=%s|screenshot=%s|upload=%s/%s|visual_model=unused\n' \
    "$run_id" "$pid" "$shot" "$upload_url" "$upload_name"

mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
