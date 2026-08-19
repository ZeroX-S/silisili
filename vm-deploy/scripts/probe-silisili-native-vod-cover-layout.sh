#!/bin/sh
set -eu

# Exercise the active Cover with a fixed, known VOD instead of a randomly
# selected live room. The pass requires balanced layout geometry and advancing
# shared-texture presentation from the same process and media load.

run_id=${SILISILI_COVER_TEST_RUN_ID:-"vod-cover-$(date +%Y%m%d-%H%M%S)"}
rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.47.aarch64.rpm}
expected_sha=${2:-91a47722490f0875e47f0012b3786e33c0344ad0037bfb9e4e9d4f7522f7675b}
expected_package=silisili-native-devel-1.1.0-1.47.aarch64
test_bvid=${SILISILI_COVER_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_COVER_TEST_CID:-37630051884}
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf
phase=preflight
pid=
starttime=

application_pids() {
    pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true
}

events_for_pid() {
    journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true
}

top_pid() {
    runuser -u defaultuser -- env \
        XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
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

set_cover_mode() {
    if grep -q '^backgroundPresentationMode=' "$settings"; then
        sed -i 's/^backgroundPresentationMode=.*/backgroundPresentationMode=cover/' \
            "$settings"
    else
        printf 'backgroundPresentationMode=cover\n' >>"$settings"
    fi
    chown defaultuser:defaultuser "$settings" 2>/dev/null || true
    grep -Fxq 'backgroundPresentationMode=cover' "$settings"
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
            --id=cn.silisili.native --single-instance \
            /usr/bin/silisili-native
}

cleanup() {
    result=$?
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    set_cover_mode 2>/dev/null || true
    stop_application
    if test "$result" -ne 0; then
        printf 'sailfish_test=failed|run=%s|reason=vod-cover-%s|evidence=journal-pid-%s\n' \
            "$run_id" "$phase" "${pid:-none}"
        test -z "${pid:-}" || events_for_pid | grep -E \
            'native (cover|cover video|system PiP|playback session|hardware video|player|software video)|QML|TypeError|ReferenceError|Binding loop|EGL|FBO|Segmentation fault|ANOM_ABEND' \
            | tail -420 || true
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

test -f "$rpm_path"
printf '%s  %s\n' "$expected_sha" "$rpm_path" | sha256sum -c -
rpm -K --nosignature "$rpm_path"
test "$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$rpm_path")" \
    = "$expected_package"
test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)" = "$expected_package"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
test -x /tmp/bonito-direct-touch
test -f "$settings"

phase=launch
stop_application
set_cover_mode
mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --set-never-blank=enabled >/dev/null
launch_vod >"/tmp/silisili-native-vod-cover-$run_id.log" 2>&1
pid=$(wait_for_single_process)
starttime=$(awk '{print $22}' "/proc/$pid/stat")

phase=foreground-playback
wait_for_marker 'native player: load command submitted' 160
wait_for_marker 'native hardware video: first shared-texture frame rendered' 240
wait_for_marker 'native software video: first-frame latch reconciled' 240
wait_for_marker 'native cover: active layout ready' 80
test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"
test "$(application_pids | wc -l)" -eq 1

foreground_events=$(events_for_pid)
test "$(printf '%s\n' "$foreground_events" \
    | grep -Fc 'native player: load command submitted' || true)" -eq 1
printf '%s\n' "$foreground_events" | grep -Fq \
    'native software video: first-frame latch reconciled'

layout_line=$(printf '%s\n' "$foreground_events" \
    | grep -F 'native cover: active layout ready' | tail -1)
printf '%s\n' "$layout_line" | grep -E \
    'order resolution-video-title-progress-actions .* actions 3 mode cover' \
    >/dev/null
printf '%s\n' "$layout_line" | grep -E \
    'gap [1-9][0-9]* .* balanced true' >/dev/null
set -- $(printf '%s\n' "$layout_line" | sed -n \
    's/.* gap \([0-9][0-9]*\) occupiedHeight \([0-9][0-9]*\) availableHeight \([0-9][0-9]*\) balanced true.*/\1 \2 \3/p')
test "$#" -eq 3
gap=$1
occupied_height=$2
available_height=$3
height_delta=$((occupied_height - available_height))
test "$height_delta" -ge -1
test "$height_delta" -le 1

phase=background-transition
if test "$(top_pid || true)" = "$pid"; then
    background_entry=physical-gesture
    # The deterministic portrait test hook uses the same transformed physical
    # edge coordinates as the established portrait PiP shutdown regression.
    /tmp/bonito-direct-touch swipe 3 1080 900 1080 500 25
else
    # The deterministic direct-launch hook can map below Lipstick's current
    # task. In that case it is already in the same inactive state a successful
    # background gesture would establish.
    background_entry=direct-inactive
fi
attempt=0
while test "$attempt" -lt 80; do
    current_top=$(top_pid || true)
    events=$(events_for_pid)
    if test "$current_top" != "$pid" \
            && printf '%s\n' "$events" | grep -F \
                'native system PiP: Lipstick foreground state foreground false' \
                >/dev/null; then
        break
    fi
    sleep 0.25
    attempt=$((attempt + 1))
done
test "$attempt" -lt 80

phase=cover-frames
attempt=0
while test "$attempt" -lt 160; do
    cover_frame_count=$(events_for_pid \
        | grep -Fc 'native cover video: live shared-texture frame presented' \
        || true)
    test "$cover_frame_count" -ge 2 && break
    sleep 0.25
    attempt=$((attempt + 1))
done
test "$attempt" -lt 160
test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"

events=$(events_for_pid)
printf '%s\n' "$events" | grep -Fq \
    'native cover video: scene graph shares persistent video texture true'
first_serial=$(printf '%s\n' "$events" \
    | grep -F 'native cover video: live shared-texture frame presented' \
    | head -1 | sed -n 's/.* serial \([0-9][0-9]*\) .*/\1/p')
last_serial=$(printf '%s\n' "$events" \
    | grep -F 'native cover video: live shared-texture frame presented' \
    | tail -1 | sed -n 's/.* serial \([0-9][0-9]*\) .*/\1/p')
test -n "$first_serial"
test -n "$last_serial"
test "$last_serial" -gt "$first_serial"
test "$(printf '%s\n' "$events" \
    | grep -Fc 'native player: load command submitted' || true)" -eq 1
test -z "$(printf '%s\n' "$events" | grep -E \
    'native transport: pause requested true|native hardware video: in-place seek requested|native hardware video: (direct pipeline failed|switching to software fallback|first-frame watchdog expired|external texture shader failed|EGLImage creation failed|GPU fence backlog)|overlay QML error|QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
    || true)"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

phase=complete
mcetool --set-never-blank=disabled >/dev/null
set_cover_mode
stop_application
trap - EXIT
printf 'native_vod_cover_layout=ready|run=%s|package=%s|pid=%s|bvid=%s|cid=%s|background_entry=%s|layout=resolution-video-title-progress-actions|gap=%s|occupied_height=%s|available_height=%s|balanced=1|first_serial=%s|last_serial=%s|media_loads=1|background_pause=0|seek_recovery=0|hardware_fallback=0|rpm_verify=clean|sha256=%s|visual_model=unused\n' \
    "$run_id" "$expected_package" "$pid" "$test_bvid" "$test_cid" \
    "$background_entry" "$gap" "$occupied_height" "$available_height" \
    "$first_serial" "$last_serial" "$expected_sha"
printf 'sailfish_test=ready|run=%s|package=%s|pid=%s|checks=15/15\n' \
    "$run_id" "$expected_package" "$pid"
