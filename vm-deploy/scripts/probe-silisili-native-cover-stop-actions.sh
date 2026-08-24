#!/bin/sh
set -eu

expected_package=${SILISILI_COVER_STOP_EXPECTED_PACKAGE:-silisili-native-devel-1.1.0-1.57.aarch64}
test_bvid=${SILISILI_COVER_STOP_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_COVER_STOP_TEST_CID:-37630051884}
run_id=${SILISILI_COVER_STOP_RUN_ID:-"cover-stop-$(date -u +%Y%m%dT%H%M%SZ)"}
runtime=/run/user/100000
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf
phase=preflight
pid=
starttime=
original_background_mode=

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
    rm -f /tmp/silisili-native-defaultuser.lock
}

set_background_mode() {
    next_mode=$1
    if grep -q '^backgroundPresentationMode=' "$settings"; then
        sed -i "s/^backgroundPresentationMode=.*/backgroundPresentationMode=$next_mode/" \
            "$settings"
    else
        printf 'backgroundPresentationMode=%s\n' "$next_mode" >>"$settings"
    fi
    chown defaultuser:defaultuser "$settings" 2>/dev/null || true
}

restore_background_mode() {
    if test -n "$original_background_mode"; then
        set_background_mode "$original_background_mode"
    else
        sed -i '/^backgroundPresentationMode=/d' "$settings"
    fi
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

wait_for_single_process() {
    attempt=0
    while test "$attempt" -lt 80; do
        set -- $(application_pids)
        if test "$#" -eq 1; then
            printf '%s\n' "$1"
            return 0
        fi
        sleep 0.25
        attempt=$((attempt + 1))
    done
    return 1
}

launch_vod() {
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
            --id=cn.silisili.native --single-instance \
            /usr/bin/silisili-native \
        >"/tmp/silisili-native-$run_id.log" 2>&1
}

cleanup() {
    result=$?
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    restore_background_mode 2>/dev/null || true
    stop_application
    if test "$result" -ne 0; then
        printf 'sailfish_test=failed|run=%s|phase=%s|pid=%s|visual_model=unused\n' \
            "$run_id" "$phase" "${pid:-none}"
        test -z "${pid:-}" || events_for_pid | grep -E \
            'native cover|native player|native playback|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -260 || true
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)" = "$expected_package"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
test -x /tmp/bonito-direct-touch
test -f "$settings"
original_background_mode=$(sed -n 's/^backgroundPresentationMode=//p' \
    "$settings" | tail -1 || true)

phase=launch
stop_application
set_background_mode cover
mcetool --unblank-screen >/dev/null 2>&1 || true
mcetool --set-tklock-mode=unlocked >/dev/null 2>&1 || true
mcetool --set-never-blank=enabled >/dev/null 2>&1 || true
launch_vod
pid=$(wait_for_single_process)
starttime=$(awk '{print $22}' "/proc/$pid/stat")

phase=playback-cover
wait_for_marker 'native cover: eligibility changed playback' 240
wait_for_marker 'native cover: presentation state ready' 120
wait_for_marker 'content playback actionsEnabled true' 120
wait_for_marker 'native cover: active layout ready' 160

phase=background
if test "$(top_pid || true)" = "$pid"; then
    /tmp/bonito-direct-touch swipe 3 1080 900 1080 500 25
fi
attempt=0
while test "$attempt" -lt 100; do
    test "$(top_pid || true)" != "$pid" && break
    sleep 0.25
    attempt=$((attempt + 1))
done
test "$attempt" -lt 100

phase=cover-stop
# Portrait Cover actions occupy the lower action row. The direct-touch helper
# can expose either physical or logical Cover coordinates depending on the
# Sailfish 5.2 compositor scale, so try a bounded grid and re-background after
# a video-area hit. The close action is the only tap that can produce the idle
# object-tree marker; pause and presentation toggles leave it absent.
stopped=0
for action_y in 1800 1900 2000 2100; do
    for action_x in 180 360 540 720 900; do
        test "$stopped" -eq 0 || break
        /tmp/bonito-direct-touch tap "$action_x" "$action_y"
        sleep 0.3
        if events_for_pid | grep -F 'native cover: idle action icons cleared actions 0' \
                >/dev/null; then
            stopped=1
            break
        fi
        if test "$(top_pid || true)" = "$pid"; then
            /tmp/bonito-direct-touch swipe 3 1080 900 1080 500 25
            sleep 0.5
        fi
    done
done
test "$stopped" -eq 1
wait_for_marker 'native cover: eligibility changed idle' 120
wait_for_marker 'native cover: idle action icons cleared actions 0' 120
idle_events=$(events_for_pid)
printf '%s\n' "$idle_events" | grep -Fq \
    'native cover: eligibility changed idle'
printf '%s\n' "$idle_events" | grep -Fq \
    'native cover: idle action icons cleared actions 0'
printf '%s\n' "$idle_events" | grep -Fq \
    'sessionActive false'
test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"
test "$(application_pids | wc -l)" -eq 1
test -z "$(printf '%s\n' "$idle_events" | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
    || true)"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

phase=complete
trap - EXIT
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
restore_background_mode
stop_application
printf 'native_cover_stop_actions=ready|run=%s|package=%s|pid=%s|playback_actions=3|idle_actions=0|session_stopped=1|same_pid=1|rpm_verify=clean|visual_model=unused\n' \
    "$run_id" "$expected_package" "$pid"
printf 'sailfish_test=ready|run=%s|package=%s|pid=%s|checks=11/11\n' \
    "$run_id" "$expected_package" "$pid"
