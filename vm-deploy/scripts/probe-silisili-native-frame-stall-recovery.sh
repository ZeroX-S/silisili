#!/bin/sh
set -eu

# Enter the real full-screen 1080P+ path and deterministically suppress frame
# publication across several consecutive droidmedia generations while the
# separate libmpv audio clock continues. Every outgoing BufferQueue generation
# must balance the strong references granted by buffer_created(), preserve CMA
# headroom and resume the same shared texture without a media/audio reload.

rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.40.aarch64.rpm}
expected_sha=${2:-ad19d38a6aaf0a3c9cc86a9fbf12641f77a48f9bb3630a61f62ea713e86f3c64}
expected_package=silisili-native-devel-1.1.0-1.40.aarch64
test_bvid=${SILISILI_STALL_TEST_BVID:-BV17P386GEg9}
test_cid=${SILISILI_STALL_TEST_CID:-40445085531}
test_quality=${SILISILI_STALL_TEST_QUALITY:-116}
stall_count=${SILISILI_STALL_TEST_COUNT:-6}
minimum_cma_free_kb=${SILISILI_STALL_MINIMUM_CMA_FREE_KB:-16384}
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
test "$stall_count" -ge 1
test "$stall_count" -le 12
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
    SILISILI_NATIVE_FORCE_ORIENTATION=landscape \
    SILISILI_NATIVE_TEST_PAGE=history-resume \
    SILISILI_NATIVE_TEST_CONTENT_MODE=fullscreen \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY="$test_quality" \
    SILISILI_NATIVE_TEST_START_POSITION=14 \
    SILISILI_NATIVE_TEST_HARDWARE_STALL_COUNT="$stall_count" \
    >/tmp/silisili-native-frame-stall-launch.log 2>&1
test_pid=$(wait_for_single_process)
test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")
binder_before=$(binder_count "$test_pid")

phase=enter-fullscreen
poll=0
while test "$poll" -lt 160; do
    events=$(events_for_pid "$test_pid")
    printf '%s\n' "$events" | grep -F \
        'native player: deterministic fullscreen regression entry' >/dev/null \
        && printf '%s\n' "$events" | grep -F \
        'native player: fullscreen surface handoff completed' >/dev/null \
        && printf '%s\n' "$events" | grep -E \
        'native (hardware video: shared framebuffer geometry|player: video framebuffer geometry reset).*profile "?fullscreen-native"?' \
        >/dev/null && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 160

phase=wait-repeated-recovery
poll=0
while test "$poll" -lt 1200; do
    events=$(events_for_pid "$test_pid")
    restart_count=$(printf '%s\n' "$events" | grep -c \
        'same-quality decoder restart completed' || true)
    test "$restart_count" -ge "$stall_count" && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 1200
test -e "/proc/$test_pid/stat"
test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"

events=$(events_for_pid "$test_pid")
injection_count=$(printf '%s\n' "$events" | grep -c \
    'deterministic frame stall injected' || true)
restart_count=$(printf '%s\n' "$events" | grep -c \
    'same-quality decoder restart completed' || true)
test "$injection_count" -eq "$stall_count"
test "$restart_count" -eq "$stall_count"
first_injected_generation=$(printf '%s\n' "$events" | awk '
    /deterministic frame stall injected/ {
        for (i = 1; i <= NF; ++i) if ($i == "generation") print $(i + 1) + 0
        exit
    }
')
last_restart_generations=$(printf '%s\n' "$events" | awk '
    /same-quality decoder restart completed/ {
        previous = 0; current = 0
        for (i = 1; i <= NF; ++i) {
            if ($i == "previousGeneration") previous = $(i + 1) + 0
            if ($i == "generation") current = $(i + 1) + 0
        }
        result = previous "|" current
    }
    END { print result }
')
previous_generation=${last_restart_generations%%|*}
recovered_generation=${last_restart_generations#*|}
test "$first_injected_generation" -gt 0
test "$recovered_generation" -gt "$previous_generation"
test "$(printf '%s\n' "$events" | grep -c \
    'native player: load command submitted' || true)" -eq 1
test "$(printf '%s\n' "$events" | grep -c \
    'native hardware video: created buffer references released.*balanced true' || true)" \
    -ge "$stall_count"
test -z "$(printf '%s\n' "$events" | grep -E \
    'created buffer references released.*balanced false' || true)"

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
if test "$stall_count" -gt 1; then
    first_injection_serial=180
else
    first_injection_serial=60
fi
last_injection_serial=$((first_injection_serial + (stall_count - 1) * 30))
expected_post_recovery_serial=$((1 + 60 * ((last_injection_serial + 118) / 60)))
poll=0
post_recovery_serial=0
while test "$poll" -lt 480; do
    events=$(events_for_pid "$test_pid")
    post_recovery_serial=$(printf '%s\n' "$events" | awk '
        /native hardware video: shared-texture frame checkpoint/ {
            serial = 0
            for (i = 1; i <= NF; ++i)
                if ($i == "serial") serial = $(i + 1) + 0
            if (serial > last) last = serial
        }
        END { print last + 0 }
    ')
    test "$post_recovery_serial" -lt "$expected_post_recovery_serial" || break
    sleep 0.25
    poll=$((poll + 1))
done
phase=validate-post-recovery-serial
test "$post_recovery_serial" -ge "$expected_post_recovery_serial"

# Check two decoded-source checkpoints entirely after the final injected
# generation, not the 60 Hz scene-graph repetition timer.
set -- $(printf '%s\n' "$events" | awk '
    /native hardware video: shared-texture frame checkpoint/ {
        serial = 0; elapsed = 0
        for (i = 1; i <= NF; ++i) {
            if ($i == "serial") serial = $(i + 1) + 0
            if ($i == "elapsedMs") elapsed = $(i + 1) + 0
        }
        if (serial == expected - 60 && first == 0) first = elapsed
        if (serial == expected && second == 0) second = elapsed
    }
    END { print first + 0, second + 0 }
' expected="$expected_post_recovery_serial")
phase=validate-post-recovery-cadence
recovery_first_elapsed_ms=$1
recovery_second_elapsed_ms=$2
test "$recovery_first_elapsed_ms" -gt 0
test "$recovery_second_elapsed_ms" -gt "$recovery_first_elapsed_ms"
recovery_unique_fps=$(awk -v first="$recovery_first_elapsed_ms" \
    -v second="$recovery_second_elapsed_ms" 'BEGIN {
        printf "%.2f", 60000.0 / (second - first)
    }')
awk -v fps="$recovery_unique_fps" 'BEGIN { exit !(fps >= 22.0) }'
phase=validate-process-state
test "$(awk '{print $3}' "/proc/$test_pid/stat")" != D
phase=validate-cma-headroom
cma_free_kb=$(awk '/^CmaFree:/ { print $2 }' /proc/meminfo)
# The Pixel 3a XL settles around 25 MiB free while its bounded 1080p OMX
# buffers are active.  Keep a fail-closed exhaustion guard without rejecting
# that measured steady state.
test "$cma_free_kb" -ge "$minimum_cma_free_kb"
phase=validate-binder-state
binder_after=$(binder_count "$test_pid")
binder_delta=$((binder_after - binder_before))

phase=production-relaunch
stop_application
rm -f /tmp/silisili-native-defaultuser.lock
launch_application >/tmp/silisili-native-production-launch.log 2>&1
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

phase=complete
printf 'native_frame_stall_recovery=ready|package=%s|bvid=%s|cid=%s|quality=%s|fullscreen=1|test_pid=%s|same_pid=1|injections=%s|restarts=%s|first_generation=%s|recovered_generation=%s|buffer_refs_balanced=1|audio_reload=0|media_loads=1|texture_retained=1|post_recovery_serial=%s|recovery_unique_fps=%s|binder_delta=%s|cma_free_kb=%s|production_pid=%s|rpm_verify=clean|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$test_bvid" "$test_cid" "$test_quality" "$test_pid" \
    "$injection_count" "$restart_count" "$first_injected_generation" \
    "$recovered_generation" "$post_recovery_serial" "$recovery_unique_fps" "$binder_delta" \
    "$cma_free_kb" "$production_pid" "$expected_sha"
