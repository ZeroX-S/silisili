#!/bin/sh
set -eu

expected_package=${SILISILI_COMPACT_CLOSE_EXPECTED_PACKAGE:-silisili-native-devel-1.1.0-1.57.aarch64}
test_bvid=${SILISILI_COMPACT_CLOSE_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_COMPACT_CLOSE_TEST_CID:-37630051884}
run_id=${SILISILI_COMPACT_CLOSE_RUN_ID:-"compact-close-$(date -u +%Y%m%dT%H%M%SZ)"}
runtime=/run/user/100000
phase=preflight
pid=
starttime=

application_pids() {
    pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true
}

events_for_pid() {
    test -n "$pid" || return 0
    journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true
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

wait_for_compact_frame() {
    limit=$1
    attempt=0
    while test "$attempt" -lt "$limit"; do
        events=$(events_for_pid)
        if printf '%s\n' "$events" | grep -F \
                'native compact player: visibility visible' \
                | grep -Eq 'frameSerial [1-9][0-9]*'; then
            return 0
        fi
        if printf '%s\n' "$events" | grep -Fq \
                'native compact player: loading cover hidden orientation portrait'; then
            return 0
        fi
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
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    stop_application
    if test "$result" -ne 0; then
        printf 'native_compact_close_stop=failed|run=%s|phase=%s|pid=%s|visual_model=unused\n' \
            "$run_id" "$phase" "${pid:-none}"
        test -z "${pid:-}" || events_for_pid | grep -E \
            'native (compact player|cover|player|playback session)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -300 || true
        printf 'sailfish_test=failed|run=%s|reason=compact-close-%s|evidence=journal-pid-%s\n' \
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

phase=launch
stop_application
mcetool --unblank-screen >/dev/null 2>&1 || true
mcetool --set-tklock-mode=unlocked >/dev/null 2>&1 || true
mcetool --set-never-blank=enabled >/dev/null 2>&1 || true
runuser -u defaultuser -- env \
    HOME=/home/defaultuser \
    XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
    WAYLAND_DISPLAY=../../display/wayland-0 \
    QT_QPA_PLATFORM=wayland \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=compact \
    SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=80 \
    /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
        --id=cn.silisili.native --single-instance \
        /usr/bin/silisili-native >"/tmp/silisili-native-$run_id.log" 2>&1
pid=$(wait_for_single_process)
starttime=$(awk '{print $22}' "/proc/$pid/stat")

phase=wait-compact
wait_for_marker 'native compact player: test transition handled' 240
wait_for_marker 'native compact player: visibility visible' 120
wait_for_marker 'content playback actionsEnabled true' 120
wait_for_marker 'native player: scene graph shares persistent video texture true' 240
wait_for_compact_frame 120
geometry=$(events_for_pid | grep -F 'native compact player: floating geometry' \
    | grep -F 'orientation portrait' | tail -1)
test -n "$geometry"
set -- $(printf '%s\n' "$geometry" | sed -n \
    's/.* x \([0-9][0-9]*\) y \([0-9][0-9]*\) width \([0-9][0-9]*\) height \([0-9][0-9]*\) aspect.*/\1 \2 \3 \4/p')
test "$#" -eq 4
compact_x=$1
compact_y=$2
compact_width=$3
compact_height=$4
test "$compact_width" -gt 0 && test "$compact_height" -gt 0

phase=show-controls
center_x=$((compact_x + compact_width / 2))
center_y=$((compact_y + compact_height / 2))
/tmp/bonito-direct-touch tap "$center_x" "$center_y"
wait_for_marker 'native compact player: controls shown touch-toggle' 80
controls=$(events_for_pid | grep -F \
    'native compact player: controls shown touch-toggle' | tail -1)
set -- $(printf '%s\n' "$controls" | sed -n \
    's/.* closeCenterX \([0-9][0-9]*\) closeCenterY \([0-9][0-9]*\).*/\1 \2/p')
test "$#" -eq 2
close_x=$1
close_y=$2

phase=close-stop
/tmp/bonito-direct-touch tap "$close_x" "$close_y"
wait_for_marker 'native compact player: close stop handled' 80
wait_for_marker 'native compact player: close stop completed' 80
wait_for_marker 'native compact player: visibility hidden active false' 80
wait_for_marker 'native cover: eligibility changed idle' 80
wait_for_marker 'native cover: idle action icons cleared actions 0' 120
events=$(events_for_pid)
handled=$(printf '%s\n' "$events" | grep -F \
    'native compact player: close stop handled' | tail -1)
completed=$(printf '%s\n' "$events" | grep -F \
    'native compact player: close stop completed' | tail -1)
idle_state=$(printf '%s\n' "$events" | grep -F \
    'native cover: presentation state ready' \
    | grep -F 'sessionActive false' \
    | grep -F 'content idle actionsEnabled false' | tail -1)
idle_actions=$(printf '%s\n' "$events" | grep -F \
    'native cover: idle action icons cleared actions 0' | tail -1)
printf '%s\n' "$handled" | grep -Fq 'sessionActiveBefore true'
printf '%s\n' "$completed" | grep -Fq \
    'sessionActive false compact false playing false mediaKind none'
test -n "$idle_state"
printf '%s\n' "$idle_actions" | grep -Fq \
    'pauseEmpty true presentationEmpty true closeEmpty true'
test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"
test "$(application_pids | wc -l)" -eq 1
test -z "$(printf '%s\n' "$events" | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
    || true)"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

phase=complete
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
stop_application
trap - EXIT
printf 'native_compact_close_stop=ready|run=%s|package=%s|pid=%s|close=%s,%s|session_active=0|playing=0|compact=0|cover=idle|actions=0|same_pid=1|rpm_verify=clean|visual_model=unused\n' \
    "$run_id" "$expected_package" "$pid" "$close_x" "$close_y"
printf 'sailfish_test=ready|run=%s|package=%s|pid=%s|checks=12/12\n' \
    "$run_id" "$expected_package" "$pid"
