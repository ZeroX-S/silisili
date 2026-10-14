#!/bin/sh
set -eu
test -S /run/display/wayland-0 || { echo 'start_gate_test=blocked|reason=wayland-display-unavailable'; exit 1; }
mode=${1:-zero}
quality=${2:-80}
page=video-detail
start=0
software=0
content=direct
case "$mode" in
  zero) ;;
  history) page=history-resume; start=14 ;;
  software) software=1 ;;
  matrix) content=quality-matrix ;;
  fullscreen) content=fullscreen ;;
  *) exit 64 ;;
esac
pid=
events=/tmp/silisili-start-gate-$mode-$quality.events
native_perf=/tmp/silisili-perf-native-start-$mode-$quality-$$.log
trap 'result=$?; if test "$result" -ne 0; then echo "start_gate_test=failed|mode=$mode|pid=$pid"; test -z "$pid" || journalctl -b "_PID=$pid" --no-pager -o cat | tail -100; fi' EXIT
pids=$(pidof silisili-native 2>/dev/null || true)
if test -n "$pids"; then kill -TERM $pids; sleep 2; fi
test -z "$(pidof silisili-native 2>/dev/null || true)"
mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
cd /home/defaultuser
runuser -u defaultuser -- env \
    XDG_RUNTIME_DIR=/run/user/100000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
    WAYLAND_DISPLAY=../../display/wayland-0 QT_QPA_PLATFORM=wayland \
    SILISILI_NATIVE_TEST_PAGE="$page" \
    SILISILI_NATIVE_TEST_CONTENT_MODE="$content" \
    SILISILI_NATIVE_TEST_BVID=BV1P4ddBBEJF \
    SILISILI_NATIVE_TEST_CID=37630051884 \
    SILISILI_NATIVE_TEST_QUALITY="$quality" \
    SILISILI_NATIVE_TEST_START_POSITION="$start" \
    SILISILI_NATIVE_TEST_SOFTWARE_VIDEO="$software" \
    SILISILI_NATIVE_TEST_PERF_LOG="$native_perf" \
    /usr/bin/invoker --no-wait --type=silica-qt5 --id=cn.silisili.native \
    --single-instance /usr/bin/silisili-native >/tmp/silisili-start-gate-launch.log 2>&1
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    pid=$(pidof silisili-native 2>/dev/null || true)
    test -z "$pid" || break
    sleep 1
done
test -n "$pid"
attempt=0
while test "$attempt" -lt 50; do
    test "$(pidof silisili-native 2>/dev/null || true)" = "$pid"
    journalctl -b "_PID=$pid" --no-pager -o short-monotonic >"$events"
    if grep -q 'initial position gate released.*audioReleased true.*firstVideoFrameReady true' "$events"; then break; fi
    attempt=$((attempt + 1))
    sleep 1
done
grep 'load command submitted.*audioStartGated true' "$events" || true
grep 'initial position gate released.*audioReleased true.*firstVideoFrameReady true' "$events" || true
if test -s "$native_perf"; then
    grep 'perf_start_ready.*audioReleased 1' "$native_perf"
else
    grep 'initial position gate released.*audioReleased true.*firstVideoFrameReady true' "$events"
fi
awk '
 /first (shared-texture|persistent shared-texture) frame rendered/ {frame=NR}
 /initial position gate released/ {if (!frame || frame>=NR) exit 1; released=1}
 END {if (!released) exit 1}
' "$events"
if test "$mode" = software; then
    grep 'software video route requested for regression' "$events"
else
    grep 'startup target frame primed.*audioClockWait false' "$events"
fi
sleep 5
test "$(pidof silisili-native)" = "$pid"
journalctl -b "_PID=$pid" --no-pager -o short-monotonic >"$events"
grep -E 'shared-texture frame checkpoint|shared-texture frame rendered' "$events" | tail -3
if test "$mode" = matrix; then
    attempt=0
    while test "$attempt" -lt 100; do
        test "$(pidof silisili-native 2>/dev/null || true)" = "$pid"
        journalctl -b "_PID=$pid" --no-pager -o short-monotonic >"$events"
        if grep -q 'native VOD quality matrix: complete' "$events"; then break; fi
        sleep 1
        attempt=$((attempt + 1))
    done
    grep 'native VOD quality matrix: complete' "$events"
    if test -s "$native_perf"; then
        awk '
          /perf_load/ {frame=0; loads++}
          /perf_target serial 0/ {frame=NR}
          /perf_start_ready/ {if (!frame || frame>=NR) bad=1; releases++}
          END {if (bad || loads<2 || releases!=loads) exit 1}
        ' "$native_perf"
    else
        awk '
      /load command submitted/ {frame=0; loads++}
      /first (shared-texture|persistent shared-texture) frame rendered/ {frame=NR}
      /initial position gate released/ {if (!frame || frame>=NR) bad=1; releases++}
      END {if (bad || loads<2 || releases!=loads) exit 1}
        ' "$events"
    fi
else
    test "$(grep -c 'load command submitted' "$events")" -eq 1
    grep -q 'shared-texture frame checkpoint' "$events"
fi
if grep -E 'ReferenceError|TypeError|first-frame watchdog expired|terminal video-output error|ANOM_ABEND|Failed to create display' "$events"; then exit 1; fi
printf 'start_gate_test=ready|mode=%s|quality=%s|pid=%s|frame_before_audio=1|frame_progress=1|events=%s\n' "$mode" "$quality" "$pid" "$events"
