#!/bin/sh
set -eu

# Install the exact candidate, open one currently live room directly, switch
# once to another advertised quality when the room exposes more than one,
# exercise pause/resume through physical touch and require 60 seconds of
# advancing hardware frames. Assertions use logs, process state and RPM
# identity only; no screenshot or visual model.

rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.45.aarch64.rpm}
expected_sha=${2:-3ad7163a959f79a30de49cd6c3b5eb3205c6b402a6cd98ac690d940d7fa604f6}
expected_package=silisili-native-devel-1.1.0-1.45.aarch64
test_room_id=${SILISILI_LIVE_TEST_ROOM_ID:-23276452}
minimum_cma_free_kb=${SILISILI_LIVE_MINIMUM_CMA_FREE_KB:-32768}
phase=preflight
test_pid=
production_pid=

events_for_pid() {
    journalctl -b "_PID=$1" --no-pager -o cat 2>/dev/null || true
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

last_hardware_serial() {
    awk '
        /native hardware video: shared-texture frame checkpoint/ {
            for (i = 1; i <= NF; ++i)
                if ($i == "serial") value = $(i + 1) + 0
        }
        END { print value + 0 }
    '
}

cleanup() {
    result=$?
    set +e
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_live_playback=failed|phase=%s|room=%s|test_pid=%s|production_pid=%s|visual_model=unused\n' \
            "$phase" "${test_room_id:-none}" "${test_pid:-none}" \
            "${production_pid:-none}"
        test -z "${test_pid:-}" || events_for_pid "$test_pid" | grep -E \
            'native (live|hardware video|player|software video)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -360 || true
        if test "$phase" != preflight; then
            stop_application
            rm -f /tmp/silisili-native-defaultuser.lock
            launch_application \
                >/tmp/silisili-native-production-after-live-gate.log 2>&1
            production_pid=$(wait_for_single_process || true)
            printf 'native_live_cleanup=ready|production_pid=%s\n' \
                "${production_pid:-none}"
        fi
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

test -n "$test_room_id"
test -x /tmp/bonito-direct-touch
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

phase=launch-live
rm -f /tmp/silisili-native-defaultuser.lock
# Full-source presentation is meaningful in the video's landscape orientation.
# A forced portrait surface can only fit 1920x1080 into a 1080x608 viewport.
launch_application \
    SILISILI_NATIVE_FORCE_ORIENTATION=landscape \
    SILISILI_NATIVE_TEST_PAGE=live-player \
    SILISILI_NATIVE_TEST_CONTENT_MODE=quality-cycle \
    SILISILI_NATIVE_TEST_ROOM_ID="$test_room_id" \
    >/tmp/silisili-native-live-playback.log 2>&1
test_pid=$(wait_for_single_process)
test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")

phase=wait-quality-cycle
poll=0
while test "$poll" -lt 320; do
    events=$(events_for_pid "$test_pid")
    if printf '%s\n' "$events" | grep -F \
        'native live quality: cycle ready' >/dev/null; then
        quality_cycle=1
        break
    fi
    if printf '%s\n' "$events" | grep -E \
        'native live: source resolved, quality [0-9]+ .* choices 1' >/dev/null \
        && printf '%s\n' "$events" | grep -E \
        'native (hardware video: first shared-texture frame rendered|player: first persistent shared-texture frame rendered)' >/dev/null; then
        quality_cycle=0
        break
    fi
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 320
test -e "/proc/$test_pid/stat"
test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"

events=$(events_for_pid "$test_pid")
expected_media_loads=$((quality_cycle + 1))
test "$(printf '%s\n' "$events" | grep -c \
    'native live: source resolved, quality' || true)" -ge "$expected_media_loads"
printf '%s\n' "$events" | grep -E \
    'native live: source request started .*requestedQuality 0 wireQuality 10000 automaticOriginal true capabilityAwareCodecSelection true' \
    >/dev/null
printf '%s\n' "$events" | grep -E \
    'native live: source resolved, quality [0-9]+ .*requestedQuality 0 wireQuality 10000 automaticOriginal true .*protocol ".+" format ".+" codec "(avc|hevc)" hardwareCapable (true|false)' \
    >/dev/null
test "$(printf '%s\n' "$events" | grep -c \
    'native player: load command submitted' || true)" -ge "$expected_media_loads"
test "$(printf '%s\n' "$events" | grep -c \
    'native hardware video: direct pipeline requested .*streamingTimeline true' || true)" -ge "$expected_media_loads"
test "$(printf '%s\n' "$events" | grep -c \
    'native hardware video: streaming timestamp origin normalized' || true)" -ge "$expected_media_loads"
test "$(printf '%s\n' "$events" | grep -E -c \
    'native (hardware video: first shared-texture frame rendered|player: first persistent shared-texture frame rendered)' || true)" -ge "$expected_media_loads"
printf '%s\n' "$events" | grep -E \
    'native player: scene graph shares persistent video texture true' \
    >/dev/null
printf '%s\n' "$events" | grep -E \
    'native hardware video: OMX decoder started .*timestampMode streaming-normalized .*binderCallbackBlocking false' \
    >/dev/null
test "$(printf '%s\n' "$events" | grep -c \
    'native live quality: actual stream ready qn' || true)" \
    -ge "$expected_media_loads"
printf '%s\n' "$events" | grep -E \
    'native live quality: actual stream ready qn [0-9]+ label .* · [0-9]+×[0-9]+ · [0-9.]+fps geometry [0-9]+ x [0-9]+ sourceFps [0-9.]+ presentation [0-9]+ x [0-9]+ videoViewport [0-9]+ x [0-9]+ profile fullscreen-native sourcePixelsPreserved true' \
    >/dev/null
test "$(printf '%s\n' "$events" | grep -c \
    'native live quality: actual stream ready .* sourcePixelsPreserved true' || true)" \
    -ge "$expected_media_loads"
if test "$quality_cycle" -eq 1; then
    printf '%s\n' "$events" | grep -E \
        'native live quality: cycle requested from [0-9]+ to [0-9]+' >/dev/null
    printf '%s\n' "$events" | grep -E \
        'native live quality: cycle ready quality [0-9]+ loadSerial 2 frameSerial 1' \
        >/dev/null
    printf '%s\n' "$events" | grep -E \
        'native live: quality switch requested .* presentationAspectRetained 1\.777' \
        >/dev/null
    test -z "$(printf '%s\n' "$events" | grep -F \
        'native layout: page live-player orientation portrait' || true)"
    printf '%s\n' "$events" | grep -F \
        'native layout: page live-player orientation landscape' >/dev/null
    printf 'live_quality_cycle=ready|mode=advertised-multiple|media_loads=%s\n' \
        "$expected_media_loads"
else
    printf '%s\n' "$events" | grep -E \
        'native live: source resolved, quality [0-9]+ .* choices 1' >/dev/null
    printf 'live_quality_cycle=not-applicable|reason=one-advertised-quality|media_loads=%s\n' \
        "$expected_media_loads"
fi
test -z "$(printf '%s\n' "$events" | grep -E \
    'native hardware video: (first-frame watchdog expired|switching to software fallback)' || true)"

phase=physical-pause
pause_count_before=$(printf '%s\n' "$events" | grep -c \
    'native live transport: pause requested true actual true' || true)
attempt=0
while test "$attempt" -lt 3; do
    /tmp/bonito-direct-touch tap 540 1080
    sleep 0.4
    events=$(events_for_pid "$test_pid")
    pause_count_after=$(printf '%s\n' "$events" | grep -c \
        'native live transport: pause requested true actual true' || true)
    test "$pause_count_after" -gt "$pause_count_before" && break
    attempt=$((attempt + 1))
done
test "$pause_count_after" -gt "$pause_count_before"

phase=physical-resume
resume_count_before=$(printf '%s\n' "$events" | grep -c \
    'native live transport: pause requested false actual false' || true)
attempt=0
while test "$attempt" -lt 3; do
    /tmp/bonito-direct-touch tap 540 1080
    sleep 0.4
    events=$(events_for_pid "$test_pid")
    resume_count_after=$(printf '%s\n' "$events" | grep -c \
        'native live transport: pause requested false actual false' || true)
    test "$resume_count_after" -gt "$resume_count_before" && break
    attempt=$((attempt + 1))
done
test "$resume_count_after" -gt "$resume_count_before"
printf 'live_controls=ready|pause=physical-touch|resume=physical-touch|same_pid=1\n'

phase=wait-cadence
poll=0
while test "$poll" -lt 160; do
    events=$(events_for_pid "$test_pid")
    baseline_serial=$(printf '%s\n' "$events" | last_hardware_serial)
    test "$baseline_serial" -ge 61 && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$baseline_serial" -ge 61

phase=hold-60s
sample=0
previous_serial=$baseline_serial
while test "$sample" -lt 12; do
    sleep 5
    test -e "/proc/$test_pid/stat"
    test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"
    process_state=$(awk '{print $3}' "/proc/$test_pid/stat")
    test "$process_state" != D
    cma_free_kb=$(awk '/^CmaFree:/ { print $2 }' /proc/meminfo)
    test "$cma_free_kb" -ge "$minimum_cma_free_kb"
    events=$(events_for_pid "$test_pid")
    frame_serial=$(printf '%s\n' "$events" | last_hardware_serial)
    test "$frame_serial" -gt "$previous_serial"
    previous_serial=$frame_serial
    printf 'live_sample=%s|pid=%s|state=%s|frame_serial=%s|cma_free_kb=%s\n' \
        "$((sample + 1))" "$test_pid" "$process_state" "$frame_serial" "$cma_free_kb"
    sample=$((sample + 1))
done

events=$(events_for_pid "$test_pid")
set -- $(printf '%s\n' "$events" | awk '
    /native (hardware video: first shared-texture frame rendered|player: first persistent shared-texture frame rendered)/ {
        first = 0; first_serial = 0; last_elapsed = 0; last_serial = 0
    }
    /native hardware video: shared-texture frame checkpoint/ {
        serial = 0; elapsed = 0
        for (i = 1; i <= NF; ++i) {
            if ($i == "serial") serial = $(i + 1) + 0
            if ($i == "elapsedMs") elapsed = $(i + 1) + 0
        }
        if (serial == 61 && first == 0) { first = elapsed; first_serial = serial }
        if (elapsed >= last_elapsed) { last_elapsed = elapsed; last_serial = serial }
    }
    END { print first_serial + 0, first + 0, last_serial + 0, last_elapsed + 0 }
')
first_serial=$1
first_elapsed_ms=$2
last_serial=$3
last_elapsed_ms=$4
test "$first_serial" -eq 61
test "$last_serial" -gt "$first_serial"
test "$last_elapsed_ms" -gt "$first_elapsed_ms"
unique_fps=$(awk -v frames="$((last_serial - first_serial))" \
    -v elapsed="$((last_elapsed_ms - first_elapsed_ms))" \
    'BEGIN { printf "%.2f", frames * 1000.0 / elapsed }')
awk -v fps="$unique_fps" 'BEGIN { exit !(fps >= 22.0) }'
test -z "$(printf '%s\n' "$events" | grep -E \
    'native hardware video: (first-frame watchdog expired|switching to software fallback|playback frame stall detected|decoded frame queue pressure)|QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND|Out of memory|Killed process' || true)"

phase=production-restore
stop_application
rm -f /tmp/silisili-native-defaultuser.lock
launch_application >/tmp/silisili-native-production-after-live-gate.log 2>&1
production_pid=$(wait_for_single_process)
poll=0
while test "$poll" -lt 80; do
    grep -Fq '/usr/bin/silisili-native' "/proc/$production_pid/maps" \
        2>/dev/null && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 80
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

trap - EXIT
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
printf 'native_live_playback=ready|package=%s|room=%s|quality_cycle=%s|media_loads=%s|initial_wire_quality=10000|actual_stream_verified=1|presentation=source-pixels-preserved|streaming_timeline=normalized|hardware_fallback=0|controls=physical-pause-resume|hold_seconds=60|first_serial=%s|last_serial=%s|unique_fps=%s|minimum_cma_free_kb=%s|production_pid=%s|rpm_verify=clean|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$test_room_id" "$quality_cycle" "$expected_media_loads" \
    "$first_serial" "$last_serial" \
    "$unique_fps" "$minimum_cma_free_kb" "$production_pid" "$expected_sha"
