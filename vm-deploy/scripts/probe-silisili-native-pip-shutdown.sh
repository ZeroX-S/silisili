#!/bin/sh
set -eu

# Enter the real Lipstick system-overlay path, then close the main QQuickView.
# The process must exit through the explicit shutdown barrier after hiding PiP,
# balancing DroidMedia references and destroying the persistent mpv/GL backend.

rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.45.aarch64.rpm}
expected_sha=${2:-3ad7163a959f79a30de49cd6c3b5eb3205c6b402a6cd98ac690d940d7fa604f6}
expected_package=silisili-native-devel-1.1.0-1.45.aarch64
configured_room_id=${SILISILI_LIVE_TEST_ROOM_ID:-}
room_id=${configured_room_id:-23276452}
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf
minimum_cma_free_kb=${SILISILI_PIP_SHUTDOWN_MINIMUM_CMA_FREE_KB:-16384}
phase=preflight
pid=

application_pids() { pgrep -f '^/usr/bin/silisili-native' || true; }
select_active_room() {
    requested=$1
    response="/tmp/silisili-native-pip-room-$$.json"
    feed="/tmp/silisili-native-pip-feed-$$.json"
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
events_for_pid() {
    test -n "$pid" || return 0
    journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true
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
wait_for_marker() {
    marker=$1; limit=$2; attempt=0
    while test "$attempt" -lt "$limit"; do
        events_for_pid | grep -Fq "$marker" && return 0
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}
cleanup() {
    result=$?
    set_mode cover 2>/dev/null || true
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_pip_shutdown=failed|phase=%s|pid=%s|visual_model=unused\n' \
            "$phase" "${pid:-none}"
        test -z "${pid:-}" || events_for_pid | grep -E \
            'native (application shutdown|system PiP|playback session|hardware video|player)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -420 || true
        stop_application
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
phase=install
stop_application
rpm -Uvh --replacepkgs "$rpm_path"
test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)" = "$expected_package"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
test -x /tmp/bonito-direct-touch
test -f "$settings"
room_id=$(select_active_room "$room_id")
printf 'native_live_room_selection=ready|requested=%s|selected=%s|fallback=%s\n' \
    "${configured_room_id:-23276452}" "$room_id" \
    "$(test "$room_id" = "${configured_room_id:-23276452}" && printf false || printf true)"
set_mode pip
mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --set-never-blank=enabled >/dev/null

phase=launch
runuser -u defaultuser -- env \
    HOME=/home/defaultuser \
    XDG_RUNTIME_DIR=/run/user/100000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
    WAYLAND_DISPLAY=../../display/wayland-0 \
    QT_QPA_PLATFORM=wayland \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=live-player \
    SILISILI_NATIVE_TEST_ROOM_ID="$room_id" \
    SILISILI_NATIVE_TEST_CLOSE_WHILE_PIP=1 \
    /usr/bin/invoker --type=silica-qt5 \
        --id=cn.silisili.native --single-instance \
        /usr/bin/silisili-native \
    >/tmp/silisili-native-pip-shutdown-launch.log 2>&1 &
attempt=0
while test "$attempt" -lt 30; do
    pid=$(application_pids | head -1)
    test -n "$pid" && break
    sleep 1
    attempt=$((attempt + 1))
done
test -n "$pid"
starttime=$(awk '{print $22}' "/proc/$pid/stat")
wait_for_marker 'native playback session: live source loaded' 35
wait_for_marker 'native hardware video: first shared-texture frame rendered' 45

phase=background-pip
/tmp/bonito-direct-touch swipe 3 1080 900 1080 500 25
wait_for_marker 'native system PiP: shown over system interface' 30
wait_for_marker 'native application shutdown test: close scheduled' 10

phase=graceful-close
attempt=0
while test "$attempt" -lt 30; do
    test ! -d "/proc/$pid" && break
    test "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true)" != "$starttime" && break
    sleep 1
    attempt=$((attempt + 1))
done
test "$attempt" -lt 30
test -z "$(application_pids)"
events=$(events_for_pid)
printf '%s\n' "$events" | grep -Fq \
    'native application shutdown: main window close received systemPiPVisible true'
printf '%s\n' "$events" | grep -Fq \
    'native application shutdown: system PiP released visible false'
printf '%s\n' "$events" | grep -Fq \
    'native application shutdown: playback resources released hardwareDecoder false mpvBackend false sharedTexture false'
printf '%s\n' "$events" | grep -Fq \
    'native application shutdown: barrier complete systemPiPVisible false playbackActive false'
printf '%s\n' "$events" | grep -Fq \
    'native player: persistent mpv instance destroyed'
decoder_generations=$(printf '%s\n' "$events" | grep -Fc \
    'native hardware video: OMX decoder started' || true)
balanced_generations=$(printf '%s\n' "$events" | grep -c \
    'native hardware video: created buffer references released.*balanced true' || true)
test "$decoder_generations" -ge 1
test "$balanced_generations" -eq "$decoder_generations"
test -z "$(printf '%s\n' "$events" | grep -E \
    'created buffer references released.*balanced false|native hardware video: (direct pipeline failed|switching to software fallback|GPU fence backlog)|overlay QML error|QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' || true)"
cma_free_kb=$(awk '/^CmaFree:/ {print $2}' /proc/meminfo)
test "${cma_free_kb:-0}" -ge "$minimum_cma_free_kb"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

set_mode cover
mcetool --set-never-blank=disabled >/dev/null
phase=complete
trap - EXIT
printf 'native_pip_shutdown=ready|package=%s|room=%s|pid=%s|decoder_generations=%s|buffer_generations_balanced=%s|processes_after=0|overlay_after=0|playback_after=0|cma_free_kb=%s|mode_restored=cover|rpm_verify=clean|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$room_id" "$pid" "$decoder_generations" \
    "$balanced_generations" "$cma_free_kb" "$expected_sha"
