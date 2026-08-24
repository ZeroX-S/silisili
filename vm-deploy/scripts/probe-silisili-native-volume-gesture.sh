#!/bin/sh
set -eu

expected_package=${SILISILI_VOLUME_EXPECTED_PACKAGE:-silisili-native-devel-1.1.0-1.57.aarch64}
test_bvid=${SILISILI_VOLUME_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_VOLUME_TEST_CID:-37630051884}
runtime=/run/user/100000
phase=preflight
pid=
initial_raw=

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

cleanup() {
    result=$?
    if test -n "$pid" && test -e "/proc/$pid/stat"; then
        # The regression page owns restoration. Give its bounded stop timer a
        # chance to run before terminating the test process on an early fail.
        attempt=0
        while test "$attempt" -lt 44; do
            events_for_pid | grep -F \
                'native system controls regression: playback stopped for restore' \
                >/dev/null && break
            sleep 0.25
            attempt=$((attempt + 1))
        done
    fi
    final_raw=
    if test -n "${pulse_address:-}" && test -n "${media_entry:-}"; then
        final_raw=$(media_volume_raw "$pulse_address" "$media_entry" || true)
    fi
    stop_application
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_volume_gesture=failed|phase=%s|pid=%s|initial_raw=%s|final_raw=%s|visual_model=unused\n' \
            "$phase" "${pid:-none}" "${initial_raw:-unknown}" "${final_raw:-unknown}"
        events_for_pid | grep -E \
            'native (system controls|gesture|detail controls|player|hardware video)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
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
initial_raw=$(media_volume_raw "$pulse_address" "$media_entry")
test -n "$initial_raw"

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
    SILISILI_NATIVE_TEST_PAGE=video-detail \
    SILISILI_NATIVE_TEST_CONTENT_MODE=system-volume-gesture \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=80 \
    /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
        --id=cn.silisili.native --single-instance \
        /usr/bin/silisili-native >/tmp/silisili-native-volume-launch.log 2>&1
pid=$(wait_for_single_process)
starttime=$(awk '{print $22}' "/proc/$pid/stat")

phase=wait-playback
wait_for_marker 'native system controls: volume route route pulse-stream-restore' 120
wait_for_marker 'native system controls regression: gesture window ready' 240
geometry=$(events_for_pid \
    | grep -F 'native detail controls: gesture geometry reason system-volume-ready' \
    | tail -1)
test -n "$geometry"
set -- $(printf '%s\n' "$geometry" | sed -n \
    's/.* x \([0-9][0-9]*\) y \([0-9][0-9]*\) width \([0-9][0-9]*\) height \([0-9][0-9]*\) pageWidth \([0-9][0-9]*\) pageHeight \([0-9][0-9]*\) systemControls true.*/\1 \2 \3 \4 \5 \6/p')
test "$#" -eq 6
gesture_x=$1
gesture_y=$2
gesture_width=$3
gesture_height=$4
page_width=$5
page_height=$6

framebuffer_size=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true)
physical_width=${framebuffer_size%,*}
physical_height=${framebuffer_size#*,}
case "$physical_width:$physical_height" in
    *[!0-9:]*|:|*:|0:*|*:0) physical_width=1080; physical_height=2160 ;;
esac

# Stay in the right half but above the inline slider/fullscreen controls. Their
# own MouseAreas correctly take pointer ownership when a gesture starts there.
touch_x=$(( (gesture_x + gesture_width * 75 / 100) * physical_width / page_width ))
upper_y=$(( (gesture_y + gesture_height * 22 / 100) * physical_height / page_height ))
lower_y=$(( (gesture_y + gesture_height * 58 / 100) * physical_height / page_height ))
if test "$initial_raw" -gt 45875; then
    start_y=$upper_y
    end_y=$lower_y
    direction=down
else
    start_y=$lower_y
    end_y=$upper_y
    direction=up
fi

phase=physical-gesture
# The test page can report its first frame before Lipstick has finished the
# final foreground/input focus handoff. Keep the physical gesture outside that
# narrow startup window so the first contact reaches the player surface.
sleep 1
/tmp/bonito-direct-touch swipe "$touch_x" "$start_y" "$touch_x" "$end_y" 650 30
wait_for_marker 'native gesture: system volume' 40
wait_for_marker 'native system controls: volume write route pulse-stream-restore' 40
changed_raw=$(media_volume_raw "$pulse_address" "$media_entry")
test -n "$changed_raw"
test "$changed_raw" -ne "$initial_raw"

phase=automatic-restore
wait_for_marker 'native system controls regression: playback stopped for restore' 48
wait_for_marker 'native system controls: playback session restored reason "playback-inactive" brightnessRestored true volumeRestored true' 48
restored_raw=$(media_volume_raw "$pulse_address" "$media_entry")
test "$restored_raw" = "$initial_raw"
test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"

events=$(events_for_pid)
test -z "$(printf '%s\n' "$events" | grep -E \
    'native system controls: (volume write failed|media StreamRestore write failed)|system volume unavailable|route pactl-fallback|QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
    || true)"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

phase=complete
stop_application
mcetool --set-never-blank=disabled >/dev/null
trap - EXIT
printf 'native_volume_gesture=ready|package=%s|pid=%s|surface=video-detail-inline|direction=%s|initial_raw=%s|changed_raw=%s|restored_raw=%s|route=pulse-stream-restore-x-maemo|physical_gesture=handled|same_pid=1|rpm_verify=clean|visual_model=unused\n' \
    "$expected_package" "$pid" "$direction" "$initial_raw" "$changed_raw" \
    "$restored_raw"
