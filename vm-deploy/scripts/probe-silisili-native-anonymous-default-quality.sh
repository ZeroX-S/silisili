#!/bin/sh
set -eu

# Launch one direct VOD regression with an isolated, credential-free HOME.
# The production account files are never copied, modified or removed.

expected_package=${SILISILI_ANONYMOUS_QUALITY_EXPECTED_PACKAGE:-silisili-native-devel-1.1.0-1.57.aarch64}
test_bvid=${SILISILI_ANONYMOUS_QUALITY_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_ANONYMOUS_QUALITY_CID:-37630051884}
run_id=${1:-anonymous-quality-$(date -u +%Y%m%dT%H%M%SZ)}
case "$run_id" in
    *[!A-Za-z0-9._-]*)
        printf 'sailfish_test=blocked|run=invalid|reason=unsafe-run-id\n' >&2
        exit 64
        ;;
esac

phase=preflight
test_pid=
anonymous_home="/tmp/silisili-anonymous-$run_id"
launcher_log="/tmp/silisili-anonymous-$run_id-launch.log"

events_for_pid() {
    journalctl -b "_PID=$1" --no-pager -o cat 2>/dev/null || true
}

application_pids() {
    pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true
}

stop_application() {
    for process_id in $(application_pids); do
        kill -TERM "$process_id" 2>/dev/null || true
    done
    wait_count=0
    while test "$wait_count" -lt 20 && test -n "$(application_pids)"; do
        sleep 0.25
        wait_count=$((wait_count + 1))
    done
    for process_id in $(application_pids); do
        kill -KILL "$process_id" 2>/dev/null || true
    done
}

wait_for_single_process() {
    attempts=0
    while test "$attempts" -lt 80; do
        set -- $(application_pids)
        if test "$#" -eq 1; then
            printf '%s\n' "$1"
            return 0
        fi
        sleep 0.25
        attempts=$((attempts + 1))
    done
    return 1
}

cleanup() {
    result=$?
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    stop_application
    rm -rf "$anonymous_home"
    rm -f "$launcher_log" /tmp/silisili-native-defaultuser.lock
    if test "$result" -ne 0; then
        printf 'sailfish_test=failed|run=%s|reason=%s|evidence=journal-pid-%s\n' \
            "$run_id" "$phase" "${test_pid:-none}"
        if test -n "${test_pid:-}"; then
            events_for_pid "$test_pid" | grep -E \
                'native (playback quality|player|hardware video|software video)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
                | tail -240 || true
        fi
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)" = "$expected_package"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

phase=anonymous-home
stop_application
rm -rf "$anonymous_home"
install -d -m0700 -o defaultuser -g users "$anonymous_home"
install -d -m0700 -o defaultuser -g users \
    "$anonymous_home/.config" "$anonymous_home/.cache"
test ! -e "$anonymous_home/.config/cn.silisili.native/account_session.json"

mcetool --unblank-screen >/dev/null 2>&1 || true
mcetool --set-tklock-mode=unlocked >/dev/null 2>&1 || true
mcetool --set-never-blank=enabled >/dev/null 2>&1 || true

phase=launch
rm -f /tmp/silisili-native-defaultuser.lock
runuser -u defaultuser -- env \
    HOME="$anonymous_home" \
    XDG_CONFIG_HOME="$anonymous_home/.config" \
    XDG_CACHE_HOME="$anonymous_home/.cache" \
    XDG_RUNTIME_DIR=/run/user/100000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
    WAYLAND_DISPLAY=../../display/wayland-0 \
    QT_QPA_PLATFORM=wayland \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=video-detail \
    SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
        --id=cn.silisili.native --single-instance \
        /usr/bin/silisili-native >"$launcher_log" 2>&1
test_pid=$(wait_for_single_process)
test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")

phase=initial-policy
poll=0
while test "$poll" -lt 240; do
    events=$(events_for_pid "$test_pid")
    if printf '%s\n' "$events" | grep -E \
            'native playback quality: initial policy .*mediaKind video .*loggedIn false .*sessionCredentials false .*override 0 .*requestedQuality 64' \
            >/dev/null \
            && printf '%s\n' "$events" | grep -E \
            'native player: source resolved, quality 64' >/dev/null \
            && printf '%s\n' "$events" | grep -E \
            'native software video: (first-frame latch reconciled|first frame ready)' \
            >/dev/null; then
        break
    fi
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 240

phase=assertions
events=$(events_for_pid "$test_pid")
printf '%s\n' "$events" | grep -E \
    'native playback quality: initial policy .*mediaKind video .*loggedIn false .*sessionCredentials false .*override 0 .*requestedQuality 64' \
    >/dev/null
printf '%s\n' "$events" | grep -E \
    'native player: DASH response below 720P; retrying 720P progressive .*requested 64 .*bestDashQuality 32' \
    >/dev/null
printf '%s\n' "$events" | grep -E \
    'native player: source resolved, quality 64 .*segments 1' \
    >/dev/null
printf '%s\n' "$events" | grep -E \
    'native hardware video: stream ready .*geometry 1280 x 720' \
    >/dev/null
test "$(printf '%s\n' "$events" | grep -c \
    'native player: load command submitted' || true)" -eq 1
test "$(printf '%s\n' "$events" | grep -c \
    -E 'native software video: (first-frame latch reconciled|first frame ready)' || true)" -eq 1
test -z "$(printf '%s\n' "$events" | grep -E \
    'QML Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND|native hardware video: (first-frame watchdog expired|switching to software fallback)' \
    || true)"
test -e "/proc/$test_pid/stat"
test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"
test ! -e "$anonymous_home/.config/cn.silisili.native/account_session.json"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

phase=cleanup
trap - EXIT
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
stop_application
rm -rf "$anonymous_home"
rm -f "$launcher_log" /tmp/silisili-native-defaultuser.lock
printf 'sailfish_test=ready|run=%s|package=%s|pid=%s|checks=10/10\n' \
    "$run_id" "$expected_package" "$test_pid"
printf 'native_anonymous_default_quality=ready|run=%s|package=%s|bvid=%s|cid=%s|logged_in=0|session_credentials=0|requested_qn=64|selected_qn=64|video=1280x720|route=progressive-720p|loads=1|first_frames=1|same_pid=1|rpm_verify=clean|production_account=untouched|visual_model=unused\n' \
    "$run_id" "$expected_package" "$test_bvid" "$test_cid"
