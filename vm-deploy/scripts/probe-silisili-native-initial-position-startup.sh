#!/bin/sh
set -eu

# Repeatedly open a real DASH video from a non-zero history position. Audio
# must remain held until the new file confirms that target, the already-ready
# hardware texture must not trigger software fallback, and the first visible
# frame must arrive from the single original media load.

rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.35.aarch64.rpm}
expected_sha=${2:-cec6e5d8705068c10f3e14e1f6e026797b0b7734e8d6a21ef35508227cb28d3e}
expected_package=silisili-native-devel-1.1.0-1.35.aarch64
test_bvid=${SILISILI_STARTUP_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_STARTUP_TEST_CID:-37630051884}
test_trials=${SILISILI_STARTUP_TEST_TRIALS:-3}
phase=preflight
test_pid=
production_pid=
maximum_media_startup_ms=0
maximum_request_startup_ms=0

events_for_pid() {
    journalctl -b "_PID=$1" --no-pager -o cat 2>/dev/null || true
}

monotonic_events_for_pid() {
    journalctl -b "_PID=$1" --no-pager -o short-monotonic 2>/dev/null || true
}

application_pids() {
    for process in /proc/[0-9]*; do
        command=$(tr '\000' ' ' <"$process/cmdline" 2>/dev/null || true)
        case "$command" in
            /usr/bin/silisili-native*)
                basename "$process"
                ;;
        esac
    done
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
}

launch_application() {
    runuser -u defaultuser -- env \
        HOME=/home/defaultuser \
        XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        WAYLAND_DISPLAY=../../display/wayland-0 \
        QT_QPA_PLATFORM=wayland \
        "$@" \
        /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
            --id=cn.silisili.native --single-instance \
            /usr/bin/silisili-native
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

event_time() {
    pattern=$1
    awk -v pattern="$pattern" '
        index($0, pattern) {
            value = $1
            gsub(/^\[/, "", value)
            gsub(/\]$/, "", value)
            print value
            exit
        }
    '
}

cleanup() {
    result=$?
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    stop_application
    rm -f /tmp/silisili-native-defaultuser.lock
    launch_application >/tmp/silisili-native-production-after-startup-gate.log 2>&1 || true
    production_pid=$(wait_for_single_process || true)
    if test "$result" -ne 0; then
        printf 'native_initial_position_startup=failed|phase=%s|test_pid=%s|production_pid=%s|visual_model=unused\n' \
            "$phase" "${test_pid:-none}" "${production_pid:-none}"
        test -z "${test_pid:-}" || events_for_pid "$test_pid" | grep -E \
            'native (history resume|hardware video|player|software video|detail perf)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -300 || true
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

mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --set-never-blank=enabled >/dev/null

trial=1
while test "$trial" -le "$test_trials"; do
    phase="trial-$trial-launch"
    stop_application
    rm -f /tmp/silisili-native-defaultuser.lock
    launch_application \
        SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
        SILISILI_NATIVE_TEST_PAGE=history-resume \
        SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
        SILISILI_NATIVE_TEST_BVID="$test_bvid" \
        SILISILI_NATIVE_TEST_CID="$test_cid" \
        SILISILI_NATIVE_TEST_QUALITY=80 \
        SILISILI_NATIVE_TEST_START_POSITION=14 \
        >/tmp/silisili-native-initial-position-startup-"$trial".log 2>&1
    test_pid=$(wait_for_single_process)
    test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")

    phase="trial-$trial-wait-first-frame"
    poll=0
    while test "$poll" -lt 240; do
        events=$(events_for_pid "$test_pid")
        printf '%s\n' "$events" | grep -F \
            'native software video: first frame ready' >/dev/null && break
        sleep 0.25
        poll=$((poll + 1))
    done
    test "$poll" -lt 240
    test -e "/proc/$test_pid/stat"
    test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"

    events=$(events_for_pid "$test_pid")
    test "$(printf '%s\n' "$events" | grep -c \
        'native player: load command submitted' || true)" -eq 1
    printf '%s\n' "$events" | grep -E \
        'native player: load command submitted .* at 14 .*startOption true audioStartGated true' \
        >/dev/null
    printf '%s\n' "$events" | grep -E \
        'native hardware video: first decoded texture ready .*published (true|false) initialPositionGate true' \
        >/dev/null
    printf '%s\n' "$events" | grep -E \
        'native player: initial position gate released target 14 actual 14(\.0+)? audioReleased true audioFromConfirmedTarget true firstVideoFrameReady true' \
        >/dev/null
    printf '%s\n' "$events" | grep -E \
        'native software video: first frame ready .*position 14(\.0+)? .*loadingCoverWithdrawn true' \
        >/dev/null
    test -z "$(printf '%s\n' "$events" | grep -E \
        'native hardware video: (first-frame watchdog expired|switching to software fallback)' || true)"

    monotonic_events=$(monotonic_events_for_pid "$test_pid")
    load_time=$(printf '%s\n' "$monotonic_events" | event_time \
        'native player: load command submitted')
    first_frame_time=$(printf '%s\n' "$monotonic_events" | event_time \
        'native software video: first frame ready')
    test -n "$load_time" && test -n "$first_frame_time"
    media_startup_ms=$(awk -v start="$load_time" -v finish="$first_frame_time" \
        'BEGIN { printf "%d", (finish - start) * 1000.0 + 0.5 }')
    test "$media_startup_ms" -gt 0
    test "$media_startup_ms" -le 2500
    request_startup_ms=$(printf '%s\n' "$events" | awk '
        /native software video: first frame ready/ {
            for (i = 1; i <= NF; ++i)
                if ($i == "requestElapsedMs") { print $(i + 1) + 0; exit }
        }
    ')
    test -n "$request_startup_ms"
    if test "$media_startup_ms" -gt "$maximum_media_startup_ms"; then
        maximum_media_startup_ms=$media_startup_ms
    fi
    if test "$request_startup_ms" -gt "$maximum_request_startup_ms"; then
        maximum_request_startup_ms=$request_startup_ms
    fi
    printf 'initial_position_trial=ready|trial=%s|pid=%s|loads=1|target=14|audio_gate=confirmed|hardware_fallback=0|media_startup_ms=%s|request_startup_ms=%s|visual_model=unused\n' \
        "$trial" "$test_pid" "$media_startup_ms" "$request_startup_ms"
    trial=$((trial + 1))
done

phase=production-restore
stop_application
rm -f /tmp/silisili-native-defaultuser.lock
launch_application >/tmp/silisili-native-production-after-startup-gate.log 2>&1
production_pid=$(wait_for_single_process)
test -n "$production_pid"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

trap - EXIT
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
printf 'native_initial_position_startup=ready|package=%s|trials=%s|target=14|single_load=1|audio_before_target=0|hardware_fallback=0|max_media_startup_ms=%s|max_request_startup_ms=%s|production_pid=%s|rpm_verify=clean|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$test_trials" "$maximum_media_startup_ms" \
    "$maximum_request_startup_ms" "$production_pid" "$expected_sha"
