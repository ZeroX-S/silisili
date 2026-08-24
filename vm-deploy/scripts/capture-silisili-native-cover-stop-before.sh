#!/bin/sh
set -eu

expected_package=${SILISILI_COVER_STOP_EXPECTED_PACKAGE:-silisili-native-devel-1.1.0-1.57.aarch64}
run_id=${SILISILI_COVER_STOP_RUN_ID:-"cover-stop-shot-$(date +%Y%m%d-%H%M%S)"}
upload_url=${SILISILI_COVER_STOP_UPLOAD_URL:-http://192.168.2.20:18103}
upload_name=${SILISILI_COVER_STOP_BEFORE_NAME:-silisili-cover-stop-before.png}
test_bvid=${SILISILI_COVER_STOP_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_COVER_STOP_TEST_CID:-37630051884}
runtime=/run/user/100000
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf
phase=preflight
pid=
keep_awake=0

cleanup() {
    result=$?
    if test "$keep_awake" -eq 1; then
        mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    fi
    if test "$result" -ne 0; then
        printf 'native_cover_stop_before=failed|run=%s|phase=%s|pid=%s|visual_model=unused\n' \
            "$run_id" "$phase" "${pid:-none}"
        test -z "${pid:-}" || events_for_pid | grep -E \
            'native cover|native player|native playback|native hardware video|native transport|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -260 || true
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

application_pids() {
    pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true
}

events_for_pid() {
    test -n "$pid" || return 0
    journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true
}

top_pid() {
    runuser -u defaultuser -- env \
        XDG_RUNTIME_DIR="$runtime" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
        gdbus call --session --dest org.nemomobile.lipstick --object-path / \
            --method org.nemomobile.compositor.privateTopmostWindowProcessId \
        2>/dev/null | grep -oE '[0-9]+' | tail -1
}

stop_application() {
    for process_id in $(application_pids); do
        kill -TERM "$process_id" 2>/dev/null || true
    done
    attempt=0
    while test "$attempt" -lt 20 && test -n "$(application_pids)"; do
        sleep 0.25
        attempt=$((attempt + 1))
    done
    for process_id in $(application_pids); do
        kill -KILL "$process_id" 2>/dev/null || true
    done
    attempt=0
    while test "$attempt" -lt 12 && test -n "$(application_pids)"; do
        sleep 0.25
        attempt=$((attempt + 1))
    done
    test -z "$(application_pids)"
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

wait_for_marker() {
    marker=$1
    limit=$2
    attempt=0
    while test "$attempt" -lt "$limit"; do
        events_for_pid | grep -F "$marker" >/dev/null && return 0
        sleep 0.25
        attempt=$((attempt + 1))
    done
    return 1
}

wait_for_first_frame() {
    limit=$1
    attempt=0
    while test "$attempt" -lt "$limit"; do
        events_for_pid | grep -E \
            'native (hardware video: first shared-texture frame rendered|player: first persistent shared-texture frame rendered)' \
            >/dev/null && return 0
        sleep 0.25
        attempt=$((attempt + 1))
    done
    return 1
}

capture_and_upload() {
    started=$(date +%s)
    /tmp/bonito-uinput-camera-key screenshot
    sleep 2
    shot=$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1)
    test -n "$shot"
    modified=$(stat -c %Y "$shot")
    test "$modified" -ge "$started"
    test "$(head -c 8 "$shot" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a
    curl -fsS -X PUT --data-binary @"$shot" "$upload_url/$upload_name" >/dev/null
    printf 'native_cover_stop_before_artifact=ready|run=%s|pid=%s|source=%s|name=%s|bytes=%s|sha256=%s|visual_model=unused\n' \
        "$run_id" "$pid" "$shot" "$upload_name" "$(wc -c <"$shot")" \
        "$(sha256sum "$shot" | awk '{print $1}')"
}

test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' silisili-native-devel)" = "$expected_package"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
test -x /tmp/bonito-direct-touch
test -x /tmp/bonito-uinput-camera-key
test -f "$settings"
case "$upload_name" in
    *[!A-Za-z0-9._-]*|'') exit 64 ;;
    *.png) ;;
    *) exit 64 ;;
esac

stop_application
set_cover_mode
mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --set-never-blank=enabled >/dev/null
keep_awake=1

phase=launch
runuser -u defaultuser -- env \
    HOME=/home/defaultuser \
    XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
    WAYLAND_DISPLAY=../../display/wayland-0 \
    QT_QPA_PLATFORM=wayland \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=video-detail \
    SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=80 \
    /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
        --id=cn.silisili.native --single-instance /usr/bin/silisili-native \
    >"/tmp/silisili-native-$run_id.log" 2>&1

attempt=0
while test "$attempt" -lt 80; do
    set -- $(application_pids)
    if test "$#" -eq 1; then
        pid=$1
        break
    fi
    sleep 0.25
    attempt=$((attempt + 1))
done
test -n "$pid"
starttime=$(awk '{print $22}' "/proc/$pid/stat")
phase=wait-playback
wait_for_marker 'content playback actionsEnabled true' 280
wait_for_first_frame 280

phase=background
test "$(top_pid || true)" = "$pid"
/tmp/bonito-direct-touch swipe 3 1080 900 1080 500 25
attempt=0
while test "$attempt" -lt 80; do
    test "$(top_pid || true)" != "$pid" && break
    sleep 0.25
    attempt=$((attempt + 1))
done
test "$attempt" -lt 80
phase=cover-frame
wait_for_marker 'native cover video: live shared-texture frame presented' 120
phase=capture
capture_and_upload

test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"
test "$(application_pids | wc -l)" -eq 1
test -z "$(events_for_pid | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
    || true)"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
keep_awake=0
phase=complete
trap - EXIT
printf 'native_cover_stop_before=ready|run=%s|package=%s|pid=%s|starttime=%s|content=playback|actions=3|background=physical-gesture|same_pid=1|rpm_verify=clean|visual_model=unused\n' \
    "$run_id" "$expected_package" "$pid" "$starttime"
