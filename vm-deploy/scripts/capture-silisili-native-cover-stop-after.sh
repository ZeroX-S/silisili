#!/bin/sh
set -eu

expected_package=${SILISILI_COVER_STOP_EXPECTED_PACKAGE:-silisili-native-devel-1.1.0-1.57.aarch64}
run_id=${SILISILI_COVER_STOP_RUN_ID:-"cover-stop-shot-$(date +%Y%m%d-%H%M%S)"}
upload_url=${SILISILI_COVER_STOP_UPLOAD_URL:-http://192.168.2.20:18103}
upload_name=${SILISILI_COVER_STOP_AFTER_NAME:-silisili-cover-stop-after.png}
close_x=${SILISILI_COVER_STOP_CLOSE_X:-442}
close_y=${SILISILI_COVER_STOP_CLOSE_Y:-808}
runtime=/run/user/100000
pid=
keep_awake=0
input_method=none

cleanup() {
    result=$?
    if test "$keep_awake" -eq 1; then
        mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    fi
    if test "$result" -ne 0; then
        printf 'native_cover_stop_after=failed|run=%s|pid=%s|visual_model=unused\n' \
            "$run_id" "${pid:-none}"
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

wait_for_marker() {
    marker=$1
    first_line=$2
    limit=$3
    attempt=0
    while test "$attempt" -lt "$limit"; do
        events_for_pid | tail -n "+$first_line" | grep -F "$marker" >/dev/null \
            && return 0
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
    printf 'native_cover_stop_after_artifact=ready|run=%s|pid=%s|source=%s|name=%s|bytes=%s|sha256=%s|visual_model=unused\n' \
        "$run_id" "$pid" "$shot" "$upload_name" "$(wc -c <"$shot")" \
        "$(sha256sum "$shot" | awk '{print $1}')"
}

test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' silisili-native-devel)" = "$expected_package"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
test -x /tmp/bonito-direct-touch
test -x /tmp/bonito-uinput-camera-key
case "$upload_name" in
    *[!A-Za-z0-9._-]*|'') exit 64 ;;
    *.png) ;;
    *) exit 64 ;;
esac

set -- $(application_pids)
test "$#" -eq 1
pid=$1
starttime=$(awk '{print $22}' "/proc/$pid/stat")
events_before=$(events_for_pid)
printf '%s\n' "$events_before" | grep -F 'content playback actionsEnabled true' >/dev/null
first_line=$(printf '%s\n' "$events_before" | wc -l)
first_line=$((first_line + 1))
test "$(top_pid || true)" != "$pid"

mcetool --unblank-screen >/dev/null 2>&1 || true
mcetool --set-tklock-mode=unlocked >/dev/null 2>&1 || true
mcetool --set-never-blank=enabled >/dev/null 2>&1 || true
keep_awake=1
sleep 1

printf 'native_cover_stop_tap=intent|run=%s|pid=%s|x=%s|y=%s|source=template-matched-action-row|visual_model=unused\n' \
    "$run_id" "$pid" "$close_x" "$close_y"
/tmp/bonito-direct-touch tap "$close_x" "$close_y"
if wait_for_marker 'native cover: stop action handled' "$first_line" 20; then
    input_method=tap
else
    mcetool --unblank-screen >/dev/null 2>&1 || true
    mcetool --set-tklock-mode=unlocked >/dev/null 2>&1 || true
    sleep 0.5
    printf 'native_cover_stop_press=intent|run=%s|pid=%s|x=%s|y=%s|duration_ms=180|source=template-matched-action-row|visual_model=unused\n' \
        "$run_id" "$pid" "$close_x" "$close_y"
    /tmp/bonito-direct-touch swipe "$close_x" "$close_y" \
        "$close_x" "$close_y" 180 3
    wait_for_marker 'native cover: stop action handled' "$first_line" 80
    input_method=press-180ms
fi

wait_for_marker 'native cover: eligibility changed idle' "$first_line" 80
wait_for_marker 'native cover: idle action icons cleared actions 0' "$first_line" 80
events_after=$(events_for_pid | tail -n "+$first_line")
printf '%s\n' "$events_after" | grep -F \
    'native cover: stop action handled' >/dev/null
printf '%s\n' "$events_after" | grep -F \
    'native cover: eligibility changed idle' \
    | grep -F 'sessionActive false' >/dev/null
printf '%s\n' "$events_after" | grep -F \
    'native cover: idle action icons cleared actions 0' \
    | grep -F 'pauseEmpty true' \
    | grep -F 'presentationEmpty true' \
    | grep -F 'closeEmpty true' >/dev/null

sleep 1
capture_and_upload

test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"
test "$(application_pids | wc -l)" -eq 1
test "$(top_pid || true)" != "$pid"
test -z "$(events_for_pid | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
    || true)"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
keep_awake=0
trap - EXIT
printf 'native_cover_stop_after=ready|run=%s|package=%s|pid=%s|starttime=%s|input=%s|point=%s,%s|handled=1|session_active=0|content=idle|actions=0|same_pid=1|rpm_verify=clean|visual_model=unused\n' \
    "$run_id" "$expected_package" "$pid" "$starttime" "$input_method" \
    "$close_x" "$close_y"
