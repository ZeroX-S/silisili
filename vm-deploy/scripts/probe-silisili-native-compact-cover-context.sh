#!/bin/sh
set -eu

expected_package=${SILISILI_COMPACT_COVER_EXPECTED_PACKAGE:-silisili-native-devel-1.1.0-1.56.aarch64}
test_bvid=${SILISILI_COMPACT_COVER_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_COMPACT_COVER_TEST_CID:-37630051884}
upload_url=${SILISILI_COMPACT_COVER_UPLOAD_URL:-http://192.168.2.20:18103}
upload_name=${SILISILI_COMPACT_COVER_UPLOAD_NAME:-silisili-compact-home-cover.png}
runtime=/run/user/100000
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf
run_id=${SILISILI_COMPACT_COVER_RUN_ID:-"compact-cover-$(date +%Y%m%d-%H%M%S)"}
phase=preflight
pid=
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
    sleep 1
    for process_id in $(application_pids); do
        kill -KILL "$process_id" 2>/dev/null || true
    done
    sleep 2
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
    grep -Fxq "backgroundPresentationMode=$next_mode" "$settings"
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

cleanup() {
    result=$?
    stop_application
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    restore_background_mode >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_compact_cover_context=failed|run=%s|phase=%s|pid=%s|visual_model=unused\n' \
            "$run_id" "$phase" "${pid:-none}"
        events_for_pid | grep -E \
            'native (cover|compact player|player|playback session|system PiP)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -300 || true
        printf 'sailfish_test=failed|run=%s|reason=compact-cover-%s|evidence=journal-pid-%s\n' \
            "$run_id" "$phase" "${pid:-none}"
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)" = "$expected_package"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
test -x /tmp/bonito-direct-touch
test -x /tmp/bonito-uinput-camera-key
test -f "$settings"
case "$upload_name" in
    *[!A-Za-z0-9._-]*|'') exit 64 ;;
    *.png) ;;
    *) exit 64 ;;
esac
original_background_mode=$(sed -n \
    's/^backgroundPresentationMode=//p' "$settings" | tail -1)

phase=launch
stop_application
set_background_mode cover
mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --set-never-blank=enabled >/dev/null
runuser -u defaultuser -- env \
    HOME=/home/defaultuser \
    XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
    WAYLAND_DISPLAY=../../display/wayland-0 \
    QT_QPA_PLATFORM=wayland \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=compact \
    SILISILI_NATIVE_TEST_CONTENT_MODE=home-cover \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=80 \
    /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
        --id=cn.silisili.native --single-instance \
        /usr/bin/silisili-native >"/tmp/silisili-native-$run_id.log" 2>&1
pid=$(wait_for_single_process)
starttime=$(awk '{print $22}' "/proc/$pid/stat")

phase=video-cover
wait_for_marker 'content playback actionsEnabled true' 240
playback_state=$(events_for_pid | grep -F \
    'native cover: presentation state ready' \
    | grep -F 'content playback actionsEnabled true' | tail -1)
printf '%s\n' "$playback_state" | grep -Fq 'eligiblePage true'
printf '%s\n' "$playback_state" | grep -Fq 'sessionActive true'
printf '%s\n' "$playback_state" | grep -Fq 'sessionEnded false'

phase=home-compact-context
wait_for_marker 'native compact player: test transition handled target home' 240
wait_for_marker 'native compact player: visibility visible' 120
attempt=0
compact_state=
while test "$attempt" -lt 120; do
    compact_state=$(events_for_pid | grep -F \
        'native cover: presentation state ready' \
        | grep -F 'eligiblePage false' \
        | grep -F 'compactActive true' \
        | grep -F 'content playback actionsEnabled true' \
        | tail -1 || true)
    test -z "$compact_state" || break
    sleep 0.25
    attempt=$((attempt + 1))
done
test -n "$compact_state"
printf '%s\n' "$compact_state" | grep -Fq 'sessionActive true'
printf '%s\n' "$compact_state" | grep -Fq 'sessionEnded false'

phase=background
test "$(top_pid || true)" = "$pid"
background_entry=physical-gesture
/tmp/bonito-direct-touch swipe 3 1080 900 1080 500 25
attempt=0
while test "$attempt" -lt 80; do
    test "$(top_pid || true)" != "$pid" && break
    sleep 0.25
    attempt=$((attempt + 1))
done
test "$attempt" -lt 80
wait_for_marker 'native cover video: live shared-texture frame presented' 120

phase=capture
started=$(date +%s)
/tmp/bonito-uinput-camera-key screenshot
sleep 2
shot=$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1)
test -n "$shot"
modified=$(stat -c %Y "$shot")
test "$modified" -ge "$started"
test "$(head -c 8 "$shot" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a
curl -fsS -X PUT --data-binary @"$shot" "$upload_url/$upload_name" >/dev/null
shot_bytes=$(wc -c <"$shot")
shot_sha=$(sha256sum "$shot" | awk '{print $1}')
printf 'native_compact_cover_artifact=ready|run=%s|pid=%s|source=%s|name=%s|bytes=%s|sha256=%s|visual_model=unused\n' \
    "$run_id" "$pid" "$shot" "$upload_name" "$shot_bytes" "$shot_sha"

events=$(events_for_pid)
home_line=$(printf '%s\n' "$events" | grep -nF \
    'native compact player: test transition handled target home' \
    | tail -1 | cut -d: -f1)
test -n "$home_line"
post_home_events=$(printf '%s\n' "$events" | tail -n "+$home_line")
printf '%s\n' "$events" | grep -F \
    'native compact player: visibility visible' \
    | grep -F 'compact true' >/dev/null
printf '%s\n' "$events" | grep -F \
    'native cover: active layout ready' \
    | grep -F 'actions 3' >/dev/null
test -z "$(printf '%s\n' "$post_home_events" | grep -F \
    'native cover: presentation state ready' \
    | grep -F 'content idle' || true)"
test -z "$(printf '%s\n' "$post_home_events" | grep -F \
    'native cover: idle action icons cleared actions 0' || true)"
test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"
test "$(application_pids | wc -l)" -eq 1
test -z "$(printf '%s\n' "$events" | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
    || true)"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

phase=complete
stop_application
mcetool --set-never-blank=disabled >/dev/null
restore_background_mode
trap - EXIT
printf 'native_compact_cover_context=ready|run=%s|package=%s|pid=%s|transition=video-detail-to-home|session_active=1|compact_active=1|content=playback|actions_enabled=1|actions=3|background_entry=%s|name=%s|bytes=%s|sha256=%s|mode_restored=%s|same_pid=1|rpm_verify=clean|visual_model=unused\n' \
    "$run_id" "$expected_package" "$pid" "$background_entry" "$upload_name" \
    "$shot_bytes" "$shot_sha" "${original_background_mode:-unset}"
printf 'sailfish_test=ready|run=%s|package=%s|pid=%s|checks=13/13\n' \
    "$run_id" "$expected_package" "$pid"
