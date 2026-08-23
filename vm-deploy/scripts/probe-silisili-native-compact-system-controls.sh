#!/bin/sh
set -eu

expected_package=${SILISILI_COMPACT_CONTROLS_EXPECTED_PACKAGE:-silisili-native-devel-1.1.0-1.56.aarch64}
test_bvid=${SILISILI_COMPACT_CONTROLS_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_COMPACT_CONTROLS_TEST_CID:-37630051884}
runtime=/run/user/100000
phase=preflight
pid=

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
    sleep 1
    for process_id in $(application_pids); do
        kill -KILL "$process_id" 2>/dev/null || true
    done
    sleep 2
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

pulse_peer_address() {
    runuser -u defaultuser -- env \
        XDG_RUNTIME_DIR="$runtime" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
        gdbus call --session --dest org.PulseAudio1 \
        --object-path /org/pulseaudio/server_lookup1 \
        --method org.freedesktop.DBus.Properties.Get \
        org.PulseAudio.ServerLookup1 Address 2>/dev/null \
        | sed -n "s/.*<['\"]\([^'\"]*\)['\"]>.*/\1/p"
}

media_entry_path() {
    address=$1
    runuser -u defaultuser -- env XDG_RUNTIME_DIR="$runtime" \
        dbus-send --peer="$address" --print-reply \
        /org/pulseaudio/stream_restore1 \
        org.PulseAudio.Ext.StreamRestore1.GetEntryByName \
        string:sink-input-by-media-role:x-maemo 2>/dev/null \
        | sed -n 's/.*object path "\([^"]*\)".*/\1/p'
}

media_volume_raw() {
    address=$1
    entry_path=$2
    runuser -u defaultuser -- env XDG_RUNTIME_DIR="$runtime" \
        dbus-send --peer="$address" --print-reply \
        "$entry_path" org.freedesktop.DBus.Properties.Get \
        string:org.PulseAudio.Ext.StreamRestore1.RestoreEntry \
        string:Volume 2>/dev/null \
        | awk '/uint32/ { value = $2 } END { print value }'
}

brightness_value() {
    mcetool -N 2>/dev/null | awk '/Brightness:/ { print $2; exit }'
}

cleanup() {
    result=$?
    stop_application
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_compact_system_controls=failed|phase=%s|pid=%s|visual_model=unused\n' \
            "$phase" "${pid:-none}"
        events_for_pid | grep -E \
            'native (compact player|gesture|system controls|player)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
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
test -S "$runtime/pulse/dbus-socket"

pulse_address=$(pulse_peer_address)
test -n "$pulse_address"
media_entry=$(media_entry_path "$pulse_address")
test -n "$media_entry"
initial_volume=$(media_volume_raw "$pulse_address" "$media_entry")
initial_brightness=$(brightness_value)
test -n "$initial_volume" && test -n "$initial_brightness"

phase=launch
stop_application
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
    SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=80 \
    /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
        --id=cn.silisili.native --single-instance \
        /usr/bin/silisili-native >/tmp/silisili-native-compact-controls-launch.log 2>&1
pid=$(wait_for_single_process)
starttime=$(awk '{print $22}' "/proc/$pid/stat")

phase=wait-compact
wait_for_marker 'native compact player: test transition handled' 240
wait_for_marker 'native compact player: visibility visible' 80
wait_for_marker 'native compact player: floating geometry' 80
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

events_before=$(events_for_pid)
lines_before=$(printf '%s\n' "$events_before" | wc -l)

phase=compact-drag
start_x=$((compact_x + compact_width / 2))
start_y=$((compact_y + compact_height / 2))
end_x=$((start_x - compact_width / 4))
end_y=$((start_y - compact_height * 3 / 10))
/tmp/bonito-direct-touch swipe "$start_x" "$start_y" "$end_x" "$end_y" 700 35

wait_for_marker 'native compact player: floating geometry drag-repositioned' 80
dragged_geometry=$(events_for_pid \
    | grep -F 'native compact player: floating geometry drag-repositioned' \
    | grep -F 'orientation portrait' | tail -1)
test -n "$dragged_geometry"
set -- $(printf '%s\n' "$dragged_geometry" | sed -n \
    's/.* x \([0-9][0-9]*\) y \([0-9][0-9]*\) width \([0-9][0-9]*\) height \([0-9][0-9]*\) aspect.*/\1 \2 \3 \4/p')
test "$#" -eq 4
dragged_x=$1
dragged_y=$2
dragged_width=$3
dragged_height=$4
test "$dragged_x" -lt "$compact_x"
test "$dragged_y" -lt "$compact_y"
test "$dragged_width" -eq "$compact_width"
test "$dragged_height" -eq "$compact_height"

after_volume=$(media_volume_raw "$pulse_address" "$media_entry")
after_brightness=$(brightness_value)
test "$after_volume" = "$initial_volume"
test "$after_brightness" = "$initial_brightness"
recent=$(events_for_pid | tail -n "+$((lines_before + 1))")
test -z "$(printf '%s\n' "$recent" | grep -E \
    'native gesture:|native system controls: (brightness changed|volume changed|volume write)' \
    || true)"
test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"
test -z "$(printf '%s\n' "$recent" | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
    || true)"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

phase=complete
stop_application
mcetool --set-never-blank=disabled >/dev/null
trap - EXIT
printf 'native_compact_drag=ready|package=%s|pid=%s|initial_geometry=%s,%s,%s,%s|dragged_geometry=%s,%s,%s,%s|brightness=%s|volume_raw=%s|system_gestures=absent|same_pid=1|rpm_verify=clean|visual_model=unused\n' \
    "$expected_package" "$pid" "$compact_x" "$compact_y" \
    "$compact_width" "$compact_height" "$dragged_x" "$dragged_y" \
    "$dragged_width" "$dragged_height" "$initial_brightness" "$initial_volume"
