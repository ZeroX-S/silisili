#!/bin/sh
set -eu

# Installs the candidate build, requests a real 4K/8K source, and proves both
# requests safely resolve to the highest empirically verified representation.
# Droidmedia's advertised 4K capability is not sufficient: on this target a
# real 4K60 allocation consumes all CMA and never presents a frame. The full
# quality ladder stays visible, while unverified UHD is capped at real 1080P60
# hardware decode without ever allocating the unsafe UHD codec session.

rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.35.aarch64.rpm}
expected_sha=${2:-cec6e5d8705068c10f3e14e1f6e026797b0b7734e8d6a21ef35508227cb28d3e}
expected_package=silisili-native-devel-1.1.0-1.35.aarch64
test_bvid=${SILISILI_UHD_TEST_BVID:-BV1P4ddBBEJF}
test_cid=${SILISILI_UHD_TEST_CID:-37630051884}
# The bounded 1080p OMX session on the Pixel 3a XL normally leaves roughly
# 25--30 MiB CMA free.  Treat less than 16 MiB as exhaustion pressure while
# still rejecting the unsafe real-UHD allocation path entirely below.
minimum_cma_free_kb=${SILISILI_UHD_MINIMUM_CMA_FREE_KB:-16384}
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
    sleep 2
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
    dmesg 2>/dev/null | grep -c "binder: $1 has pending async transaction" || true
}

cleanup() {
    result=$?
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_ultrahd_recovery=failed|phase=%s|test_pid=%s|production_pid=%s|visual_model=unused\n' \
            "$phase" "${test_pid:-none}" "${production_pid:-none}"
        test -z "${test_pid:-}" || events_for_pid "$test_pid" | grep -E \
            'native (player|hardware video|detail perf)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -260 || true
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

test -n "$expected_sha"
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

phase=launch-4k-request
rm -f /tmp/silisili-native-defaultuser.lock
launch_application \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=history-resume \
    SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=120 \
    SILISILI_NATIVE_TEST_START_POSITION=14 \
    SILISILI_NATIVE_TEST_RESET_OPERATIONAL_QUALITY=1 \
    >/tmp/silisili-native-ultrahd-4k-launch.log 2>&1
test_pid=$(wait_for_single_process)
test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")

phase=wait-4k-safe-frame
poll=0
while test "$poll" -lt 160; do
    events=$(events_for_pid "$test_pid")
    printf '%s\n' "$events" | grep -F \
        'native player: unsafe ultra-HD representation avoided' >/dev/null \
        && printf '%s\n' "$events" | grep -E \
        'native (hardware video: first shared-texture frame rendered|player: first persistent shared-texture frame rendered)' >/dev/null \
        && printf '%s\n' "$events" | grep -F \
        'native detail perf: loading cover hidden loading false' >/dev/null \
        && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 160
events=$(events_for_pid "$test_pid")
printf '%s\n' "$events" | grep -E \
    'native player: persisted operational quality ceiling 116 safeDefault 116 unverifiedUltraHdOptIn false' >/dev/null
printf '%s\n' "$events" | grep -E \
    'native player: unsafe ultra-HD representation avoided.*requested 120 selected 116 .*selectedGeometry 1920 x 1080 .*operationalMaximumQuality 116 .*softwareFallback false' >/dev/null
printf '%s\n' "$events" | grep -E \
    'native player: DASH source resolved, quality 116 .*video 1920 x 1080' >/dev/null
printf '%s\n' "$events" | grep -E \
    'native hardware video: OMX decoder started .*size 1920 x 1080 .*decodedQueueLimit 8 .*compressedPacketLimit 8 .*steadyPacketLimit 8 .*compressedInputLeadLimitMs 1500 .*binderCallbackBlocking false' \
    >/dev/null
test -z "$(printf '%s\n' "$events" | grep -F \
    'native hardware video: switching to software fallback' || true)"
test -z "$(printf '%s\n' "$events" | grep -E \
    'OMX decoder started .*size (3840 x 2160|7680 x 4320)|DASH source resolved, quality (120|127)' || true)"
test -z "$(printf '%s\n' "$events" | grep -F \
    'native hardware video: first-frame watchdog expired' || true)"

phase=physical-transport-controls
pause_count_before=$(printf '%s\n' "$events" | grep -c \
    'native transport: pause requested true' || true)
/tmp/bonito-direct-touch tap 540 500
sleep 0.4
events=$(events_for_pid "$test_pid")
pause_count_after=$(printf '%s\n' "$events" | grep -c \
    'native transport: pause requested true' || true)
if test "$pause_count_after" -le "$pause_count_before"; then
    # The first tap revealed controls after their normal auto-hide.
    /tmp/bonito-direct-touch tap 540 500
    sleep 0.4
    events=$(events_for_pid "$test_pid")
    pause_count_after=$(printf '%s\n' "$events" | grep -c \
        'native transport: pause requested true' || true)
fi
test "$pause_count_after" -gt "$pause_count_before"
resume_count_before=$(printf '%s\n' "$events" | grep -c \
    'native transport: pause requested false' || true)
/tmp/bonito-direct-touch tap 540 500
sleep 0.4
events=$(events_for_pid "$test_pid")
resume_count_after=$(printf '%s\n' "$events" | grep -c \
    'native transport: pause requested false' || true)
test "$resume_count_after" -gt "$resume_count_before"
printf 'ultrahd_controls=ready|loading=0|pause=physical-touch|resume=physical-touch|same_pid=1\n'

phase=wait-4k-stable-cadence
poll=0
stable_start_index=
while test "$poll" -lt 80; do
    events=$(events_for_pid "$test_pid")
    stable_start_index=$(printf '%s\n' "$events" | awk '
        /native player: frame floor window/ {
            window_index = 0
            fps = 0
            for (i = 1; i <= NF; ++i) {
                if ($i == "index") window_index = $(i + 1) + 0
                if ($i == "fps") fps = $(i + 1) + 0
            }
            if (fps >= 45.0) ++consecutive
            else consecutive = 0
            last = window_index
        }
        END { if (consecutive >= 10) print last }
    ')
    test -n "$stable_start_index" && break
    sleep 0.25
    poll=$((poll + 1))
done
test -n "$stable_start_index"

phase=hold-4k-60s
sample=0
previous_frame_index=$stable_start_index
while test "$sample" -lt 12; do
    sleep 5
    test -e "/proc/$test_pid/stat"
    test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"
    process_state=$(awk '{print $3}' "/proc/$test_pid/stat")
    cma_free_kb=$(awk '/^CmaFree:/ { print $2 }' /proc/meminfo)
    test "$cma_free_kb" -ge "$minimum_cma_free_kb"
    events=$(events_for_pid "$test_pid")
    frame_index=$(printf '%s\n' "$events" | awk '
        /native player: frame floor window/ {
            for (i = 1; i <= NF; ++i)
                if ($i == "index") last = $(i + 1) + 0
        }
        END { print last + 0 }
    ')
    test "$frame_index" -gt "$previous_frame_index"
    previous_frame_index=$frame_index
    printf 'ultrahd_4k_sample=%s|pid=%s|state=%s|frame_index=%s|cma_free_kb=%s|binder_workaround_diagnostic=%s\n' \
        "$((sample + 1))" "$test_pid" "$process_state" "$frame_index" "$cma_free_kb" \
        "$(binder_count "$test_pid")"
    sample=$((sample + 1))
done
events=$(events_for_pid "$test_pid")
four_k_binder_diagnostic=$(binder_count "$test_pid")
four_k_windows=$(printf '%s\n' "$events" | awk -v start="$stable_start_index" '
    /native player: frame floor window/ {
        window_index = 0
        for (i = 1; i <= NF; ++i)
            if ($i == "index") window_index = $(i + 1) + 0
        if (window_index > start) ++count
    }
    END { print count + 0 }
')
test "$four_k_windows" -ge 50
four_k_minimum=$(printf '%s\n' "$events" | awk -v start="$stable_start_index" '
    /native player: frame floor window/ {
        window_index = 0
        value = 0
        for (i = 1; i <= NF; ++i) {
            if ($i == "index") window_index = $(i + 1) + 0
            if ($i == "fps") value = $(i + 1) + 0
        }
        if (window_index > start) {
            if (!seen || value < minimum) minimum = value
            seen = 1
        }
    }
    END { if (seen) printf("%.3f", minimum); else print "0" }
')
awk -v fps="$four_k_minimum" 'BEGIN { exit !(fps + 0 >= 45.0) }'
test -z "$(printf '%s\n' "$events" | grep -F \
    'native hardware video: decoded frame queue pressure' || true)"
test -z "$(printf '%s\n' "$events" | grep -F \
    'native hardware video: nonblocking callback dropped excess frame' || true)"
test -z "$(printf '%s\n' "$events" | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND|Out of memory|Killed process' || true)"

phase=launch-8k-guard
stop_application
rm -f /tmp/silisili-native-defaultuser.lock
launch_application \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=video-detail \
    SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
    SILISILI_NATIVE_TEST_BVID="$test_bvid" \
    SILISILI_NATIVE_TEST_CID="$test_cid" \
    SILISILI_NATIVE_TEST_QUALITY=127 \
    >/tmp/silisili-native-ultrahd-8k-launch.log 2>&1
test_pid=$(wait_for_single_process)
test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")

poll=0
while test "$poll" -lt 160; do
    events=$(events_for_pid "$test_pid")
    printf '%s\n' "$events" | grep -F \
        'native player: unsafe ultra-HD representation avoided' >/dev/null \
        && printf '%s\n' "$events" | grep -E \
        'native (hardware video: first shared-texture frame rendered|player: first persistent shared-texture frame rendered)' >/dev/null \
        && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 160
events=$(events_for_pid "$test_pid")
printf '%s\n' "$events" | grep -E \
    'unsafe ultra-HD representation avoided.*requested 127 selected 116 .*selectedGeometry 1920 x 1080 .*operationalMaximumQuality 116 .*softwareFallback false' \
    >/dev/null
printf '%s\n' "$events" | grep -E \
    'native hardware video: OMX decoder started .*size 1920 x 1080 .*decodedQueueLimit 8 .*compressedPacketLimit 8 .*steadyPacketLimit 8 .*compressedInputLeadLimitMs 1500 .*binderCallbackBlocking false' \
    >/dev/null
test -z "$(printf '%s\n' "$events" | grep -F \
    'native hardware video: switching to software fallback' || true)"
test -z "$(printf '%s\n' "$events" | grep -E \
    'OMX decoder started .*size (3840 x 2160|7680 x 4320)|DASH source resolved, quality (120|127)' || true)"

phase=hold-8k-guard
sample=0
previous_frame_index=0
while test "$sample" -lt 4; do
    sleep 5
    test -e "/proc/$test_pid/stat"
    test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"
    process_state=$(awk '{print $3}' "/proc/$test_pid/stat")
    cma_free_kb=$(awk '/^CmaFree:/ { print $2 }' /proc/meminfo)
    test "$cma_free_kb" -ge "$minimum_cma_free_kb"
    events=$(events_for_pid "$test_pid")
    frame_index=$(printf '%s\n' "$events" | awk '
        /native player: frame floor window/ {
            for (i = 1; i <= NF; ++i)
                if ($i == "index") last = $(i + 1) + 0
        }
        END { print last + 0 }
    ')
    test "$frame_index" -gt "$previous_frame_index"
    previous_frame_index=$frame_index
    printf 'ultrahd_8k_guard_sample=%s|pid=%s|state=%s|frame_index=%s|cma_free_kb=%s|binder_workaround_diagnostic=%s\n' \
        "$((sample + 1))" "$test_pid" "$process_state" "$frame_index" "$cma_free_kb" \
        "$(binder_count "$test_pid")"
    sample=$((sample + 1))
done
events=$(events_for_pid "$test_pid")
test -z "$(printf '%s\n' "$events" | grep -F \
    'native hardware video: decoded frame queue pressure' || true)"
test -z "$(printf '%s\n' "$events" | grep -F \
    'native hardware video: nonblocking callback dropped excess frame' || true)"

phase=production-relaunch
stop_application
rm -f /tmp/silisili-native-defaultuser.lock
launch_application >/tmp/silisili-native-production-launch.log 2>&1
production_pid=$(wait_for_single_process)
poll=0
while test "$poll" -lt 60; do
    production_events=$(events_for_pid "$production_pid")
    printf '%s\n' "$production_events" | grep -F \
        'native app: build identity "silisili-native-devel" "1.1.0" "1.35"' \
        >/dev/null && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 60
phase=complete
printf 'native_ultrahd_recovery=ready|package=%s|bvid=%s|cid=%s|4k_requested=120|unverified_uhd_omx_attempted=0|safe_ceiling=116|selected_geometry=1920x1080|history_start=14|controls=physical-pause-resume|loading_stuck=0|input_lead_ms=1500|hold_seconds=60|minimum_fps=%s|frame_windows=%s|queue_pressure=0|minimum_cma_free_kb=%s|binder_workaround_diagnostic=%s|8k_requested=127|8k_selected=116|uhd_software_fallback=0|production_pid=%s|rpm_verify=clean|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$test_bvid" "$test_cid" "$four_k_minimum" \
    "$four_k_windows" "$minimum_cma_free_kb" "$four_k_binder_diagnostic" \
    "$production_pid" "$expected_sha"
