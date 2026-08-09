#!/bin/sh
set -eu

# Deterministically suppress hardware-frame publication after 60 frames while
# the separate libmpv audio clock continues. The production watchdog must
# restart only the same-quality droidmedia video decoder, retain the existing
# shared texture and media-load serial, and resume advancing frames without a
# quality change, audio reload, screenshot or visual-model assertion.

rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.24.aarch64.rpm}
expected_sha=${2:-7c8cf3bf3ba0df5b45388a467add9689f50345bcc25f90413eb56fb4689de5a6}
expected_package=silisili-native-devel-1.1.0-1.24.aarch64
test_bvid=${SILISILI_STALL_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_STALL_TEST_CID:-37630051884}
phase=preflight
test_pid=
production_pid=

events_for_pid() {
    journalctl -b "_PID=$1" --no-pager -o cat 2>/dev/null || true
}

application_pids() {
    for process in /proc/[0-9]*; do
        executable=$(readlink "$process/exe" 2>/dev/null || true)
        case "$executable" in
            /usr/bin/silisili-native|"/usr/bin/silisili-native (deleted)")
                basename "$process"
                ;;
        esac
    done
}

stop_application() {
    for process_id in $(application_pids); do
        kill -TERM "$process_id" 2>/dev/null || true
    done
    killall -TERM silisili-native 2>/dev/null || true
    sleep 1
    for process_id in $(application_pids); do
        kill -KILL "$process_id" 2>/dev/null || true
    done
    killall -KILL silisili-native 2>/dev/null || true
    sleep 3
}

launch_application() {
    runuser -u defaultuser -- env \
        HOME=/home/defaultuser \
        XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        WAYLAND_DISPLAY=../../display/wayland-0 \
        QT_QPA_PLATFORM=wayland \
        "$@" \
        /usr/bin/invoker --verbose --verbose --no-wait --type=generic \
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

binder_count() {
    dmesg 2>/dev/null | grep -c \
        "binder: $1 has pending async transaction" || true
}

cleanup() {
    result=$?
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_frame_stall_recovery=failed|phase=%s|test_pid=%s|production_pid=%s|visual_model=unused\n' \
            "$phase" "${test_pid:-none}" "${production_pid:-none}"
        test -z "${test_pid:-}" || events_for_pid "$test_pid" | grep -E \
            'native (hardware video|player|detail perf)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -260 || true
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

phase=launch-injected-playback
rm -f /tmp/silisili-native-defaultuser.lock
launch_application \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=history-resume \
    SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=80 \
    SILISILI_NATIVE_TEST_START_POSITION=14 \
    SILISILI_NATIVE_TEST_HARDWARE_STALL_ONCE=1 \
    >/tmp/silisili-native-frame-stall-launch.log 2>&1
test_pid=$(wait_for_single_process)
test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")
binder_before=$(binder_count "$test_pid")

phase=wait-recovery
poll=0
while test "$poll" -lt 480; do
    events=$(events_for_pid "$test_pid")
    restart_line=$(printf '%s\n' "$events" | awk \
        '/same-quality decoder restart completed/ { line = $0 } END { print line }')
    case "$restart_line" in
        *"audioReload false"*"textureRetained true"*) break ;;
    esac
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 480
test -e "/proc/$test_pid/stat"
test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"

events=$(events_for_pid "$test_pid")
injected_generation=$(printf '%s\n' "$events" | awk '
    /deterministic frame stall injected/ {
        for (i = 1; i <= NF; ++i) if ($i == "generation") print $(i + 1) + 0
        exit
    }
')
restart_generations=$(printf '%s\n' "$events" | awk '
    /same-quality decoder restart completed/ {
        previous = 0; current = 0
        for (i = 1; i <= NF; ++i) {
            if ($i == "previousGeneration") previous = $(i + 1) + 0
            if ($i == "generation") current = $(i + 1) + 0
        }
        print previous "|" current
        exit
    }
')
previous_generation=${restart_generations%%|*}
recovered_generation=${restart_generations#*|}
test "$injected_generation" -eq "$previous_generation"
test "$recovered_generation" -gt "$previous_generation"
test "$(printf '%s\n' "$events" | grep -c \
    'native player: load command submitted' || true)" -eq 1

phase=wait-recovered-decoder
poll=0
while test "$poll" -lt 160; do
    events=$(events_for_pid "$test_pid")
    printf '%s\n' "$events" | grep -E \
        "native hardware video: OMX decoder started generation $recovered_generation .*binderCallbackBlocking false" \
        >/dev/null && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 160
printf '%s\n' "$events" | grep -E \
    "native hardware video: OMX decoder started generation $recovered_generation .*binderCallbackBlocking false" \
    >/dev/null
test -z "$(printf '%s\n' "$events" | grep -F \
    'native hardware video: switching to software fallback' || true)"

phase=wait-post-recovery-frames
poll=0
while test "$poll" -lt 160; do
    events=$(events_for_pid "$test_pid")
    post_recovery_serial=$(printf '%s\n' "$events" | awk \
        -v generation="$recovered_generation" '
        /shared-texture frame checkpoint/ {
            serial = 0
            for (i = 1; i <= NF; ++i) if ($i == "serial") serial = $(i + 1) + 0
            if (serial > last) last = serial
        }
        END { print last + 0 }
    ')
    test "$post_recovery_serial" -ge 121 && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$post_recovery_serial" -ge 121

# Check decoded-source cadence, not the 60 Hz scene-graph repetition timer.
# Serial 61 is the first logged checkpoint after the injected generation was
# replaced; serial 121 is exactly 60 newly published hardware frames later.
set -- $(printf '%s\n' "$events" | awk '
    /native hardware video: shared-texture frame checkpoint/ {
        serial = 0; elapsed = 0
        for (i = 1; i <= NF; ++i) {
            if ($i == "serial") serial = $(i + 1) + 0
            if ($i == "elapsedMs") elapsed = $(i + 1) + 0
        }
        if (serial == 61 && first == 0) first = elapsed
        if (serial == 121 && second == 0) second = elapsed
    }
    END { print first + 0, second + 0 }
')
recovery_first_elapsed_ms=$1
recovery_second_elapsed_ms=$2
test "$recovery_first_elapsed_ms" -gt 0
test "$recovery_second_elapsed_ms" -gt "$recovery_first_elapsed_ms"
recovery_unique_fps=$(awk -v first="$recovery_first_elapsed_ms" \
    -v second="$recovery_second_elapsed_ms" 'BEGIN {
        printf "%.2f", 60000.0 / (second - first)
    }')
awk -v fps="$recovery_unique_fps" 'BEGIN { exit !(fps >= 22.0) }'
test "$(awk '{print $3}' "/proc/$test_pid/stat")" != D
cma_free_kb=$(awk '/^CmaFree:/ { print $2 }' /proc/meminfo)
test "$cma_free_kb" -ge 32768
binder_after=$(binder_count "$test_pid")
binder_delta=$((binder_after - binder_before))

phase=production-relaunch
stop_application
rm -f /tmp/silisili-native-defaultuser.lock
launch_application >/tmp/silisili-native-production-launch.log 2>&1
production_pid=$(wait_for_single_process)
poll=0
while test "$poll" -lt 80; do
    production_events=$(events_for_pid "$production_pid")
    printf '%s\n' "$production_events" | grep -F \
        'native app: build identity "silisili-native-devel" "1.1.0" "1.24"' \
        >/dev/null && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 80
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

phase=complete
printf 'native_frame_stall_recovery=ready|package=%s|test_pid=%s|same_pid=1|injected_generation=%s|recovered_generation=%s|audio_reload=0|media_loads=1|texture_retained=1|post_recovery_serial=%s|recovery_unique_fps=%s|binder_delta=%s|cma_free_kb=%s|production_pid=%s|rpm_verify=clean|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$test_pid" "$injected_generation" \
    "$recovered_generation" "$post_recovery_serial" "$recovery_unique_fps" "$binder_delta" \
    "$cma_free_kb" "$production_pid" "$expected_sha"
