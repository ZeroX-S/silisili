#!/bin/sh
set -eu

# Exercise one real live room through both supported Sailfish background
# presentations. Evidence comes from process, media-load, shared-texture,
# Cover/PiP frame and frame-swap markers; no screenshot or visual model.

expected_package=silisili-native-devel-1.1.0-1.45.aarch64
expected_sha=3ad7163a959f79a30de49cd6c3b5eb3205c6b402a6cd98ac690d940d7fa604f6
rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.45.aarch64.rpm}
configured_room_id=${SILISILI_LIVE_TEST_ROOM_ID:-}
room_id=${configured_room_id:-23276452}
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf
phase=preflight
pid=

application_pids() { pgrep -f '^/usr/bin/silisili-native' || true; }
select_active_room() {
    requested=$1
    response="/tmp/silisili-native-background-room-$$.json"
    feed="/tmp/silisili-native-background-feed-$$.json"
    if curl --connect-timeout 5 --max-time 15 --silent --show-error \
        --output "$response" \
        "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo?room_id=$requested&no_playurl=1&platform=web"; then
        status=$(sed -n 's/.*"live_status":[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
            "$response" | head -1)
        if test "${status:-0}" = 1; then
            rm -f "$response" "$feed"
            printf '%s\n' "$requested"
            return 0
        fi
    fi
    if test -n "$configured_room_id"; then
        rm -f "$response" "$feed"
        return 1
    fi
    curl --connect-timeout 5 --max-time 15 --silent --show-error \
        --output "$feed" \
        'https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getList?platform=web'
    candidates=$(grep -oE '"roomid":[0-9]+' "$feed" 2>/dev/null \
        | cut -d: -f2 | awk '!seen[$0]++' | head -12 || true)
    for candidate in $candidates; do
        curl --connect-timeout 5 --max-time 15 --silent --show-error \
            --output "$response" \
            "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo?room_id=$candidate&no_playurl=1&platform=web"
        status=$(sed -n 's/.*"live_status":[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
            "$response" | head -1)
        if test "${status:-0}" = 1; then
            rm -f "$response" "$feed"
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    rm -f "$response" "$feed"
    return 1
}
events_for_pid() { journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true; }
top_pid() {
    runuser -u defaultuser -- env XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        gdbus call --session --dest org.nemomobile.lipstick --object-path / \
            --method org.nemomobile.compositor.privateTopmostWindowProcessId \
        2>/dev/null | grep -oE '[0-9]+' | tail -1
}
stop_application() {
    for old_pid in $(application_pids); do
        kill -TERM "$old_pid" 2>/dev/null || true
    done
    sleep 1
    for old_pid in $(application_pids); do
        kill -KILL "$old_pid" 2>/dev/null || true
    done
    sleep 2
    rm -f /tmp/silisili-native-defaultuser.lock
}
set_mode() {
    mode=$1
    if grep -q '^backgroundPresentationMode=' "$settings"; then
        sed -i "s/^backgroundPresentationMode=.*/backgroundPresentationMode=$mode/" "$settings"
    else
        printf 'backgroundPresentationMode=%s\n' "$mode" >>"$settings"
    fi
    chown defaultuser:defaultuser "$settings" 2>/dev/null || true
    grep -Fxq "backgroundPresentationMode=$mode" "$settings"
}
wait_for_count() {
    marker=$1; minimum=$2; limit=$3; attempt=0
    while test "$attempt" -lt "$limit"; do
        count=$(events_for_pid | grep -Fc "$marker" || true)
        test "$count" -ge "$minimum" && return 0
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}
wait_foreground() {
    attempt=0
    while test "$attempt" -lt 25; do
        test "$(top_pid || true)" = "$pid" && return 0
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}
launch_live() {
    mode=$1
    stop_application
    set_mode "$mode"
    runuser -u defaultuser -- env \
        HOME=/home/defaultuser \
        XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        WAYLAND_DISPLAY=../../display/wayland-0 \
        QT_QPA_PLATFORM=wayland \
        SILISILI_NATIVE_FORCE_ORIENTATION=landscape \
        SILISILI_NATIVE_TEST_PAGE=live-player \
        SILISILI_NATIVE_TEST_ROOM_ID="$room_id" \
        /usr/bin/invoker --type=silica-qt5 \
            --id=cn.silisili.native --single-instance \
            /usr/bin/silisili-native \
        >>"/tmp/silisili-native-live-background-$mode.log" 2>&1 &
    attempt=0
    while test "$attempt" -lt 30; do
        pid=$(application_pids | head -1)
        test -n "$pid" && break
        sleep 1
        attempt=$((attempt + 1))
    done
    test -n "$pid"
    # A direct regression launch can start below an unrelated Lipstick task.
    # Media readiness and the explicit Cover/PiP transitions below are the
    # relevant gates, so do not turn that desktop ordering into a playback
    # failure before the background presentation is exercised.
    wait_for_count 'native cover: idle logo ready' 1 15
    wait_for_count 'native playback session: live activated' 1 30
    wait_for_count 'native playback session: live source loaded' 1 30
    wait_for_count 'native hardware video: first shared-texture frame rendered' 1 40
    wait_for_count 'sourcePixelsPreserved true' 1 40
    wait_for_count 'native cover: active layout ready' 1 15
    test "$(events_for_pid | grep -Fc 'native player: load command submitted' || true)" -eq 1
    events_for_pid | grep -E \
        'native cover: idle logo ready source QSize\(144, 56\)|native cover: idle logo ready source 144x56' \
        >/dev/null
    events_for_pid | grep -E \
        'native cover: idle logo ready .* watermarks 40' >/dev/null
    events_for_pid | grep -E \
        'native cover: active layout ready order resolution-video-title-progress-actions .* actions 3' \
        >/dev/null
    events_for_pid | grep -E \
        'native cover: active layout ready .* gap [1-9][0-9]* .* balanced true' \
        >/dev/null
    test "$(events_for_pid | grep -Fc 'native cover: active layout ready' || true)" -le 4
    events_for_pid | grep -E \
        'native live quality: actual stream ready .* profile fullscreen-native sourcePixelsPreserved true' \
        >/dev/null
}
fail() {
    rc=$?
    set_mode cover 2>/dev/null || true
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$rc" -ne 0; then
        printf 'native_live_background=failed|phase=%s|pid=%s|visual_model=unused\n' \
            "$phase" "${pid:-none}"
        test -z "${pid:-}" || events_for_pid | grep -E \
            'native (playback session|cover video|system PiP|hardware video|player|software video)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -500 || true
    fi
    return "$rc"
}
trap fail EXIT
trap 'exit 130' HUP INT TERM

test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' silisili-native-devel)" = \
    "$expected_package"
printf '%s  %s\n' "$expected_sha" "$rpm_path" | sha256sum -c -
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
test -x /tmp/bonito-direct-touch
test -f "$settings"
room_id=$(select_active_room "$room_id")
printf 'native_live_room_selection=ready|requested=%s|selected=%s|fallback=%s\n' \
    "${configured_room_id:-23276452}" "$room_id" \
    "$(test "$room_id" = "${configured_room_id:-23276452}" && printf false || printf true)"
mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --set-never-blank=enabled >/dev/null

phase=cover-launch
launch_live cover
cover_pid=$pid
cover_starttime=$(awk '{print $22}' "/proc/$pid/stat")
phase=cover-background
/tmp/bonito-direct-touch swipe 540 2157 540 1257 500 25
attempt=0
while test "$attempt" -lt 20; do
    test "$(top_pid || true)" != "$pid" && break
    sleep 1
    attempt=$((attempt + 1))
done
test "$attempt" -lt 20
wait_for_count 'native cover video: live shared-texture frame presented' 2 30
cover_events=$(events_for_pid)
printf '%s\n' "$cover_events" | grep -Fq \
    'native cover video: scene graph shares persistent video texture true'
first_cover_serial=$(printf '%s\n' "$cover_events" \
    | grep -F 'native cover video: live shared-texture frame presented' \
    | head -1 | sed -n 's/.* serial \([0-9][0-9]*\) .*/\1/p')
last_cover_serial=$(printf '%s\n' "$cover_events" \
    | grep -F 'native cover video: live shared-texture frame presented' \
    | tail -1 | sed -n 's/.* serial \([0-9][0-9]*\) .*/\1/p')
test -n "$first_cover_serial" && test "$last_cover_serial" -gt "$first_cover_serial"
test -z "$(printf '%s\n' "$cover_events" | grep -F \
    'native transport: pause requested true' || true)"
phase=cover-audit
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$cover_starttime"
test "$(events_for_pid | grep -Fc 'native player: load command submitted' || true)" -eq 1
test "$(events_for_pid | grep -Fc 'native cover: active layout ready' || true)" -le 4
test -z "$(events_for_pid | grep -F 'native hardware video: in-place seek requested' || true)"

phase=pip-launch
launch_live pip
pip_pid=$pid
pip_starttime=$(awk '{print $22}' "/proc/$pid/stat")
phase=pip-background
/tmp/bonito-direct-touch swipe 540 2157 540 1257 500 25
wait_for_count 'native system PiP: shown over system interface' 1 30
wait_for_count 'native system PiP: live shared-texture frame presented' 2 30
wait_for_count 'native system PiP: frame swap window' 2 25
pip_events=$(events_for_pid)
shown=$(printf '%s\n' "$pip_events" | grep -F \
    'native system PiP: shown over system interface' | tail -1)
printf '%s\n' "$shown" | grep -Fq 'mediaKind "live"'
set -- $(printf '%s\n' "$shown" \
    | sed -n 's/.*content QRect(\([0-9][0-9]*\),\([0-9][0-9]*\) \([0-9][0-9]*\)x\([0-9][0-9]*\)).*/\1 \2 \3 \4/p')
test "$#" -eq 4
pip_x=$1; pip_y=$2; pip_width=$3; pip_height=$4
test -z "$(printf '%s\n' "$pip_events" | grep -F \
    'native system PiP: frame swap window' | tail -2 | grep -F 'below45 true' || true)"
test -z "$(printf '%s\n' "$pip_events" | grep -F \
    'native transport: pause requested true' || true)"
phase=pip-restore
/tmp/bonito-direct-touch tap "$((pip_x + pip_width / 2))" \
    "$((pip_y + pip_height / 2))"
wait_for_count 'native system PiP: foreground restore requested' 1 20
wait_foreground
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$pip_starttime"
test "$(events_for_pid | grep -Fc 'native player: load command submitted' || true)" -eq 1
test "$(events_for_pid | grep -Fc 'native cover: active layout ready' || true)" -le 4
test -z "$(events_for_pid | grep -F 'native hardware video: in-place seek requested' || true)"

phase=final-audit
all_events=$(printf '%s\n%s\n' "$cover_events" "$pip_events")
test -z "$(printf '%s\n' "$all_events" | grep -E \
    'native hardware video: (direct pipeline failed|switching to software fallback|external texture shader failed|EGLImage creation failed|GPU fence backlog)|overlay QML error|QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' || true)"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
stop_application
set_mode cover
mcetool --set-never-blank=disabled >/dev/null
phase=complete
trap - EXIT
printf 'native_live_background=ready|package=%s|room=%s|idle_logo=144x56|watermarks=40|active_layout=resolution-video-title-progress-actions|cover_distribution=balanced|cover_actions=3|cover_pid=%s|cover_first_serial=%s|cover_last_serial=%s|cover_media_loads=1|cover_seek_recovery=0|pip_pid=%s|pip_media_loads=1|pip_seek_recovery=0|pip_media_kind=live|same_decoder=1|background_pause=0|fallback=0|rpm_verify=clean|mode_restored=cover|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$room_id" "$cover_pid" "$first_cover_serial" \
    "$last_cover_serial" "$pip_pid" "$expected_sha"
