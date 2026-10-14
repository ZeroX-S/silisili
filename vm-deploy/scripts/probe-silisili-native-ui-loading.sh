#!/bin/sh
set -eu
# Run on a Sailfish device. Exercises real API/model/delegate creation without
# hidden playback prewarming; retains timings alongside native media markers.
run=${1:-ui-loading-$(date +%Y%m%d-%H%M%S)}
case "$run" in *[!A-Za-z0-9_-]*) exit 64;; esac
events=/tmp/silisili-ui-$run.events
perf=/tmp/silisili-perf-native-$run.log
package=$(rpm -q silisili-native-devel)
pid=
trap 'rc=$?; if test "$rc" -ne 0; then echo "sailfish_test=failed|run=$run|pid=$pid|evidence=$events"; fi' EXIT
old=$(pidof silisili-native 2>/dev/null || true)
if test -n "$old"; then kill -TERM $old; sleep 2; fi
test -z "$(pidof silisili-native 2>/dev/null || true)"
mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
runuser -u defaultuser -- env \
    XDG_RUNTIME_DIR=/run/user/100000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
    WAYLAND_DISPLAY=../../display/wayland-0 QT_QPA_PLATFORM=wayland \
    SILISILI_NATIVE_TEST_PAGE=video-detail \
    SILISILI_NATIVE_TEST_CONTENT_MODE=direct \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_BVID=BV1P4ddBBEJF \
    SILISILI_NATIVE_TEST_CID=37630051884 \
    SILISILI_NATIVE_TEST_QUALITY=80 \
    SILISILI_NATIVE_TEST_PERF_LOG="$perf" \
    /usr/bin/invoker --no-wait --type=silica-qt5 --id=cn.silisili.native \
    --single-instance /usr/bin/silisili-native >"/tmp/silisili-ui-$run.launch" 2>&1
sleep 1
pid=$(pidof silisili-native)
start=$(awk '{print $22}' "/proc/$pid/stat")
attempt=0
while test "$attempt" -lt 60; do
    test "$(pidof silisili-native)" = "$pid"
    journalctl -b "_PID=$pid" --no-pager -o short-monotonic >"$events"
    if grep -q 'native ui loading: comment preview ready 0' "$events" \
       && grep -q 'native ui loading: related preview ready 0' "$events" \
       && grep -q 'perf_start_ready.*audioReleased 1' "$perf" 2>/dev/null; then break; fi
    attempt=$((attempt + 1))
    sleep 0.25
done
test "$attempt" -lt 60
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$start"
test "$(grep -c 'native detail perf: loading comments' "$events")" -eq 1
test "$(grep -c 'native detail perf: loading related' "$events")" -eq 1
if grep -E 'TypeError|ReferenceError|Binding loop|Cannot assign|first-frame watchdog expired|terminal video-output error' "$events"; then exit 1; fi
grep -E 'detail ready elapsedMs|native ui loading:.*(loading false|preview ready)' "$events"
cat "$perf"
echo "sailfish_test=ready|run=$run|package=$package|pid=$pid|checks=comments-related-delegates-first-frame-no-duplicate-requests"
