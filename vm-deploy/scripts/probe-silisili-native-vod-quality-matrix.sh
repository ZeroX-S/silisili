#!/bin/sh
set -eu

# Exercise every safe VOD resolution advertised by one real video in ascending
# order. Each step must resolve exactly, present a new hardware frame in the
# same process, retain playback position and release the outgoing droidmedia
# BufferQueue references without exhausting CMA. 4K/8K requests are covered by
# probe-silisili-native-ultrahd-recovery.sh because this phone deliberately
# resolves those unsafe decoder allocations to its verified 1080P60 ceiling.

rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.40.aarch64.rpm}
expected_sha=${2:-ad19d38a6aaf0a3c9cc86a9fbf12641f77a48f9bb3630a61f62ea713e86f3c64}
expected_package=silisili-native-devel-1.1.0-1.40.aarch64
test_bvid=${SILISILI_QUALITY_TEST_BVID:-BV17P386GEg9}
test_cid=${SILISILI_QUALITY_TEST_CID:-40445085531}
minimum_cma_free_kb=${SILISILI_QUALITY_MINIMUM_CMA_FREE_KB:-16384}
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
            /usr/bin/silisili-native*) basename "$process" ;;
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

cleanup() {
    result=$?
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_vod_quality_matrix=failed|phase=%s|test_pid=%s|production_pid=%s|visual_model=unused\n' \
            "$phase" "${test_pid:-none}" "${production_pid:-none}"
        test -z "${test_pid:-}" || events_for_pid "$test_pid" | grep -E \
            'native (VOD quality matrix|player|hardware video|detail perf)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -320 || true
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

phase=launch-quality-matrix
rm -f /tmp/silisili-native-defaultuser.lock
launch_application \
    SILISILI_NATIVE_FORCE_ORIENTATION=landscape \
    SILISILI_NATIVE_TEST_PAGE=video-detail \
    SILISILI_NATIVE_TEST_CONTENT_MODE=quality-matrix \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=116 \
    >/tmp/silisili-native-quality-matrix-launch.log 2>&1
test_pid=$(wait_for_single_process)
test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")

phase=wait-quality-matrix
poll=0
minimum_observed_cma_kb=999999999
while test "$poll" -lt 1600; do
    test -e "/proc/$test_pid/stat"
    test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"
    test "$(awk '{print $3}' "/proc/$test_pid/stat")" != D
    cma_free_kb=$(awk '/^CmaFree:/ { print $2 }' /proc/meminfo)
    if test "$cma_free_kb" -lt "$minimum_observed_cma_kb"; then
        minimum_observed_cma_kb=$cma_free_kb
    fi
    test "$cma_free_kb" -ge "$minimum_cma_free_kb"
    events=$(events_for_pid "$test_pid")
    printf '%s\n' "$events" | grep -F \
        'native VOD quality matrix: complete' >/dev/null && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 1600

events=$(events_for_pid "$test_pid")
complete_line=$(printf '%s\n' "$events" | awk \
    '/native VOD quality matrix: complete/ { line = $0 } END { print line }')
requested_ids=$(printf '%s\n' "$complete_line" | awk '
    {
        for (i = 1; i <= NF; ++i) if ($i == "requested") {
            value = $(i + 1); gsub(/"/, "", value); print value; exit
        }
    }
')
resolved_ids=$(printf '%s\n' "$complete_line" | awk '
    {
        for (i = 1; i <= NF; ++i) if ($i == "resolved") {
            value = $(i + 1); gsub(/"/, "", value); print value; exit
        }
    }
')
test -n "$requested_ids"
test "$requested_ids" = "$resolved_ids"

# The selected history video is expected to expose the complete resolution
# ladder through 1080P+. 1080P60 is validated by the separate known-60fps UHD
# probe and is also exercised here automatically whenever it is advertised.
for required_quality in 16 32 64 80 112; do
    case ",$requested_ids," in
        *,"$required_quality",*) ;;
        *) false ;;
    esac
done

step_count=$(printf '%s\n' "$events" | grep -c \
    'native VOD quality matrix: step ready' || true)
test "$step_count" -eq "$(printf '%s' "$requested_ids" | awk -F, '{ print NF }')"
for required_geometry in \
    'quality 16 .*video 640 x 360' \
    'quality 32 .*video (852|854) x 480' \
    'quality 64 .*video 1280 x 720' \
    'quality 80 .*video 1920 x 1080' \
    'quality 112 .*video 1920 x 1080'; do
    printf '%s\n' "$events" | grep -E \
        "native player: DASH source resolved, $required_geometry" >/dev/null
done
test -z "$(printf '%s\n' "$events" | grep -F \
    'native hardware video: switching to software fallback' || true)"
test -z "$(printf '%s\n' "$events" | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND|Out of memory|Killed process' || true)"

# The regression page stops the production playback session after its final
# step. Wait for that last BufferQueue callback before terminating the process.
phase=wait-final-buffer-release
poll=0
while test "$poll" -lt 80; do
    events=$(events_for_pid "$test_pid")
    decoder_generations=$(printf '%s\n' "$events" | grep -c \
        'native hardware video: OMX decoder started' || true)
    balanced_generations=$(printf '%s\n' "$events" | grep -c \
        'native hardware video: created buffer references released.*balanced true' || true)
    test "$decoder_generations" -gt 0 \
        && test "$balanced_generations" -eq "$decoder_generations" && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 80
phase=stop-matrix-process
stop_application
events=$(events_for_pid "$test_pid")
decoder_generations=$(printf '%s\n' "$events" | grep -c \
    'native hardware video: OMX decoder started' || true)
balanced_generations=$(printf '%s\n' "$events" | grep -c \
    'native hardware video: created buffer references released.*balanced true' || true)
test "$decoder_generations" -ge "$step_count"
test "$balanced_generations" -eq "$decoder_generations"
test -z "$(printf '%s\n' "$events" | grep -E \
    'created buffer references released.*balanced false' || true)"

phase=production-relaunch
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
printf 'native_vod_quality_matrix=ready|package=%s|bvid=%s|cid=%s|requested=%s|resolved=%s|steps=%s|decoder_generations=%s|buffer_generations_balanced=%s|minimum_cma_free_kb=%s|same_pid=1|software_fallback=0|production_pid=%s|rpm_verify=clean|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$test_bvid" "$test_cid" "$requested_ids" \
    "$resolved_ids" "$step_count" "$decoder_generations" \
    "$balanced_generations" "$minimum_observed_cma_kb" "$production_pid" \
    "$expected_sha"
